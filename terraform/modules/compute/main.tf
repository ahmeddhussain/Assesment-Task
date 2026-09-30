data "aws_region" "current" {}

# ==========================================
# 1. SECURITY GROUPS
# ==========================================

resource "aws_security_group" "alb_sg" {
  name        = "${var.environment}-alb-sg"
  description = "Allow inbound HTTP from internet"
  vpc_id      = var.vpc_id

  ingress {
    description = "Public HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.environment}-alb-sg" }
}

resource "aws_security_group" "ecs_sg" {
  name        = "${var.environment}-ecs-sg"
  description = "Allow traffic strictly from ALB"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Frontend from ALB only"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  ingress {
    description     = "Backend API from ALB only"
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  # Egress is needed to reach ECR, Secrets Manager and CloudWatch through the NAT Gateway
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.environment}-ecs-sg" }
}

# Only the ECS tasks may reach the database (attached here to avoid a dependency cycle)
resource "aws_security_group_rule" "ecs_to_db" {
  type                     = "ingress"
  description              = "MySQL from ECS tasks only"
  from_port                = 3306
  to_port                  = 3306
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.ecs_sg.id
  security_group_id        = var.db_security_group_id
}

# ==========================================
# 2. ALB & TARGET GROUPS
# ==========================================

resource "aws_lb" "main" {
  name                       = "${var.environment}-alb"
  internal                   = false
  load_balancer_type         = "application"
  security_groups            = [aws_security_group.alb_sg.id]
  subnets                    = var.public_subnet_ids
  drop_invalid_header_fields = true
  enable_deletion_protection = false # assessment only - true in production
  tags                       = { Name = "${var.environment}-alb" }
}

resource "aws_lb_target_group" "frontend" {
  name        = "${var.environment}-tg-frontend"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    path    = "/"
    matcher = "200"
  }

  tags = { Name = "${var.environment}-tg-frontend" }
}

resource "aws_lb_target_group" "backend" {
  name        = "${var.environment}-tg-backend"
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    path    = "/health"
    matcher = "200"
  }

  tags = { Name = "${var.environment}-tg-backend" }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.frontend.arn
  }
}

resource "aws_lb_listener_rule" "backend_rule" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend.arn
  }

  condition {
    path_pattern {
      values = ["/api/*"] # Only /api/* is public; /metrics is never routed
    }
  }
}

# ==========================================
# 3. ECS CLUSTER & IAM
# ==========================================

resource "aws_ecs_cluster" "main" {
  name = "${var.environment}-ecs-cluster"
  tags = { Name = "${var.environment}-ecs-cluster" }
}

# Execution role: used by the ECS agent to pull images, write logs and fetch secrets.
# There is intentionally NO task role - the application code has zero AWS permissions.
resource "aws_iam_role" "ecs_execution_role" {
  name = "${var.environment}-ecs-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

# AWS-managed: ECR pull + CloudWatch Logs CreateLogStream/PutLogEvents
resource "aws_iam_role_policy_attachment" "ecs_execution_policy" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Least privilege: read exactly ONE secret (log groups are now created by Terraform,
# so the old logs:CreateLogGroup permission is no longer needed)
resource "aws_iam_role_policy" "ecs_secrets_policy" {
  name = "${var.environment}-ecs-secrets-policy"
  role = aws_iam_role.ecs_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = [var.app_secret_arn]
    }]
  })
}

# ==========================================
# 4. ECR REPOSITORIES
# ==========================================

resource "aws_ecr_repository" "frontend" {
  name                 = "${var.environment}-frontend"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true # assessment only

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = { Name = "${var.environment}-frontend" }
}

resource "aws_ecr_repository" "backend" {
  name                 = "${var.environment}-backend"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = { Name = "${var.environment}-backend" }
}

# Keep storage costs bounded: retain only the 10 most recent images
resource "aws_ecr_lifecycle_policy" "keep_recent" {
  for_each   = { frontend = aws_ecr_repository.frontend.name, backend = aws_ecr_repository.backend.name }
  repository = each.value

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 10 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}

# ==========================================
# 5. CLOUDWATCH LOG GROUPS (managed, with retention)
# ==========================================

resource "aws_cloudwatch_log_group" "backend" {
  name              = "/ecs/${var.environment}-backend"
  retention_in_days = var.log_retention_days
  tags              = { Name = "${var.environment}-backend-logs" }
}

resource "aws_cloudwatch_log_group" "frontend" {
  name              = "/ecs/${var.environment}-frontend"
  retention_in_days = var.log_retention_days
  tags              = { Name = "${var.environment}-frontend-logs" }
}

# ==========================================
# 6. TASK DEFINITIONS
# ==========================================

resource "aws_ecs_task_definition" "backend" {
  family                   = "${var.environment}-backend-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn

  container_definitions = jsonencode([
    {
      name  = "backend"
      image = "${aws_ecr_repository.backend.repository_url}:latest" # Bootstrap image only. CI/CD replaces this with an immutable Git SHA tag.

      essential    = true
      portMappings = [{ containerPort = 3000, hostPort = 3000 }]

      # Secrets are injected at container start from Secrets Manager JSON keys
      secrets = [
        { name = "DB_HOST", valueFrom = "${var.app_secret_arn}:DB_HOST::" },
        { name = "DB_USER", valueFrom = "${var.app_secret_arn}:DB_USER::" },
        { name = "DB_PASS", valueFrom = "${var.app_secret_arn}:DB_PASS::" },
        { name = "DB_NAME", valueFrom = "${var.app_secret_arn}:DB_NAME::" },
        { name = "PORT", valueFrom = "${var.app_secret_arn}:PORT::" }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.backend.name
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" = "backend"
        }
      }
    }
  ])
}

resource "aws_ecs_task_definition" "frontend" {
  family                   = "${var.environment}-frontend-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn

  container_definitions = jsonencode([
    {
      name  = "frontend"
      image = "${aws_ecr_repository.frontend.repository_url}:latest" # Bootstrap image only. CI/CD replaces this with an immutable Git SHA tag.

      essential    = true
      portMappings = [{ containerPort = 8080, hostPort = 8080 }]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.frontend.name
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" = "frontend"
        }
      }
    }
  ])
}

# ==========================================
# 7. ECS SERVICES
# ==========================================

resource "aws_ecs_service" "backend" {
  name                              = "${var.environment}-backend-service"
  cluster                           = aws_ecs_cluster.main.id
  task_definition                   = aws_ecs_task_definition.backend.arn
  launch_type                       = "FARGATE"
  desired_count                     = 1
  health_check_grace_period_seconds = 60

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.ecs_sg.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.backend.arn
    container_name   = "backend"
    container_port   = 3000
  }

  # A bad release rolls back automatically instead of taking the service down
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  depends_on = [aws_lb_listener_rule.backend_rule]

  # The CI pipeline registers new task-definition revisions (image :<git-sha>);
  # Terraform must not revert them on the next apply.
  lifecycle {
    ignore_changes = [task_definition]
  }

  tags = { Name = "${var.environment}-backend-service" }
}

resource "aws_ecs_service" "frontend" {
  name                              = "${var.environment}-frontend-service"
  cluster                           = aws_ecs_cluster.main.id
  task_definition                   = aws_ecs_task_definition.frontend.arn
  launch_type                       = "FARGATE"
  desired_count                     = 1
  health_check_grace_period_seconds = 60

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.ecs_sg.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.frontend.arn
    container_name   = "frontend"
    container_port   = 8080
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  depends_on = [aws_lb_listener.http]

  lifecycle {
    ignore_changes = [task_definition]
  }

  tags = { Name = "${var.environment}-frontend-service" }
}
