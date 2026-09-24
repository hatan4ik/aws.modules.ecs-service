# Integration suites

The suites in this directory apply the module for real in **your** AWS account
and destroy everything afterwards. They complement the contract tests in
`tests/`, which run with `mock_provider`, need no credentials, and use the AWS
documentation placeholder account `123456789012` and fake resource IDs on
purpose: they prove the module's interface and rendering, not that AWS accepts
it. These suites prove the latter.

Nothing here is tied to an account, region, or landing zone. Credentials and
the region come from the environment; every prerequisite is a disposable
fixture created by [`setup/`](setup/) with a random suffix, so concurrent runs
never collide.

| Suite | What it proves | Runs a task | Needs | Typical time |
| --- | --- | --- | --- | --- |
| `smoke.tftest.hcl` | Task definition, both IAM roles, security group and rules, log group, service, scalable target and policy are accepted by the APIs. `desired_count = 0`, so no image is pulled and no egress is needed. | No | credentials, region | about 3 minutes |
| `e2e.tftest.hcl` | A real task pulls a public image over a public subnet and reaches steady state under the circuit breaker. | Yes, one Fargate task | credentials, region | about 8 minutes |

## Run it in your account

```bash
export AWS_PROFILE=<your profile>   # or AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY / AWS_SESSION_TOKEN
export AWS_REGION=<region>
make integration-smoke              # terraform init -test-directory=tests/integration && terraform test -test-directory=tests/integration -filter=tests/integration/smoke.tftest.hcl
make integration-e2e
```

The credentials need the permissions in
[`iam/integration-permissions-policy.json`](iam/integration-permissions-policy.json)
(replace `<ACCOUNT_ID>`). IAM role creation is scoped to names starting with
`ecs-service-it-` and `ecs-service-e2e-`, which is what the fixtures produce.

`terraform test` runs `tests/` only by default, so these suites never run in
the credential-free quality pipeline. The fixture module is excluded from the
Checkov and Trivy scans (`.checkov.yml`, `trivy.yaml`) because it is
short-lived test infrastructure, not a deployable pattern.

## Run it from GitHub Actions (owner lane)

The `integration` workflow (`.github/workflows/integration.yml`) is dispatch-only
and assumes a role through GitHub OIDC. It reads everything account-specific
from the protected `integration` environment of the repository, so the code
stays universal:

| Environment variable | Meaning |
| --- | --- |
| `AWS_INTEGRATION_ROLE_ARN` | Role the workflow assumes. Trust policy: [`iam/github-oidc-trust-policy.json`](iam/github-oidc-trust-policy.json) with `<OWNER>/<REPO>` set to this repository; permissions: the policy above. |
| `AWS_INTEGRATION_REGION` | Region for the disposable fixtures. |

Dispatch with `gh workflow run integration.yml -f suite=smoke` (or `e2e`).
Protect the environment with required reviewers so a run cannot be started
from a pull request by anyone with write access.

For this repository's owner the environment is prepared with the sandbox
region; the role ARN is added once the role exists in the sandbox account,
created through the platform's delivery IAM module with the trust policy above
and the subject `repo:hatan4ik/aws.modules.ecs-service:environment:integration`.
