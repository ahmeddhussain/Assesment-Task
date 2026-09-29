output "db_endpoint" { value = aws_db_instance.mysql.address }
output "db_security_group_id" { value = aws_security_group.db_sg.id }