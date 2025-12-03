output "ec2_public_ip" {
  value = aws_instance.web.public_ip
}

output "primary_bucket_name" {
  value = aws_s3_bucket.app_bucket.bucket
}

output "backup_bucket_name" {
  value = aws_s3_bucket.backup_bucket.bucket
}

output "rds_endpoint" {
  value       = aws_db_instance.postgres.address
  description = "Postgres endpoint (5432)"
}

output "rds_backup_endpoint" {
  value       = aws_db_instance.postgres_backup.address
  description = "Backup Postgres endpoint (5432)"
}

output "s3_replicator_lambda_arn" {
  value = aws_lambda_function.s3_replicator.arn
}

output "db_backup_lambda_arn" {
  value = aws_lambda_function.db_backup.arn
}
