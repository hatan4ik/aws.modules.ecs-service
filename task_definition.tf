resource "aws_ecs_task_definition" "this" {
  # checkov:skip=CKV_AWS_97: EFS transit_encryption defaults to ENABLED through the volumes variable type and IAM authorization is validated to require it; the check cannot resolve dynamic block values.
  family                   = local.family
  cpu                      = tostring(var.cpu)
  memory                   = tostring(var.memory)
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = module.iam.task_execution_role_arn
  task_role_arn            = module.iam.task_role_arn
  pid_mode                 = var.pid_mode
  skip_destroy             = var.skip_destroy
  track_latest             = var.track_latest
  enable_fault_injection   = var.enable_fault_injection
  container_definitions    = jsonencode(local.container_definitions)

  runtime_platform {
    operating_system_family = var.operating_system_family
    cpu_architecture        = var.cpu_architecture
  }

  dynamic "ephemeral_storage" {
    for_each = var.ephemeral_storage_size_in_gib == null ? [] : [var.ephemeral_storage_size_in_gib]

    content {
      size_in_gib = ephemeral_storage.value
    }
  }

  dynamic "volume" {
    for_each = var.volumes

    content {
      name                = volume.key
      configure_at_launch = volume.value.configure_at_launch

      dynamic "efs_volume_configuration" {
        for_each = volume.value.efs == null ? [] : [volume.value.efs]

        content {
          file_system_id          = efs_volume_configuration.value.file_system_id
          root_directory          = efs_volume_configuration.value.root_directory
          transit_encryption      = efs_volume_configuration.value.transit_encryption
          transit_encryption_port = efs_volume_configuration.value.transit_encryption_port

          dynamic "authorization_config" {
            for_each = efs_volume_configuration.value.authorization_config == null ? [] : [efs_volume_configuration.value.authorization_config]

            content {
              access_point_id = authorization_config.value.access_point_id
              iam             = authorization_config.value.iam
            }
          }
        }
      }
    }
  }

  tags = merge(var.tags, { Name = local.family })

  lifecycle {
    precondition {
      condition     = local.fargate_task_size_valid
      error_message = "cpu and memory must be a supported Fargate combination: 256 CPU with 512-2048 MiB; 512 with 1024-4096; 1024 with 2048-8192; 2048 with 4096-16384; 4096 with 8192-30720; 8192 with 16384-61440 (4096 steps); 16384 with 32768-122880 (8192 steps)."
    }

    precondition {
      condition     = !local.windows_task || contains([1024, 2048, 4096], var.cpu)
      error_message = "Windows Fargate tasks require cpu of 1024, 2048, or 4096."
    }

    precondition {
      condition     = alltrue([for definition in values(var.container_definitions) : !var.require_image_digest || can(regex("@sha256:[0-9a-f]{64}$", definition.image))])
      error_message = "Every container image must be pinned to an immutable sha256 digest (repository@sha256:<64 hex>). Set require_image_digest = false to opt out deliberately."
    }

    precondition {
      condition     = length(setsubtract(local.referenced_volume_names, toset(keys(var.volumes)))) == 0
      error_message = "Every mount_points.source_volume must name a key of volumes."
    }
  }
}
