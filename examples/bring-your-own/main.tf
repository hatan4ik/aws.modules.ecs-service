provider "aws" {
  region = var.region
}

module "service" {
  source = "../../"

  name        = var.name
  cluster_arn = var.cluster_arn
  subnet_ids  = var.subnet_ids
  tags        = var.tags

  container_definitions = {
    app = {
      image         = var.image
      port_mappings = [{ name = "http", container_port = 8080 }]
      secrets       = { API_TOKEN = var.api_token_parameter_arn }
    }
  }

  # Every managed resource is replaced by a caller-supplied one. The module
  # wires the identifiers through and creates only the task definition and the
  # service; it never modifies the supplied roles or security groups.
  create_security_group = false
  security_group_ids    = var.security_group_ids

  create_task_execution_role = false
  task_execution_role_arn    = var.task_execution_role_arn

  create_task_role = false
  task_role_arn    = var.task_role_arn

  create_cloudwatch_log_group = false
  cloudwatch_log_group_name   = var.cloudwatch_log_group_name
}

# The container references an SSM parameter, so the execution role needs
# ssm:GetParameters on it. The module derives that policy but cannot attach it
# to a role it does not own; the caller closes the gap.
resource "aws_iam_role_policy" "task_execution_derived" {
  count = module.service.task_execution_role_derived_policy == null ? 0 : 1

  name   = "${var.name}-derived"
  role   = regex("[^/]+$", var.task_execution_role_arn)
  policy = module.service.task_execution_role_derived_policy
}
