data "aws_caller_identity" "current" {}

locals {
  name = "${var.project}-${var.environment}"

  account_id = data.aws_caller_identity.current.account_id
  owner      = split("/", var.github_repo)[0]
  repo       = split("/", var.github_repo)[1]

  state_bucket_arn = "arn:aws:s3:::${var.state_bucket_name}"
  name_prefix      = "${var.project}-*"

  # GitHub may put numeric ids into the subject (repo:owner@<id>/name@<id>:...).
  # StringLike lets the ids vary while owner, repo name and subject stay pinned.
  # The plain form covers repos that still use the old subject format.
  # Never repo:joheee/*.
  repo_subjects = [
    "repo:${var.github_repo}",
    "repo:${local.owner}@*/${local.repo}@*",
  ]

  plan_subjects = [for s in local.repo_subjects : "${s}:pull_request"]

  apply_subjects = flatten([
    for s in local.repo_subjects : [
      "${s}:ref:refs/heads/${var.github_branch}",
      "${s}:environment:${var.environment}",
    ]
  ])
}

module "network" {
  source = "./modules/network"

  name                    = local.name
  vpc_cidr                = var.vpc_cidr
  az_count                = var.az_count
  nat_gateway_per_az      = var.nat_gateway_per_az
  flow_log_retention_days = var.flow_log_retention_days
}

# ---------------------------------------------------------------------------
# GitHub OIDC provider: one per account, already created by the TicTacToe
# repos. Looked up here, never created, so destroying this stack cannot break
# those pipelines.
# ---------------------------------------------------------------------------
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

# ---------------------------------------------------------------------------
# GitHub Actions roles, one pair per environment (the names include the
# environment because each environment has its own state). The state bucket is
# created by hand before the first init; see the README.
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "github_trust" {
  for_each = {
    plan  = local.plan_subjects
    apply = local.apply_subjects
  }

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = each.value
    }
  }
}

# Plan role: pull requests only, read-only.
resource "aws_iam_role" "plan" {
  name               = "${local.name}-github-plan"
  description        = "Read-only role for terraform plan on pull requests."
  assume_role_policy = data.aws_iam_policy_document.github_trust["plan"].json
}

data "aws_iam_policy_document" "plan" {
  statement {
    sid       = "StateBucketList"
    actions   = ["s3:ListBucket", "s3:GetBucketVersioning"]
    resources = [local.state_bucket_arn]
  }

  statement {
    sid       = "StateRead"
    actions   = ["s3:GetObject"]
    resources = ["${local.state_bucket_arn}/*"]
  }

  # plan takes the state lock, which is a <key>.tflock object. The plan role may
  # write only those, never the state file itself.
  statement {
    sid       = "StateLockfile"
    actions   = ["s3:PutObject", "s3:DeleteObject"]
    resources = ["${local.state_bucket_arn}/*.tflock"]
  }

  # Describe/List calls do not support resource-level permissions, so "*" is
  # required here. They are read-only and limited to this region.
  statement {
    sid = "ReadNetwork"
    actions = [
      "ec2:Describe*",
      "logs:DescribeLogGroups",
      "logs:ListTagsForResource",
      "logs:ListTagsLogGroup",
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.aws_region]
    }
  }

  # IAM reads are limited to this project's names. IAM is global, so no region
  # condition applies.
  statement {
    sid = "ReadProjectIam"
    actions = [
      "iam:GetRole", "iam:GetRolePolicy", "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies", "iam:ListRoleTags", "iam:GetPolicy",
      "iam:GetPolicyVersion", "iam:ListPolicyVersions",
    ]
    resources = [
      "arn:aws:iam::${local.account_id}:role/${local.name_prefix}",
      "arn:aws:iam::${local.account_id}:policy/${local.name_prefix}",
    ]
  }

  # Extended on Day 2 with ECS, ELB, RDS and Secrets Manager read actions.
}

resource "aws_iam_role_policy" "plan" {
  name   = "terraform-plan"
  role   = aws_iam_role.plan.id
  policy = data.aws_iam_policy_document.plan.json
}

# Apply role: the main branch and this environment's GitHub Environment only.
resource "aws_iam_role" "apply" {
  name               = "${local.name}-github-apply"
  description        = "Role for terraform apply and destroy from main and the ${var.environment} environment."
  assume_role_policy = data.aws_iam_policy_document.github_trust["apply"].json
}

data "aws_iam_policy_document" "apply" {
  statement {
    sid       = "StateBucketList"
    actions   = ["s3:ListBucket", "s3:GetBucketVersioning"]
    resources = [local.state_bucket_arn]
  }

  statement {
    sid       = "StateObjects"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${local.state_bucket_arn}/*"]
  }

  # Most EC2/VPC create and describe calls do not support resource-level
  # permissions, so these use "*". The blast radius is bounded by the region
  # condition and by IAM below being limited to project-prefixed names. No
  # ec2:*Instance* here: Fargate needs none, and the org SCP denies
  # DescribeInstances anyway.
  statement {
    sid = "Network"
    actions = [
      "ec2:*Vpc*", "ec2:*Subnet*", "ec2:*InternetGateway*", "ec2:*RouteTable*",
      "ec2:*Route", "ec2:*SecurityGroup*", "ec2:*NatGateway*", "ec2:*Address*",
      "ec2:*FlowLogs", "ec2:*Tags", "ec2:Describe*",
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.aws_region]
    }
  }

  statement {
    sid = "ProjectLogGroups"
    actions = [
      "logs:CreateLogGroup", "logs:DeleteLogGroup", "logs:PutRetentionPolicy",
      "logs:DeleteRetentionPolicy", "logs:TagResource", "logs:UntagResource",
      "logs:ListTagsForResource", "logs:ListTagsLogGroup",
    ]
    resources = [
      "arn:aws:logs:${var.aws_region}:${local.account_id}:log-group:/${local.name_prefix}",
      "arn:aws:logs:${var.aws_region}:${local.account_id}:log-group:/${local.name_prefix}:*",
    ]
  }

  # DescribeLogGroups does not support resource-level permissions.
  statement {
    sid       = "DescribeLogGroups"
    actions   = ["logs:DescribeLogGroups"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.aws_region]
    }
  }

  # IAM: only roles and policies named after the project. IAM is global, so no
  # region condition applies.
  statement {
    sid = "ProjectIam"
    actions = [
      "iam:CreateRole", "iam:DeleteRole", "iam:GetRole", "iam:UpdateRole",
      "iam:UpdateAssumeRolePolicy", "iam:TagRole", "iam:UntagRole", "iam:ListRoleTags",
      "iam:PutRolePolicy", "iam:GetRolePolicy", "iam:DeleteRolePolicy",
      "iam:ListRolePolicies", "iam:ListAttachedRolePolicies",
      "iam:AttachRolePolicy", "iam:DetachRolePolicy",
      "iam:CreatePolicy", "iam:DeletePolicy", "iam:GetPolicy", "iam:GetPolicyVersion",
      "iam:ListPolicyVersions", "iam:CreatePolicyVersion", "iam:DeletePolicyVersion",
      "iam:TagPolicy", "iam:UntagPolicy",
    ]
    resources = [
      "arn:aws:iam::${local.account_id}:role/${local.name_prefix}",
      "arn:aws:iam::${local.account_id}:policy/${local.name_prefix}",
    ]
  }

  # Terraform may only hand project roles to the services that need them.
  statement {
    sid       = "PassProjectRoles"
    actions   = ["iam:PassRole"]
    resources = ["arn:aws:iam::${local.account_id}:role/${local.name_prefix}"]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["vpc-flow-logs.amazonaws.com"]
    }
  }

  # Extended on Day 2 with ECS, ELB, RDS and Secrets Manager actions, and the
  # matching ecs-tasks.amazonaws.com / monitoring.rds.amazonaws.com PassRole.
}

resource "aws_iam_role_policy" "apply" {
  name   = "terraform-apply"
  role   = aws_iam_role.apply.id
  policy = data.aws_iam_policy_document.apply.json
}
