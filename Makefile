SHELL := /bin/bash
.DEFAULT_GOAL := check

ROOT_DIRS     := . modules/container-definition modules/iam modules/security-group modules/autoscaling
# Only example directories that contain Terraform, so a stray file under examples/ is ignored.
EXAMPLE_DIRS  := $(sort $(patsubst %/,%,$(dir $(wildcard examples/*/*.tf))))
ALL_DIRS      := $(ROOT_DIRS) $(EXAMPLE_DIRS)
TFLINT_CONFIG := $(CURDIR)/.tflint.hcl
TFDOCS_CONFIG := $(CURDIR)/.terraform-docs.yml
# Must match the terraform-docs bundled by the CI action (terraform-docs/gh-actions
# v1.4.1 ships 0.20.0); newer versions change table formatting and fail the
# docs drift check in CI.
TFDOCS_VERSION := v0.20.0

.PHONY: check fmt fmt-fix init validate lint test variants docs-version docs docs-check security clean

check: fmt validate lint test variants docs-check security

fmt:
	@echo "==> fmt ."
	@terraform fmt -check -recursive -diff

fmt-fix:
	@echo "==> fmt-fix ."
	@terraform fmt -recursive

init:
	@for dir in $(ALL_DIRS); do \
	  echo "==> init $$dir"; \
	  (cd "$$dir" && terraform init -backend=false -input=false >/dev/null) || exit 1; \
	done

validate: init
	@for dir in $(ALL_DIRS); do \
	  echo "==> validate $$dir"; \
	  (cd "$$dir" && terraform validate) || exit 1; \
	done

lint:
	@echo "==> lint (tflint --init)"
	@tflint --init --config="$(TFLINT_CONFIG)"
	@for dir in $(ALL_DIRS); do \
	  echo "==> lint $$dir"; \
	  (cd "$$dir" && tflint --config="$(TFLINT_CONFIG)" --format compact) || exit 1; \
	done

test:
	@for dir in $(ROOT_DIRS); do \
	  echo "==> test $$dir"; \
	  (cd "$$dir" && terraform test) || exit 1; \
	done

variants:
	@echo "==> variants service.tf"
	@scripts/check-service-variants.sh service.tf

docs-version:
	@terraform-docs --version | grep -q "$(TFDOCS_VERSION)" || { \
	  echo "error: terraform-docs $(TFDOCS_VERSION) is required (found: $$(terraform-docs --version)); CI generates docs with that version" >&2; exit 1; }

docs: docs-version
	@for dir in $(ALL_DIRS); do \
	  echo "==> docs $$dir"; \
	  terraform-docs -c "$(TFDOCS_CONFIG)" "$$dir" || exit 1; \
	done

docs-check: docs-version
	@for dir in $(ALL_DIRS); do \
	  echo "==> docs-check $$dir"; \
	  terraform-docs -c "$(TFDOCS_CONFIG)" --output-check "$$dir" || exit 1; \
	done

security:
	@echo "==> security checkov ."
	@checkov -d . --framework terraform --quiet --compact
	@if command -v trivy >/dev/null 2>&1; then \
	  echo "==> security trivy ."; \
	  trivy config --severity HIGH,CRITICAL --exit-code 1 .; \
	else \
	  echo "==> security trivy . (skipped: trivy not on PATH)"; \
	fi

clean:
	@echo "==> clean ."
	@find . -type d -name .terraform -prune -exec rm -rf {} +
	@find . -mindepth 2 -name .terraform.lock.hcl -not -path '*/.terraform/*' -delete
