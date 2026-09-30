variable "aws_region" {
  type        = string
  description = "AWS region"
  default     = "us-east-1"
}

variable "environment" {
  type        = string
  description = "Deployment environment"
  default     = "dev"
}

variable "db_name" {
  type        = string
  description = "Database name"
  default     = "devopsdb"
}

variable "alert_email" {
  type        = string
  description = "Email to receive CloudWatch 5XX error alerts"
  default     = "ahmedkhater2611@gmail.com"
}