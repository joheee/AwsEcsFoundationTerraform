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

  # Apply is only possible from a job that declares this environment's GitHub
  # Environment, so prod's required-reviewer approval is enforced by AWS, not
  # just by the workflow file. There is deliberately no branch subject here.
  apply_subjects = [for s in local.repo_subjects : "${s}:environment:${var.environment}"]
}

module "network" {
  source = "./modules/network"

  name                    = local.name
  vpc_cidr                = var.vpc_cidr
  az_count                = var.az_count
  nat_gateway_per_az      = var.nat_gateway_per_az
  flow_log_retention_days = var.flow_log_retention_days
}

module "ecs_service" {
  source = "./modules/ecs_service"

  name               = local.name
  vpc_id             = module.network.vpc_id
  public_subnet_ids  = module.network.public_subnet_ids
  private_subnet_ids = module.network.private_subnet_ids

  container_image         = var.container_image
  container_port          = var.container_port
  cpu                     = var.service_cpu
  memory                  = var.service_memory
  desired_count           = var.service_desired_count
  alb_deletion_protection = var.alb_deletion_protection
  container_insights      = var.container_insights

  # The service learns where the database is, and gets the credentials from
  # Secrets Manager at start-up. The password never passes through Terraform.
  environment_variables = {
    DB_HOST = module.rds_postgres.address
    DB_PORT = tostring(module.rds_postgres.port)
    DB_NAME = module.rds_postgres.db_name
  }
  secrets = {
    DB_USERNAME = "${module.rds_postgres.master_user_secret_arn}:username::"
    DB_PASSWORD = "${module.rds_postgres.master_user_secret_arn}:password::"
  }
  secret_arns = [module.rds_postgres.master_user_secret_arn]
}

module "rds_postgres" {
  source = "./modules/rds_postgres"

  name       = local.name
  vpc_id     = module.network.vpc_id
  subnet_ids = module.network.isolated_subnet_ids

  # ALB -> service -> database: only the service may connect.
  allowed_security_group_ids = [module.ecs_service.service_security_group_id]

  engine_version        = var.db_engine_version
  instance_class        = var.db_instance_class
  allocated_storage     = var.db_allocated_storage
  multi_az              = var.db_multi_az
  backup_retention_days = var.db_backup_retention_days
  deletion_protection   = var.db_deletion_protection
  skip_final_snapshot   = var.db_skip_final_snapshot
}

# The service may talk to the database port, and only to the database. Kept in
# the root so neither module needs to know about the other.
resource "aws_vpc_security_group_egress_rule" "service_to_db" {
  security_group_id            = module.ecs_service.service_security_group_id
  description                  = "PostgreSQL to the database"
  ip_protocol                  = "tcp"
  from_port                    = module.rds_postgres.port
  to_port                      = module.rds_postgres.port
  referenced_security_group_id = module.rds_postgres.security_group_id
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
  # The OIDC provider is looked up by URL (a data source), which lists all
  # providers and then reads the match. List calls take no resource-level
  # permissions, so "*" is required; the read is pinned to the one provider.
  statement {
    sid       = "FindGithubOidcProvider"
    actions   = ["iam:ListOpenIDConnectProviders"]
    resources = ["*"]
  }

  statement {
    sid       = "ReadGithubOidcProvider"
    actions   = ["iam:GetOpenIDConnectProvider"]
    resources = [data.aws_iam_openid_connect_provider.github.arn]
  }

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

  # ECS, ELB, RDS and Secrets Manager reads. All are Describe/List calls that
  # take no resource-level permissions, so "*" is required; limited to this region.
  statement {
    sid = "ReadPlatform"
    actions = [
      "ecs:Describe*",
      "ecs:List*",
      "elasticloadbalancing:Describe*",
      "rds:Describe*",
      "rds:ListTagsForResource",
      "secretsmanager:DescribeSecret",
      "secretsmanager:GetResourcePolicy",
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.aws_region]
    }
  }
}

resource "aws_iam_role_policy" "plan" {
  name   = "terraform-plan"
  role   = aws_iam_role.plan.id
  policy = data.aws_iam_policy_document.plan.json
}

# Apply role: this environment's GitHub Environment only (no branch subject).
resource "aws_iam_role" "apply" {
  name               = "${local.name}-github-apply"
  description        = "Role for terraform apply and destroy from the ${var.environment} GitHub Environment."
  assume_role_policy = data.aws_iam_policy_document.github_trust["apply"].json
}

data "aws_iam_policy_document" "apply" {
  # The OIDC provider is looked up by URL (a data source), which lists all
  # providers and then reads the match. List calls take no resource-level
  # permissions, so "*" is required; the read is pinned to the one provider.
  statement {
    sid       = "FindGithubOidcProvider"
    actions   = ["iam:ListOpenIDConnectProviders"]
    resources = ["*"]
  }

  statement {
    sid       = "ReadGithubOidcProvider"
    actions   = ["iam:GetOpenIDConnectProvider"]
    resources = [data.aws_iam_openid_connect_provider.github.arn]
  }

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
      values   = ["vpc-flow-logs.amazonaws.com", "ecs-tasks.amazonaws.com"]
    }
  }

  # ECS and RDS create their service-linked roles on first use in an account.
  statement {
    sid       = "ServiceLinkedRoles"
    actions   = ["iam:CreateServiceLinkedRole"]
    resources = ["arn:aws:iam::${local.account_id}:role/aws-service-role/*"]

    condition {
      test     = "StringEquals"
      variable = "iam:AWSServiceName"
      values = [
        "ecs.amazonaws.com",
        "rds.amazonaws.com",
        "elasticloadbalancing.amazonaws.com",
      ]
    }
  }

  # ECS: resource-level where the API supports it.
  statement {
    sid = "ProjectEcs"
    actions = [
      "ecs:CreateCluster", "ecs:DeleteCluster", "ecs:UpdateCluster",
      "ecs:UpdateClusterSettings", "ecs:PutClusterCapacityProviders",
      "ecs:CreateService", "ecs:UpdateService", "ecs:DeleteService",
      "ecs:TagResource", "ecs:UntagResource", "ecs:ListTagsForResource",
    ]
    resources = [
      "arn:aws:ecs:${var.aws_region}:${local.account_id}:cluster/${local.name_prefix}",
      "arn:aws:ecs:${var.aws_region}:${local.account_id}:service/${local.name_prefix}/*",
      "arn:aws:ecs:${var.aws_region}:${local.account_id}:task-definition/${local.name_prefix}:*",
    ]
  }

  # Task definition registration and the Describe/List calls do not support
  # resource-level permissions.
  statement {
    sid = "EcsNoResourceLevel"
    actions = [
      "ecs:RegisterTaskDefinition", "ecs:DeregisterTaskDefinition",
      "ecs:DeleteTaskDefinitions", "ecs:Describe*", "ecs:List*",
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.aws_region]
    }
  }

  # Load balancers, target groups and listeners are created by name pattern;
  # most ELB create/modify actions cannot be scoped to an ARN that does not
  # exist yet, so "*" is used with the region condition.
  statement {
    sid       = "LoadBalancing"
    actions   = ["elasticloadbalancing:*"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.aws_region]
    }
  }

  statement {
    sid = "ProjectRds"
    actions = [
      "rds:CreateDBInstance", "rds:ModifyDBInstance", "rds:DeleteDBInstance",
      "rds:RebootDBInstance", "rds:CreateDBSubnetGroup", "rds:ModifyDBSubnetGroup",
      "rds:DeleteDBSubnetGroup", "rds:AddTagsToResource", "rds:RemoveTagsFromResource",
      "rds:ListTagsForResource", "rds:CreateDBSnapshot",
    ]
    resources = [
      "arn:aws:rds:${var.aws_region}:${local.account_id}:db:${local.name_prefix}",
      "arn:aws:rds:${var.aws_region}:${local.account_id}:subgrp:${local.name_prefix}",
      "arn:aws:rds:${var.aws_region}:${local.account_id}:snapshot:${local.name_prefix}",
    ]
  }

  statement {
    sid       = "RdsDescribe"
    actions   = ["rds:Describe*"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.aws_region]
    }
  }

  # RDS creates and owns the master-password secret (rds!db-<id>); Terraform
  # only needs to read and tag it, and to delete it with the instance.
  statement {
    sid = "RdsManagedSecret"
    actions = [
      "secretsmanager:DescribeSecret", "secretsmanager:GetResourcePolicy",
      "secretsmanager:TagResource", "secretsmanager:DeleteSecret",
    ]
    resources = ["arn:aws:secretsmanager:${var.aws_region}:${local.account_id}:secret:rds!db-*"]
  }
}

resource "aws_iam_role_policy" "apply" {
  name   = "terraform-apply"
  role   = aws_iam_role.apply.id
  policy = data.aws_iam_policy_document.apply.json
}
