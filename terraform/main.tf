# 1. Networking Module
module "networking" {
  source               = "./modules/networking"
  environment          = var.environment
  vpc_cidr             = "10.0.0.0/16"
  public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnet_cidrs = ["10.0.3.0/24", "10.0.4.0/24"]
  availability_zones   = ["us-east-1a", "us-east-1b"]
}

# 2. Database Module (Generates password and spins up encrypted RDS)
module "database" {
  source      = "./modules/database"
  environment = var.environment
  vpc_id      = module.networking.vpc_id
  subnet_ids  = module.networking.private_subnet_ids
  db_name     = var.db_name
}

# 3. Secrets Manager Module (Bundles all config into Secrets Manager)
module "secrets" {
  source      = "./modules/secrets"
  environment = var.environment
  db_host     = module.database.db_endpoint
  db_user     = module.database.db_user
  db_password = module.database.db_password
  db_name     = var.db_name
  app_port    = "3000"
}

# 4. Compute Module (ALB + ECS Fargate pulling from Secrets Manager)
module "compute" {
  source               = "./modules/compute"
  environment          = var.environment
  vpc_id               = module.networking.vpc_id
  public_subnet_ids    = module.networking.public_subnet_ids
  private_subnet_ids   = module.networking.private_subnet_ids
  db_security_group_id = module.database.db_security_group_id
  app_secret_arn       = module.secrets.secret_arn
}

# 5. Monitoring Module (CloudWatch Alarms & SNS)
module "monitoring" {
  source         = "./modules/monitoring"
  environment    = var.environment
  alb_arn_suffix = module.compute.alb_arn_suffix
  alert_email    = var.alert_email
}