# AWS Terraform Lab

This repo provisions a small AWS environment that touches most core services—networking, compute, storage, database, serverless, and monitoring—while staying simple enough for experimentation.

## Architecture Overview

- **VPC** (`vpc.tf`): One VPC with DNS enabled, an Internet Gateway, and a single public subnet routed to the internet.
- **EC2 + IAM** (`ec2.tf`):
  - Security group allows SSH only from your public IP and HTTP from anywhere.
  - IAM role/policy gives the instance S3 access via an instance profile.
  - Latest Amazon Linux 2023 `t3.micro` boots Nginx through `user_data`.
- **S3** (`s3.tf`): Randomly suffixed app bucket plus a backup bucket. Object-created events on the primary bucket trigger a Lambda that copies files into the backup bucket.
- **Lambda** (`lambda.tf` + `index.js`): Three Node.js 20 functions—`s3_replicator` for bucket-to-bucket copies, `db_seed` to populate the primary Postgres table, and `db_backup` that connects to both RDS instances to sync the data.
- **RDS** (`rds.tf`): Primary PostgreSQL 16.1 instance and a second backup instance that you can keep in sync through the Lambda job.
- **CloudWatch** (`cloudwatch.tf`): CPUUtilization alarm against the EC2 instance.
- **Outputs** (`outputs.tf`): EC2 public IP, both S3 bucket names, both RDS endpoints, and the Lambda ARNs.

## Prerequisites

- Terraform ≥ 1.5
- AWS credentials with sufficient permissions (set via env vars or shared config)
- Zip utility for packaging the Lambda
- A value for `db_password` (set through `terraform.tfvars`, environment variable `TF_VAR_db_password`, or `-var`)

## Setup

1. **Package the Lambda**

   ```powershell
   npm install
   zip -r lambda_payload.zip index.js node_modules package.json package-lock.json
   ```

   Re-run the `zip` command every time you change the handler code or dependencies.

2. **Initialize Terraform**

   ```powershell
   terraform init
   ```

3. **Plan & Apply**

   ```powershell
   terraform plan
   terraform apply
   ```

   Confirm the plan output. Terraform will prompt for the DB password if you didn’t set it via vars.

4. **Review Outputs**

   After apply, note the EC2 IP, S3 bucket, RDS endpoint, and Lambda ARN in the CLI output.

## Validating the Stack

- **EC2**: Visit `http://<ec2_public_ip>` to see the Nginx landing page. SSH using the key pair associated with the instance (update the resource if you need a specific key).
- **Lambda (S3 replicator)**: Upload a file to the primary bucket output from Terraform. The S3 event notification invokes the replicator Lambda which copies the object to the backup bucket. Check CloudWatch Logs for `s3_replicator` or list the destination bucket to confirm.
- **Lambda (DB seeding)**: Terraform immediately invokes `db_seed` after the infrastructure comes online. Connect to the primary DB and query `inventory_sample` to confirm the starter rows are present. If you need to reseed, re-run the function manually.
- **Lambda (DB backup)**: The function runs hourly via EventBridge. You can also invoke it on-demand to copy rows from `inventory_sample` in the primary DB to the backup DB. Insert/update rows in the source table (via EC2 + `psql`) and rerun the function to observe the sync.
- **RDS**: From the EC2 box, connect with `psql -h <rds_endpoint> -U admin`. You can also tunnel via SSH from your machine if needed.
- **RDS backup flow**: Connect to both DB endpoints and query `inventory_sample`. The Lambda creates the table automatically and truncates it on the backup side before inserting fresh rows so you can easily confirm the replication.
- **S3**: Upload objects to the bucket and re-run the Lambda to confirm S3 access.
- **CloudWatch Alarm**: Stress the EC2 CPU (e.g., `yes > /dev/null`) to trigger the alarm.

## Cleanup

Destroy all resources when you’re done to avoid charges:

```powershell
terraform destroy
```

## Extensions

- Add private subnets + NAT, move RDS/Lambda there.
- Parameterize CIDR blocks and instance sizes for multi-environment deployments.
- Attach the CloudWatch alarm to an SNS topic or Auto Scaling policy.
- Introduce API Gateway in front of Lambda or Load Balancer in front of EC2 for more advanced scenarios.

---

Feel free to tailor the README with your own notes as you extend the lab.
