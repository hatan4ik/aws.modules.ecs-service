mock_provider "aws" {}

variables {
  cluster_name = "platform"
  service_name = "orders-api"
  min_capacity = 2
  max_capacity = 10
  tags         = { Environment = "test" }
}

run "registers_target_with_predefined_target_tracking" {
  command = plan

  variables {
    policies = {
      cpu = { target_tracking = { predefined_metric_type = "ECSServiceAverageCPUUtilization", target_value = 60 } }
      requests = {
        target_tracking = {
          predefined_metric_type = "ALBRequestCountPerTarget"
          resource_label         = "app/platform/0123456789abcdef/targetgroup/orders/0123456789abcdef"
          target_value           = 1000
          scale_in_cooldown      = 600
          disable_scale_in       = true
        }
      }
    }
  }

  assert {
    condition     = aws_appautoscaling_target.this.resource_id == "service/platform/orders-api" && aws_appautoscaling_target.this.scalable_dimension == "ecs:service:DesiredCount" && aws_appautoscaling_target.this.service_namespace == "ecs"
    error_message = "The scalable target must address the ECS service desired count."
  }

  assert {
    condition     = aws_appautoscaling_target.this.min_capacity == 2 && aws_appautoscaling_target.this.max_capacity == 10
    error_message = "Capacity bounds must pass through."
  }

  assert {
    condition     = aws_appautoscaling_policy.this["cpu"].name == "orders-api-cpu" && aws_appautoscaling_policy.this["cpu"].policy_type == "TargetTrackingScaling"
    error_message = "Policies must be named after the service and policy key."
  }

  assert {
    condition     = aws_appautoscaling_policy.this["cpu"].target_tracking_scaling_policy_configuration[0].target_value == 60 && aws_appautoscaling_policy.this["cpu"].target_tracking_scaling_policy_configuration[0].scale_in_cooldown == 300 && aws_appautoscaling_policy.this["cpu"].target_tracking_scaling_policy_configuration[0].scale_out_cooldown == 60
    error_message = "Target tracking must apply conservative scale-in and fast scale-out cooldown defaults."
  }

  assert {
    condition     = aws_appautoscaling_policy.this["requests"].target_tracking_scaling_policy_configuration[0].predefined_metric_specification[0].resource_label == "app/platform/0123456789abcdef/targetgroup/orders/0123456789abcdef" && aws_appautoscaling_policy.this["requests"].target_tracking_scaling_policy_configuration[0].disable_scale_in == true
    error_message = "ALB request-count policies must carry the resource label and scale-in setting."
  }

  assert {
    condition     = length(aws_appautoscaling_policy.this["cpu"].step_scaling_policy_configuration) == 0
    error_message = "Target tracking policies must not render step scaling configuration."
  }
}

run "defaults_to_cpu_target_tracking_when_policies_is_null" {
  command = plan

  variables {
    policies = null
  }

  assert {
    condition     = length(aws_appautoscaling_policy.this) == 1 && aws_appautoscaling_policy.this["cpu"].target_tracking_scaling_policy_configuration[0].target_value == 60 && aws_appautoscaling_policy.this["cpu"].target_tracking_scaling_policy_configuration[0].predefined_metric_specification[0].predefined_metric_type == "ECSServiceAverageCPUUtilization"
    error_message = "A null policies value must fall back to CPU target tracking at 60 percent."
  }
}

run "creates_no_policies_for_an_empty_map" {
  command = plan

  variables {
    policies = {}
  }

  assert {
    condition     = length(aws_appautoscaling_policy.this) == 0
    error_message = "An explicit empty policies map must create a target without policies."
  }
}

run "renders_customized_metric_and_step_scaling" {
  command = plan

  variables {
    policies = {
      queue = {
        target_tracking = {
          customized_metric = {
            metric_name = "ApproximateNumberOfMessagesVisible"
            namespace   = "AWS/SQS"
            statistic   = "Average"
            dimensions  = { QueueName = "orders" }
          }
          target_value = 100
        }
      }
      burst = {
        policy_type = "StepScaling"
        step_scaling = {
          cooldown = 120
          step_adjustments = [
            { scaling_adjustment = 1, metric_interval_lower_bound = 0, metric_interval_upper_bound = 20 },
            { scaling_adjustment = 3, metric_interval_lower_bound = 20 },
          ]
        }
      }
    }
  }

  assert {
    condition     = aws_appautoscaling_policy.this["queue"].target_tracking_scaling_policy_configuration[0].customized_metric_specification[0].namespace == "AWS/SQS" && length(aws_appautoscaling_policy.this["queue"].target_tracking_scaling_policy_configuration[0].customized_metric_specification[0].dimensions) == 1
    error_message = "Customized metrics must render namespace and dimensions."
  }

  assert {
    condition     = aws_appautoscaling_policy.this["burst"].policy_type == "StepScaling" && aws_appautoscaling_policy.this["burst"].step_scaling_policy_configuration[0].adjustment_type == "ChangeInCapacity" && aws_appautoscaling_policy.this["burst"].step_scaling_policy_configuration[0].cooldown == 120 && length(aws_appautoscaling_policy.this["burst"].step_scaling_policy_configuration[0].step_adjustment) == 2
    error_message = "Step scaling must render its adjustment steps."
  }

  assert {
    condition     = length(output.policy_arns) == 2
    error_message = "Policy ARNs must be exposed by policy key."
  }
}

run "renders_scheduled_actions" {
  command = plan

  variables {
    scheduled_actions = {
      business_hours = { schedule = "cron(0 8 ? * MON-FRI *)", timezone = "Europe/London", min_capacity = 4 }
      night          = { schedule = "cron(0 20 ? * MON-FRI *)", timezone = "Europe/London", min_capacity = 1, max_capacity = 4 }
    }
  }

  assert {
    condition     = aws_appautoscaling_scheduled_action.this["business_hours"].name == "orders-api-business_hours" && tonumber(aws_appautoscaling_scheduled_action.this["business_hours"].scalable_target_action[0].min_capacity) == 4 && aws_appautoscaling_scheduled_action.this["business_hours"].scalable_target_action[0].max_capacity == null
    error_message = "Scheduled actions must set only the declared bounds."
  }

  assert {
    condition     = aws_appautoscaling_scheduled_action.this["night"].timezone == "Europe/London" && length(output.scheduled_action_arns) == 2
    error_message = "Scheduled actions must keep their timezone and be exposed by key."
  }
}

run "rejects_min_above_max" {
  command = plan

  variables {
    min_capacity = 11
  }

  expect_failures = [aws_appautoscaling_target.this]
}

run "rejects_target_tracking_without_configuration" {
  command = plan

  variables {
    policies = { cpu = {} }
  }

  expect_failures = [var.policies]
}

run "rejects_both_metric_specifications" {
  command = plan

  variables {
    policies = {
      cpu = {
        target_tracking = {
          predefined_metric_type = "ECSServiceAverageCPUUtilization"
          customized_metric      = { metric_name = "x", namespace = "y", statistic = "Average" }
          target_value           = 50
        }
      }
    }
  }

  expect_failures = [var.policies]
}

run "rejects_alb_metric_without_resource_label" {
  command = plan

  variables {
    policies = {
      requests = { target_tracking = { predefined_metric_type = "ALBRequestCountPerTarget", target_value = 500 } }
    }
  }

  expect_failures = [var.policies]
}

run "rejects_scheduled_action_without_bounds" {
  command = plan

  variables {
    scheduled_actions = { noop = { schedule = "rate(1 hour)" } }
  }

  expect_failures = [var.scheduled_actions]
}
