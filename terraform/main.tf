# Use the region's real AZs instead of hardcoding them
data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 2)
}

# 1. Networking Module
module "networking" {
  source               = "./modules/networking"
  environment          = var.environment
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  availability_zones   = local.azs
}

# 2. Database Module (generates password and spins up encrypted RDS)
module "database" {
  source      = "./modules/database"
  environment = var.environment
  vpc_id      = module.networking.vpc_id
  subnet_ids  = module.networking.private_subnet_ids
  db_name     = var.db_name
}

# 3. Secrets Manager Module (bundles all app config into one secret)
module "secrets" {
  source      = "./modules/secrets"
  environment = var.environment
  db_host     = module.database.db_endpoint
  db_user     = module.database.db_user
  db_password = module.database.db_password
  db_name     = var.db_name
  app_port    = "3000"
}

# 4. Compute Module (ALB + ECS Fargate + ECR + log groups)
module "compute" {
  source               = "./modules/compute"
  environment          = var.environment
  vpc_id               = module.networking.vpc_id
  public_subnet_ids    = module.networking.public_subnet_ids
  private_subnet_ids   = module.networking.private_subnet_ids
  db_security_group_id = module.database.db_security_group_id
  app_secret_arn       = module.secrets.secret_arn
}

# 5. Monitoring Module (CloudWatch alarms + SNS email)
module "monitoring" {
  source                 = "./modules/monitoring"
  environment            = var.environment
  alert_email            = var.alert_email
  alb_arn_suffix         = module.compute.alb_arn_suffix
  backend_tg_arn_suffix  = module.compute.backend_tg_arn_suffix
  ecs_cluster_name       = module.compute.ecs_cluster_name
  backend_service_name   = module.compute.backend_service_name
  db_instance_identifier = module.database.db_instance_identifier
}
