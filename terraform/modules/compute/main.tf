# --- Security Groups ---
resource "aws_security_group" "alb_sg" {
  name        = "${var.environment}-alb-sg"
  description = "Allow inbound HTTP from internet"
  vpc_id      = var.vpc_id

  ingress {
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
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  ingress {
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.environment}-ecs-sg" }
}

# Attach ingress rule from ECS SG into Database SG (breaks dependency cycle)
resource "aws_security_group_rule" "ecs_to_db" {
  type                     = "ingress"
  from_port                = 3306
  to_port                  = 3306
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.ecs_sg.id
  security_group_id        = var.db_security_group_id
}

# --- ALB & Target Groups ---
resource "aws_lb" "main" {
  name               = "${var.environment}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = var.public_subnet_ids
  tags               = { Name = "${var.environment}-alb" }
}

resource "aws_lb_target_group" "frontend" {
  name        = "${var.environment}-tg-frontend"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    path = "/"
    matcher = "200"
  }
}

resource "aws_lb_target_group" "backend" {
  name        = "${var.environment}-tg-backend"
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    path = "/health"
    matcher = "200"
  }
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
      values = ["/api/*"] # Only /api/* is public!
    }
  }
}

# --- ECS Cluster & IAM ---
resource "aws_ecs_cluster" "main" {
  name = "${var.environment}-ecs-cluster"
  tags = { Name = "${var.environment}-ecs-cluster" }
}

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

resource "aws_iam_role_policy_attachment" "ecs_execution_policy" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# --- ECR Repositories ---
resource "aws_ecr_repository" "frontend" {
  name                 = "${var.environment}-frontend"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
}

resource "aws_ecr_repository" "backend" {
  name                 = "${var.environment}-backend"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
}

# --- Task Definitions ---
resource "aws_ecs_task_definition" "backend" {
  family                   = "${var.environment}-backend-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn

  container_definitions = jsonencode([
    {
      name      = "backend"
      image     = "${aws_ecr_repository.backend.repository_url}:latest"
      essential = true
      portMappings = [{ containerPort = 3000, hostPort = 3000 }]
      
      # Pull ALL environment variables securely from Secrets Manager JSON keys
      secrets = [
        { name = "DB_HOST", valueFrom = "${var.app_secret_arn}:DB_HOST::" },
        { name = "DB_USER", valueFrom = "${var.app_secret_arn}:DB_USER::" },
        { name = "DB_PASS", valueFrom = "${var.app_secret_arn}:DB_PASS::" },
        { name = "DB_NAME", valueFrom = "${var.app_secret_arn}:DB_NAME::" },
        { name = "PORT",    valueFrom = "${var.app_secret_arn}:PORT::" }
      ]
      
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/${var.environment}-backend"
          "awslogs-region"        = "us-east-1"
          "awslogs-stream-prefix" = "backend"
          "awslogs-create-group"  = "true"
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
      name      = "frontend"
      image     = "${aws_ecr_repository.frontend.repository_url}:latest"
      essential = true
      portMappings = [{ containerPort = 8080, hostPort = 8080 }]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/${var.environment}-frontend"
          "awslogs-region"        = "us-east-1"
          "awslogs-stream-prefix" = "frontend"
          "awslogs-create-group"  = "true"
        }
      }
    }
  ])
}

# --- Services ---
resource "aws_ecs_service" "backend" {
  name            = "${var.environment}-backend-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.backend.arn
  launch_type     = "FARGATE"
  desired_count   = 1

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
}

resource "aws_ecs_service" "frontend" {
  name            = "${var.environment}-frontend-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.frontend.arn
  launch_type     = "FARGATE"
  desired_count   = 1

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
}

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
# Allow ECS to create CloudWatch Log Groups automatically
resource "aws_iam_role_policy" "ecs_logs_policy" {
  name = "${var.environment}-ecs-logs-policy"
  role = aws_iam_role.ecs_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogGroup"]
      Resource = "arn:aws:logs:us-east-1:*:log-group:/ecs/*"
    }]
  })
}