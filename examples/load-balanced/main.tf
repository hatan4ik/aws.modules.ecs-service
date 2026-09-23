provider "aws" {
  region = var.region
}

# ------------------------------------------------------------------ ALB

resource "aws_security_group" "alb" {
  name        = "${var.name}-alb"
  description = "Internal ALB in front of ECS service ${var.name}"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = "${var.name}-alb" })
}

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  security_group_id = aws_security_group.alb.id

  description = "HTTPS from internal clients"
  ip_protocol = "tcp"
  from_port   = 443
  to_port     = 443
  cidr_ipv4   = var.client_cidr

  tags = var.tags
}

resource "aws_vpc_security_group_egress_rule" "alb_to_tasks" {
  security_group_id = aws_security_group.alb.id

  description                  = "HTTP to the task security group"
  ip_protocol                  = "tcp"
  from_port                    = 8080
  to_port                      = 8080
  referenced_security_group_id = module.service.security_group_id

  tags = var.tags
}

resource "aws_lb" "this" {
  name               = var.name
  internal           = true
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.subnet_ids

  drop_invalid_header_fields = true
  enable_deletion_protection = true

  access_logs {
    bucket  = var.access_logs_bucket
    prefix  = var.name
    enabled = true
  }

  tags = var.tags
}

resource "aws_lb_target_group" "this" {
  name        = var.name
  vpc_id      = var.vpc_id
  target_type = "ip"
  port        = 8080
  protocol    = "HTTP"

  deregistration_delay = 30

  health_check {
    path                = "/healthz"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = var.tags
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }

  tags = var.tags
}

# -------------------------------------------------------------- service

module "service" {
  source = "../../"

  name        = var.name
  cluster_arn = var.cluster_arn
  vpc_id      = var.vpc_id
  subnet_ids  = var.subnet_ids
  tags        = var.tags

  desired_count = 2

  container_definitions = {
    app = {
      image         = var.image
      port_mappings = [{ name = "http", container_port = 8080, app_protocol = "http" }]
    }
  }

  load_balancers = {
    http = {
      target_group_arn = aws_lb_target_group.this.arn
      container_name   = "app"
      container_port   = 8080
    }
  }

  # Give a new task time to warm up before failing ALB health checks count.
  health_check_grace_period_seconds = 60

  security_group_ingress_rules = {
    alb = {
      description                  = "HTTP from the ALB"
      from_port                    = 8080
      to_port                      = 8080
      referenced_security_group_id = aws_security_group.alb.id
    }
  }

  security_group_egress_rules = {
    https = {
      description = "TLS for image pulls and dependencies"
      from_port   = 443
      to_port     = 443
      cidr_ipv4   = var.egress_cidr
    }
  }

  autoscaling = {
    min_capacity = 2
    max_capacity = 10
    policies = {
      requests = {
        target_tracking = {
          predefined_metric_type = "ALBRequestCountPerTarget"
          resource_label         = "${aws_lb.this.arn_suffix}/${aws_lb_target_group.this.arn_suffix}"
          target_value           = 1000
        }
      }
      cpu = {
        target_tracking = {
          predefined_metric_type = "ECSServiceAverageCPUUtilization"
          target_value           = 60
        }
      }
    }
  }
}
