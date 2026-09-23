provider "aws" {
  region = var.region
}

# Gateway endpoints are reached through their managed prefix lists, not the VPC
# CIDR, so egress to them must be declared separately.
data "aws_prefix_list" "s3" {
  name = "com.amazonaws.${var.region}.s3"
}

data "aws_prefix_list" "dynamodb" {
  name = "com.amazonaws.${var.region}.dynamodb"
}

# The identity-provider client lives next to the service, not inside the
# module: it has its own lifecycle and the module only needs its ID.
resource "aws_cognito_user_pool_client" "this" {
  name         = var.name
  user_pool_id = var.cognito_user_pool_id

  generate_secret                      = false
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes                 = ["openid", "email", "profile"]
  supported_identity_providers         = ["COGNITO"]
  callback_urls                        = var.callback_urls
  logout_urls                          = var.logout_urls
  explicit_auth_flows                  = ["ALLOW_REFRESH_TOKEN_AUTH", "ALLOW_USER_SRP_AUTH"]
  prevent_user_existence_errors        = "ENABLED"
  enable_token_revocation              = true
}

module "service" {
  source = "../../"

  name        = var.name
  cluster_arn = var.cluster_arn
  vpc_id      = var.vpc_id
  subnet_ids  = var.subnet_ids
  tags        = var.tags

  desired_count          = 2
  enable_execute_command = true
  force_new_deployment   = var.force_new_deployment

  container_definitions = {
    app = {
      image         = var.image
      port_mappings = [{ name = "http", container_port = 8080 }]

      environment = {
        COGNITO_USER_POOL_ID = var.cognito_user_pool_id
        COGNITO_CLIENT_ID    = aws_cognito_user_pool_client.this.id
        SESSION_TABLE_NAME   = split("/", var.session_table_arn)[1]
      }

      health_check = {
        command      = ["CMD-SHELL", "curl -fsS http://localhost:8080/healthz || exit 1"]
        start_period = 10
      }
    }
  }

  # ------------------------------------------------------------- network
  security_group_name = "${var.name}-tasks"

  # The only paths out of these subnets are VPC endpoints: interface endpoints
  # answer inside the VPC CIDR, gateway endpoints behind their prefix lists.
  security_group_egress_rules = {
    vpc_tls = {
      description = "TLS to interface VPC endpoints and internal services"
      from_port   = 443
      to_port     = 443
      cidr_ipv4   = var.vpc_cidr
    }
    s3_tls = {
      description    = "TLS to the S3 gateway endpoint for ECR image layers"
      from_port      = 443
      to_port        = 443
      prefix_list_id = data.aws_prefix_list.s3.id
    }
    dynamodb_tls = {
      description    = "TLS to the DynamoDB gateway endpoint for the session table"
      from_port      = 443
      to_port        = 443
      prefix_list_id = data.aws_prefix_list.dynamodb.id
    }
  }

  # ----------------------------------------------------------------- IAM
  task_execution_role_path         = "/ecs/"
  task_role_path                   = "/ecs/"
  task_execution_role_kms_key_arns = [var.kms_key_arn]

  task_role_statements = {
    SessionTable = {
      actions = [
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:UpdateItem",
        "dynamodb:DeleteItem",
        "dynamodb:Query",
      ]
      resources = [var.session_table_arn, "${var.session_table_arn}/index/*"]
    }
  }

  # ------------------------------------------------------------- logging
  cloudwatch_log_group_kms_key_id = var.kms_key_arn

  # ------------------------------------------------------------- scaling
  autoscaling = {
    min_capacity = 2
    max_capacity = 12
    policies = {
      cpu = {
        target_tracking = {
          predefined_metric_type = "ECSServiceAverageCPUUtilization"
          target_value           = 60
        }
      }
    }
  }
}
