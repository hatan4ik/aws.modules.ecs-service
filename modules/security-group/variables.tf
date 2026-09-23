variable "create" {
  description = "Create the security group and its rules. When false the module creates nothing and outputs null identifiers."
  type        = bool
  default     = true
  nullable    = false
}

variable "name" {
  description = "Security group name. Must be unique within the VPC."
  type        = string
  nullable    = false

  validation {
    condition     = length(var.name) >= 1 && length(var.name) <= 255 && !startswith(var.name, "sg-")
    error_message = "name must be 1-255 characters and must not start with sg-."
  }
}

variable "description" {
  description = "Security group description. Changing it replaces the group."
  type        = string
  default     = "ECS task security group"
  nullable    = false
}

variable "vpc_id" {
  description = "VPC the security group belongs to. Required when create is true."
  type        = string
  default     = null
}

variable "ingress_rules" {
  description = "Ingress rules keyed by a stable identifier. Each rule names exactly one source: cidr_ipv4, cidr_ipv6, prefix_list_id, referenced_security_group_id, or self."
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

  validation {
    condition = alltrue([for rule in values(var.ingress_rules) :
      length([for source in [rule.cidr_ipv4, rule.cidr_ipv6, rule.prefix_list_id, rule.referenced_security_group_id] : source if source != null]) + (rule.self ? 1 : 0) == 1
    ])
    error_message = "Each ingress rule must declare exactly one source: cidr_ipv4, cidr_ipv6, prefix_list_id, referenced_security_group_id, or self."
  }

  validation {
    condition = alltrue([for rule in values(var.ingress_rules) :
      rule.ip_protocol == "-1" ? (rule.from_port == null && rule.to_port == null) : (
        (rule.from_port == null || rule.to_port == null) ? false : (rule.from_port >= -1 && rule.to_port <= 65535 && rule.from_port <= rule.to_port)
      )
    ])
    error_message = "Ingress rules for a specific protocol need from_port and to_port (-1 to 65535, from_port <= to_port); all-protocol (-1) rules must not set ports."
  }
}

variable "egress_rules" {
  description = "Egress rules keyed by a stable identifier, same shape as ingress_rules. A group with no egress rules cannot pull images or reach any dependency."
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

  validation {
    condition = alltrue([for rule in values(var.egress_rules) :
      length([for source in [rule.cidr_ipv4, rule.cidr_ipv6, rule.prefix_list_id, rule.referenced_security_group_id] : source if source != null]) + (rule.self ? 1 : 0) == 1
    ])
    error_message = "Each egress rule must declare exactly one destination: cidr_ipv4, cidr_ipv6, prefix_list_id, referenced_security_group_id, or self."
  }

  validation {
    condition = alltrue([for rule in values(var.egress_rules) :
      rule.ip_protocol == "-1" ? (rule.from_port == null && rule.to_port == null) : (
        (rule.from_port == null || rule.to_port == null) ? false : (rule.from_port >= -1 && rule.to_port <= 65535 && rule.from_port <= rule.to_port)
      )
    ])
    error_message = "Egress rules for a specific protocol need from_port and to_port (-1 to 65535, from_port <= to_port); all-protocol (-1) rules must not set ports."
  }
}

variable "tags" {
  description = "Tags applied to the security group and every rule."
  type        = map(string)
  default     = {}
  nullable    = false
}
