# Private ECS Fargate service module

Creates one or more variable-driven, private Amazon ECS Fargate services in an
existing ECS cluster and VPC. Each service uses an immutable OCI image digest,
two or more private subnets, a dedicated task/execution role, encrypted logs,
least-privilege optional secret/session access, ECS deployment rollback, and
CPU target tracking.

## Security boundary

- Tasks never receive a public IP.
- A task security group has no ingress unless the caller explicitly supplies
  approved source security groups and a container port.
- Default egress is TLS to the supplied VPC CIDR only, for private endpoints.
- Task egress is created before the ECS service can launch; callers can request
  one Terraform-managed fresh deployment with `force_new_deployment`.
- Images must end in a SHA-256 digest; mutable tags are rejected.
- Cognito clients, when requested, use Authorization Code with PKCE-compatible
  public clients and HTTPS callback/logout URLs. This module never outputs a
  client secret.
- An empty `applications` map creates no AWS resources.

## Example

```hcl
applications = {
  api = {
    image_digest = "123456789012.dkr.ecr.us-east-2.amazonaws.com/app@sha256:<64-hex-digest>"
    cpu          = 256
    memory       = 512
    desired_count = 1
    autoscaling = {
      min_capacity = 1
      max_capacity = 3
    }
    container_port              = 8080
    enable_session_table_access = true
  }
}
```

The caller supplies the existing cluster/VPC/KMS identifiers and may use task
policy statements for narrowly scoped application data access. Public ingress,
load balancers, DNS, ACM, WAF, and a Cognito hosted domain remain separate,
explicitly approved delivery concerns.

When an application declares the typed `cognito` client contract, the module
injects the resulting `COGNITO_USER_POOL_ID` and `COGNITO_CLIENT_ID` into the
task definition. Callers cannot override those values in the application
environment map, so a service validates tokens for the client Terraform created.

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
| <a name="provider_terraform"></a> [terraform](#provider\_terraform) | n/a |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_appautoscaling_policy.application_cpu](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/appautoscaling_policy) | resource |
| [aws_appautoscaling_target.application](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/appautoscaling_target) | resource |
| [aws_cloudwatch_log_group.application](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_cognito_user_pool_client.application](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cognito_user_pool_client) | resource |
| [aws_ecs_service.application](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_service) | resource |
| [aws_ecs_task_definition.application](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_task_definition) | resource |
| [aws_iam_role.execution](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.task](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.execution_secrets](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.task](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy_attachment.execution](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_security_group.application](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_vpc_security_group_egress_rule.application_https_to_vpc](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.application](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [terraform_data.application_contract](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_application_data_kms_key_arn"></a> [application\_data\_kms\_key\_arn](#input\_application\_data\_kms\_key\_arn) | KMS key used by application log groups and optionally granted to task execution roles for encrypted secrets. | `string` | n/a | yes |
| <a name="input_applications"></a> [applications](#input\_applications) | Map of immutable-image private Fargate services. An empty map creates no workload resources. | <pre>map(object({<br/>    image_digest         = string<br/>    cpu                  = number<br/>    memory               = number<br/>    desired_count        = number<br/>    force_new_deployment = optional(bool, false)<br/>    autoscaling = object({<br/>      min_capacity       = number<br/>      max_capacity       = number<br/>      cpu_target_percent = optional(number, 60)<br/>    })<br/>    container_port              = optional(number)<br/>    command                     = optional(list(string), [])<br/>    environment                 = optional(map(string), {})<br/>    secret_arns                 = optional(map(string), {})<br/>    secret_kms_key_arns         = optional(set(string), [])<br/>    task_policy_statements      = optional(map(object({ actions = set(string), resources = set(string) })), {})<br/>    enable_session_table_access = optional(bool, false)<br/>    ingress_security_group_ids  = optional(set(string), [])<br/>    enable_execute_command      = optional(bool, false)<br/>    readonly_root_filesystem    = optional(bool, true)<br/>    ephemeral_storage_gib       = optional(number)<br/>    cpu_architecture            = optional(string, "X86_64")<br/>    health_check = optional(object({<br/>      command      = list(string)<br/>      interval     = number<br/>      timeout      = number<br/>      retries      = number<br/>      start_period = number<br/>    }))<br/>    cognito = optional(object({<br/>      callback_urls                = set(string)<br/>      logout_urls                  = set(string)<br/>      allowed_oauth_scopes         = set(string)<br/>      supported_identity_providers = optional(set(string), ["COGNITO"])<br/>    }))<br/>    tags = optional(map(string), {})<br/>  }))</pre> | `{}` | no |
| <a name="input_cluster_arn"></a> [cluster\_arn](#input\_cluster\_arn) | ARN of the existing ECS cluster that hosts the private Fargate services. | `string` | n/a | yes |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | Name of the existing ECS cluster, required by Application Auto Scaling. | `string` | n/a | yes |
| <a name="input_cognito_user_pool_id"></a> [cognito\_user\_pool\_id](#input\_cognito\_user\_pool\_id) | Existing Cognito user-pool ID. Required only by applications that declare a Cognito app client. | `string` | `null` | no |
| <a name="input_log_retention_in_days"></a> [log\_retention\_in\_days](#input\_log\_retention\_in\_days) | CloudWatch retention for per-service application logs. | `number` | n/a | yes |
| <a name="input_name"></a> [name](#input\_name) | Stable lowercase prefix for the workload resources. | `string` | n/a | yes |
| <a name="input_private_subnet_ids"></a> [private\_subnet\_ids](#input\_private\_subnet\_ids) | At least two existing private subnet IDs, one per Availability Zone. | `set(string)` | n/a | yes |
| <a name="input_session_table_arn"></a> [session\_table\_arn](#input\_session\_table\_arn) | Existing application session-table ARN. Required only by applications that opt into session-table access. | `string` | `null` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Mandatory ownership and cost-allocation tags applied to every supported resource. | `map(string)` | n/a | yes |
| <a name="input_vpc_cidr"></a> [vpc\_cidr](#input\_vpc\_cidr) | CIDR of the private workload VPC. Task security groups allow only TLS egress to this CIDR by default. | `string` | n/a | yes |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | ID of the private workload VPC. | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_services"></a> [services](#output\_services) | Non-secret private workload identifiers by application key. |
<!-- END_TF_DOCS -->
