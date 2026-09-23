mock_provider "aws" {}

variables {
  name        = "orders-api"
  cluster_arn = "arn:aws:ecs:us-east-1:123456789012:cluster/platform"
  vpc_id      = "vpc-0123456789abcdef0"
  subnet_ids  = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]

  security_group_egress_rules = {
    https = { from_port = 443, to_port = 443, cidr_ipv4 = "0.0.0.0/0" }
  }
}

run "merges_secret_references_across_containers_into_the_execution_role" {
  command = plan

  variables {
    container_definitions = {
      app = {
        image   = "123456789012.dkr.ecr.us-east-1.amazonaws.com/orders@sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        secrets = { DB_PASSWORD = "arn:aws:secretsmanager:us-east-1:123456789012:secret:orders/db-AbCdEf:password::" }
      }
      log-router = {
        image                  = "123456789012.dkr.ecr.us-east-1.amazonaws.com/fluent-bit@sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        essential              = false
        secrets                = { API_KEY = "arn:aws:ssm:us-east-1:123456789012:parameter/orders/api-key" }
        firelens_configuration = { type = "fluentbit" }
        log_configuration      = { log_driver = "awslogs", options = { "awslogs-group" = "/aws/ecs/router" } }
      }
    }
    task_execution_role_kms_key_arns = ["arn:aws:kms:us-east-1:123456789012:key/11111111-1111-1111-1111-111111111111"]
    enable_execute_command           = true
    task_role_statements = {
      ReadOrdersTable = { actions = ["dynamodb:GetItem"], resources = ["arn:aws:dynamodb:us-east-1:123456789012:table/orders"] }
    }
  }

  assert {
    condition     = jsondecode(output.task_execution_role_derived_policy).Statement[0].Resource == ["arn:aws:secretsmanager:us-east-1:123456789012:secret:orders/db-AbCdEf"] && jsondecode(output.task_execution_role_derived_policy).Statement[1].Resource == ["arn:aws:ssm:us-east-1:123456789012:parameter/orders/api-key"] && jsondecode(output.task_execution_role_derived_policy).Statement[2].Action == ["kms:Decrypt"]
    error_message = "Secrets from every container must be merged into one least-privilege execution policy."
  }

  assert {
    condition     = jsondecode(output.task_role_derived_policy).Statement[0].Sid == "OpenEcsExecChannels" && aws_ecs_service.this[0].enable_execute_command == true
    error_message = "Enabling ECS Exec must grant the channel permissions and enable it on the service."
  }

  assert {
    condition     = jsondecode(aws_ecs_task_definition.this.container_definitions)[0].name == "app" && jsondecode(aws_ecs_task_definition.this.container_definitions)[1].name == "log-router"
    error_message = "Containers must render in sorted key order for deterministic task definitions."
  }

  assert {
    condition     = jsondecode(aws_ecs_task_definition.this.container_definitions)[1].logConfiguration.options["awslogs-group"] == "/aws/ecs/router" && jsondecode(aws_ecs_task_definition.this.container_definitions)[0].logConfiguration.options["awslogs-group"] == "/aws/ecs/platform/orders-api"
    error_message = "A container's own log configuration must win over the managed default."
  }
}
