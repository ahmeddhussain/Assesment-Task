# 1. Random password (never typed or committed by a human)
resource "random_password" "db_password" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# 2. Subnet group (private subnets only)
resource "aws_db_subnet_group" "db_subnets" {
  name       = "${var.environment}-db-subnet-group"
  subnet_ids = var.subnet_ids
  tags       = { Name = "${var.environment}-db-subnet-group" }
}

# 3. Security group - no egress rules (RDS never initiates connections);
#    the ingress rule (3306 from the ECS SG only) is attached by the compute module.
resource "aws_security_group" "db_sg" {
  name        = "${var.environment}-db-sg"
  description = "Database Security Group"
  vpc_id      = var.vpc_id
  tags        = { Name = "${var.environment}-db-sg" }
}

# 4. RDS instance
resource "aws_db_instance" "mysql" {
  identifier                 = "${var.environment}-mysql-db"
  engine                     = "mysql"
  engine_version             = "8.0"
  instance_class             = "db.t3.micro"
  allocated_storage          = 20
  storage_type               = "gp2"
  storage_encrypted          = true # Encryption at rest
  db_name                    = var.db_name
  username                   = "dbadmin"
  password                   = random_password.db_password.result
  db_subnet_group_name       = aws_db_subnet_group.db_subnets.name
  vpc_security_group_ids     = [aws_security_group.db_sg.id]
  publicly_accessible        = false
  multi_az                   = false # single-AZ to save cost - see README
  backup_retention_period    = 1
  auto_minor_version_upgrade = true
  skip_final_snapshot        = true # assessment only - would be false in production
  tags                       = { Name = "${var.environment}-mysql-db" }
}
