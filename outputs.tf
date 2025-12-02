output "ec2_public_ip" {
  value = aws_instance.web.public_ip
}

output "s3_bucket_name" {
  value = aws_s3_bucket.app_bucket.bucket
}

output "rds_endpoint" {
  value       = aws_db_instance.postgres.address
  description = "Postgres endpoint (5432)"
}

output "lambda_arn" {
  value = aws_lambda_function.s3_handler.arn
}
