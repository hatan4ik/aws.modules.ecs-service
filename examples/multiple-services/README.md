# Multiple services

Runs a fleet of services from one root module by using `for_each` on the module
block. `aws.modules.ecs-service` provisions exactly one service per call on
purpose: a service is the unit that gets its own task definition, roles,
security group, log group and scaling policy, and a plan error names the one
service that caused it. Fleets are therefore expressed in the caller, as a map
of service specifications, not as a list inside the module. Use this shape when
several services share a cluster, VPC and subnets and you want them declared
side by side.

Each entry supplies its image, port, size, initial count, environment and
optional autoscaling bounds; the module derives `<name_prefix>-<key>` and
everything else. Adding a service is adding a map entry; removing one destroys
exactly that service. Because every service has its own module instance, you can
still `-target` or `moved` a single one.

## Run

Declare the fleet in a `terraform.tfvars`:

```hcl
cluster_arn = "arn:aws:ecs:us-east-1:123456789012:cluster/platform"
vpc_id      = "vpc-0123456789abcdef0"
vpc_cidr    = "10.0.0.0/16"
subnet_ids  = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]

services = {
  orders-api = {
    image          = "123456789012.dkr.ecr.us-east-1.amazonaws.com/orders-api@sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    container_port = 8080
    cpu            = 512
    memory         = 1024
    desired_count  = 2
    environment    = { LOG_LEVEL = "info" }
    autoscaling    = { min_capacity = 2, max_capacity = 8 }
  }
  payments-api = {
    image          = "123456789012.dkr.ecr.us-east-1.amazonaws.com/payments-api@sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    container_port = 8081
    cpu            = 1024
    memory         = 2048
    desired_count  = 3
  }
}
```

```sh
terraform init && terraform plan -var cluster_arn=arn:aws:ecs:us-east-1:123456789012:cluster/platform
```

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
| <a name="input_cluster_arn"></a> [cluster\_arn](#input\_cluster\_arn) | ARN of the existing ECS cluster shared by every service. | `string` | n/a | yes |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Prefix for every service name; the service key is appended (<prefix>-<key>). | `string` | `"platform"` | no |
| <a name="input_region"></a> [region](#input\_region) | AWS region of the cluster and the VPC. | `string` | `"us-east-1"` | no |
| <a name="input_services"></a> [services](#input\_services) | Services to run, keyed by a short name that becomes the suffix of the service name. desired\_count must lie within autoscaling bounds when autoscaling is set. | <pre>map(object({<br/>    image          = string<br/>    container_port = number<br/>    cpu            = number<br/>    memory         = number<br/>    desired_count  = number<br/>    environment    = optional(map(string), {})<br/>    autoscaling = optional(object({<br/>      min_capacity = number<br/>      max_capacity = number<br/>    }))<br/>  }))</pre> | n/a | yes |
| <a name="input_subnet_ids"></a> [subnet\_ids](#input\_subnet\_ids) | Private subnets shared by every service; use at least two Availability Zones. | `list(string)` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to every resource of every service. | `map(string)` | `{}` | no |
| <a name="input_vpc_cidr"></a> [vpc\_cidr](#input\_vpc\_cidr) | CIDR of the VPC; TLS egress is limited to it. | `string` | n/a | yes |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | VPC in which each task security group is created. | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_security_group_ids"></a> [security\_group\_ids](#output\_security\_group\_ids) | Task security group IDs keyed by service key. |
| <a name="output_service_arns"></a> [service\_arns](#output\_service\_arns) | ECS service ARNs keyed by service key. |
| <a name="output_task_definition_arns"></a> [task\_definition\_arns](#output\_task\_definition\_arns) | Task definition ARNs keyed by service key. |
<!-- END_TF_DOCS -->
