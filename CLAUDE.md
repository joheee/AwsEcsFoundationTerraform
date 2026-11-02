# CLAUDE.md

Read `GOALS.md` first. It defines what this repo creates, what is out of scope
and the definition of done. When a choice is unclear, pick the option that makes
the "clean, repeatable, two-environment AWS foundation" story clearer.

## Context

- Portfolio project #1: Terraform for a VPC, ECS on Fargate behind an ALB, and
  RDS PostgreSQL, in `staging` and `prod`, applied by GitHub Actions via OIDC.
- It builds on joheee/AwsBaseInfra (same module style). Project 4's
  joheee/TicTacToeInfra solved the same bootstrap/OIDC problems; reuse its
  patterns rather than inventing new ones.
- Region `ap-southeast-2` only (org SCP). The SCP also denies
  `ec2:DescribeInstances`; don't add anything that needs it.

## Layout

- State bucket: created by hand once (not in Terraform). The GitHub OIDC
  provider already exists in the account and is only looked up with a data
  source. The per-environment plan (read-only) and apply roles live in the root
  module's `main.tf`; the first apply of each environment is run locally.
- `modules/network`, `modules/ecs_service`, `modules/rds_postgres`: reusable
  modules, each with `main.tf`, `variables.tf`, `outputs.tf`.
- Root module (`*.tf` at the top level): wires the modules, S3 backend with
  `use_lockfile = true`.
- `envs/staging.tfvars`, `envs/prod.tfvars` and `envs/<env>.backend.hcl`:
  the only place environments differ. Init with
  `terraform init -backend-config=envs/<env>.backend.hcl` and plan with
  `-var-file=envs/<env>.tfvars`.
- `.github/workflows/`: `terraform.yml` (PR checks and plan, apply on merge)
  and `destroy.yml` (manual, per environment, needs approval).

## Working rules

- Never commit secrets, `*.tfstate`, `.terraform/`, or tfvars with real
  secret values. Environment tfvars hold only non-secret sizing and names.
- Database passwords never go through Terraform: use
  `manage_master_user_password = true` and pass the secret ARN to ECS.
- Least privilege: scope IAM policies to specific ARNs. Explain any `"*"`
  resource in a comment.
- OIDC trust policies pin this exact repo and a branch, pull request or
  environment subject; never `repo:joheee/*`.
- Every resource gets `project`, `environment` and `managed_by = terraform`
  tags through the provider's `default_tags`.
- Pin Terraform and provider versions in `versions.tf`; commit
  `.terraform.lock.hcl`.
- Don't rename or remove outputs listed in the README; add new ones.
- Run `terraform fmt -recursive`, `terraform validate` and `tflint` before
  every commit.
- Never run `terraform apply` or `destroy` without being asked; show the plan
  first. Destroy environments after demos to keep costs down.
- Commits: author `joheee <johevinblesstowi07@gmail.com>`, no Co-Authored-By
  trailer. Ask before committing or pushing.
- Tick the boxes in the GOALS.md "Definition of done" as items are finished.
