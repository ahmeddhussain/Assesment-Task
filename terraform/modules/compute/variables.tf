variable "environment" { type = string }
variable "vpc_id" { type = string }
variable "public_subnet_ids" { type = list(string) }
variable "private_subnet_ids" { type = list(string) }
variable "db_security_group_id" { type = string }
variable "app_secret_arn" { type = string }

variable "log_retention_days" {
  type        = number
  description = "CloudWatch Logs retention for the ECS log groups"
  default     = 14
}
