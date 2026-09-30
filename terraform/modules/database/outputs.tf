output "db_endpoint" { value = aws_db_instance.mysql.address }
output "db_user" { value = aws_db_instance.mysql.username }
output "db_password" {
  value     = random_password.db_password.result
  sensitive = true
}
output "db_security_group_id" { value = aws_security_group.db_sg.id }
output "db_instance_identifier" { value = aws_db_instance.mysql.identifier }
