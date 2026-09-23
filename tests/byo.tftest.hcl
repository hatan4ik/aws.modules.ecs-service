mock_provider "aws" {}

variables {
  name        = "orders-api"
  cluster_arn = "arn:aws:ecs:us-east-1:123456789012:cluster/platform"
  subnet_ids  = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]

  container_definitions = {
    app = {
      image   = "123456789012.dkr.ecr.us-east-1.amazonaws.com/orders@sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
      secrets = { TOKEN = "arn:aws:ssm:us-east-1:123456789012:parameter/orders/token" }
    }
  }

  create_security_group       = false
  security_group_ids          = ["sg-0aaaaaaaaaaaaaaaa"]
  create_task_execution_role  = false
  task_execution_role_arn     = "arn:aws:iam::123456789012:role/platform/shared-execution"
  create_task_role            = false
  task_role_arn               = "arn:aws:iam::123456789012:role/orders-task"
  create_cloudwatch_log_group = false
  cloudwatch_log_group_name   = "/platform/orders"
}

run "creates_only_the_task_definition_and_service" {
  command = plan

  assert {
    condition     = length(aws_cloudwatch_log_group.this) == 0
    error_message = "No log group may be created when the caller supplies one."
  }

  assert {
    condition     = output.task_execution_role_arn == "arn:aws:iam::123456789012:role/platform/shared-execution" && output.task_role_arn == "arn:aws:iam::123456789012:role/orders-task" && output.task_execution_role_name == "shared-execution"
    error_message = "Supplied role ARNs must flow to the task definition and outputs unchanged."
  }

  assert {
    condition     = aws_ecs_task_definition.this.execution_role_arn == "arn:aws:iam::123456789012:role/platform/shared-execution" && aws_ecs_task_definition.this.task_role_arn == "arn:aws:iam::123456789012:role/orders-task"
    error_message = "The task definition must reference the supplied roles."
  }

  assert {
    condition     = jsondecode(aws_ecs_task_definition.this.container_definitions)[0].logConfiguration.options["awslogs-group"] == "/platform/orders" && output.cloudwatch_log_group_name == "/platform/orders" && output.cloudwatch_log_group_arn == null
    error_message = "A supplied log group name must still be injected into containers."
  }

  assert {
    condition     = output.security_group_id == null && aws_ecs_service.this[0].network_configuration[0].security_groups == toset(["sg-0aaaaaaaaaaaaaaaa"])
    error_message = "A supplied security group must be used verbatim."
  }

  assert {
    condition     = jsondecode(output.task_execution_role_derived_policy).Statement[0].Action == ["ssm:GetParameters"]
    error_message = "The derived policy must be exposed so the caller can attach it to their execution role."
  }

  expect_failures = [check.supplied_execution_role_secrets]
}

run "skips_log_injection_when_no_group_is_named" {
  command = plan

  variables {
    cloudwatch_log_group_name = null
  }

  assert {
    condition     = !contains(keys(jsondecode(aws_ecs_task_definition.this.container_definitions)[0]), "logConfiguration") && output.cloudwatch_log_group_name == null
    error_message = "Without a managed or named log group no log configuration may be injected."
  }

  expect_failures = [check.supplied_execution_role_secrets]
}
