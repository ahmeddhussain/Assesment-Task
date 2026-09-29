variable "environment" { type = string }
variable "db_host" { type = string }
variable "db_user" { type = string }
variable "db_password" { 
  type      = string 
  sensitive = true 
}
variable "db_name" { type = string }
variable "app_port" { 
  type    = string 
  default = "3000" 
}