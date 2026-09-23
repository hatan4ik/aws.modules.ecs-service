# security-group

Owns the task security group and its rules. It is a separate module because network policy has its own reviewers and lifecycle, and because every rule must be an independent resource so a caller can add, change, or remove one without disturbing the others or the group itself.

## Usage

```hcl
module "security_group" {
  source = "git::https://github.com/hatan4ik/aws.modules.ecs-service.git//modules/security-group?ref=<commit-sha>" # v1.0.0

  name        = "orders-api"
  description = "Tasks of ECS service orders-api"
  vpc_id      = "vpc-0123456789abcdef0"

  ingress_rules = {
    from_alb = { description = "HTTP from the load balancer", from_port = 8080, to_port = 8080, referenced_security_group_id = "sg-0aaaaaaaaaaaaaaaa" }
  }

  egress_rules = {
    vpc_tls = { description = "TLS to VPC endpoints", from_port = 443, to_port = 443, cidr_ipv4 = "10.0.0.0/16" }
    s3_tls  = { description = "TLS to the S3 gateway endpoint", from_port = 443, to_port = 443, prefix_list_id = "pl-0123456789abcdef0" }
    dns     = { from_port = 53, to_port = 53, ip_protocol = "udp", cidr_ipv4 = "10.0.0.2/32" }
  }

  tags = { Environment = "prod" }
}
```

## Behaviour

- Exactly one source per rule. Each rule names one of `cidr_ipv4`, `cidr_ipv6`, `prefix_list_id`, `referenced_security_group_id`, or `self = true`. A rule with zero or two sources fails validation at plan time.
- `self`. `self = true` sets `referenced_security_group_id` to the group's own ID, for traffic between tasks in the same group.
- Ports. `ip_protocol` defaults to `tcp`. A protocol-specific rule needs both `from_port` and `to_port` (-1 to 65535, `from_port <= to_port`). An all-protocol rule (`ip_protocol = "-1"`) must set neither.
- No implicit egress. The AWS provider revokes the default allow-all egress rule when it creates a VPC security group, so the group starts with no rules at all. Declare egress or tasks cannot pull images or reach any dependency.
- Standalone rules. Every rule is an `aws_vpc_security_group_ingress_rule` or `aws_vpc_security_group_egress_rule` keyed by your map key and tagged `Name = <name>-<key>`. Keys are stable identifiers: renaming a key replaces that rule only. Rule IDs are exposed by key in `ingress_rule_ids` and `egress_rule_ids`.
- Description replaces the group. `description` is immutable on `aws_security_group`; changing it destroys and re-creates the group and every rule, and any service attached to it must be updated. Keep it stable, or set it once to match a group you are preserving.
- Names. 1 to 255 characters, unique within the VPC, and must not start with `sg-`.
- `create = false`. Nothing is created, `id` and `arn` are null, and the rule maps are ignored. `vpc_id` is required only when `create` is true; the precondition names it.

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
| [aws_security_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_vpc_security_group_egress_rule.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_create"></a> [create](#input\_create) | Create the security group and its rules. When false the module creates nothing and outputs null identifiers. | `bool` | `true` | no |
| <a name="input_description"></a> [description](#input\_description) | Security group description. Changing it replaces the group. | `string` | `"ECS task security group"` | no |
| <a name="input_egress_rules"></a> [egress\_rules](#input\_egress\_rules) | Egress rules keyed by a stable identifier, same shape as ingress\_rules. A group with no egress rules cannot pull images or reach any dependency. | <pre>map(object({<br/>    description                  = optional(string)<br/>    from_port                    = optional(number)<br/>    to_port                      = optional(number)<br/>    ip_protocol                  = optional(string, "tcp")<br/>    cidr_ipv4                    = optional(string)<br/>    cidr_ipv6                    = optional(string)<br/>    prefix_list_id               = optional(string)<br/>    referenced_security_group_id = optional(string)<br/>    self                         = optional(bool, false)<br/>  }))</pre> | `{}` | no |
| <a name="input_ingress_rules"></a> [ingress\_rules](#input\_ingress\_rules) | Ingress rules keyed by a stable identifier. Each rule names exactly one source: cidr\_ipv4, cidr\_ipv6, prefix\_list\_id, referenced\_security\_group\_id, or self. | <pre>map(object({<br/>    description                  = optional(string)<br/>    from_port                    = optional(number)<br/>    to_port                      = optional(number)<br/>    ip_protocol                  = optional(string, "tcp")<br/>    cidr_ipv4                    = optional(string)<br/>    cidr_ipv6                    = optional(string)<br/>    prefix_list_id               = optional(string)<br/>    referenced_security_group_id = optional(string)<br/>    self                         = optional(bool, false)<br/>  }))</pre> | `{}` | no |
| <a name="input_name"></a> [name](#input\_name) | Security group name. Must be unique within the VPC. | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to the security group and every rule. | `map(string)` | `{}` | no |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | VPC the security group belongs to. Required when create is true. | `string` | `null` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_arn"></a> [arn](#output\_arn) | Security group ARN, or null when create is false. |
| <a name="output_egress_rule_ids"></a> [egress\_rule\_ids](#output\_egress\_rule\_ids) | Egress rule IDs keyed by rule key. |
| <a name="output_id"></a> [id](#output\_id) | Security group ID, or null when create is false. |
| <a name="output_ingress_rule_ids"></a> [ingress\_rule\_ids](#output\_ingress\_rule\_ids) | Ingress rule IDs keyed by rule key. |
<!-- END_TF_DOCS -->
