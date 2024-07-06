variable "region" {
  default     = "us-east-1"
  description = "AWS region"
}

variable "db_user" {
  description = "RDS root user"
}

variable "db_password" {
#   sensitive   = true
  description = "RDS root user password"
}

variable "aws_access_key" {
  default     = "us-east-1"
  sensitive = true
  description = "aws access key"
}

variable "aws_secret_key" {
  sensitive   = true
  description = "aws secret key"
}