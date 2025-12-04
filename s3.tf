# Primary application bucket that users upload into.
resource "aws_s3_bucket" "app_bucket" {
  bucket = "${var.project_name}-bucket-${random_id.bucket_suffix.hex}"
}

# Backup bucket that receives copies via Lambda.
resource "aws_s3_bucket" "backup_bucket" {
  bucket = "${var.project_name}-backup-${random_id.bucket_suffix.hex}"
}

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket_public_access_block" "app_bucket_pab" {
  bucket = aws_s3_bucket.app_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "backup_bucket_pab" {
  bucket = aws_s3_bucket.backup_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Wire up the bucket to invoke Lambda on each new object.
resource "aws_s3_bucket_notification" "app_bucket_notifications" {
  bucket = aws_s3_bucket.app_bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.s3_replicator.arn
    events              = ["s3:ObjectCreated:*"]
  }

  depends_on = [aws_lambda_permission.allow_s3_invoke]
}
