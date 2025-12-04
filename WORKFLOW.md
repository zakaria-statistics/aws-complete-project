# Workflow Overview

This project started as a small lab showcasing most AWS building blocks under Terraform. The sections below recap the original setup and highlight the new components that were just added to help you practice end-to-end interactions among Lambda, S3, and RDS.

## Previous State

- **S3**: A single private bucket with public access blocked. No automation was connected to new uploads.
- **Lambda**: One Node.js handler packaged in `lambda_payload.zip` that simply listed objects in the bucket when invoked manually.
- **RDS**: A single PostgreSQL instance (db.t3.micro) inside the public subnets, reachable only from the EC2 security group.
- **Automation**: No native workflow existed between these services. Practicing interactions meant logging into each resource manually (e.g., running `psql` from the EC2 instance or uploading sample files to S3).

## What's New

- **Dual Buckets & Object Replication**
  - Added a second S3 bucket (`backup_bucket`) and kept both private via access blocks.
  - Created an S3 event notification so every `ObjectCreated` event in the primary bucket invokes a new Lambda (`s3_replicator`).
  - The replicator Lambda copies the uploaded object into the backup bucket, providing an automatic two-bucket use case.

- **Dual RDS Instances, Seeding & Lambda Backup Flow**
  - Added a second PostgreSQL instance (`postgres_backup`) that mirrors the networking setup of the primary database.
  - Introduced a Lambda security group and attached the managed VPC access policy so Lambda functions can reach both DBs.
  - Added a `db_seed` Lambda that populates the `inventory_sample` table inside the primary DB as soon as Terraform finishes deploying.
  - Added a `db_backup` Lambda that connects to both databases, ensures the `inventory_sample` table exists, then truncates and reloads the backup DB with rows from the primary DB. It runs hourly through an EventBridge rule (and can be invoked on-demand).

- **Code Updates**
  - `index.js` now exports three handlers (`s3Replicator`, `dbSeed`, and `dbBackup`) and brings in the `pg` dependency to talk to PostgreSQL.
  - Terraform now passes bucket names, DB endpoints, and credentials to the functions through environment variables.

- **Outputs & Docs**
  - Terraform outputs include both bucket names, both DB endpoints, and each Lambda ARN, making it easier to test the flows.
  - The README details how to package the Lambda with dependencies and describes how to validate both S3 and database workflows.

## How to Use the Workflow

1. **Package & Deploy**
   - Run `npm install` followed by `zip -r lambda_payload.zip index.js node_modules package.json package-lock.json`.
   - Execute `terraform init`, `terraform plan`, and `terraform apply` to create the infrastructure.
   - The apply step automatically invokes the `db_seed` Lambda so `inventory_sample` in the primary DB contains starter rows for experimentation.

2. **Practice the S3 Flow**
   - Upload any file to the primary bucket output by Terraform.
   - Watch CloudWatch Logs for `s3_replicator` or list the backup bucket to confirm the replication.

3. **Practice the DB Backup Flow**
  - Connect to the primary DB (via EC2 or port-forward) and insert rows into `inventory_sample`.
  - Manually invoke the `db_backup` Lambda or wait for the hourly EventBridge trigger.
  - Query the backup DB to verify that rows were replicated.

This new setup creates tangible practice exercises that demonstrate how serverless compute can mediate data movement between both S3 buckets and RDS instances.

## Lambda, IAM, and S3 Components

| Component | Definition | Purpose / Interaction |
| --- | --- | --- |
| Lambda IAM role | `aws_iam_role.lambda_role` in `lambda.tf` | Trusts `lambda.amazonaws.com` so both functions can assume it. |
| Inline IAM policy | `aws_iam_role_policy.lambda_policy` | Grants CloudWatch Logs permissions, `s3:ListBucket` on both buckets, and object-level `Get/Put` for copies. |
| Managed policy attachment | `aws_iam_role_policy_attachment.lambda_vpc_access` | Adds the AWS-managed `AWSLambdaVPCAccessExecutionRole` so the DB backup function can create ENIs inside the VPC. |
| Lambda security group | `aws_security_group.lambda_sg` | Lets Lambda functions reach out to RDS. Referenced by both RDS SG ingress rules and the `db_backup` Lambda `vpc_config`. |
| Primary bucket | `aws_s3_bucket.app_bucket` | Source bucket for uploads; triggers the replicator Lambda. Public access is fully blocked via `aws_s3_bucket_public_access_block.app_bucket_pab`. |
| Backup bucket | `aws_s3_bucket.backup_bucket` | Destination bucket for replicated objects; also private with its own access block. |
| Bucket notification | `aws_s3_bucket_notification.app_bucket_notifications` | Subscribes the replicator Lambda to all `s3:ObjectCreated:*` events in the primary bucket. Requires `aws_lambda_permission.allow_s3_invoke`. |
| Replicator Lambda | `aws_lambda_function.s3_replicator` (`index.s3Replicator`) | Reads `SOURCE_BUCKET`/`DEST_BUCKET` env vars and copies uploaded keys via `CopyObject`. Runs outside the VPC because it only needs S3 access. |
| DB seeding Lambda | `aws_lambda_function.db_seed` (`index.seedPrimaryDb`) | Runs inside the VPC to insert starter rows into the primary database. Invoked automatically during Terraform apply via `aws_lambda_invocation.seed_primary_db`. |
| DB backup Lambda | `aws_lambda_function.db_backup` (`index.dbBackup`) | Uses the shared IAM role, but also joins the VPC to reach both RDS endpoints. Reads connection details from env vars and syncs the `inventory_sample` table. |
| DB seed invocation | `data.aws_lambda_invocation.seed_primary_db` | Forces Terraform to invoke the seeding Lambda once the DB is available so the primary database is ready for exercises. |
| EventBridge trigger | `aws_cloudwatch_event_rule.db_backup_schedule` + `aws_cloudwatch_event_target.db_backup_target` | Fires the DB backup Lambda hourly. Permission granted through `aws_lambda_permission.allow_eventbridge_invoke`. |

Together, these resources show how Lambda assumes IAM roles, uses IAM policies for S3 access, reacts to S3 events, and runs on a schedule—all while remaining least-privileged. Use this table as a map when navigating `lambda.tf`, `s3.tf`, and `index.js`.
