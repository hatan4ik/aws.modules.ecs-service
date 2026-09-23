# Complete service

Every major feature of `aws.modules.ecs-service` in one call: an ARM64 task at
1024 CPU / 2048 MiB with 50 GiB ephemeral storage, an `app` container with a
health check, Secrets Manager and SSM secrets, ulimits, dropped Linux
capabilities, an EFS volume and a bind volume; a non-essential FireLens
`log-router` sidecar the app depends on; a one-shot `init` migration container
the app waits for; a mixed FARGATE / FARGATE_SPOT capacity provider strategy;
ECS Exec; deployment alarms; Service Connect; a scoped task role; a
KMS-encrypted log group; and CPU, memory and scheduled autoscaling. Use it as a
reference for the shape of each input, then copy the parts you need.

Two details are easy to miss. The app's `awsfirelens` log configuration targets
the same log group the module creates, so the example names that group
explicitly and grants the task role permission to write to it, because Fluent
Bit runs under the task role rather than the execution role. And because the
task mounts EFS, egress needs NFS (2049) to the VPC in addition to TLS; egress
is otherwise TLS-only.

## Run

The example takes many environment-specific inputs, so a `terraform.tfvars` is
easier than `-var` flags:

```hcl
cluster_arn                   = "arn:aws:ecs:us-east-1:123456789012:cluster/platform"
vpc_id                        = "vpc-0123456789abcdef0"
vpc_cidr                      = "10.0.0.0/16"
egress_cidr                   = "0.0.0.0/0"
subnet_ids                    = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]
image                         = "123456789012.dkr.ecr.us-east-1.amazonaws.com/orders-api@sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
efs_file_system_id            = "fs-0123456789abcdef0"
efs_access_point_id           = "fsap-0123456789abcdef0"
database_url_secret_arn       = "arn:aws:secretsmanager:us-east-1:123456789012:secret:orders/database-AbCdEf"
api_token_parameter_arn       = "arn:aws:ssm:us-east-1:123456789012:parameter/orders/api-token"
secrets_kms_key_arns          = ["arn:aws:kms:us-east-1:123456789012:key/11111111-1111-1111-1111-111111111111"]
logs_kms_key_arn              = "arn:aws:kms:us-east-1:123456789012:key/22222222-2222-2222-2222-222222222222"
assets_bucket_arn             = "arn:aws:s3:::orders-assets"
service_connect_namespace_arn = "arn:aws:servicediscovery:us-east-1:123456789012:namespace/ns-0123456789abcdef"
deployment_alarm_names        = ["orders-api-5xx-rate"]
ingress_security_group_id     = "sg-0123456789abcdef0"
```

```sh
terraform init && terraform plan -var cluster_arn=arn:aws:ecs:us-east-1:123456789012:cluster/platform
```

Any input not set in `terraform.tfvars` can be passed with `-var` as above.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.7.0, < 2.0.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.35.0, < 7.0.0 |

## Providers

No providers.

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_service"></a> [service](#module\_service) | ../../ | n/a |

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_api_token_parameter_arn"></a> [api\_token\_parameter\_arn](#input\_api\_token\_parameter\_arn) | SSM Parameter Store parameter ARN injected as API\_TOKEN. | `string` | n/a | yes |
| <a name="input_assets_bucket_arn"></a> [assets\_bucket\_arn](#input\_assets\_bucket\_arn) | S3 bucket ARN whose objects the task role may read. | `string` | n/a | yes |
| <a name="input_cluster_arn"></a> [cluster\_arn](#input\_cluster\_arn) | ARN of the existing ECS cluster that runs the service. | `string` | n/a | yes |
| <a name="input_database_url_secret_arn"></a> [database\_url\_secret\_arn](#input\_database\_url\_secret\_arn) | Secrets Manager secret ARN injected as DATABASE\_URL. | `string` | n/a | yes |
| <a name="input_deployment_alarm_names"></a> [deployment\_alarm\_names](#input\_deployment\_alarm\_names) | CloudWatch alarm names that fail and roll back a deployment. | `set(string)` | n/a | yes |
| <a name="input_efs_access_point_id"></a> [efs\_access\_point\_id](#input\_efs\_access\_point\_id) | EFS access point that scopes the /data mount. | `string` | n/a | yes |
| <a name="input_efs_file_system_id"></a> [efs\_file\_system\_id](#input\_efs\_file\_system\_id) | EFS file system mounted at /data. | `string` | n/a | yes |
| <a name="input_egress_cidr"></a> [egress\_cidr](#input\_egress\_cidr) | IPv4 CIDR the tasks may reach on TCP 443 for image pulls and dependencies. Use 0.0.0.0/0 when the subnets route through a NAT gateway, or the VPC CIDR when AWS APIs are reached through VPC endpoints. No default: unrestricted egress is a deliberate choice. | `string` | n/a | yes |
| <a name="input_image"></a> [image](#input\_image) | Application image pinned to a sha256 digest (repository@sha256:<64 hex>). Also runs the migration container. | `string` | n/a | yes |
| <a name="input_ingress_security_group_id"></a> [ingress\_security\_group\_id](#input\_ingress\_security\_group\_id) | Security group of the upstream that may reach the tasks on port 8080. | `string` | n/a | yes |
| <a name="input_log_router_image"></a> [log\_router\_image](#input\_log\_router\_image) | Fluent Bit image for the FireLens sidecar, pinned to a sha256 digest. | `string` | `"public.ecr.aws/aws-observability/aws-for-fluent-bit@sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"` | no |
| <a name="input_logs_kms_key_arn"></a> [logs\_kms\_key\_arn](#input\_logs\_kms\_key\_arn) | KMS key that encrypts the CloudWatch log group. Its key policy must trust the CloudWatch Logs service principal. | `string` | n/a | yes |
| <a name="input_name"></a> [name](#input\_name) | Service name; also names the task family, roles, security group and log group. | `string` | `"orders-api"` | no |
| <a name="input_region"></a> [region](#input\_region) | AWS region of the cluster and the VPC. | `string` | `"us-east-1"` | no |
| <a name="input_secrets_kms_key_arns"></a> [secrets\_kms\_key\_arns](#input\_secrets\_kms\_key\_arns) | KMS keys that protect the referenced secret and parameter; the execution role may decrypt with them. | `set(string)` | n/a | yes |
| <a name="input_service_connect_namespace_arn"></a> [service\_connect\_namespace\_arn](#input\_service\_connect\_namespace\_arn) | AWS Cloud Map namespace ARN the service publishes to through Service Connect. | `string` | n/a | yes |
| <a name="input_subnet_ids"></a> [subnet\_ids](#input\_subnet\_ids) | Private subnets the tasks run in; use at least two Availability Zones. | `list(string)` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to every resource. | `map(string)` | <pre>{<br/>  "Environment": "production",<br/>  "Team": "orders"<br/>}</pre> | no |
| <a name="input_vpc_cidr"></a> [vpc\_cidr](#input\_vpc\_cidr) | CIDR of the VPC; TLS and NFS egress are limited to it. | `string` | n/a | yes |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | VPC in which the task security group is created. | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_autoscaling_policy_arns"></a> [autoscaling\_policy\_arns](#output\_autoscaling\_policy\_arns) | Scaling policy ARNs keyed by policy key (cpu, memory). |
| <a name="output_autoscaling_scheduled_action_arns"></a> [autoscaling\_scheduled\_action\_arns](#output\_autoscaling\_scheduled\_action\_arns) | Scheduled action ARNs keyed by action key. |
| <a name="output_autoscaling_target_resource_id"></a> [autoscaling\_target\_resource\_id](#output\_autoscaling\_target\_resource\_id) | Application Auto Scaling resource ID of the service. |
| <a name="output_cloudwatch_log_group_arn"></a> [cloudwatch\_log\_group\_arn](#output\_cloudwatch\_log\_group\_arn) | ARN of the created log group. |
| <a name="output_cloudwatch_log_group_name"></a> [cloudwatch\_log\_group\_name](#output\_cloudwatch\_log\_group\_name) | Name of the KMS-encrypted log group both containers write to. |
| <a name="output_cluster_name"></a> [cluster\_name](#output\_cluster\_name) | Cluster name the module derived from cluster\_arn. |
| <a name="output_container_definitions"></a> [container\_definitions](#output\_container\_definitions) | Rendered container definitions as embedded in the task definition. |
| <a name="output_security_group_id"></a> [security\_group\_id](#output\_security\_group\_id) | ID of the task security group. |
| <a name="output_security_group_ids"></a> [security\_group\_ids](#output\_security\_group\_ids) | Every security group attached to the tasks. |
| <a name="output_service_arn"></a> [service\_arn](#output\_service\_arn) | ARN of the ECS service. |
| <a name="output_service_id"></a> [service\_id](#output\_service\_id) | ID of the ECS service. |
| <a name="output_service_name"></a> [service\_name](#output\_service\_name) | Name of the ECS service. |
| <a name="output_task_definition_arn"></a> [task\_definition\_arn](#output\_task\_definition\_arn) | ARN of the registered task definition revision. |
| <a name="output_task_definition_arn_without_revision"></a> [task\_definition\_arn\_without\_revision](#output\_task\_definition\_arn\_without\_revision) | Task definition ARN without the revision suffix, for deployers that always take the latest. |
| <a name="output_task_definition_family"></a> [task\_definition\_family](#output\_task\_definition\_family) | Task definition family. |
| <a name="output_task_definition_revision"></a> [task\_definition\_revision](#output\_task\_definition\_revision) | Registered task definition revision. |
| <a name="output_task_execution_role_arn"></a> [task\_execution\_role\_arn](#output\_task\_execution\_role\_arn) | ARN of the created task execution role. |
| <a name="output_task_execution_role_name"></a> [task\_execution\_role\_name](#output\_task\_execution\_role\_name) | Name of the created task execution role. |
| <a name="output_task_role_arn"></a> [task\_role\_arn](#output\_task\_role\_arn) | ARN of the created task role. |
| <a name="output_task_role_name"></a> [task\_role\_name](#output\_task\_role\_name) | Name of the created task role. |
<!-- END_TF_DOCS -->
