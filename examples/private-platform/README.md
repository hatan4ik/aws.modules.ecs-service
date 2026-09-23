# Private platform service

A service in subnets with no NAT gateway and no internet route, where the only
egress paths are VPC endpoints. Interface endpoints (ECR API, CloudWatch Logs,
Secrets Manager, SSM, STS) answer from inside the VPC CIDR, so one TLS rule to
`vpc_cidr` covers them. Gateway endpoints (S3 for ECR image layers, DynamoDB for
the session table) sit behind AWS-managed prefix lists, so each gets its own TLS
rule keyed on `data.aws_prefix_list`. Nothing else can leave the task. Use this
pattern when the platform team owns the network and application teams must not
be able to widen it.

The example also shows two deliberate boundaries of the module. Identity is
not an ECS concern, so the Cognito app client is created here, next to the
service, and only its ID is passed in through `environment`; the module never
creates identity-provider resources. Data access is declared, not assumed: the
task role gets exactly the DynamoDB actions the app needs on the table and its
indexes through `task_role_statements`. One KMS key encrypts the log group and is
granted to the execution role for decrypting secrets, roles live under `/ecs/`,
ECS Exec is enabled for break-glass access, and CPU target tracking keeps between
two and twelve tasks running.

## Run

```sh
terraform init
terraform plan \
  -var cluster_arn=arn:aws:ecs:us-east-1:123456789012:cluster/platform \
  -var vpc_id=vpc-0123456789abcdef0 \
  -var vpc_cidr=10.0.0.0/16 \
  -var 'subnet_ids=["subnet-0123456789abcdef0","subnet-0123456789abcdef1"]' \
  -var image=123456789012.dkr.ecr.us-east-1.amazonaws.com/orders-api@sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 \
  -var kms_key_arn=arn:aws:kms:us-east-1:123456789012:key/11111111-1111-1111-1111-111111111111 \
  -var session_table_arn=arn:aws:dynamodb:us-east-1:123456789012:table/orders-sessions \
  -var cognito_user_pool_id=us-east-1_AbCdEfGhI \
  -var 'callback_urls=["https://orders.example.internal/oauth2/callback"]' \
  -var 'logout_urls=["https://orders.example.internal/"]'
```

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.7.0, < 2.0.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.35.0, < 7.0.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 6.35.0, < 7.0.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_service"></a> [service](#module\_service) | ../../ | n/a |

## Resources

| Name | Type |
|------|------|
| [aws_cognito_user_pool_client.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cognito_user_pool_client) | resource |
| [aws_prefix_list.dynamodb](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/prefix_list) | data source |
| [aws_prefix_list.s3](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/prefix_list) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_callback_urls"></a> [callback\_urls](#input\_callback\_urls) | HTTPS URLs Cognito may redirect to after sign-in. | `list(string)` | n/a | yes |
| <a name="input_cluster_arn"></a> [cluster\_arn](#input\_cluster\_arn) | ARN of the existing ECS cluster that runs the service. | `string` | n/a | yes |
| <a name="input_cognito_user_pool_id"></a> [cognito\_user\_pool\_id](#input\_cognito\_user\_pool\_id) | Existing Cognito user pool the app client is created in. | `string` | n/a | yes |
| <a name="input_force_new_deployment"></a> [force\_new\_deployment](#input\_force\_new\_deployment) | Force a new deployment on the next apply, for example after an endpoint policy changed. | `bool` | `false` | no |
| <a name="input_image"></a> [image](#input\_image) | Container image pinned to a sha256 digest (repository@sha256:<64 hex>), hosted in ECR so it is pulled through the endpoints. | `string` | n/a | yes |
| <a name="input_kms_key_arn"></a> [kms\_key\_arn](#input\_kms\_key\_arn) | KMS key that encrypts the log group and protects the secrets the execution role reads. | `string` | n/a | yes |
| <a name="input_logout_urls"></a> [logout\_urls](#input\_logout\_urls) | HTTPS URLs Cognito may redirect to after sign-out. | `list(string)` | n/a | yes |
| <a name="input_name"></a> [name](#input\_name) | Service name; also names the Cognito client, roles and log group. | `string` | `"orders-api"` | no |
| <a name="input_region"></a> [region](#input\_region) | AWS region of the cluster, the VPC and its endpoints. | `string` | `"us-east-1"` | no |
| <a name="input_session_table_arn"></a> [session\_table\_arn](#input\_session\_table\_arn) | ARN of the DynamoDB session table the task role may read and write. | `string` | n/a | yes |
| <a name="input_subnet_ids"></a> [subnet\_ids](#input\_subnet\_ids) | Private subnets without a NAT route; use at least two Availability Zones. | `list(string)` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to every resource. | `map(string)` | `{}` | no |
| <a name="input_vpc_cidr"></a> [vpc\_cidr](#input\_vpc\_cidr) | CIDR of the VPC; interface endpoints answer from it. | `string` | n/a | yes |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | VPC in which the task security group is created. | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_autoscaling_target_resource_id"></a> [autoscaling\_target\_resource\_id](#output\_autoscaling\_target\_resource\_id) | Application Auto Scaling resource ID of the service. |
| <a name="output_cloudwatch_log_group_name"></a> [cloudwatch\_log\_group\_name](#output\_cloudwatch\_log\_group\_name) | Name of the KMS-encrypted log group. |
| <a name="output_cognito_client_id"></a> [cognito\_client\_id](#output\_cognito\_client\_id) | ID of the Cognito app client injected as COGNITO\_CLIENT\_ID. |
| <a name="output_security_group_id"></a> [security\_group\_id](#output\_security\_group\_id) | ID of the task security group (<name>-tasks). |
| <a name="output_service_arn"></a> [service\_arn](#output\_service\_arn) | ARN of the ECS service. |
| <a name="output_service_name"></a> [service\_name](#output\_service\_name) | Name of the ECS service. |
| <a name="output_task_definition_arn"></a> [task\_definition\_arn](#output\_task\_definition\_arn) | ARN of the registered task definition revision. |
| <a name="output_task_role_arn"></a> [task\_role\_arn](#output\_task\_role\_arn) | ARN of the task role that holds the session-table statement. |
<!-- END_TF_DOCS -->
