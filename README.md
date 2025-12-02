# AWS Terraform Lab

This repo provisions a small AWS environment that touches most core services—networking, compute, storage, database, serverless, and monitoring—while staying simple enough for experimentation.

## Architecture Overview

- **VPC** (`vpc.tf`): One VPC with DNS enabled, an Internet Gateway, and a single public subnet routed to the internet.
- **EC2 + IAM** (`ec2.tf`):
  - Security group allows SSH only from your public IP and HTTP from anywhere.
  - IAM role/policy gives the instance S3 access via an instance profile.
  - Latest Amazon Linux 2023 `t3.micro` boots Nginx through `user_data`.
- **S3** (`s3.tf`): Randomly suffixed bucket plus Public Access Block to enforce private storage.
- **Lambda** (`lambda.tf` + `index.js`): Node.js 20 function with permissions for CloudWatch Logs and S3.
- **RDS** (`rds.tf`): PostgreSQL 16.1 instance in the subnet group, reachable only from the EC2 SG.
- **CloudWatch** (`cloudwatch.tf`): CPUUtilization alarm against the EC2 instance.
- **Outputs** (`outputs.tf`): EC2 public IP, S3 bucket name, RDS endpoint, Lambda ARN.

## Prerequisites

- Terraform ≥ 1.5
- AWS credentials with sufficient permissions (set via env vars or shared config)
- Zip utility for packaging the Lambda
- A value for `db_password` (set through `terraform.tfvars`, environment variable `TF_VAR_db_password`, or `-var`)

## Setup

1. **Package the Lambda**

   ```powershell
   zip lambda_payload.zip index.js
   ```

   Include `node_modules` if you add dependencies.

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
- **Lambda**: Test-invoke from the AWS Console or CLI. Set the `BUCKET_NAME` environment variable (via console or extend Terraform) so the function can list bucket contents.
- **RDS**: From the EC2 box, connect with `psql -h <rds_endpoint> -U admin`. You can also tunnel via SSH from your machine if needed.
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
