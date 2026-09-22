mock_provider "aws" {
  mock_data "aws_partition" {
    defaults = {
      partition = "aws"
    }
  }

  mock_data "aws_region" {
    defaults = {
      region = "us-east-2"
    }
  }

  mock_data "aws_prefix_list" {
    defaults = {
      id = "pl-4ca54025"
    }
  }
}

run "private_fargate_service_plan" {
  command = plan

  variables {
    name                         = "sandbox-workload-dev"
    cluster_arn                  = "arn:aws:ecs:us-east-2:123456789012:cluster/sandbox-platform-dev-cluster"
    cluster_name                 = "sandbox-platform-dev-cluster"
    vpc_id                       = "vpc-0123456789abcdef0"
    vpc_cidr                     = "10.64.0.0/16"
    private_subnet_ids           = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]
    application_data_kms_key_arn = "arn:aws:kms:us-east-2:123456789012:key/12345678-1234-1234-1234-123456789012"
    log_retention_in_days        = 365
    cognito_user_pool_id         = "us-east-2_example"
    session_table_arn            = "arn:aws:dynamodb:us-east-2:123456789012:table/sandbox-platform-dev-session"
    tags = {
      Environment = "dev"
      ManagedBy   = "terraform"
    }
    applications = {
      api = {
        image_digest         = "123456789012.dkr.ecr.us-east-2.amazonaws.com/sandbox-platform-dev-application@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        cpu                  = 256
        memory               = 512
        desired_count        = 1
        force_new_deployment = true
        autoscaling = {
          min_capacity       = 1
          max_capacity       = 2
          cpu_target_percent = 60
        }
        container_port              = 8080
        environment                 = { LOG_LEVEL = "info" }
        enable_session_table_access = true
        cognito = {
          callback_urls        = ["https://app.example.com/callback"]
          logout_urls          = ["https://app.example.com/logout"]
          allowed_oauth_scopes = ["openid", "email"]
        }
      }
    }
  }

  assert {
    condition     = aws_ecs_service.application["api"].network_configuration[0].assign_public_ip == false
    error_message = "Fargate tasks must remain private."
  }

  assert {
    condition     = aws_ecs_service.application["api"].force_new_deployment == true
    error_message = "Callers must be able to request a Terraform-managed fresh ECS deployment after a private networking prerequisite changes."
  }

  assert {
    condition     = aws_vpc_security_group_egress_rule.application_https_to_s3["api"].prefix_list_id == "pl-4ca54025"
    error_message = "Private Fargate tasks must reach ECR image layers through the regional S3 gateway prefix list."
  }

  assert {
    condition     = local.application_environment["api"]["COGNITO_USER_POOL_ID"] == "us-east-2_example"
    error_message = "Cognito-backed applications must receive the declared user-pool ID without repeating it in each environment map."
  }

}
