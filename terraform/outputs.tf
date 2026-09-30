output "application_url" {
  description = "Public Load Balancer URL for the Application"
  value       = "http://${module.compute.alb_dns_name}"
}

output "rds_endpoint" {
  description = "Private RDS MySQL Endpoint"
  value       = module.database.db_endpoint
}

output "ecs_cluster_name" {
  description = "ECS cluster name (used by the app deploy pipeline)"
  value       = module.compute.ecs_cluster_name
}
