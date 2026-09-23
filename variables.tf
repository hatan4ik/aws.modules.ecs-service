# ---------------------------------------------------------------------------
# Identity
# ---------------------------------------------------------------------------

variable "name" {
  description = "Service name. Also the default task family, security group name, and prefix for IAM roles and autoscaling policies. Lowercase alphanumerics and hyphens, 1-54 characters, so every derived name fits its AWS limit."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,52}[a-z0-9])?$", var.name))
    error_message = "name must be 1-54 lowercase alphanumeric characters or hyphens, starting and ending with an alphanumeric character."
  }
}

variable "cluster_arn" {
  description = "ARN of the existing ECS cluster that runs the service. The module derives the cluster name, partition, region, and account from it and performs no lookups."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^arn:[a-z-]+:ecs:[a-z0-9-]+:[0-9]{12}:cluster/[A-Za-z0-9_-]+$", var.cluster_arn))
    error_message = "cluster_arn must be a full ECS cluster ARN (arn:<partition>:ecs:<region>:<account>:cluster/<name>)."
  }
}

variable "tags" {
  description = "Tags applied to every resource the module creates. The module adds a Name tag and never overrides caller tags."
  type        = map(string)
  default     = {}
  nullable    = false
}

# ---------------------------------------------------------------------------
# Task definition
# ---------------------------------------------------------------------------

variable "family" {
  description = "Task definition family. Defaults to name."
  type        = string
  default     = null
}

variable "cpu" {
  description = "Task-level CPU units. Must be a Fargate size (256, 512, 1024, 2048, 4096, 8192, 16384) and compatible with memory."
  type        = number
  default     = 256
  nullable    = false

  validation {
    condition     = contains([256, 512, 1024, 2048, 4096, 8192, 16384], var.cpu)
    error_message = "cpu must be one of 256, 512, 1024, 2048, 4096, 8192, or 16384."
  }
}

variable "memory" {
  description = "Task-level memory in MiB. Must be a Fargate size compatible with cpu (validated at plan time)."
  type        = number
  default     = 512
  nullable    = false
}

variable "cpu_architecture" {
  description = "CPU architecture of the task: X86_64 or ARM64."
  type        = string
  default     = "X86_64"
  nullable    = false

  validation {
    condition     = contains(["X86_64", "ARM64"], var.cpu_architecture)
    error_message = "cpu_architecture must be X86_64 or ARM64."
  }
}

variable "operating_system_family" {
  description = "Operating system family of the task: LINUX or a WINDOWS_SERVER_<2019|2022|2025>_<CORE|FULL> value. Windows tasks need at least 1024 CPU units."
  type        = string
  default     = "LINUX"
  nullable    = false

  validation {
    condition     = can(regex("^(LINUX|WINDOWS_SERVER_20(19|22|25)_(CORE|FULL))$", var.operating_system_family))
    error_message = "operating_system_family must be LINUX or WINDOWS_SERVER_<2019|2022|2025>_<CORE|FULL>."
  }
}

variable "ephemeral_storage_size_in_gib" {
  description = "Ephemeral task storage in GiB (21-200). Null keeps the 20 GiB Fargate default."
  type        = number
  default     = null

  validation {
    condition     = var.ephemeral_storage_size_in_gib == null ? true : (var.ephemeral_storage_size_in_gib >= 21 && var.ephemeral_storage_size_in_gib <= 200)
    error_message = "ephemeral_storage_size_in_gib must be between 21 and 200."
  }
}

variable "volumes" {
  description = "Task volumes keyed by name. An empty object is a bind mount on ephemeral storage; efs attaches an EFS file system (encrypted in transit by default)."
  type = map(object({
    configure_at_launch = optional(bool)
    efs = optional(object({
      file_system_id          = string
      root_directory          = optional(string, "/")
      transit_encryption      = optional(string, "ENABLED")
      transit_encryption_port = optional(number)
      authorization_config = optional(object({
        access_point_id = optional(string)
        iam             = optional(string, "ENABLED")
      }))
    }))
  }))
  default  = {}
  nullable = false

  validation {
    condition = alltrue([for volume in values(var.volumes) : volume.efs == null ? true : (
      contains(["ENABLED", "DISABLED"], volume.efs.transit_encryption) &&
      (volume.efs.authorization_config == null ? true : (
        contains(["ENABLED", "DISABLED"], volume.efs.authorization_config.iam) &&
        (volume.efs.authorization_config.iam == "ENABLED" ? volume.efs.transit_encryption == "ENABLED" : true)
      ))
    )])
    error_message = "EFS transit_encryption and authorization_config.iam must be ENABLED or DISABLED, and IAM authorization requires transit encryption."
  }
}

variable "pid_mode" {
  description = "Process namespace sharing for the task. Fargate supports only task (shared) or null (per container)."
  type        = string
  default     = null

  validation {
    condition     = var.pid_mode == null ? true : var.pid_mode == "task"
    error_message = "pid_mode must be null or task on Fargate."
  }
}

variable "require_image_digest" {
  description = "Reject container images that are not pinned to a sha256 digest. Digest pinning makes deployments reproducible and rollbacks exact."
  type        = bool
  default     = true
  nullable    = false
}

variable "skip_destroy" {
  description = "Keep old task definition revisions active when Terraform would deregister them."
  type        = bool
  default     = false
  nullable    = false
}

variable "track_latest" {
  description = "Track the latest ACTIVE revision of the family, for families also registered outside Terraform."
  type        = bool
  default     = false
  nullable    = false
}

variable "enable_fault_injection" {
  description = "Allow AWS Fault Injection Service experiments against the task."
  type        = bool
  default     = false
  nullable    = false
}

variable "container_definitions" {
  description = "Containers in the task keyed by container name. At least one must be essential. See modules/container-definition for every attribute."
  type = map(object({
    image              = string
    essential          = optional(bool, true)
    command            = optional(list(string))
    entrypoint         = optional(list(string))
    working_directory  = optional(string)
    user               = optional(string)
    cpu                = optional(number)
    memory             = optional(number)
    memory_reservation = optional(number)
    environment        = optional(map(string), {})
    environment_files = optional(list(object({
      type  = optional(string, "s3")
      value = string
    })), [])
    secrets = optional(map(string), {})
    port_mappings = optional(list(object({
      name           = optional(string)
      container_port = number
      host_port      = optional(number)
      protocol       = optional(string, "tcp")
      app_protocol   = optional(string)
    })), [])
    health_check = optional(object({
      command      = list(string)
      interval     = optional(number, 30)
      timeout      = optional(number, 5)
      retries      = optional(number, 3)
      start_period = optional(number)
    }))
    readonly_root_filesystem = optional(bool, true)
    linux_parameters = optional(object({
      init_process_enabled = optional(bool, false)
      capabilities = optional(object({
        add  = optional(list(string), [])
        drop = optional(list(string), [])
      }))
    }))
    ulimits = optional(list(object({
      name       = string
      soft_limit = number
      hard_limit = number
    })), [])
    mount_points = optional(list(object({
      source_volume  = string
      container_path = string
      read_only      = optional(bool, false)
    })), [])
    volumes_from = optional(list(object({
      source_container = string
      read_only        = optional(bool, false)
    })), [])
    container_dependencies = optional(list(object({
      container_name = string
      condition      = string
    })), [])
    start_timeout = optional(number)
    stop_timeout  = optional(number)
    docker_labels = optional(map(string), {})
    system_controls = optional(list(object({
      namespace = string
      value     = string
    })), [])
    log_configuration = optional(object({
      log_driver = string
      options    = optional(map(string), {})
      secret_options = optional(list(object({
        name       = string
        value_from = string
      })), [])
    }))
    repository_credentials = optional(object({
      credentials_parameter = string
    }))
    firelens_configuration = optional(object({
      type    = string
      options = optional(map(string), {})
    }))
    restart_policy = optional(object({
      enabled                = bool
      ignored_exit_codes     = optional(list(number), [])
      restart_attempt_period = optional(number)
    }))
    interactive         = optional(bool, false)
    pseudo_terminal     = optional(bool, false)
    version_consistency = optional(string)
  }))
  nullable = false

  validation {
    condition     = length(var.container_definitions) > 0
    error_message = "container_definitions must declare at least one container."
  }

  validation {
    condition     = alltrue([for name in keys(var.container_definitions) : can(regex("^[a-zA-Z0-9][a-zA-Z0-9_-]{0,254}$", name))])
    error_message = "Container names must be 1-255 letters, digits, hyphens, or underscores, starting with a letter or digit."
  }

  validation {
    condition     = anytrue([for definition in values(var.container_definitions) : definition.essential])
    error_message = "At least one container must be essential, otherwise the task can never be considered running."
  }

  validation {
    condition = alltrue(flatten([for definition in values(var.container_definitions) : concat(
      [for dependency in definition.container_dependencies : contains(keys(var.container_definitions), dependency.container_name)],
      [for volume in definition.volumes_from : contains(keys(var.container_definitions), volume.source_container)],
    )]))
    error_message = "container_dependencies and volumes_from must reference containers declared in container_definitions."
  }
}

# ---------------------------------------------------------------------------
# Service
# ---------------------------------------------------------------------------

variable "desired_count" {
  description = "Number of tasks to run at creation. Later drift is ignored because autoscaling, deployments, and operators legitimately change it."
  type        = number
  default     = 1
  nullable    = false

  validation {
    condition     = var.desired_count >= 0
    error_message = "desired_count must be zero or greater."
  }
}

variable "capacity_provider_strategy" {
  description = "Fargate capacity provider strategy keyed by a short name. When non-empty the service uses the strategy instead of launch_type FARGATE, which enables FARGATE_SPOT."
  type = map(object({
    capacity_provider = string
    weight            = optional(number, 1)
    base              = optional(number)
  }))
  default  = {}
  nullable = false

  validation {
    condition = alltrue([for strategy in values(var.capacity_provider_strategy) :
      contains(["FARGATE", "FARGATE_SPOT"], strategy.capacity_provider) && strategy.weight >= 0 && (strategy.base == null ? true : strategy.base >= 0)
    ]) && length([for strategy in values(var.capacity_provider_strategy) : strategy if strategy.base != null]) <= 1
    error_message = "capacity_provider must be FARGATE or FARGATE_SPOT, weights and base must be non-negative, and at most one entry may set base."
  }
}

variable "platform_version" {
  description = "Fargate platform version: LATEST or an explicit version such as 1.4.0."
  type        = string
  default     = "LATEST"
  nullable    = false

  validation {
    condition     = can(regex("^(LATEST|[0-9]+\\.[0-9]+\\.[0-9]+)$", var.platform_version))
    error_message = "platform_version must be LATEST or a semantic version such as 1.4.0."
  }
}

variable "enable_execute_command" {
  description = "Enable ECS Exec on the service and grant the task role the SSM channel permissions it needs."
  type        = bool
  default     = false
  nullable    = false
}

variable "enable_ecs_managed_tags" {
  description = "Let ECS tag tasks with cluster and service names."
  type        = bool
  default     = true
  nullable    = false
}

variable "propagate_tags" {
  description = "Propagate tags to tasks from the SERVICE, the TASK_DEFINITION, or NONE."
  type        = string
  default     = "SERVICE"
  nullable    = false

  validation {
    condition     = contains(["SERVICE", "TASK_DEFINITION", "NONE"], var.propagate_tags)
    error_message = "propagate_tags must be SERVICE, TASK_DEFINITION, or NONE."
  }
}

variable "force_new_deployment" {
  description = "Force a new deployment on every apply, for example after a networking prerequisite changed."
  type        = bool
  default     = false
  nullable    = false
}

variable "force_delete" {
  description = "Delete the service even when it still has running tasks."
  type        = bool
  default     = false
  nullable    = false
}

variable "wait_for_steady_state" {
  description = "Block apply until the service reaches a steady state."
  type        = bool
  default     = false
  nullable    = false
}

variable "health_check_grace_period_seconds" {
  description = "Seconds to ignore failing load balancer health checks after a task starts. Only valid with load_balancers."
  type        = number
  default     = null

  validation {
    condition     = var.health_check_grace_period_seconds == null ? true : (var.health_check_grace_period_seconds >= 0 && var.health_check_grace_period_seconds <= 2147483647)
    error_message = "health_check_grace_period_seconds must be between 0 and 2147483647."
  }
}

variable "deployment_minimum_healthy_percent" {
  description = "Lower limit of running tasks during a deployment, as a percentage of desired_count."
  type        = number
  default     = 100
  nullable    = false

  validation {
    condition     = var.deployment_minimum_healthy_percent >= 0 && var.deployment_minimum_healthy_percent <= 100
    error_message = "deployment_minimum_healthy_percent must be between 0 and 100."
  }
}

variable "deployment_maximum_percent" {
  description = "Upper limit of running tasks during a deployment, as a percentage of desired_count."
  type        = number
  default     = 200
  nullable    = false

  validation {
    condition     = var.deployment_maximum_percent >= 100
    error_message = "deployment_maximum_percent must be at least 100."
  }
}

variable "deployment_circuit_breaker" {
  description = "ECS deployment circuit breaker. Enabled with rollback by default; only valid with the ECS deployment controller."
  type = object({
    enable   = optional(bool, true)
    rollback = optional(bool, true)
  })
  default  = {}
  nullable = false
}

variable "deployment_controller_type" {
  description = "Deployment controller: ECS, CODE_DEPLOY, or EXTERNAL."
  type        = string
  default     = "ECS"
  nullable    = false

  validation {
    condition     = contains(["ECS", "CODE_DEPLOY", "EXTERNAL"], var.deployment_controller_type)
    error_message = "deployment_controller_type must be ECS, CODE_DEPLOY, or EXTERNAL."
  }
}

variable "deployment_configuration" {
  description = "ECS-native deployment strategy (ROLLING, BLUE_GREEN, LINEAR, or CANARY) with bake time, traffic shifting, and lifecycle hooks. Blue/green needs load_balancers[*].advanced_configuration."
  type = object({
    strategy             = optional(string, "ROLLING")
    bake_time_in_minutes = optional(number)
    canary = optional(object({
      canary_percent              = number
      canary_bake_time_in_minutes = optional(number)
    }))
    linear = optional(object({
      step_percent              = number
      step_bake_time_in_minutes = optional(number)
    }))
    lifecycle_hooks = optional(map(object({
      hook_target_arn  = string
      role_arn         = string
      lifecycle_stages = set(string)
      target_type      = optional(string)
      hook_details     = optional(string)
      timeout = optional(object({
        action             = optional(string)
        timeout_in_minutes = optional(number)
      }))
    })), {})
  })
  default = null

  validation {
    condition     = var.deployment_configuration == null ? true : contains(["ROLLING", "BLUE_GREEN", "LINEAR", "CANARY"], var.deployment_configuration.strategy)
    error_message = "deployment_configuration.strategy must be ROLLING, BLUE_GREEN, LINEAR, or CANARY."
  }
}

variable "alarms" {
  description = "CloudWatch alarms that fail (and by default roll back) a deployment."
  type = object({
    alarm_names = set(string)
    enable      = optional(bool, true)
    rollback    = optional(bool, true)
  })
  default = null

  validation {
    condition     = var.alarms == null ? true : length(var.alarms.alarm_names) > 0
    error_message = "alarms.alarm_names must list at least one alarm."
  }
}

variable "availability_zone_rebalancing" {
  description = "Let ECS rebalance tasks across Availability Zones: ENABLED or DISABLED."
  type        = string
  default     = "ENABLED"
  nullable    = false

  validation {
    condition     = contains(["ENABLED", "DISABLED"], var.availability_zone_rebalancing)
    error_message = "availability_zone_rebalancing must be ENABLED or DISABLED."
  }
}

variable "load_balancers" {
  description = "Target groups the service registers with, keyed by a short name. container_name must be a declared container. advanced_configuration is required for blue/green deployments."
  type = map(object({
    target_group_arn = string
    container_name   = string
    container_port   = number
    advanced_configuration = optional(object({
      alternate_target_group_arn = string
      production_listener_rule   = string
      role_arn                   = string
      test_listener_rule         = optional(string)
    }))
  }))
  default  = {}
  nullable = false
}

variable "service_registries" {
  description = "AWS Cloud Map service registry for the service."
  type = object({
    registry_arn   = string
    port           = optional(number)
    container_name = optional(string)
    container_port = optional(number)
  })
  default = null
}

variable "service_connect_configuration" {
  description = "ECS Service Connect configuration. Each service's port_name must match a named port mapping on a declared container."
  type = object({
    enabled   = optional(bool, true)
    namespace = optional(string)
    log_configuration = optional(object({
      log_driver = string
      options    = optional(map(string), {})
      secret_options = optional(list(object({
        name       = string
        value_from = string
      })), [])
    }))
    services = optional(list(object({
      port_name             = string
      discovery_name        = optional(string)
      ingress_port_override = optional(number)
      client_alias = optional(object({
        port     = number
        dns_name = optional(string)
      }))
      timeout = optional(object({
        idle_timeout_seconds        = optional(number)
        per_request_timeout_seconds = optional(number)
      }))
      tls = optional(object({
        role_arn = optional(string)
        kms_key  = optional(string)
        issuer_cert_authority = object({
          aws_pca_authority_arn = string
        })
      }))
    })), [])
  })
  default = null
}

variable "vpc_lattice_configurations" {
  description = "VPC Lattice target groups the service registers with."
  type = set(object({
    port_name        = string
    role_arn         = string
    target_group_arn = string
  }))
  default  = []
  nullable = false
}

variable "ignore_task_definition_changes" {
  description = "Ignore task definition drift on the service so an external deployer (CI, CodeDeploy) owns rollouts while Terraform still owns the service."
  type        = bool
  default     = false
  nullable    = false
}

variable "timeouts" {
  description = "Create, update, and delete timeouts for the service, as duration strings."
  type = object({
    create = optional(string)
    update = optional(string)
    delete = optional(string)
  })
  default = null
}

# ---------------------------------------------------------------------------
# Networking
# ---------------------------------------------------------------------------

variable "subnet_ids" {
  description = "Subnets the tasks run in. Use at least two, in different Availability Zones, for resilience."
  type        = set(string)
  nullable    = false

  validation {
    condition     = length(var.subnet_ids) >= 1
    error_message = "subnet_ids must list at least one subnet."
  }
}

variable "assign_public_ip" {
  description = "Give tasks a public IP. Leave false; expose services through a load balancer instead."
  type        = bool
  default     = false
  nullable    = false
}

variable "create_security_group" {
  description = "Create a task security group. When false, security_group_ids must supply at least one group."
  type        = bool
  default     = true
  nullable    = false
}

variable "vpc_id" {
  description = "VPC of the managed security group. Required when create_security_group is true."
  type        = string
  default     = null
}

variable "security_group_name" {
  description = "Name of the managed security group. Defaults to name."
  type        = string
  default     = null
}

variable "security_group_description" {
  description = "Description of the managed security group. Changing it replaces the group."
  type        = string
  default     = null
}

variable "security_group_ingress_rules" {
  description = "Ingress rules for the managed security group keyed by a stable identifier. Each rule names exactly one source: cidr_ipv4, cidr_ipv6, prefix_list_id, referenced_security_group_id, or self. Empty by default: nothing can reach the tasks."
  type = map(object({
    description                  = optional(string)
    from_port                    = optional(number)
    to_port                      = optional(number)
    ip_protocol                  = optional(string, "tcp")
    cidr_ipv4                    = optional(string)
    cidr_ipv6                    = optional(string)
    prefix_list_id               = optional(string)
    referenced_security_group_id = optional(string)
    self                         = optional(bool, false)
  }))
  default  = {}
  nullable = false
}

variable "security_group_egress_rules" {
  description = "Egress rules for the managed security group, same shape as security_group_ingress_rules. Declare what the tasks may reach; without egress they cannot pull images."
  type = map(object({
    description                  = optional(string)
    from_port                    = optional(number)
    to_port                      = optional(number)
    ip_protocol                  = optional(string, "tcp")
    cidr_ipv4                    = optional(string)
    cidr_ipv6                    = optional(string)
    prefix_list_id               = optional(string)
    referenced_security_group_id = optional(string)
    self                         = optional(bool, false)
  }))
  default  = {}
  nullable = false
}

variable "security_group_ids" {
  description = "Additional security groups attached to the tasks, or the only groups when create_security_group is false."
  type        = set(string)
  default     = []
  nullable    = false
}

# ---------------------------------------------------------------------------
# IAM
# ---------------------------------------------------------------------------

variable "create_task_execution_role" {
  description = "Create the task execution role. When false, supply task_execution_role_arn and grant it the permissions in output task_execution_role_derived_policy."
  type        = bool
  default     = true
  nullable    = false
}

variable "task_execution_role_arn" {
  description = "Existing task execution role ARN used when create_task_execution_role is false."
  type        = string
  default     = null
}

variable "task_execution_role_name" {
  description = "Name of the created task execution role. Defaults to <name>-execution."
  type        = string
  default     = null
}

variable "task_execution_role_path" {
  description = "IAM path of the created task execution role."
  type        = string
  default     = "/"
  nullable    = false
}

variable "task_execution_role_description" {
  description = "Description of the created task execution role."
  type        = string
  default     = null
}

variable "task_execution_role_permissions_boundary" {
  description = "Permissions boundary policy ARN for the created task execution role."
  type        = string
  default     = null
}

variable "task_execution_role_policy_arns" {
  description = "Additional managed policies attached to the created task execution role."
  type        = set(string)
  default     = []
  nullable    = false
}

variable "task_execution_role_statements" {
  description = "Additional inline statements for the created task execution role, keyed by alphanumeric Sid."
  type = map(object({
    effect    = optional(string, "Allow")
    actions   = set(string)
    resources = set(string)
    conditions = optional(list(object({
      test     = string
      variable = string
      values   = set(string)
    })), [])
  }))
  default  = {}
  nullable = false
}

variable "task_execution_role_kms_key_arns" {
  description = "KMS keys the execution role may decrypt: keys protecting referenced secrets, parameters, or ECR repositories."
  type        = set(string)
  default     = []
  nullable    = false
}

variable "create_task_role" {
  description = "Create the task role. When false, supply task_role_arn."
  type        = bool
  default     = true
  nullable    = false
}

variable "task_role_arn" {
  description = "Existing task role ARN used when create_task_role is false."
  type        = string
  default     = null
}

variable "task_role_name" {
  description = "Name of the created task role. Defaults to <name>-task."
  type        = string
  default     = null
}

variable "task_role_path" {
  description = "IAM path of the created task role."
  type        = string
  default     = "/"
  nullable    = false
}

variable "task_role_description" {
  description = "Description of the created task role."
  type        = string
  default     = null
}

variable "task_role_permissions_boundary" {
  description = "Permissions boundary policy ARN for the created task role."
  type        = string
  default     = null
}

variable "task_role_policy_arns" {
  description = "Managed policies attached to the created task role."
  type        = set(string)
  default     = []
  nullable    = false
}

variable "task_role_statements" {
  description = "Inline statements for the created task role, keyed by alphanumeric Sid. Declare application data access here."
  type = map(object({
    effect    = optional(string, "Allow")
    actions   = set(string)
    resources = set(string)
    conditions = optional(list(object({
      test     = string
      variable = string
      values   = set(string)
    })), [])
  }))
  default  = {}
  nullable = false
}

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

variable "create_cloudwatch_log_group" {
  description = "Create a CloudWatch log group and inject an awslogs configuration into every container that has none."
  type        = bool
  default     = true
  nullable    = false
}

variable "cloudwatch_log_group_name" {
  description = "Log group name. Defaults to /aws/ecs/<cluster>/<name>. When create_cloudwatch_log_group is false and this is set, containers log to the named existing group."
  type        = string
  default     = null
}

variable "cloudwatch_log_group_retention_in_days" {
  description = "Retention of the created log group in days (0 keeps logs forever)."
  type        = number
  default     = 365
  nullable    = false

  validation {
    condition     = contains([0, 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.cloudwatch_log_group_retention_in_days)
    error_message = "cloudwatch_log_group_retention_in_days must be a CloudWatch Logs retention value."
  }
}

variable "cloudwatch_log_group_kms_key_id" {
  description = "KMS key ARN that encrypts the created log group. The key policy must allow the CloudWatch Logs service principal."
  type        = string
  default     = null
}

variable "cloudwatch_log_group_class" {
  description = "Log group class: STANDARD or INFREQUENT_ACCESS."
  type        = string
  default     = "STANDARD"
  nullable    = false

  validation {
    condition     = contains(["STANDARD", "INFREQUENT_ACCESS"], var.cloudwatch_log_group_class)
    error_message = "cloudwatch_log_group_class must be STANDARD or INFREQUENT_ACCESS."
  }
}

variable "cloudwatch_log_group_skip_destroy" {
  description = "Keep the log group and its data when the module is destroyed."
  type        = bool
  default     = false
  nullable    = false
}

# ---------------------------------------------------------------------------
# Autoscaling
# ---------------------------------------------------------------------------

variable "autoscaling" {
  description = "Application Auto Scaling for the service. Null disables it. Omitting policies applies CPU target tracking at 60 percent. See modules/autoscaling for policy and schedule shapes."
  type = object({
    min_capacity = number
    max_capacity = number
    policies = optional(map(object({
      policy_type = optional(string, "TargetTrackingScaling")
      target_tracking = optional(object({
        predefined_metric_type = optional(string)
        resource_label         = optional(string)
        customized_metric = optional(object({
          metric_name = string
          namespace   = string
          statistic   = string
          unit        = optional(string)
          dimensions  = optional(map(string), {})
        }))
        target_value       = number
        scale_in_cooldown  = optional(number, 300)
        scale_out_cooldown = optional(number, 60)
        disable_scale_in   = optional(bool, false)
      }))
      step_scaling = optional(object({
        adjustment_type          = optional(string, "ChangeInCapacity")
        cooldown                 = optional(number, 60)
        metric_aggregation_type  = optional(string, "Average")
        min_adjustment_magnitude = optional(number)
        step_adjustments = list(object({
          scaling_adjustment          = number
          metric_interval_lower_bound = optional(number)
          metric_interval_upper_bound = optional(number)
        }))
      }))
    })))
    scheduled_actions = optional(map(object({
      schedule     = string
      timezone     = optional(string)
      min_capacity = optional(number)
      max_capacity = optional(number)
      start_time   = optional(string)
      end_time     = optional(string)
    })), {})
  })
  default = null

  validation {
    condition     = var.autoscaling == null ? true : (var.autoscaling.min_capacity >= 0 && var.autoscaling.max_capacity >= var.autoscaling.min_capacity)
    error_message = "autoscaling.min_capacity must be non-negative and no greater than autoscaling.max_capacity."
  }
}
