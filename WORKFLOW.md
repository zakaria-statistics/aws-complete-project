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

- **Dual RDS Instances & Lambda Backup Flow**
  - Added a second PostgreSQL instance (`postgres_backup`) that mirrors the networking setup of the primary database.
  - Introduced a Lambda security group and attached the managed VPC access policy so Lambda functions can reach both DBs.
  - Added a `db_backup` Lambda that connects to both databases, ensures the `inventory_sample` table exists, then truncates and reloads the backup DB with rows from the primary DB. It runs hourly through an EventBridge rule (and can be invoked on-demand).

- **Code Updates**
  - `index.js` now exports two handlers (`s3Replicator` and `dbBackup`) and brings in the `pg` dependency to talk to PostgreSQL.
  - Terraform now passes bucket names, DB endpoints, and credentials to the functions through environment variables.

- **Outputs & Docs**
  - Terraform outputs include both bucket names, both DB endpoints, and each Lambda ARN, making it easier to test the flows.
  - The README details how to package the Lambda with dependencies and describes how to validate both S3 and database workflows.

## How to Use the Workflow

1. **Package & Deploy**
   - Run `npm install` followed by `zip -r lambda_payload.zip index.js node_modules package.json package-lock.json`.
   - Execute `terraform init`, `terraform plan`, and `terraform apply` to create the infrastructure.

2. **Practice the S3 Flow**
   - Upload any file to the primary bucket output by Terraform.
   - Watch CloudWatch Logs for `s3_replicator` or list the backup bucket to confirm the replication.

3. **Practice the DB Backup Flow**
   - Connect to the primary DB (via EC2 or port-forward) and insert rows into `inventory_sample`.
   - Manually invoke the `db_backup` Lambda or wait for the hourly EventBridge trigger.
   - Query the backup DB to verify that rows were replicated.

This new setup creates tangible practice exercises that demonstrate how serverless compute can mediate data movement between both S3 buckets and RDS instances.
