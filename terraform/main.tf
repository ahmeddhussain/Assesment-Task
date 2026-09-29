# 1. Networking Module (VPC, Subnets, NAT Gateway)
module "networking" {
  source               = "./modules/networking"
  environment          = var.environment
  vpc_cidr             = "10.0.0.0/16"
  public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnet_cidrs = ["10.0.3.0/24", "10.0.4.0/24"]
  availability_zones   = ["us-east-1a", "us-east-1b"]
}

# 2. Database Module (RDS MySQL 8.0, Encrypted, Private Subnets)
module "database" {
  source      = "./modules/database"
  environment = var.environment
  vpc_id      = module.networking.vpc_id
  subnet_ids  = module.networking.private_subnet_ids
  db_name     = var.db_name
  db_username = var.db_username
  db_password = var.db_password
}

# 3. Compute Module (ALB, ECS Fargate, ECR, SG Ingress Rule)
module "compute" {
  source                = "./modules/compute"
  environment           = var.environment
  vpc_id                = module.networking.vpc_id
  public_subnet_ids     = module.networking.public_subnet_ids
  private_subnet_ids    = module.networking.private_subnet_ids
  db_host               = module.database.db_endpoint
  db_name               = var.db_name
  db_username           = var.db_username
  db_password           = var.db_password
  db_security_group_id  = module.database.db_security_group_id
}

# 4. Monitoring Module (CloudWatch Logs, ALB 5XX Metric Alarm, SNS Alerts)
module "monitoring" {
  source         = "./modules/monitoring"
  environment    = var.environment
  alb_arn_suffix = module.compute.alb_arn_suffix
  alert_email    = var.alert_email
}