variable "name" {
  description = "Container name. Unique within the task definition; referenced by port mappings, dependencies, load balancers, and Service Connect."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9_-]{0,254}$", var.name))
    error_message = "name must be 1-255 characters of letters, digits, hyphens, or underscores, starting with a letter or digit."
  }
}

variable "image" {
  description = "Container image reference. By default it must be pinned to an immutable sha256 digest; see require_image_digest."
  type        = string
  nullable    = false
}

variable "require_image_digest" {
  description = "Reject image references that are not pinned to a sha256 digest. Mutable tags make deployments non-reproducible and defeat rollback."
  type        = bool
  default     = true
  nullable    = false
}

variable "essential" {
  description = "Whether the task stops when this container exits. At least one container per task must be essential."
  type        = bool
  default     = true
  nullable    = false
}

variable "command" {
  description = "Command passed to the container, overriding the image CMD."
  type        = list(string)
  default     = null
}

variable "entrypoint" {
  description = "Entry point passed to the container, overriding the image ENTRYPOINT."
  type        = list(string)
  default     = null
}

variable "working_directory" {
  description = "Working directory in which commands run inside the container."
  type        = string
  default     = null
}

variable "user" {
  description = "User (and optional group) the container process runs as, for example \"1000:1000\". Prefer a non-root user."
  type        = string
  default     = null
}

variable "cpu" {
  description = "CPU units reserved for this container. Optional on Fargate; the task-level cpu is the hard limit."
  type        = number
  default     = null
}

variable "memory" {
  description = "Hard memory limit in MiB for this container. The container is killed when it exceeds this value."
  type        = number
  default     = null
}

variable "memory_reservation" {
  description = "Soft memory reservation in MiB for this container."
  type        = number
  default     = null
}

variable "environment" {
  description = "Plain-text environment variables. Values are visible in the task definition; use secrets for sensitive values."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "environment_files" {
  description = "Environment files loaded from S3 objects (.env format)."
  type = list(object({
    type  = optional(string, "s3")
    value = string
  }))
  default  = []
  nullable = false

  validation {
    condition     = alltrue([for file in var.environment_files : file.type == "s3" && can(regex("^arn:[^:]+:s3:::", file.value))])
    error_message = "Each environment file must be type \"s3\" with an S3 object ARN as its value."
  }
}

variable "secrets" {
  description = "Secrets injected as environment variables. Keys are variable names; values are AWS Secrets Manager secret ARNs (optionally with :json-key:version-stage:version-id) or SSM Parameter Store parameter ARNs."
  type        = map(string)
  default     = {}
  nullable    = false

  validation {
    condition     = alltrue([for value in values(var.secrets) : can(regex("^arn:[^:]+:(secretsmanager|ssm):", value))])
    error_message = "Every secret value must be a Secrets Manager secret ARN or an SSM parameter ARN."
  }
}

variable "port_mappings" {
  description = "Ports the container exposes. On Fargate (awsvpc) hostPort always equals containerPort. Set name to reference the port from Service Connect."
  type = list(object({
    name           = optional(string)
    container_port = number
    host_port      = optional(number)
    protocol       = optional(string, "tcp")
    app_protocol   = optional(string)
  }))
  default  = []
  nullable = false

  validation {
    condition = alltrue([for mapping in var.port_mappings :
      mapping.container_port >= 1 && mapping.container_port <= 65535 &&
      (mapping.host_port == null ? true : mapping.host_port == mapping.container_port) &&
      contains(["tcp", "udp"], mapping.protocol) &&
      (mapping.app_protocol == null ? true : contains(["http", "http2", "grpc"], mapping.app_protocol))
    ])
    error_message = "Each port mapping needs container_port 1-65535, host_port equal to container_port (awsvpc), protocol tcp or udp, and app_protocol http, http2, or grpc when set."
  }
}

variable "health_check" {
  description = "Container health check run by the ECS agent. The command is an exec-style list, usually starting with CMD-SHELL."
  type = object({
    command      = list(string)
    interval     = optional(number, 30)
    timeout      = optional(number, 5)
    retries      = optional(number, 3)
    start_period = optional(number)
  })
  default = null

  validation {
    condition = var.health_check == null ? true : (
      length(var.health_check.command) > 0 &&
      var.health_check.interval >= 5 && var.health_check.interval <= 300 &&
      var.health_check.timeout >= 2 && var.health_check.timeout <= 60 &&
      var.health_check.retries >= 1 && var.health_check.retries <= 10 &&
      (var.health_check.start_period == null ? true : (var.health_check.start_period >= 0 && var.health_check.start_period <= 300))
    )
    error_message = "health_check needs a non-empty command, interval 5-300, timeout 2-60, retries 1-10, and start_period 0-300 when set."
  }
}

variable "readonly_root_filesystem" {
  description = "Mount the container root filesystem read-only. Keep enabled and write to declared volumes or /tmp mounts instead."
  type        = bool
  default     = true
  nullable    = false
}

variable "linux_parameters" {
  description = "Linux-specific options. Fargate supports initProcessEnabled and capabilities (add is limited to SYS_PTRACE; drop may remove any capability)."
  type = object({
    init_process_enabled = optional(bool, false)
    capabilities = optional(object({
      add  = optional(list(string), [])
      drop = optional(list(string), [])
    }))
  })
  default = null

  validation {
    condition     = var.linux_parameters == null ? true : (var.linux_parameters.capabilities == null ? true : alltrue([for capability in var.linux_parameters.capabilities.add : capability == "SYS_PTRACE"]))
    error_message = "Fargate permits adding only the SYS_PTRACE capability."
  }
}

variable "ulimits" {
  description = "Resource limits applied to the container process."
  type = list(object({
    name       = string
    soft_limit = number
    hard_limit = number
  }))
  default  = []
  nullable = false
}

variable "mount_points" {
  description = "Task volumes mounted into the container. source_volume must match a volume declared on the task definition."
  type = list(object({
    source_volume  = string
    container_path = string
    read_only      = optional(bool, false)
  }))
  default  = []
  nullable = false
}

variable "volumes_from" {
  description = "Volumes inherited from another container in the task."
  type = list(object({
    source_container = string
    read_only        = optional(bool, false)
  }))
  default  = []
  nullable = false
}

variable "container_dependencies" {
  description = "Start-order dependencies on other containers in the task."
  type = list(object({
    container_name = string
    condition      = string
  }))
  default  = []
  nullable = false

  validation {
    condition     = alltrue([for dependency in var.container_dependencies : contains(["START", "COMPLETE", "SUCCESS", "HEALTHY"], dependency.condition)])
    error_message = "Each dependency condition must be START, COMPLETE, SUCCESS, or HEALTHY."
  }
}

variable "start_timeout" {
  description = "Seconds to wait for dependencies before giving up on starting this container."
  type        = number
  default     = null
}

variable "stop_timeout" {
  description = "Seconds to wait after SIGTERM before the container is forcibly killed. Fargate allows 2-120."
  type        = number
  default     = null

  validation {
    condition     = var.stop_timeout == null ? true : (var.stop_timeout >= 2 && var.stop_timeout <= 120)
    error_message = "stop_timeout must be between 2 and 120 seconds on Fargate."
  }
}

variable "docker_labels" {
  description = "Key/value labels added to the container."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "system_controls" {
  description = "Kernel parameters (sysctls) set in the container."
  type = list(object({
    namespace = string
    value     = string
  }))
  default  = []
  nullable = false
}

variable "log_configuration" {
  description = "Log driver configuration. When null, the parent module injects an awslogs configuration for its managed log group."
  type = object({
    log_driver = string
    options    = optional(map(string), {})
    secret_options = optional(list(object({
      name       = string
      value_from = string
    })), [])
  })
  default = null

  validation {
    condition     = var.log_configuration == null ? true : alltrue([for option in var.log_configuration.secret_options : can(regex("^arn:[^:]+:(secretsmanager|ssm):", option.value_from))])
    error_message = "Each log secret option must reference a Secrets Manager secret ARN or an SSM parameter ARN."
  }
}

variable "repository_credentials" {
  description = "Secrets Manager secret ARN holding private registry credentials."
  type = object({
    credentials_parameter = string
  })
  default = null
}

variable "firelens_configuration" {
  description = "FireLens log router configuration for a fluentbit or fluentd sidecar."
  type = object({
    type    = string
    options = optional(map(string), {})
  })
  default = null

  validation {
    condition     = var.firelens_configuration == null ? true : contains(["fluentbit", "fluentd"], var.firelens_configuration.type)
    error_message = "firelens_configuration.type must be fluentbit or fluentd."
  }
}

variable "restart_policy" {
  description = "Container restart policy that restarts the container in place instead of replacing the task."
  type = object({
    enabled                = bool
    ignored_exit_codes     = optional(list(number), [])
    restart_attempt_period = optional(number)
  })
  default = null

  validation {
    condition     = var.restart_policy == null ? true : (var.restart_policy.restart_attempt_period == null ? true : (var.restart_policy.restart_attempt_period >= 60 && var.restart_policy.restart_attempt_period <= 1800))
    error_message = "restart_policy.restart_attempt_period must be between 60 and 1800 seconds when set."
  }
}

variable "interactive" {
  description = "Allocate stdin for the container (docker run -i)."
  type        = bool
  default     = false
  nullable    = false
}

variable "pseudo_terminal" {
  description = "Allocate a TTY for the container (docker run -t)."
  type        = bool
  default     = false
  nullable    = false
}

variable "version_consistency" {
  description = "Whether ECS resolves the image tag to a digest at deployment time (enabled or disabled). Irrelevant when the image is already digest-pinned."
  type        = string
  default     = null

  validation {
    condition     = var.version_consistency == null ? true : contains(["enabled", "disabled"], var.version_consistency)
    error_message = "version_consistency must be enabled or disabled when set."
  }
}
