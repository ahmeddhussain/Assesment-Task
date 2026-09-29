output "alb_dns_name" { value = aws_lb.main.dns_name }
output "alb_arn_suffix" { value = aws_lb.main.arn_suffix }
output "ecs_security_group_id" { value = aws_security_group.ecs_sg.id }
output "backend_ecr_url" { value = aws_ecr_repository.backend.repository_url }
output "frontend_ecr_url" { value = aws_ecr_repository.frontend.repository_url }