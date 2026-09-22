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
