variable "cluster_name" {
  description = "Name of the ECS cluster hosting the service."
  type        = string
  nullable    = false
}

variable "service_name" {
  description = "Name of the ECS service to scale. Also prefixes policy and scheduled-action names."
  type        = string
  nullable    = false
}

variable "min_capacity" {
  description = "Minimum number of tasks Application Auto Scaling may keep running."
  type        = number
  nullable    = false

  validation {
    condition     = var.min_capacity >= 0
    error_message = "min_capacity must be zero or greater."
  }
}

variable "max_capacity" {
  description = "Maximum number of tasks Application Auto Scaling may run."
  type        = number
  nullable    = false

  validation {
    condition     = var.max_capacity >= 0
    error_message = "max_capacity must be zero or greater."
  }
}

variable "policies" {
  description = "Scaling policies keyed by a short name. Defaults (also when null) to CPU target tracking at 60 percent; pass {} for a target with no policies. Target tracking uses one predefined ECS/ALB metric or one customized CloudWatch metric; step scaling needs a caller-managed CloudWatch alarm that targets the policy ARN."
  type = map(object({
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
  }))
  default = {
    cpu = { target_tracking = { predefined_metric_type = "ECSServiceAverageCPUUtilization", target_value = 60 } }
  }
  nullable = false

  validation {
    condition     = alltrue([for key in keys(var.policies) : can(regex("^[a-z0-9][a-z0-9-]{0,62}$", key))])
    error_message = "Policy keys must be 1-63 lowercase alphanumeric characters or hyphens."
  }

  validation {
    condition = alltrue([for policy in values(var.policies) :
      contains(["TargetTrackingScaling", "StepScaling"], policy.policy_type) &&
      (policy.policy_type == "TargetTrackingScaling" ? (policy.target_tracking != null && policy.step_scaling == null) : (policy.step_scaling != null && policy.target_tracking == null))
    ])
    error_message = "Each policy must be TargetTrackingScaling with a target_tracking block or StepScaling with a step_scaling block, never both."
  }

  validation {
    condition = alltrue([for policy in values(var.policies) : policy.target_tracking == null ? true : (
      (policy.target_tracking.predefined_metric_type != null) != (policy.target_tracking.customized_metric != null) &&
      policy.target_tracking.target_value > 0 &&
      policy.target_tracking.scale_in_cooldown >= 0 && policy.target_tracking.scale_out_cooldown >= 0 &&
      (policy.target_tracking.predefined_metric_type == null ? true : contains(["ECSServiceAverageCPUUtilization", "ECSServiceAverageMemoryUtilization", "ALBRequestCountPerTarget"], policy.target_tracking.predefined_metric_type)) &&
      (policy.target_tracking.predefined_metric_type == "ALBRequestCountPerTarget" ? policy.target_tracking.resource_label != null : true)
    )])
    error_message = "Target tracking needs exactly one of predefined_metric_type (ECSServiceAverageCPUUtilization, ECSServiceAverageMemoryUtilization, or ALBRequestCountPerTarget with resource_label) or customized_metric, a positive target_value, and non-negative cooldowns."
  }

  validation {
    condition = alltrue([for policy in values(var.policies) : policy.step_scaling == null ? true : (
      length(policy.step_scaling.step_adjustments) > 0 &&
      contains(["ChangeInCapacity", "ExactCapacity", "PercentChangeInCapacity"], policy.step_scaling.adjustment_type) &&
      contains(["Average", "Minimum", "Maximum"], policy.step_scaling.metric_aggregation_type)
    )])
    error_message = "Step scaling needs at least one step adjustment, adjustment_type ChangeInCapacity/ExactCapacity/PercentChangeInCapacity, and metric_aggregation_type Average/Minimum/Maximum."
  }
}

variable "scheduled_actions" {
  description = "Scheduled capacity changes keyed by a short name. schedule is an at(), cron(), or rate() expression; at least one of min_capacity or max_capacity must be set."
  type = map(object({
    schedule     = string
    timezone     = optional(string)
    min_capacity = optional(number)
    max_capacity = optional(number)
    start_time   = optional(string)
    end_time     = optional(string)
  }))
  default  = {}
  nullable = false

  validation {
    condition = alltrue([for key, action in var.scheduled_actions :
      can(regex("^[a-zA-Z0-9][a-zA-Z0-9_-]{0,62}$", key)) &&
      can(regex("^(at|cron|rate)\\(.+\\)$", action.schedule)) &&
      (action.min_capacity != null || action.max_capacity != null)
    ])
    error_message = "Each scheduled action needs a key of letters, digits, hyphens, or underscores, an at()/cron()/rate() schedule, and at least one of min_capacity or max_capacity."
  }
}

variable "tags" {
  description = "Tags applied to the scalable target."
  type        = map(string)
  default     = {}
  nullable    = false
}
