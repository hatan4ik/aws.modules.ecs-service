output "container_definition" {
  description = "Rendered ECS container definition (camelCase keys, nulls stripped) ready for jsonencode into a task definition."
  value       = local.container_definition

  precondition {
    condition     = !var.require_image_digest || can(regex("@sha256:[0-9a-f]{64}$", var.image))
    error_message = "image must be pinned to an immutable sha256 digest (repository@sha256:<64 hex>). Set require_image_digest = false to opt out deliberately."
  }
}

output "secret_arns" {
  description = "Sorted, de-duplicated ARNs referenced by secrets and log secret options; used to derive execution-role permissions."
  value       = local.secret_arns
}
