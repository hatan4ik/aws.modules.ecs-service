module "autoscaling" {
  source = "./modules/autoscaling"
  count  = var.autoscaling == null ? 0 : 1

  cluster_name      = local.cluster_name
  service_name      = local.service.name
  min_capacity      = var.autoscaling.min_capacity
  max_capacity      = var.autoscaling.max_capacity
  policies          = var.autoscaling.policies
  scheduled_actions = var.autoscaling.scheduled_actions
  tags              = var.tags
}
