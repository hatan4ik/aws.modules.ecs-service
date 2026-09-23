variable "name" {
  description = "Service name used to derive role names (<name>-execution and <name>-task) unless explicit names are given."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,52}[a-z0-9])?$", var.name))
    error_message = "name must be 1-54 lowercase alphanumeric characters or hyphens, so derived role names fit the 64-character IAM limit."
  }
}

variable "cluster_arn" {
  description = "ARN of the ECS cluster the tasks run in. Provides the partition, region, and account used in trust-policy conditions and managed-policy ARNs."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^arn:[a-z-]+:ecs:[a-z0-9-]+:[0-9]{12}:cluster/[A-Za-z0-9_-]+$", var.cluster_arn))
    error_message = "cluster_arn must be a full ECS cluster ARN (arn:<partition>:ecs:<region>:<account>:cluster/<name>)."
  }
}

variable "tags" {
  description = "Tags applied to every role this module creates."
  type        = map(string)
  default     = {}
  nullable    = false
}

# ---------------------------------------------------------------------------
# Task execution role: used by the ECS agent to pull images, write logs, and
# fetch secrets before the container starts.
# ---------------------------------------------------------------------------

variable "create_task_execution_role" {
  description = "Create the task execution role. Set false and supply task_execution_role_arn to use an existing role; the module never modifies a supplied role."
  type        = bool
  default     = true
  nullable    = false
}

variable "task_execution_role_arn" {
  description = "Existing task execution role ARN, required when create_task_execution_role is false."
  type        = string
  default     = null
}

variable "task_execution_role_name" {
  description = "Name of the created task execution role. Defaults to <name>-execution."
  type        = string
  default     = null

  validation {
    condition     = var.task_execution_role_name == null ? true : (length(var.task_execution_role_name) <= 64 && can(regex("^[\\w+=,.@-]+$", var.task_execution_role_name)))
    error_message = "task_execution_role_name must be at most 64 characters of letters, digits, or +=,.@_- ."
  }
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
  description = "Permissions boundary policy ARN applied to the created task execution role."
  type        = string
  default     = null
}

variable "task_execution_role_policy_arns" {
  description = "Additional managed policy ARNs attached to the created task execution role. AmazonECSTaskExecutionRolePolicy is always attached."
  type        = set(string)
  default     = []
  nullable    = false
}

variable "task_execution_role_statements" {
  description = "Extra inline policy statements for the created task execution role, keyed by Sid (alphanumeric)."
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

  validation {
    condition = alltrue([for sid, statement in var.task_execution_role_statements :
      can(regex("^[A-Za-z0-9]{1,100}$", sid)) &&
      contains(["Allow", "Deny"], statement.effect) &&
      length(statement.actions) > 0 && length(statement.resources) > 0 &&
      length(distinct([for condition in statement.conditions : "${condition.test}|${condition.variable}"])) == length(statement.conditions)
    ])
    error_message = "Each statement key must be an alphanumeric Sid, effect must be Allow or Deny, actions and resources must be non-empty, and condition test/variable pairs must be unique."
  }
}

variable "secret_arns" {
  description = "Secrets Manager secret and SSM parameter ARNs referenced by the task's containers. The execution role is granted read access to exactly these."
  type        = set(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for arn in var.secret_arns : can(regex("^arn:[^:]+:(secretsmanager|ssm):", arn))])
    error_message = "Every secret ARN must be a Secrets Manager secret ARN or an SSM parameter ARN."
  }
}

variable "kms_key_arns" {
  description = "KMS key ARNs the execution role may decrypt: keys protecting secrets, parameters, or ECR repositories."
  type        = set(string)
  default     = []
  nullable    = false
}

# ---------------------------------------------------------------------------
# Task role: assumed by the application code inside the containers.
# ---------------------------------------------------------------------------

variable "create_task_role" {
  description = "Create the task role. Set false and supply task_role_arn to use an existing role; the module never modifies a supplied role."
  type        = bool
  default     = true
  nullable    = false
}

variable "task_role_arn" {
  description = "Existing task role ARN, required when create_task_role is false."
  type        = string
  default     = null
}

variable "task_role_name" {
  description = "Name of the created task role. Defaults to <name>-task."
  type        = string
  default     = null

  validation {
    condition     = var.task_role_name == null ? true : (length(var.task_role_name) <= 64 && can(regex("^[\\w+=,.@-]+$", var.task_role_name)))
    error_message = "task_role_name must be at most 64 characters of letters, digits, or +=,.@_- ."
  }
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
  description = "Permissions boundary policy ARN applied to the created task role."
  type        = string
  default     = null
}

variable "task_role_policy_arns" {
  description = "Managed policy ARNs attached to the created task role."
  type        = set(string)
  default     = []
  nullable    = false
}

variable "task_role_statements" {
  description = "Inline policy statements for the created task role, keyed by Sid (alphanumeric). This is where application data access is declared."
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

  validation {
    condition = alltrue([for sid, statement in var.task_role_statements :
      can(regex("^[A-Za-z0-9]{1,100}$", sid)) &&
      contains(["Allow", "Deny"], statement.effect) &&
      length(statement.actions) > 0 && length(statement.resources) > 0 &&
      length(distinct([for condition in statement.conditions : "${condition.test}|${condition.variable}"])) == length(statement.conditions)
    ])
    error_message = "Each statement key must be an alphanumeric Sid, effect must be Allow or Deny, actions and resources must be non-empty, and condition test/variable pairs must be unique."
  }
}

variable "enable_execute_command" {
  description = "Grant the task role the SSM messages permissions ECS Exec needs."
  type        = bool
  default     = false
  nullable    = false
}
