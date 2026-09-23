locals {
  # arn:<partition>:ecs:<region>:<account>:cluster/<name>
  cluster_arn_parts = split(":", var.cluster_arn)
  region            = local.cluster_arn_parts[3]
  cluster_name      = split("/", local.cluster_arn_parts[5])[1]

  family = coalesce(var.family, var.name)

  # A capacity provider strategy and launch_type are mutually exclusive.
  launch_type = length(var.capacity_provider_strategy) == 0 ? "FARGATE" : null

  cloudwatch_log_group_name = var.create_cloudwatch_log_group ? coalesce(var.cloudwatch_log_group_name, "/aws/ecs/${local.cluster_name}/${var.name}") : var.cloudwatch_log_group_name

  # Injected into every container that declares no log configuration of its own.
  default_log_configuration = local.cloudwatch_log_group_name == null ? null : {
    log_driver = "awslogs"
    options = {
      "awslogs-group"         = local.cloudwatch_log_group_name
      "awslogs-region"        = local.region
      "awslogs-stream-prefix" = var.name
    }
    secret_options = []
  }

  # Sorted so the rendered JSON, and therefore the task definition revision,
  # only changes when a container actually changes.
  container_definitions = [for name in sort(keys(var.container_definitions)) : module.container_definition[name].container_definition]
  secret_arns           = toset(flatten([for definition in module.container_definition : definition.secret_arns]))

  security_group_ids = concat(
    var.create_security_group ? [module.security_group.id] : [],
    sort(tolist(var.security_group_ids)),
  )

  declared_port_names     = toset(flatten([for definition in values(var.container_definitions) : [for mapping in definition.port_mappings : mapping.name if mapping.name != null]]))
  referenced_volume_names = toset(flatten([for definition in values(var.container_definitions) : [for mount in definition.mount_points : mount.source_volume]]))

  # Valid Fargate task sizes: memory (MiB) per CPU unit tier.
  fargate_task_sizes = tomap({
    "256"   = tolist([512, 1024, 2048])
    "512"   = range(1024, 4097, 1024)
    "1024"  = range(2048, 8193, 1024)
    "2048"  = range(4096, 16385, 1024)
    "4096"  = range(8192, 30721, 1024)
    "8192"  = range(16384, 61441, 4096)
    "16384" = range(32768, 122881, 8192)
  })
  fargate_task_size_valid = contains(keys(local.fargate_task_sizes), tostring(var.cpu)) ? contains(local.fargate_task_sizes[tostring(var.cpu)], var.memory) : false
  windows_task            = startswith(var.operating_system_family, "WINDOWS")

  # Exactly one service variant exists; see service.tf.
  service = var.ignore_task_definition_changes ? aws_ecs_service.ignore_task_definition[0] : aws_ecs_service.this[0]
}
