variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "eu-west-1"
}

variable "project_name" {
  description = "Prefix for resource names"
  type        = string
  default     = "tf-lab"
}

variable "db_password" {
  description = "RDS master password"
  type        = string
  sensitive   = true
}
