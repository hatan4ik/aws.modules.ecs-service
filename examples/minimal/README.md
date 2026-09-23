# Minimal service

The smallest working call of `aws.modules.ecs-service`: one essential container
listening on port 8080, the default 256 CPU / 512 MiB Fargate size, module-created
IAM roles, log group and security group, and a single egress rule. Everything
else keeps the module's secure defaults: no public IP, no ingress, read-only
root filesystem, deployment circuit breaker with rollback. Start here when you
want to see exactly what a service needs before layering on features.

The one thing you must always declare is egress. The managed security group has
no rules until you add them, and the module's `security_group_egress` check warns
on every plan until you do.

## Run

```sh
terraform init
terraform plan \
  -var cluster_arn=arn:aws:ecs:us-east-1:123456789012:cluster/platform \
  -var vpc_id=vpc-0123456789abcdef0 \
  -var 'subnet_ids=["subnet-0123456789abcdef0","subnet-0123456789abcdef1"]' \
  -var image=123456789012.dkr.ecr.us-east-1.amazonaws.com/orders-api@sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 \
  -var egress_cidr=0.0.0.0/0
```

`egress_cidr` is the only outbound path the tasks get. `0.0.0.0/0` suits subnets that route through a NAT gateway; use the VPC CIDR when AWS APIs are reached through VPC endpoints (see `examples/private-platform`).

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.7.0, < 2.0.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.35.0, < 7.0.0 |

## Providers

No providers.

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_service"></a> [service](#module\_service) | ../../ | n/a |

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_cluster_arn"></a> [cluster\_arn](#input\_cluster\_arn) | ARN of the existing ECS cluster that runs the service. | `string` | n/a | yes |
| <a name="input_egress_cidr"></a> [egress\_cidr](#input\_egress\_cidr) | IPv4 CIDR the tasks may reach on TCP 443 for image pulls and dependencies. Use 0.0.0.0/0 when the subnets route through a NAT gateway, or the VPC CIDR when AWS APIs are reached through VPC endpoints. No default: unrestricted egress is a deliberate choice. | `string` | n/a | yes |
| <a name="input_image"></a> [image](#input\_image) | Container image pinned to a sha256 digest (repository@sha256:<64 hex>). | `string` | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | AWS region of the cluster and the VPC. | `string` | `"us-east-1"` | no |
| <a name="input_subnet_ids"></a> [subnet\_ids](#input\_subnet\_ids) | Private subnets the tasks run in; use at least two Availability Zones. | `list(string)` | n/a | yes |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | VPC in which the task security group is created. | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_security_group_id"></a> [security\_group\_id](#output\_security\_group\_id) | ID of the task security group the module created. |
| <a name="output_service_arn"></a> [service\_arn](#output\_service\_arn) | ARN of the ECS service. |
| <a name="output_service_name"></a> [service\_name](#output\_service\_name) | Name of the ECS service. |
| <a name="output_task_definition_arn"></a> [task\_definition\_arn](#output\_task\_definition\_arn) | ARN of the registered task definition revision. |
<!-- END_TF_DOCS -->
