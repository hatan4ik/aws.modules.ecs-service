resource "aws_appautoscaling_target" "this" {
  service_namespace  = "ecs"
  scalable_dimension = "ecs:service:DesiredCount"
  resource_id        = "service/${var.cluster_name}/${var.service_name}"
  min_capacity       = var.min_capacity
  max_capacity       = var.max_capacity

  tags = var.tags

  lifecycle {
    precondition {
      condition     = var.min_capacity <= var.max_capacity
      error_message = "min_capacity must be less than or equal to max_capacity."
    }
  }
}

resource "aws_appautoscaling_policy" "this" {
  for_each = var.policies

  name               = "${var.service_name}-${each.key}"
  policy_type        = each.value.policy_type
  service_namespace  = aws_appautoscaling_target.this.service_namespace
  scalable_dimension = aws_appautoscaling_target.this.scalable_dimension
  resource_id        = aws_appautoscaling_target.this.resource_id

  dynamic "target_tracking_scaling_policy_configuration" {
    for_each = each.value.target_tracking == null ? [] : [each.value.target_tracking]

    content {
      target_value       = target_tracking_scaling_policy_configuration.value.target_value
      scale_in_cooldown  = target_tracking_scaling_policy_configuration.value.scale_in_cooldown
      scale_out_cooldown = target_tracking_scaling_policy_configuration.value.scale_out_cooldown
      disable_scale_in   = target_tracking_scaling_policy_configuration.value.disable_scale_in

      dynamic "predefined_metric_specification" {
        for_each = target_tracking_scaling_policy_configuration.value.predefined_metric_type == null ? [] : [target_tracking_scaling_policy_configuration.value]

        content {
          predefined_metric_type = predefined_metric_specification.value.predefined_metric_type
          resource_label         = predefined_metric_specification.value.resource_label
        }
      }

      dynamic "customized_metric_specification" {
        for_each = target_tracking_scaling_policy_configuration.value.customized_metric == null ? [] : [target_tracking_scaling_policy_configuration.value.customized_metric]

        content {
          metric_name = customized_metric_specification.value.metric_name
          namespace   = customized_metric_specification.value.namespace
          statistic   = customized_metric_specification.value.statistic
          unit        = customized_metric_specification.value.unit

          dynamic "dimensions" {
            for_each = customized_metric_specification.value.dimensions

            content {
              name  = dimensions.key
              value = dimensions.value
            }
          }
        }
      }
    }
  }

  dynamic "step_scaling_policy_configuration" {
    for_each = each.value.step_scaling == null ? [] : [each.value.step_scaling]

    content {
      adjustment_type          = step_scaling_policy_configuration.value.adjustment_type
      cooldown                 = step_scaling_policy_configuration.value.cooldown
      metric_aggregation_type  = step_scaling_policy_configuration.value.metric_aggregation_type
      min_adjustment_magnitude = step_scaling_policy_configuration.value.min_adjustment_magnitude

      dynamic "step_adjustment" {
        for_each = step_scaling_policy_configuration.value.step_adjustments

        content {
          scaling_adjustment          = step_adjustment.value.scaling_adjustment
          metric_interval_lower_bound = step_adjustment.value.metric_interval_lower_bound
          metric_interval_upper_bound = step_adjustment.value.metric_interval_upper_bound
        }
      }
    }
  }
}

resource "aws_appautoscaling_scheduled_action" "this" {
  for_each = var.scheduled_actions

  name               = "${var.service_name}-${each.key}"
  service_namespace  = aws_appautoscaling_target.this.service_namespace
  scalable_dimension = aws_appautoscaling_target.this.scalable_dimension
  resource_id        = aws_appautoscaling_target.this.resource_id
  schedule           = each.value.schedule
  timezone           = each.value.timezone
  start_time         = each.value.start_time
  end_time           = each.value.end_time

  scalable_target_action {
    min_capacity = each.value.min_capacity
    max_capacity = each.value.max_capacity
  }
}
