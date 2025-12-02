variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-west-2"
}

variable "aws_access_key" {
  description = "AWS Access Key"
  type        = string

}

variable "aws_secret_key" {
  description = "AWS Secret Key"
  type        = string
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
  default     = "StrongPassw0rd!"
}

variable "ssh_key_name" {
  description = "Name of an existing EC2 key pair to use for SSH"
  type        = string
  default     = "ec2-key-ssh"
}

