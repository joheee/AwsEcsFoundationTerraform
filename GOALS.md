# Project goals: AWS foundation in Terraform, deployed by GitHub Actions

This repo is portfolio project #1 for my Upwork DevOps profile. The point is the
**foundation**: a client should look at it and think "this person can stand up a
clean, multi-environment AWS base for my product, with no stored keys and no
hand-made resources, and tell me what it costs".

It grows out of my earlier repo
[joheee/AwsBaseInfra](https://github.com/joheee/AwsBaseInfra) (VPC, subnet, NIC,
EC2, IAM role and EKS modules with an S3 backend). This repo keeps that modular
style and fixes what it was missing: routing, security groups, outputs, version
pins, tagging, two environments and a pipeline.

## The pitch (what a client buys)

> "Production-ready AWS foundation in Terraform, 4 days." A VPC across two
> availability zones, a container platform (ECS on Fargate) behind a load
> balancer, a private PostgreSQL database on RDS, remote state with locking,
> and GitHub Actions that plans every pull request and applies on merge using
> OIDC (no AWS keys anywhere). Staging and prod come from the same code.

It matches jobs like "Healthcare AWS foundation", "AWS gap analysis",
"Environment review", "EKS rebuild" and "AWS LEMP release process".

## Objectives

1. **Remote state.** S3 bucket (versioned, encrypted, public access blocked)
   with S3 native locking (`use_lockfile = true`), one state key per
   environment. The bucket is created by hand once; the CI roles are in the
   root module, one plan/apply pair per environment, trusting the account's
   existing GitHub OIDC provider (looked up, not created).
2. **Network module.** VPC across two AZs with public, private (app) and
   isolated (database) subnets, internet gateway, route tables and NAT.
   Staging uses one NAT gateway to save money; prod can switch to one per AZ
   with a variable. VPC flow logs to CloudWatch.
3. **Container platform module (ECS on Fargate).** ECS cluster, an
   Application Load Balancer in the public subnets, one sample service in the
   private subnets, task and execution roles, CloudWatch log group, and
   security groups that only allow ALB → service → database. The container
   image is a variable (a public sample image by default).
4. **Database module (RDS PostgreSQL).** Private, encrypted, in the isolated
   subnets, reachable only from the service's security group. The master
   password is generated and stored by RDS in Secrets Manager
   (`manage_master_user_password = true`), so it never appears in code or
   Terraform state. Automated backups on; deletion protection on in prod.
5. **Two environments from one codebase.** `staging` and `prod` use the same
   root module with different `envs/<env>.tfvars` and backend keys. Sizes,
   NAT count, multi-AZ and deletion protection differ only through variables.
6. **GitHub Actions with OIDC.** Two manual workflows, each with a
   `staging` / `prod` dropdown. The Terraform workflow runs `fmt -check`,
   `validate`, `tflint` and `checkov`, then plans, applies that exact plan and
   adds an Infracost estimate to the run summary. It runs under the chosen
   GitHub Environment, so `prod` needs a manual approval. Apply roles trust
   only this repo's GitHub Environments (so AWS enforces the prod approval);
   never `repo:joheee/*`.
7. **Prove create and destroy.** A manually triggered `destroy` workflow (one
   environment at a time, needs approval; it keeps the environment's CI roles so
   it never cuts off its own access). One logged run where staging is created
   from nothing, the sample service answers through the ALB, and the whole
   environment is destroyed again. The run links are the proof.
8. **Client-style README.** Architecture diagram (draw.io or Mermaid), the
   bootstrap and first-apply steps, the outputs table, how to add a third
   environment, destroy steps, monthly cost per environment (Infracost), and
   links to the create and destroy runs.

## Out of scope

- EKS. My AwsBaseInfra repo already shows an EKS cluster, it adds about $73 a
  month per environment, and project 7 covers Kubernetes properly. The README
  can mention EKS as the alternative to the ECS module.
- App CI/CD (build, push, rolling deploy). That's project 4 (TicTacToeCICD).
  Here the service only runs a given image.
- Custom domain and HTTPS on the ALB. Optional stretch: ACM certificate plus a
  Route 53 or Cloudflare record. Until then the ALB serves HTTP.
- Multi-account setup (AWS Organizations, Control Tower). Both environments
  live in one account, separated by name prefix and state key.
- Running the TicTacToe app on this platform. Optional stretch once
  everything above is done.

## Constraints

- Region is `ap-southeast-2`; the account's org SCP blocks other regions.
- The SCP also denies `ec2:DescribeInstances`. Fargate needs no EC2
  instances, so this should not matter, but avoid data sources or modules
  that list instances.
- Keep it cheap: destroy environments when not demoing. Running costs are
  mostly NAT gateway, ALB and RDS.

## Plan (4 days)

| Day | Work |
|---|---|
| 1 | State bucket (by hand), OIDC lookup and plan/apply roles in the root module. Network module with routing, NAT and flow logs. Staging network applied. |
| 2 | ECS (cluster, ALB, service, roles, logs) and RDS modules with security groups and Secrets Manager. Sample service answers through the ALB in staging. |
| 3 | GitHub Actions: manual Terraform workflow (checks, plan, apply, Infracost) and destroy workflow, both with an environment dropdown; prod behind approval. |
| 4 | Prod environment, logged create-and-destroy run, diagram, cost estimate, README handover, Upwork portfolio entry. |

## Tools and software

Terraform (>= 1.10) · AWS provider 6.x · Amazon VPC · NAT gateway · Amazon ECS
on Fargate · Application Load Balancer · Amazon RDS for PostgreSQL · AWS
Secrets Manager · Amazon S3 (state) · AWS IAM + GitHub OIDC · CloudWatch Logs ·
GitHub Actions · tflint · checkov · Infracost · draw.io

## Definition of done

- [x] State bucket exists (hand-made); the root module creates the plan/apply roles against the existing GitHub OIDC provider. _(roles created by the first local apply of staging and prod)_
- [x] Network, ECS and RDS live in reusable modules with variables and outputs.
- [x] `staging` and `prod` deploy from the same code; only tfvars and the backend key differ. _(both applied from the same root module)_
- [ ] The sample service answers through the ALB; the database is reachable only from the service. _(ALB answers 200 in staging; the database restriction is by security-group design, not yet tested)_
- [ ] No AWS keys or database passwords in the repo or in Terraform state. _(by design; check the state once)_
- [ ] The Terraform workflow shows fmt, validate, tflint, checkov, plan and an Infracost estimate for the chosen environment. _(checks and plan run green on staging; checkov is still soft-fail; Infracost needs `INFRACOST_API_KEY`)_
- [ ] Staging applies from the workflow; prod applies only after approval. _(staging applied from the workflow after the CI role permissions were completed; the prod approval gate is not yet exercised)_
- [ ] A logged run creates staging from nothing, and another destroys it. _(the first workflow apply resumed from earlier failed runs, so it is not a clean create; destroy run in progress; a clean create run is still needed)_
- [ ] README has the diagram, bootstrap and destroy steps, outputs table, cost per environment and run links. _(written; cost and run links still to fill)_
