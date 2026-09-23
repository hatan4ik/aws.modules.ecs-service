# Contributing

Thank you for improving `aws.modules.ecs-service`. This guide covers the toolchain, the local quality gate, how features are tested and where they belong, commit and pull request conventions, and how releases are cut.

## Development setup

The module targets Terraform `>= 1.7.0, < 2.0.0` and is developed against 1.7.5, the version the consuming platform pins. Install the toolchain:

| Tool | Purpose | Install |
| --- | --- | --- |
| [tfenv](https://github.com/tfutils/tfenv) | Pin the Terraform version | `tfenv install 1.7.5 && tfenv use 1.7.5` |
| [tflint](https://github.com/terraform-linters/tflint) | Lint with the Terraform and AWS rulesets configured in `.tflint.hcl` | `brew install tflint && tflint --init` |
| [terraform-docs](https://terraform-docs.io) v0.24 | Generate the inputs and outputs tables in every README | `brew install terraform-docs` |
| [checkov](https://www.checkov.io) | Static security policy | `pip install checkov` |
| [trivy](https://trivy.dev) | Misconfiguration scanning | `brew install trivy` |
| [pre-commit](https://pre-commit.com) | Run the gate on every commit | `pip install pre-commit && pre-commit install` |

Clone, initialise without a backend, and run the gate once to confirm the setup:

```sh
terraform init -backend=false -input=false
make check
```

## The local gate

`make check` is the default target and the same gate CI runs. It stops at the first failing target and must pass before you open a pull request.

| Target | What it runs |
| --- | --- |
| `make fmt` | `terraform fmt -check -recursive -diff` from the repository root. `make fmt-fix` rewrites the files instead. |
| `make validate` | `make init` (`terraform init -backend=false`) followed by `terraform validate` in the root, every submodule, and every example directory. |
| `make lint` | `tflint --init` and then `tflint` in every directory with the root `.tflint.hcl`: documented and typed variables, documented outputs, snake_case naming, no unused declarations, pinned required versions and providers. |
| `make test` | `terraform test` in the root and in each `modules/*` directory. No credentials are needed. |
| `make docs` | `terraform-docs -c .terraform-docs.yml` in every directory, regenerating the tables between the `BEGIN_TF_DOCS` and `END_TF_DOCS` markers. Run it after touching any variable or output. |
| `make docs-check` | The same in `--output-check` mode: fails when a README is out of date. This is the variant `make check` and CI run. |
| `make security` | `checkov -d . --framework terraform`, and `trivy config --severity HIGH,CRITICAL` when trivy is on the PATH. A skip needs an inline `checkov:skip=` comment with a reason, like the one on the task definition. |
| `make check` | `fmt`, `validate`, `lint`, `test`, `docs-check`, `security`, in that order. |

## Test-first workflow

Every behaviour in this module is pinned by a test before it is implemented. Write the failing `run` block first, then the code, then run `make test`.

- Tests live in `tests/*.tftest.hcl` for the root and `modules/<name>/tests/*.tftest.hcl` for each submodule. Each file starts with `mock_provider "aws" {}` and a `variables` block holding a valid baseline; each `run` overrides only what it exercises.
- Use `command = plan`. Nothing here talks to AWS, so tests run in seconds and in CI without credentials.
- Validations are tested with `expect_failures`. Point it at the object that carries the check: `[var.cpu]` for a variable validation, `[aws_ecs_task_definition.this]` for a resource precondition, `[output.container_definition]` for an output precondition, `[check.security_group_egress]` for a `check` block. A run with `expect_failures` passes only if exactly those objects fail; add a positive run alongside so the happy path is covered too.
- Assertions must not depend on unknown values. With a mock provider, computed attributes such as ARNs and IDs are unknown at plan time, so assert on arguments you set (`name`, `policy`, `tags`) and on outputs derived from them. Where the provider marks an optional attribute computed when null, pin it in the test so the plan is fully known; `configure_at_launch = false` on volumes in `tests/service.tftest.hcl` is the example.
- `||` and `&&` do not short-circuit in Terraform 1.7. Both operands are always evaluated, so `var.x == null || var.x.field > 0` fails when `x` is null. Guard with a conditional instead: `var.x == null ? true : var.x.field > 0`. This applies to validations, preconditions, and test assertions alike.
- Keep assertion `error_message` text a statement of the guaranteed behaviour. It becomes the documentation of the contract when a test fails.
- The two `aws_ecs_service` resource blocks in `service.tf` must stay identical apart from `lifecycle.ignore_changes`. A change to one is a change to both; `tests/service.tftest.hcl` covers the `ignore_task_definition_changes` variant.

## Where to add a feature

Each submodule owns one concern and has one reason to change. The root only composes.

| Concern | Lives in |
| --- | --- |
| A container attribute (a new `containerDefinitions` field) | `modules/container-definition`: add the variable with validation, render it in `main.tf` under its camelCase key, add a test. Then expose it in the root `container_definitions` object type and pass it through in `main.tf`. |
| IAM: a derived permission, a statement shape, trust conditions | `modules/iam`. Derived statements go in `locals.tf`; the root must not build policy JSON. |
| Security-group rule shape or defaults | `modules/security-group`. The root passes the rule maps through untouched. |
| Scaling policy types, metrics, schedules | `modules/autoscaling`. The root passes `var.autoscaling` fields through. |
| Task definition arguments (volumes, runtime platform, storage) | Root `task_definition.tf` and `variables.tf`. |
| Service arguments and integrations (load balancers, Service Connect, deployment configuration) | Root `service.tf`, applied to both service resources. |
| Log group | Root `main.tf`. |
| Cross-resource validation the submodule cannot see (a mount point naming an undeclared volume, a load balancer naming an undeclared container) | Root preconditions in `task_definition.tf` or `service.tf`, or `checks.tf` when the situation is valid but usually unintended. |

Rules that apply everywhere: no data sources (derive from inputs), every variable has a description, a type, and a validation where a wrong value would otherwise fail at apply time, every output has a description, defaults are the secure choice, and any new managed resource gets a `create_*` flag and a matching bring-your-own input so outputs stay identical either way.

## Commits

Use [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/). The scope is the submodule or root file the change touches.

```text
feat(autoscaling): add predictive scaling policy type
fix(iam): reduce secret ARNs with version stages to the base secret
docs: describe the ignore_task_definition_changes variant
test(security-group): cover ipv6 all-protocol egress
feat!: require cluster_arn instead of cluster_name
```

Append `!` after the type or scope for a breaking change and add a `BREAKING CHANGE:` footer explaining what consumers must do. Breaking changes ship only in a major release with an entry in the upgrade guide.

## Pull request checklist

- [ ] `make check` passes locally.
- [ ] New behaviour has a test; changed validations have both a passing and an `expect_failures` run.
- [ ] Variables and outputs have descriptions; `make docs` regenerated the README tables.
- [ ] Both `aws_ecs_service` blocks were updated if service arguments changed.
- [ ] `CHANGELOG.md` has an entry under `## [Unreleased]` in the right category.
- [ ] Breaking changes carry `!`, a `BREAKING CHANGE:` footer, and an update to `docs/UPGRADE-<major>.md`.
- [ ] Examples still initialise and validate; a new feature worth showing has an example.
- [ ] No data sources, no hard-coded account, region, or partition, no new defaults that weaken security.

## Release process

Releases are cut by maintainers.

1. Move the `## [Unreleased]` entries in `CHANGELOG.md` under a new `## [X.Y.Z] - YYYY-MM-DD` heading, add its compare link, and merge that change to `main`.
2. Create a signed annotated tag on the merge commit. The signing key must be registered with GitHub so the tag shows as Verified:

   ```sh
   git tag -s vX.Y.Z -m "aws.modules.ecs-service vX.Y.Z"
   git push origin vX.Y.Z
   ```

3. Dispatch the `module-release` workflow (`.github/workflows/module-release.yml`) with `release_tag = vX.Y.Z`. It verifies the signed tag, formatting, validation, tests, and generated docs, then publishes the GitHub release.
4. Announce the release with the commit SHA. Consumers pin that SHA, not the tag:

   ```hcl
   source = "git::https://github.com/hatan4ik/aws.modules.ecs-service.git?ref=<commit-sha>" # vX.Y.Z
   ```

Tags are never moved or deleted once published. A bad release is followed by a new patch release.
