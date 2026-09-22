variable "name" {
  description = "Stable lowercase prefix for the workload resources."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,47}$", var.name))
    error_message = "name must be a 3-48 character lowercase, hyphenated identifier."
  }
}

variable "cluster_arn" {
  description = "ARN of the existing ECS cluster that hosts the private Fargate services."
  type        = string
  nullable    = false
}

variable "cluster_name" {
  description = "Name of the existing ECS cluster, required by Application Auto Scaling."
  type        = string
  nullable    = false
}

variable "vpc_id" {
  description = "ID of the private workload VPC."
  type        = string
  nullable    = false
}

variable "vpc_cidr" {
  description = "CIDR of the private workload VPC. Task security groups allow only TLS egress to this CIDR by default."
  type        = string
  nullable    = false
}

variable "private_subnet_ids" {
  description = "At least two existing private subnet IDs, one per Availability Zone."
  type        = set(string)
  nullable    = false

  validation {
    condition     = length(var.private_subnet_ids) >= 2
    error_message = "At least two private subnet IDs are required."
  }
}

variable "application_data_kms_key_arn" {
  description = "KMS key used by application log groups and optionally granted to task execution roles for encrypted secrets."
  type        = string
  nullable    = false
}

variable "log_retention_in_days" {
  description = "CloudWatch retention for per-service application logs."
  type        = number
  nullable    = false

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.log_retention_in_days)
    error_message = "log_retention_in_days must be an AWS CloudWatch Logs retention value."
  }
}

variable "cognito_user_pool_id" {
  description = "Existing Cognito user-pool ID. Required only by applications that declare a Cognito app client."
  type        = string
  default     = null
  nullable    = true
}

variable "session_table_arn" {
  description = "Existing application session-table ARN. Required only by applications that opt into session-table access."
  type        = string
  default     = null
  nullable    = true
}

variable "tags" {
  description = "Mandatory ownership and cost-allocation tags applied to every supported resource."
  type        = map(string)
  nullable    = false
}

variable "applications" {
  description = "Map of immutable-image private Fargate services. An empty map creates no workload resources."
  type = map(object({
    image_digest  = string
    cpu           = number
    memory        = number
    desired_count = number
    autoscaling = object({
      min_capacity       = number
      max_capacity       = number
      cpu_target_percent = optional(number, 60)
    })
    container_port              = optional(number)
    command                     = optional(list(string), [])
    environment                 = optional(map(string), {})
    secret_arns                 = optional(map(string), {})
    secret_kms_key_arns         = optional(set(string), [])
    task_policy_statements      = optional(map(object({ actions = set(string), resources = set(string) })), {})
    enable_session_table_access = optional(bool, false)
    ingress_security_group_ids  = optional(set(string), [])
    enable_execute_command      = optional(bool, false)
    readonly_root_filesystem    = optional(bool, true)
    ephemeral_storage_gib       = optional(number)
    cpu_architecture            = optional(string, "X86_64")
    health_check = optional(object({
      command      = list(string)
      interval     = number
      timeout      = number
      retries      = number
      start_period = number
    }))
    cognito = optional(object({
      callback_urls                = set(string)
      logout_urls                  = set(string)
      allowed_oauth_scopes         = set(string)
      supported_identity_providers = optional(set(string), ["COGNITO"])
    }))
    tags = optional(map(string), {})
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for key in keys(var.applications) : can(regex("^[a-z][a-z0-9-]{1,30}$", key))])
    error_message = "Application keys must be 2-31 character lowercase, hyphenated identifiers."
  }

  validation {
    condition     = alltrue([for application in values(var.applications) : can(regex("@sha256:[0-9a-f]{64}$", application.image_digest))])
    error_message = "Every image_digest must end with an immutable OCI sha256 digest."
  }

  validation {
    condition = alltrue([for application in values(var.applications) : contains(lookup({
      "256"   = [512, 1024, 2048]
      "512"   = [1024, 2048, 3072, 4096]
      "1024"  = [2048, 3072, 4096, 5120, 6144, 7168, 8192]
      "2048"  = [4096, 5120, 6144, 7168, 8192, 9216, 10240, 11264, 12288, 13312, 14336, 15360, 16384]
      "4096"  = [8192, 9216, 10240, 11264, 12288, 13312, 14336, 15360, 16384, 17408, 18432, 19456, 20480, 21504, 22528, 23552, 24576, 25600, 26624, 27648, 28672, 29696, 30720]
      "8192"  = [16384, 20480, 24576, 28672, 32768, 36864, 40960, 45056, 49152, 53248, 57344, 61440]
      "16384" = [32768, 40960, 49152, 57344, 65536, 73728, 81920, 90112, 98304, 106496, 114688, 122880]
    }, tostring(application.cpu), []), application.memory)])
    error_message = "Each CPU and memory pair must be a supported Fargate task-size combination."
  }

  validation {
    condition = alltrue([for application in values(var.applications) : (
      application.desired_count >= application.autoscaling.min_capacity &&
      application.desired_count <= application.autoscaling.max_capacity &&
      application.autoscaling.min_capacity >= 0 &&
      application.autoscaling.max_capacity >= 0 &&
      application.autoscaling.cpu_target_percent >= 10 &&
      application.autoscaling.cpu_target_percent <= 90
    )])
    error_message = "desired_count must be inside non-negative autoscaling bounds and CPU target must be 10-90 percent."
  }

  validation {
    condition     = alltrue([for application in values(var.applications) : application.container_port == null ? true : (application.container_port >= 1 && application.container_port <= 65535)])
    error_message = "container_port, when set, must be between 1 and 65535."
  }

  validation {
    condition     = alltrue([for application in values(var.applications) : application.ephemeral_storage_gib == null ? true : (application.ephemeral_storage_gib >= 21 && application.ephemeral_storage_gib <= 200)])
    error_message = "ephemeral_storage_gib, when set, must be between 21 and 200 GiB."
  }

  validation {
    condition     = alltrue([for application in values(var.applications) : application.cpu_architecture == "X86_64" || application.cpu_architecture == "ARM64"])
    error_message = "cpu_architecture must be X86_64 or ARM64."
  }

  validation {
    condition = alltrue(flatten([for application in values(var.applications) : concat(
      [for secret_arn in values(application.secret_arns) : startswith(secret_arn, "arn:")],
      application.cognito == null ? [] : [for url in application.cognito.callback_urls : startswith(url, "https://")],
      application.cognito == null ? [] : [for url in application.cognito.logout_urls : startswith(url, "https://")]
    )]))
    error_message = "Secret ARNs must be ARNs and Cognito callback/logout URLs must use HTTPS."
  }
}
