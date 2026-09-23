# Composition root. Each concern lives in a focused submodule with its own
# tests; this file wires them together for one ECS service.

module "container_definition" {
  source   = "./modules/container-definition"
  for_each = var.container_definitions

  name  = each.key
  image = each.value.image
  # Digest enforcement is applied once, on the task definition, so the plan
  # reports a single actionable error for the whole task.
  require_image_digest = false

  essential                = each.value.essential
  command                  = each.value.command
  entrypoint               = each.value.entrypoint
  working_directory        = each.value.working_directory
  user                     = each.value.user
  cpu                      = each.value.cpu
  memory                   = each.value.memory
  memory_reservation       = each.value.memory_reservation
  environment              = each.value.environment
  environment_files        = each.value.environment_files
  secrets                  = each.value.secrets
  port_mappings            = each.value.port_mappings
  health_check             = each.value.health_check
  readonly_root_filesystem = each.value.readonly_root_filesystem
  linux_parameters         = each.value.linux_parameters
  ulimits                  = each.value.ulimits
  mount_points             = each.value.mount_points
  volumes_from             = each.value.volumes_from
  container_dependencies   = each.value.container_dependencies
  start_timeout            = each.value.start_timeout
  stop_timeout             = each.value.stop_timeout
  docker_labels            = each.value.docker_labels
  system_controls          = each.value.system_controls
  log_configuration        = each.value.log_configuration != null ? each.value.log_configuration : local.default_log_configuration
  repository_credentials   = each.value.repository_credentials
  firelens_configuration   = each.value.firelens_configuration
  restart_policy           = each.value.restart_policy
  interactive              = each.value.interactive
  pseudo_terminal          = each.value.pseudo_terminal
  version_consistency      = each.value.version_consistency
}

module "iam" {
  source = "./modules/iam"

  name        = var.name
  cluster_arn = var.cluster_arn
  tags        = var.tags

  create_task_execution_role               = var.create_task_execution_role
  task_execution_role_arn                  = var.task_execution_role_arn
  task_execution_role_name                 = var.task_execution_role_name
  task_execution_role_path                 = var.task_execution_role_path
  task_execution_role_description          = var.task_execution_role_description
  task_execution_role_permissions_boundary = var.task_execution_role_permissions_boundary
  task_execution_role_policy_arns          = var.task_execution_role_policy_arns
  task_execution_role_statements           = var.task_execution_role_statements
  secret_arns                              = local.secret_arns
  kms_key_arns                             = var.task_execution_role_kms_key_arns

  create_task_role               = var.create_task_role
  task_role_arn                  = var.task_role_arn
  task_role_name                 = var.task_role_name
  task_role_path                 = var.task_role_path
  task_role_description          = var.task_role_description
  task_role_permissions_boundary = var.task_role_permissions_boundary
  task_role_policy_arns          = var.task_role_policy_arns
  task_role_statements           = var.task_role_statements
  enable_execute_command         = var.enable_execute_command
}

module "security_group" {
  source = "./modules/security-group"

  create        = var.create_security_group
  name          = coalesce(var.security_group_name, var.name)
  description   = coalesce(var.security_group_description, "Tasks of ECS service ${var.name}")
  vpc_id        = var.vpc_id
  ingress_rules = var.security_group_ingress_rules
  egress_rules  = var.security_group_egress_rules
  tags          = var.tags
}

resource "aws_cloudwatch_log_group" "this" {
  count = var.create_cloudwatch_log_group ? 1 : 0

  name              = local.cloudwatch_log_group_name
  retention_in_days = var.cloudwatch_log_group_retention_in_days
  kms_key_id        = var.cloudwatch_log_group_kms_key_id
  log_group_class   = var.cloudwatch_log_group_class
  skip_destroy      = var.cloudwatch_log_group_skip_destroy

  tags = merge(var.tags, { Name = local.cloudwatch_log_group_name })
}
