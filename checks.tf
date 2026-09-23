# Advisory checks: they warn on every plan and apply but never block. Each
# describes a configuration that is valid yet usually unintended.

check "security_group_egress" {
  assert {
    condition     = !var.create_security_group || length(var.security_group_egress_rules) > 0
    error_message = "The managed task security group has no egress rules. Tasks cannot pull images or reach dependencies unless another attached security group allows it."
  }
}

check "multi_az" {
  assert {
    condition     = length(var.subnet_ids) >= 2
    error_message = "The service runs in a single subnet. Use at least two subnets in different Availability Zones for resilience."
  }
}

check "supplied_execution_role_secrets" {
  assert {
    condition     = var.create_task_execution_role || length(local.secret_arns) == 0
    error_message = "Containers reference secrets or parameters but the task execution role is caller-supplied. Attach output task_execution_role_derived_policy (or equivalent) to that role or tasks will fail to start."
  }
}
