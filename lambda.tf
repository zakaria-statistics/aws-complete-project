# Shared IAM role used by both Lambda functions.
resource "aws_iam_role" "lambda_role" {
  name = "${var.project_name}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "lambda.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })
}

# Inline policy grants CloudWatch logging plus bucket access for replication.
resource "aws_iam_role_policy" "lambda_policy" {
  name = "${var.project_name}-lambda-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"],
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect  = "Allow",
        Action  = ["s3:ListBucket"],
        Resource = [
          aws_s3_bucket.app_bucket.arn,
          aws_s3_bucket.backup_bucket.arn
        ]
      },
      {
        Effect = "Allow",
        Action = ["s3:GetObject", "s3:PutObject"],
        Resource = [
          "${aws_s3_bucket.app_bucket.arn}/*",
          "${aws_s3_bucket.backup_bucket.arn}/*"
        ]
      }
    ]
  })
}

# Managed policy attachment so Lambdas can create ENIs inside the VPC.
resource "aws_iam_role_policy_attachment" "lambda_vpc_access" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# Security group referenced by the Lambda VPC config and RDS SG ingress.
resource "aws_security_group" "lambda_sg" {
  name        = "${var.project_name}-lambda-sg"
  description = "Allow Lambda access to RDS"
  vpc_id      = aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-lambda-sg"
  }
}

# Handles S3 ObjectCreated events and copies objects into the backup bucket.
resource "aws_lambda_function" "s3_replicator" {
  function_name = "${var.project_name}-lambda-s3-replicator"
  role          = aws_iam_role.lambda_role.arn
  handler       = "index.s3Replicator"
  runtime       = "nodejs20.x"
  timeout       = 30

  environment {
    variables = {
      SOURCE_BUCKET = aws_s3_bucket.app_bucket.bucket
      DEST_BUCKET   = aws_s3_bucket.backup_bucket.bucket
    }
  }

  filename         = "${path.module}/lambda_payload.zip"
  source_code_hash = filebase64sha256("${path.module}/lambda_payload.zip")
}

# Runs inside the VPC to read/write both Postgres instances for backups.
resource "aws_lambda_function" "db_backup" {
  function_name = "${var.project_name}-lambda-db-backup"
  role          = aws_iam_role.lambda_role.arn
  handler       = "index.dbBackup"
  runtime       = "nodejs20.x"
  timeout       = 60
  memory_size   = 512

  vpc_config {
    subnet_ids         = [aws_subnet.public_a.id, aws_subnet.public_b.id]
    security_group_ids = [aws_security_group.lambda_sg.id]
  }

  environment {
    variables = {
      SOURCE_DB_HOST = aws_db_instance.postgres.address
      SOURCE_DB_NAME = aws_db_instance.postgres.db_name
      SOURCE_DB_PORT = aws_db_instance.postgres.port
      TARGET_DB_HOST = aws_db_instance.postgres_backup.address
      TARGET_DB_NAME = aws_db_instance.postgres_backup.db_name
      TARGET_DB_PORT = aws_db_instance.postgres_backup.port
      DB_USER        = aws_db_instance.postgres.username
      DB_PASSWORD    = var.db_password
      TABLE_NAME     = "inventory_sample"
    }
  }

  filename         = "${path.module}/lambda_payload.zip"
  source_code_hash = filebase64sha256("${path.module}/lambda_payload.zip")
}

# Seeds the primary database with starter rows so the backup workflow has data.
resource "aws_lambda_function" "db_seed" {
  function_name = "${var.project_name}-lambda-db-seed"
  role          = aws_iam_role.lambda_role.arn
  handler       = "index.seedPrimaryDb"
  runtime       = "nodejs20.x"
  timeout       = 30
  memory_size   = 256

  vpc_config {
    subnet_ids         = [aws_subnet.public_a.id, aws_subnet.public_b.id]
    security_group_ids = [aws_security_group.lambda_sg.id]
  }

  environment {
    variables = {
      SOURCE_DB_HOST = aws_db_instance.postgres.address
      SOURCE_DB_NAME = aws_db_instance.postgres.db_name
      SOURCE_DB_PORT = aws_db_instance.postgres.port
      DB_USER        = aws_db_instance.postgres.username
      DB_PASSWORD    = var.db_password
      TABLE_NAME     = "inventory_sample"
      SEED_ROWS = jsonencode([
        { item_id = 1, item_name = "Widget Alpha", quantity = 25 },
        { item_id = 2, item_name = "Widget Beta", quantity = 12 },
        { item_id = 3, item_name = "Widget Gamma", quantity = 7 }
      ])
    }
  }

  filename         = "${path.module}/lambda_payload.zip"
  source_code_hash = filebase64sha256("${path.module}/lambda_payload.zip")
}

resource "aws_lambda_permission" "allow_s3_invoke" {
  statement_id  = "AllowExecutionFromS3"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.s3_replicator.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.app_bucket.arn
}

# EventBridge schedule to run the DB backup every hour.
resource "aws_cloudwatch_event_rule" "db_backup_schedule" {
  name                = "${var.project_name}-db-backup-schedule"
  description         = "Invoke the DB backup Lambda once per hour"
  schedule_expression = "rate(1 hour)"
}

resource "aws_cloudwatch_event_target" "db_backup_target" {
  rule = aws_cloudwatch_event_rule.db_backup_schedule.name
  arn  = aws_lambda_function.db_backup.arn
}

resource "aws_lambda_permission" "allow_eventbridge_invoke" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.db_backup.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.db_backup_schedule.arn
}

# Invoke the seeding Lambda during apply so the primary DB has data immediately.
data "aws_lambda_invocation" "seed_primary_db" {
  depends_on = [aws_lambda_function.db_seed, aws_db_instance.postgres]

  function_name = aws_lambda_function.db_seed.function_name
  input         = jsonencode({})
}
