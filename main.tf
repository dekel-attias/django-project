# Define the AWS provider and region
provider "aws" {
  region  = var.aws_region
  profile = "654654205521_AdministratorAccess"
}

# Define variables for user input
variable "aws_region" {
  description = "The AWS region to deploy the resources in."
  type        = string
  default     = "us-east-1"
}

variable "ecs_service_port" {
  description = "The port that the ECS service will be listening on."
  type        = number
  default     = 8080
}

variable "deploy_ecs_services" {
  description = "Set to true to deploy the ECS services, false otherwise."
  type        = bool
  default     = false
}

# Data source to retrieve a list of availability zones
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

# -----------------------------------------------------------------------------
# VPC and Networking
# -----------------------------------------------------------------------------

# Define the VPC
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "ecs-private-vpc"
  }
}

# Create an Internet Gateway for the public subnets
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "ecs-private-vpc-igw"
  }
}

# Public Subnets
resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.${count.index + 1}.0/24"
  map_public_ip_on_launch = true
  availability_zone       = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "ecs-public-subnet-${count.index + 1}"
  }
}

# Private Subnets
resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.${count.index + 3}.0/24"
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "ecs-private-subnet-${count.index + 1}"
  }
}

# -----------------------------------------------------------------------------
# Routing
# -----------------------------------------------------------------------------

# Route Table for public subnets
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "public-route-table"
  }
}

# Associate public route table with public subnets
resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Route Tables for private subnets
resource "aws_route_table" "private" {
  count  = 2
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "private-route-table-${count.index + 1}"
  }
}

# Associate private route tables with private subnets
resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# -----------------------------------------------------------------------------
# Security Groups
# -----------------------------------------------------------------------------

# Security Group for the ALB
resource "aws_security_group" "alb" {
  vpc_id      = aws_vpc.main.id
  name        = "alb-sg"
  description = "Allow HTTP inbound traffic to the ALB"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow outbound traffic to the entire VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  tags = {
    Name = "alb-sg"
  }
}

# Security Group for ECS tasks
resource "aws_security_group" "ecs_tasks" {
  vpc_id      = aws_vpc.main.id
  name        = "ecs-tasks-sg"
  description = "Allow traffic from ALB to ECS tasks and outbound to VPC Endpoints"

  ingress {
    from_port       = var.ecs_service_port
    to_port         = var.ecs_service_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "Allow outbound HTTPS traffic to VPC Endpoints"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ecs-tasks-sg"
  }
}

# VPC Endpoint Security Group
resource "aws_security_group" "vpce" {
  name        = "vpce-sg"
  description = "Allow HTTPS access to VPC Endpoints"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  tags = {
    Name = "vpce-sg"
  }
}

# -----------------------------------------------------------------------------
# Application Load Balancer
# -----------------------------------------------------------------------------

# ALB resource
resource "aws_lb" "ecs_alb" {
  name               = "ecs-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [for subnet in aws_subnet.public : subnet.id]

  tags = {
    Name = "ecs-alb"
  }
}

# Target Group for the ALB
resource "aws_lb_target_group" "ecs_tg" {
  name        = "ecs-tg"
  port        = var.ecs_service_port
  protocol    = "HTTP" # Target group always listens on HTTP
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  tags = {
    Name = "ecs-tg"
  }
}

# ALB Listener
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.ecs_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ecs_tg.arn
  }
}

# -----------------------------------------------------------------------------
# VPC Endpoints
# -----------------------------------------------------------------------------

# ECR API and Docker Registry endpoints are required for ECS to pull images
resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.api"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  security_group_ids  = [aws_security_group.vpce.id]
  subnet_ids          = [for subnet in aws_subnet.private : subnet.id]
}

resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  security_group_ids  = [aws_security_group.vpce.id]
  subnet_ids          = [for subnet in aws_subnet.private : subnet.id]
}

# S3 Gateway Endpoint for ECR image layers
resource "aws_vpc_endpoint" "s3_gateway" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [for rt in aws_route_table.private : rt.id]
}

# VPC endpoint for ECS
resource "aws_vpc_endpoint" "ecs" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ecs"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  security_group_ids  = [aws_security_group.vpce.id]
  subnet_ids          = [for subnet in aws_subnet.private : subnet.id]
}

# VPC endpoint for CloudWatch Logs
resource "aws_vpc_endpoint" "logs" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.logs"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  security_group_ids  = [aws_security_group.vpce.id]
  subnet_ids          = [for subnet in aws_subnet.private : subnet.id]
}

# VPC endpoint for DynamoDB
resource "aws_vpc_endpoint" "dynamodb" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.eu-central-1.dynamodb"
  route_table_ids   = [for rt in aws_route_table.private : rt.id]
  vpc_endpoint_type = "Gateway"
}

# -----------------------------------------------------------------------------
# ECS Resources
# -----------------------------------------------------------------------------

# ECR Repository to store the Docker image
resource "aws_ecr_repository" "app_repo" {
  name = "hello-world-app"
}

# IAM role for ECS tasks to pull images from ECR
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "ecs-task-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      },
    ]
  })
}

# IAM policy to allow ECS tasks to access ECR and CloudWatch logs
resource "aws_iam_role_policy_attachment" "ecs_task_execution_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ECS Cluster
resource "aws_ecs_cluster" "main" {
  name = "hello-world-cluster"
}

# ECS Task Definition
resource "aws_ecs_task_definition" "app_task" {
  family                   = "hello-world-app-family"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "hello-world-container"
      image     = "${aws_ecr_repository.app_repo.repository_url}:latest"
      cpu       = 256
      memory    = 512
      essential = true
      portMappings = [
        {
          containerPort = var.ecs_service_port
          hostPort      = var.ecs_service_port
          protocol      = "tcp"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/hello-world-app"
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])
}

# CloudWatch Log Group for the ECS tasks
resource "aws_cloudwatch_log_group" "app_log_group" {
  name = "/ecs/hello-world-app"
}

# ECS Service 1
resource "aws_ecs_service" "app_service" {
  count           = var.deploy_ecs_services ? 1 : 0
  name            = "hello-world-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app_task.arn
  desired_count   = 2 # Deploy 2 tasks for high availability
  launch_type     = "FARGATE"

  network_configuration {
    security_groups = [aws_security_group.ecs_tasks.id]
    subnets         = [for subnet in aws_subnet.private : subnet.id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.ecs_tg.arn
    container_name   = "hello-world-container"
    container_port   = var.ecs_service_port
  }
}

resource "aws_iam_role" "ecs_task_role" {
  name = "ecs-task-dynamodb-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      },
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_policy" "ecs_dynamodb_write_policy" {
  name        = "ecs-dynamodb-write"
  description = "Allow ECS tasks to write to the user_messages DynamoDB table"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "dynamodb:PutItem"
        ],
        Resource = "arn:aws:dynamodb:eu-central-1:${data.aws_caller_identity.current.account_id}:table/user_messages"
      }
    ]
  })
}


resource "aws_iam_role_policy_attachment" "attach_policy" {
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = aws_iam_policy.ecs_dynamodb_write_policy.arn
}

# DynamoDB table

resource "aws_dynamodb_table" "user_messages" {
  name         = "user_messages"
  billing_mode = "PAY_PER_REQUEST" # no need to manage read/write capacity
  hash_key     = "message_id"

  attribute {
    name = "message_id"
    type = "S" # S = String
  }

  stream_enabled   = true
  stream_view_type = "NEW_IMAGE" # Triggers with full new row content

  tags = {
    Environment = "dev"
    Project     = "ecs-message-api"
  }
}


# Lambda

resource "aws_iam_role" "lambda_role" {
  name = "lambda-dynamo-to-s3-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = {
        Service = "lambda.amazonaws.com"
      },
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_policy" "lambda_dynamodb_policy" {
  name = "lambda-dynamo-read"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "dynamodb:GetRecords",
          "dynamodb:GetShardIterator",
          "dynamodb:DescribeStream",
          "dynamodb:ListStreams"
        ],
        Resource = aws_dynamodb_table.user_messages.stream_arn
      },
      {
        Effect = "Allow",
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "attach_lambda_policy" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_dynamodb_policy.arn
}

resource "aws_lambda_function" "message_handler" {
  function_name = "dynamo-stream-to-s3"
  handler       = "handler.lambda_handler"
  runtime       = "python3.9"
  role          = aws_iam_role.lambda_role.arn
  timeout       = 10

  filename = "../lambda/lambda.zip" # You’ll provide this zip file

  source_code_hash = filebase64sha256("../lambda/lambda.zip")

  environment {
  variables = {
    SNS_TOPIC_ARN = aws_sns_topic.message_alerts.arn
  }
}
}

resource "aws_lambda_event_source_mapping" "dynamo_trigger" {
  event_source_arn  = aws_dynamodb_table.user_messages.stream_arn
  function_name     = aws_lambda_function.message_handler.arn
  starting_position = "LATEST"
  batch_size        = 1
  enabled           = true
}

resource "aws_iam_policy" "lambda_s3_write_policy" {
  name = "lambda-s3-write-policy"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "s3:PutObject"
        ],
        Resource = "${aws_s3_bucket.message_bucket.arn}/*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "attach_lambda_s3_policy" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_s3_write_policy.arn
}

# SNS

resource "aws_sns_topic" "message_alerts" {
  name = "user-message-alerts"
}

resource "aws_sns_topic_subscription" "email_sub" {
  topic_arn = aws_sns_topic.message_alerts.arn
  protocol  = "email"
  endpoint  = "guy.dankovich@gmail.com"
}

resource "aws_iam_policy" "lambda_publish_sns" {
  name = "lambda-publish-to-message-alerts"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = "sns:Publish",
        Resource = aws_sns_topic.message_alerts.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "attach_lambda_publish_sns" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_publish_sns.arn
}

# S3 Bucket
resource "aws_s3_bucket" "message_bucket" {
  bucket = "guyd-test-message-bucket-${data.aws_caller_identity.current.account_id}" # must be globally unique

  tags = {
    Name        = "message-bucket"
    Environment = "dev"
  }
}

resource "aws_s3_bucket_versioning" "message_bucket_versioning" {
  bucket = aws_s3_bucket.message_bucket.id

  versioning_configuration {
    status = "Enabled"
  }
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "vpc_id" {
  description = "The ID of the new VPC."
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets."
  value       = [for subnet in aws_subnet.public : subnet.id]
}

output "private_subnet_ids" {
  description = "IDs of the private subnets."
  value       = [for subnet in aws_subnet.private : subnet.id]
}

output "alb_dns_name" {
  description = "The DNS name of the Application Load Balancer."
  value       = aws_lb.ecs_alb.dns_name
}

output "ecs_security_group_id" {
  description = "The ID of the security group for ECS tasks."
  value       = aws_security_group.ecs_tasks.id
}

output "target_group_arn" {
  description = "The ARN of the Target Group for ECS tasks."
  value       = aws_lb_target_group.ecs_tg.arn
}

output "ecr_repository_url" {
  description = "The URL of the ECR repository to push your Docker image to."
  value       = aws_ecr_repository.app_repo.repository_url
}

output "ecs_cluster_name" {
  description = "The name of the ECS cluster."
  value       = aws_ecs_cluster.main.name
}
