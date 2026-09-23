# autoscaling

Owns Application Auto Scaling for one ECS service: the scalable target, target-tracking and step scaling policies, and scheduled capacity changes. It is a separate module because scaling policy shape evolves independently of the service, and because you may need to scale a service the root module did not create.

## Usage

```hcl
module "autoscaling" {
  source = "git::https://github.com/hatan4ik/aws.modules.ecs-service.git//modules/autoscaling?ref=<commit-sha>" # v1.0.0

  cluster_name = "platform"
  service_name = "orders-api"
  min_capacity = 2
  max_capacity = 10

  policies = {
    cpu = { target_tracking = { predefined_metric_type = "ECSServiceAverageCPUUtilization", target_value = 60 } }
    requests = {
      target_tracking = {
        predefined_metric_type = "ALBRequestCountPerTarget"
        resource_label         = "app/platform/0123456789abcdef/targetgroup/orders/0123456789abcdef"
        target_value           = 1000
        disable_scale_in       = true
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

  scheduled_actions = {
    business_hours = { schedule = "cron(0 8 ? * MON-FRI *)", timezone = "Europe/London", min_capacity = 4 }
    night          = { schedule = "cron(0 20 ? * MON-FRI *)", timezone = "Europe/London", min_capacity = 1 }
  }

  tags = { Environment = "prod" }
}

# Step scaling needs an alarm you own. Its action is the policy ARN.
resource "aws_cloudwatch_metric_alarm" "queue_depth" {
  alarm_name          = "orders-api-queue-depth"
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  dimensions          = { QueueName = "orders" }
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 2
  threshold           = 100
  comparison_operator = "GreaterThanThreshold"
  alarm_actions       = [module.autoscaling.policy_arns["burst"]]
}
```

## Behaviour

- Target. `service/<cluster_name>/<service_name>` on `ecs:service:DesiredCount`. A precondition requires `min_capacity <= max_capacity`; both must be zero or greater.
- `policies` semantics. Omitted or `null` means the default: one CPU target-tracking policy keyed `cpu` at 60 percent. `{}` means a target with no policies, for when you manage policies elsewhere. Any other map replaces the default entirely, so include a `cpu` entry if you still want it.
- Naming. Policies and scheduled actions are named `<service_name>-<key>`. Policy keys are 1 to 63 lowercase alphanumerics or hyphens; scheduled-action keys also allow uppercase and underscores.
- Target tracking. Exactly one of `predefined_metric_type` (`ECSServiceAverageCPUUtilization`, `ECSServiceAverageMemoryUtilization`, or `ALBRequestCountPerTarget`, which requires `resource_label`) or `customized_metric` (`metric_name`, `namespace`, `statistic`, optional `unit` and `dimensions`). `target_value` must be positive. `scale_in_cooldown` defaults to 300 seconds and `scale_out_cooldown` to 60: conservative scale-in, fast scale-out. `disable_scale_in` is available.
- Step scaling. `policy_type = "StepScaling"` with a `step_scaling` block and at least one step adjustment. `adjustment_type` defaults to `ChangeInCapacity`, `cooldown` to 60, `metric_aggregation_type` to `Average`. The module creates no alarm: you create a CloudWatch alarm whose `alarm_actions` includes `policy_arns["<key>"]`.
- Scheduled actions. `schedule` is an `at(...)`, `cron(...)`, or `rate(...)` expression; at least one of `min_capacity` and `max_capacity` must be set; `timezone`, `start_time`, and `end_time` are optional. Only the bounds you set are changed at trigger time.
- Tags are applied to the scalable target.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.7.0, < 2.0.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.35.0, < 7.0.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.66.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_appautoscaling_policy.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/appautoscaling_policy) | resource |
| [aws_appautoscaling_scheduled_action.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/appautoscaling_scheduled_action) | resource |
| [aws_appautoscaling_target.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/appautoscaling_target) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | Name of the ECS cluster hosting the service. | `string` | n/a | yes |
| <a name="input_max_capacity"></a> [max\_capacity](#input\_max\_capacity) | Maximum number of tasks Application Auto Scaling may run. | `number` | n/a | yes |
| <a name="input_min_capacity"></a> [min\_capacity](#input\_min\_capacity) | Minimum number of tasks Application Auto Scaling may keep running. | `number` | n/a | yes |
| <a name="input_policies"></a> [policies](#input\_policies) | Scaling policies keyed by a short name. Defaults (also when null) to CPU target tracking at 60 percent; pass {} for a target with no policies. Target tracking uses one predefined ECS/ALB metric or one customized CloudWatch metric; step scaling needs a caller-managed CloudWatch alarm that targets the policy ARN. | <pre>map(object({<br/>    policy_type = optional(string, "TargetTrackingScaling")<br/>    target_tracking = optional(object({<br/>      predefined_metric_type = optional(string)<br/>      resource_label         = optional(string)<br/>      customized_metric = optional(object({<br/>        metric_name = string<br/>        namespace   = string<br/>        statistic   = string<br/>        unit        = optional(string)<br/>        dimensions  = optional(map(string), {})<br/>      }))<br/>      target_value       = number<br/>      scale_in_cooldown  = optional(number, 300)<br/>      scale_out_cooldown = optional(number, 60)<br/>      disable_scale_in   = optional(bool, false)<br/>    }))<br/>    step_scaling = optional(object({<br/>      adjustment_type          = optional(string, "ChangeInCapacity")<br/>      cooldown                 = optional(number, 60)<br/>      metric_aggregation_type  = optional(string, "Average")<br/>      min_adjustment_magnitude = optional(number)<br/>      step_adjustments = list(object({<br/>        scaling_adjustment          = number<br/>        metric_interval_lower_bound = optional(number)<br/>        metric_interval_upper_bound = optional(number)<br/>      }))<br/>    }))<br/>  }))</pre> | <pre>{<br/>  "cpu": {<br/>    "target_tracking": {<br/>      "predefined_metric_type": "ECSServiceAverageCPUUtilization",<br/>      "target_value": 60<br/>    }<br/>  }<br/>}</pre> | no |
| <a name="input_scheduled_actions"></a> [scheduled\_actions](#input\_scheduled\_actions) | Scheduled capacity changes keyed by a short name. schedule is an at(), cron(), or rate() expression; at least one of min\_capacity or max\_capacity must be set. | <pre>map(object({<br/>    schedule     = string<br/>    timezone     = optional(string)<br/>    min_capacity = optional(number)<br/>    max_capacity = optional(number)<br/>    start_time   = optional(string)<br/>    end_time     = optional(string)<br/>  }))</pre> | `{}` | no |
| <a name="input_service_name"></a> [service\_name](#input\_service\_name) | Name of the ECS service to scale. Also prefixes policy and scheduled-action names. | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to the scalable target. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_policy_arns"></a> [policy\_arns](#output\_policy\_arns) | Scaling policy ARNs keyed by policy key. Use these as CloudWatch alarm actions for step scaling. |
| <a name="output_scheduled_action_arns"></a> [scheduled\_action\_arns](#output\_scheduled\_action\_arns) | Scheduled action ARNs keyed by action key. |
| <a name="output_target_arn"></a> [target\_arn](#output\_target\_arn) | ARN of the scalable target. |
| <a name="output_target_resource_id"></a> [target\_resource\_id](#output\_target\_resource\_id) | Application Auto Scaling resource ID of the service (service/<cluster>/<service>). |
<!-- END_TF_DOCS -->
