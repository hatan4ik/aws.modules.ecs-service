# Load-balanced service

Puts an internal Application Load Balancer in front of the service. The example
creates the ALB, an `ip` target group on port 8080 with a `/healthz` health
check, an HTTPS listener on a TLS 1.3 policy, and an ALB security group that
accepts 443 from a client CIDR and may only talk to the task security group on
8080. The module registers the `app` container with the target group, opens
8080 from the ALB security group only, and waits 60 seconds before load balancer
health checks can stop a fresh task. Use this when the service is consumed over
HTTP by clients inside the network; put a public ALB, WAF and DNS in front of it
as separate concerns.

Scaling follows traffic rather than CPU alone: an `ALBRequestCountPerTarget`
target-tracking policy keeps each task near 1,000 requests per minute, with a
CPU policy as a backstop. The `resource_label` the policy needs is built from
the ALB and target group `arn_suffix` attributes, so the wiring is entirely
within Terraform. The ALB drops invalid headers, has deletion protection and
writes access logs to a bucket you supply; the module owns nothing about the
load balancer except the registration.

## Run

```sh
terraform init
terraform plan \
  -var cluster_arn=arn:aws:ecs:us-east-1:123456789012:cluster/platform \
  -var vpc_id=vpc-0123456789abcdef0 \
  -var 'subnet_ids=["subnet-0123456789abcdef0","subnet-0123456789abcdef1"]' \
  -var image=123456789012.dkr.ecr.us-east-1.amazonaws.com/orders-api@sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 \
  -var certificate_arn=arn:aws:acm:us-east-1:123456789012:certificate/11111111-1111-1111-1111-111111111111 \
  -var client_cidr=10.0.0.0/16 \
  -var access_logs_bucket=platform-alb-access-logs \
  -var egress_cidr=0.0.0.0/0
```

`egress_cidr` is the tasks' only outbound path; `0.0.0.0/0` assumes a NAT gateway route.

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
| [aws_lb.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb) | resource |
| [aws_lb_listener.https](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener) | resource |
| [aws_lb_target_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group) | resource |
| [aws_security_group.alb](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_vpc_security_group_egress_rule.alb_to_tasks](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.alb_https](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_access_logs_bucket"></a> [access\_logs\_bucket](#input\_access\_logs\_bucket) | Name of the S3 bucket that receives load balancer access logs. Its policy must allow the regional ELB log-delivery principal. | `string` | n/a | yes |
| <a name="input_certificate_arn"></a> [certificate\_arn](#input\_certificate\_arn) | ACM certificate ARN served by the HTTPS listener. | `string` | n/a | yes |
| <a name="input_client_cidr"></a> [client\_cidr](#input\_client\_cidr) | CIDR allowed to reach the load balancer on 443, for example the VPC or a corporate range. | `string` | n/a | yes |
| <a name="input_cluster_arn"></a> [cluster\_arn](#input\_cluster\_arn) | ARN of the existing ECS cluster that runs the service. | `string` | n/a | yes |
| <a name="input_egress_cidr"></a> [egress\_cidr](#input\_egress\_cidr) | IPv4 CIDR the tasks may reach on TCP 443 for image pulls and dependencies. Use 0.0.0.0/0 when the subnets route through a NAT gateway, or the VPC CIDR when AWS APIs are reached through VPC endpoints. No default: unrestricted egress is a deliberate choice. | `string` | n/a | yes |
| <a name="input_image"></a> [image](#input\_image) | Container image pinned to a sha256 digest (repository@sha256:<64 hex>). It must answer GET /healthz on port 8080. | `string` | n/a | yes |
| <a name="input_name"></a> [name](#input\_name) | Service name; also names the load balancer, target group and security groups (32 characters or fewer). | `string` | `"orders-api"` | no |
| <a name="input_region"></a> [region](#input\_region) | AWS region of the cluster and the VPC. | `string` | `"us-east-1"` | no |
| <a name="input_subnet_ids"></a> [subnet\_ids](#input\_subnet\_ids) | Private subnets for the tasks and the internal load balancer; use at least two Availability Zones. | `list(string)` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to every resource. | `map(string)` | `{}` | no |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | VPC of the load balancer, the target group and the security groups. | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_alb_arn"></a> [alb\_arn](#output\_alb\_arn) | ARN of the internal load balancer. |
| <a name="output_alb_dns_name"></a> [alb\_dns\_name](#output\_alb\_dns\_name) | DNS name of the internal load balancer. |
| <a name="output_alb_security_group_id"></a> [alb\_security\_group\_id](#output\_alb\_security\_group\_id) | ID of the load balancer security group. |
| <a name="output_autoscaling_policy_arns"></a> [autoscaling\_policy\_arns](#output\_autoscaling\_policy\_arns) | Scaling policy ARNs keyed by policy key (requests, cpu). |
| <a name="output_listener_arn"></a> [listener\_arn](#output\_listener\_arn) | ARN of the HTTPS listener. |
| <a name="output_service_arn"></a> [service\_arn](#output\_service\_arn) | ARN of the ECS service. |
| <a name="output_service_name"></a> [service\_name](#output\_service\_name) | Name of the ECS service. |
| <a name="output_target_group_arn"></a> [target\_group\_arn](#output\_target\_group\_arn) | ARN of the IP target group the service registers with. |
| <a name="output_task_definition_arn"></a> [task\_definition\_arn](#output\_task\_definition\_arn) | ARN of the registered task definition revision. |
| <a name="output_task_security_group_id"></a> [task\_security\_group\_id](#output\_task\_security\_group\_id) | ID of the task security group. |
<!-- END_TF_DOCS -->
