resource "aws_cloudwatch_log_group" "ctfd" {
  name = var.app_name

  tags = {
    Environment = "production"
    Application = var.app_name
  }
}

resource "aws_secretsmanager_secret" "database_url" {
  name                           = "database_url"
  force_overwrite_replica_secret = true
  recovery_window_in_days        = 0
}

resource "aws_secretsmanager_secret_version" "database_url" {
  secret_id     = aws_secretsmanager_secret.database_url.id
  secret_string = var.db_connection_string
}

resource "aws_secretsmanager_secret" "redis_url" {
  count                          = var.cache_connection_string != null ? 1 : 0
  name                           = "redis_url"
  force_overwrite_replica_secret = true
  recovery_window_in_days        = 0
}

resource "aws_secretsmanager_secret_version" "redis_url" {
  count     = var.cache_connection_string != null ? 1 : 0
  secret_id = aws_secretsmanager_secret.redis_url[0].id
  secret_string = var.cache_connection_string
}

resource "aws_secretsmanager_secret" "ctfd_secret" {
  name                           = "ctfd_secret"
  force_overwrite_replica_secret = true
  recovery_window_in_days        = 0
}

resource "aws_secretsmanager_secret_version" "ctfd_secret" {
  secret_id     = aws_secretsmanager_secret.ctfd_secret.id
  secret_string = var.ctfd_secret_key
}

resource "aws_secretsmanager_secret" "registry_creds" {
  count                          = var.registry_password != null ? 1 : 0
  name                           = "registry_creds"
  force_overwrite_replica_secret = true
  recovery_window_in_days        = 0
}

resource "aws_secretsmanager_secret_version" "registry_creds" {
  count     = var.registry_password != null ? 1 : 0
  secret_id = aws_secretsmanager_secret.registry_creds[0].id
  secret_string = jsonencode({
    "username" = var.registry_username,
    "password" = var.registry_password
  })
}

data "aws_region" "current" {}

module "container_definition" {
  source                   = "cloudposse/ecs-container-definition/aws"
  version                  = "0.61.1"
  container_name           = var.app_name
  container_image          = var.ctfd_image
  container_memory         = 1024
  container_cpu            = 512
  readonly_root_filesystem = false

  repository_credentials = var.registry_password != null ? { credentialsParameter = aws_secretsmanager_secret_version.registry_creds[0].arn } : null
  log_configuration = {
    logDriver = "awslogs"
    options = {
      awslogs-group         = aws_cloudwatch_log_group.ctfd.name
      awslogs-region        = data.aws_region.current.id
      awslogs-stream-prefix = var.app_name
    }
  }
  secrets = concat(
    [
      {
        name      = "DATABASE_URL",
        valueFrom = aws_secretsmanager_secret.database_url.arn
      },
      {
        name      = "SECRET_KEY",
        valueFrom = aws_secretsmanager_secret.ctfd_secret.arn
      }
    ],
    var.cache_connection_string != null ? [
      {
        name      = "REDIS_URL",
        valueFrom = aws_secretsmanager_secret.redis_url[0].arn
      }
    ] : []
  )
  environment = [
    {
      name  = "WORKERS"
      value = 3
    },
    {
      name  = "REVERSE_PROXY"
      value = true
    },
    {
      name  = "UPLOAD_PROVIDER"
      value = "s3"
    },
    {
      name  = "AWS_S3_BUCKET"
      value = var.challenge_bucket
    },
    {
      name  = "ACCESS_LOG"
      value = local.access_log
    },
    {
      name  = "ERROR_LOG"
      value = local.error_log
    }
  ]
  port_mappings = [
    {
      containerPort = local.container_port
      hostPort      = local.container_port
      protocol      = "tcp"
    }
  ]
}

data "aws_iam_policy_document" "ecs_task_assume_role" {
  version = "2012-10-17"
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "ecs_get_secrets" {
  version = "2012-10-17"
  # Required to read Secrets
  statement {
    effect = "Allow"

    actions = [
      "ssm:GetParameters",
      "secretsmanager:GetSecretValue"
    ]

    resources = concat(
      local.secrets_arn_list,
      var.registry_password != null ? [aws_secretsmanager_secret.registry_creds[0].arn] : []
    )

  }
}
resource "aws_iam_role" "ecs_task_execution_role" {
  name               = "ecs-staging-execution-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume_role.json
}
resource "aws_iam_role_policy" "ecs_get_secrets" {
  name   = "ecs_get_secrets"
  role   = aws_iam_role.ecs_task_execution_role.name
  policy = data.aws_iam_policy_document.ecs_get_secrets.json
}
resource "aws_iam_role_policy_attachment" "ecs_task_execution_role" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "s3_full_access" {
  version = "2012-10-17"
  statement {
    effect = "Allow"
    actions = [
      "s3:ListBucket",
    ]

    resources = [
      var.challenge_bucket_arn
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:DeleteObject"
    ]

    resources = [
      "${var.challenge_bucket_arn}/*"
    ]
  }
}
resource "aws_iam_role" "ecs_task_role" {
  name               = "ecs-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume_role.json
}
resource "aws_iam_role_policy" "s3_full_access" {
  name   = "s3_full_access"
  role   = aws_iam_role.ecs_task_role.name
  policy = data.aws_iam_policy_document.s3_full_access.json
}

resource "aws_ecs_task_definition" "ctfd" {
  family                   = var.app_name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 512
  memory                   = 1024
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn
  container_definitions    = module.container_definition.json_map_encoded_list
  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "ARM64"
  }
}

resource "aws_security_group" "allow_http" {
  name        = "allow_http"
  description = "Allow HTTP inbound traffic"
  vpc_id      = var.vpc_id

  ingress {
    description      = "HTTP from Internet"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "allow_http"
  }
}

data "aws_vpc" "selected" {
  id = var.vpc_id
}

resource "aws_security_group" "alb_to_ecs_service" {
  name        = "alb_to_ecs_service"
  description = "Allow inbound traffic from ALB to ECS Service"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTP from ALB"
    from_port   = local.container_port
    to_port     = local.container_port
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.selected.cidr_block]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "allow_http"
  }
}

resource "aws_lb" "ctfd" {
  name               = "${var.app_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.allow_http.id]
  subnets            = var.public_subnet_ids

  enable_deletion_protection = false

  tags = {
    Environment = "production"
  }
}

resource "aws_lb_target_group" "ctfd" {
  name_prefix = "${var.app_name}-"
  port        = local.container_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"
  health_check {
    path = "/healthcheck"
  }
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_listener" "listener" {
  load_balancer_arn = aws_lb.ctfd.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ctfd.arn
  }
}

resource "aws_ecs_service" "ctfd" {
  name            = var.app_name
  cluster         = module.ecs.cluster_id
  task_definition = aws_ecs_task_definition.ctfd.arn
  depends_on      = [aws_lb_listener.listener, aws_iam_role_policy_attachment.ecs_task_execution_role]
  launch_type     = "FARGATE"

  desired_count                      = var.frontend_desired_count
  deployment_minimum_healthy_percent = var.frontend_minimum_healthy_percent
  deployment_maximum_percent         = var.frontend_maximum_percent

  load_balancer {
    target_group_arn = aws_lb_target_group.ctfd.arn
    container_name   = var.app_name
    container_port   = local.container_port
  }
  network_configuration {
    assign_public_ip = false
    security_groups  = [aws_security_group.alb_to_ecs_service.id]
    subnets          = var.private_subnet_ids
  }
}

resource "aws_appautoscaling_target" "ctfd" {
  max_capacity       = var.frontend_maximum_count
  min_capacity       = var.frontend_minimum_count
  resource_id        = "service/${var.ecs_cluster_name}/${aws_ecs_service.ctfd.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

# CloudWatch Alarm for scaling up (high CPU)
resource "aws_cloudwatch_metric_alarm" "ecs_cpu_high" {
  alarm_name          = "${var.app_name}-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 300
  statistic           = "Average"
  threshold           = 70
  alarm_description   = "Scale up when CPU utilization is high"
  alarm_actions       = [aws_appautoscaling_policy.ecs_scale_up.arn]

  dimensions = {
    ServiceName = aws_ecs_service.ctfd.name
    ClusterName = module.ecs.cluster_id
  }

  tags = {
    Name = "${var.app_name}-cpu-high-alarm"
  }
}

# CloudWatch Alarm for scaling up (high request count)
resource "aws_cloudwatch_metric_alarm" "ecs_request_count_high" {
  alarm_name          = "${var.app_name}-request-count-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "RequestCountPerTarget"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  statistic           = "Sum"
  threshold           = 100
  alarm_description   = "Scale up when request count is high"
  alarm_actions       = [aws_appautoscaling_policy.ecs_scale_up.arn]

  dimensions = {
    TargetGroup  = aws_lb_target_group.ctfd.arn_suffix
    LoadBalancer = aws_lb.ctfd.arn_suffix
  }

  tags = {
    Name = "${var.app_name}-request-count-high-alarm"
  }
}

# CloudWatch Alarm for scaling down (low CPU)
resource "aws_cloudwatch_metric_alarm" "ecs_cpu_low" {
  alarm_name          = "${var.app_name}-cpu-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 300
  statistic           = "Average"
  threshold           = 30
  alarm_description   = "Scale down when CPU utilization is low"
  alarm_actions       = [aws_appautoscaling_policy.ecs_scale_down.arn]

  dimensions = {
    ServiceName = aws_ecs_service.ctfd.name
    ClusterName = module.ecs.cluster_id
  }

  tags = {
    Name = "${var.app_name}-cpu-low-alarm"
  }
}

# Auto-scaling policy: Scale up
resource "aws_appautoscaling_policy" "ecs_scale_up" {
  name               = "${var.app_name}-scale-up"
  policy_type        = "StepScaling"
  service_namespace  = aws_appautoscaling_target.ctfd.service_namespace
  resource_id        = aws_appautoscaling_target.ctfd.resource_id
  scalable_dimension = aws_appautoscaling_target.ctfd.scalable_dimension

  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown               = 60
    metric_aggregation_type = "Average"

    step_adjustment {
      metric_interval_lower_bound = 0
      scaling_adjustment          = 1
    }
  }
}

# Auto-scaling policy: Scale down
resource "aws_appautoscaling_policy" "ecs_scale_down" {
  name               = "${var.app_name}-scale-down"
  policy_type        = "StepScaling"
  service_namespace  = aws_appautoscaling_target.ctfd.service_namespace
  resource_id        = aws_appautoscaling_target.ctfd.resource_id
  scalable_dimension = aws_appautoscaling_target.ctfd.scalable_dimension

  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown               = 300
    metric_aggregation_type = "Average"

    step_adjustment {
      metric_interval_upper_bound = 0
      scaling_adjustment           = -1
    }
  }
}
