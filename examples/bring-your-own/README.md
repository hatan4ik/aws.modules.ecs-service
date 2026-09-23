# Bring your own roles, security groups and log group

Substitutes every resource the module would normally create with one the caller
already owns: the task security groups, the task execution role, the task role
and the CloudWatch log group. The module then creates only the task definition
and the service, wires the supplied identifiers into both, and exposes them
through the same outputs a managed configuration would. Use this when a platform
team hands out shared roles and security groups, or when migrating a service
whose IAM and networking must not change.

The module never modifies a supplied role, so permissions it would have attached
to a role it created have to be attached by you. For the execution role the
module still computes that policy from the secrets the containers reference and
exposes it as `task_execution_role_derived_policy`; the example attaches it with
an `aws_iam_role_policy` on the role name parsed from the ARN, guarded by
`count` so nothing is created when no secrets are declared. Until that policy is
in place the module's `supplied_execution_role_secrets` check warns on every
plan; that warning is expected, and it disappears once the attachment exists.
The same pattern applies to `task_role_derived_policy` when ECS Exec is enabled
with a supplied task role.

## Run

```sh
terraform init
terraform plan \
  -var cluster_arn=arn:aws:ecs:us-east-1:123456789012:cluster/platform \
  -var 'subnet_ids=["subnet-0123456789abcdef0","subnet-0123456789abcdef1"]' \
  -var image=123456789012.dkr.ecr.us-east-1.amazonaws.com/orders-api@sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 \
  -var 'security_group_ids=["sg-0123456789abcdef0"]' \
  -var task_execution_role_arn=arn:aws:iam::123456789012:role/platform/shared-execution \
  -var task_role_arn=arn:aws:iam::123456789012:role/orders-api-task \
  -var cloudwatch_log_group_name=/platform/orders-api \
  -var api_token_parameter_arn=arn:aws:ssm:us-east-1:123456789012:parameter/orders/api-token
```

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.7.0, < 2.0.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.35.0, < 7.0.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 6.35.0, < 7.0.0 |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_service"></a> [service](#module\_service) | ../../ | n/a |

## Resources

| Name | Type |
| ---- | ---- |
| [aws_iam_role_policy.task_execution_derived](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_api_token_parameter_arn"></a> [api\_token\_parameter\_arn](#input\_api\_token\_parameter\_arn) | SSM Parameter Store parameter ARN injected as API\_TOKEN. | `string` | n/a | yes |
| <a name="input_cloudwatch_log_group_name"></a> [cloudwatch\_log\_group\_name](#input\_cloudwatch\_log\_group\_name) | Existing CloudWatch log group the containers write to through awslogs. | `string` | n/a | yes |
| <a name="input_cluster_arn"></a> [cluster\_arn](#input\_cluster\_arn) | ARN of the existing ECS cluster that runs the service. | `string` | n/a | yes |
| <a name="input_image"></a> [image](#input\_image) | Container image pinned to a sha256 digest (repository@sha256:<64 hex>). | `string` | n/a | yes |
| <a name="input_name"></a> [name](#input\_name) | Service name; also the task definition family. | `string` | `"orders-api"` | no |
| <a name="input_region"></a> [region](#input\_region) | AWS region of the cluster. | `string` | `"us-east-1"` | no |
| <a name="input_security_group_ids"></a> [security\_group\_ids](#input\_security\_group\_ids) | Existing security groups attached to the tasks. They must already allow the egress the tasks need. | `set(string)` | n/a | yes |
| <a name="input_subnet_ids"></a> [subnet\_ids](#input\_subnet\_ids) | Private subnets the tasks run in; use at least two Availability Zones. | `list(string)` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to the task definition and the service. | `map(string)` | `{}` | no |
| <a name="input_task_execution_role_arn"></a> [task\_execution\_role\_arn](#input\_task\_execution\_role\_arn) | Existing task execution role. It must trust ecs-tasks.amazonaws.com and carry AmazonECSTaskExecutionRolePolicy. | `string` | n/a | yes |
| <a name="input_task_role_arn"></a> [task\_role\_arn](#input\_task\_role\_arn) | Existing task role the application code assumes. | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_cloudwatch_log_group_name"></a> [cloudwatch\_log\_group\_name](#output\_cloudwatch\_log\_group\_name) | Log group the containers write to, exactly as supplied. |
| <a name="output_security_group_ids"></a> [security\_group\_ids](#output\_security\_group\_ids) | Security groups attached to the tasks, exactly as supplied. |
| <a name="output_service_arn"></a> [service\_arn](#output\_service\_arn) | ARN of the ECS service. |
| <a name="output_service_name"></a> [service\_name](#output\_service\_name) | Name of the ECS service. |
| <a name="output_task_definition_arn"></a> [task\_definition\_arn](#output\_task\_definition\_arn) | ARN of the registered task definition revision. |
| <a name="output_task_execution_role_derived_policy"></a> [task\_execution\_role\_derived\_policy](#output\_task\_execution\_role\_derived\_policy) | Policy the module derived for the supplied execution role, attached by this example. |
| <a name="output_task_execution_role_name"></a> [task\_execution\_role\_name](#output\_task\_execution\_role\_name) | Name the module parsed from the supplied execution role ARN. |
<!-- END_TF_DOCS -->
