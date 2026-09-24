variable "name_prefix" {
  description = "Prefix for every disposable fixture; a random suffix is appended so concurrent runs never collide."
  type        = string
  default     = "ecs-service-it"

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,38}[a-z0-9])?$", var.name_prefix))
    error_message = "name_prefix must be 1-40 lowercase alphanumeric characters or hyphens."
  }
}

variable "cidr_block" {
  description = "CIDR of the disposable VPC."
  type        = string
  default     = "10.99.0.0/16"
}

variable "public_subnets" {
  description = "Also create two public subnets with an internet gateway route, for suites that pull public images without a NAT gateway."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags applied to every fixture in addition to the identifying defaults."
  type        = map(string)
  default     = {}
}
