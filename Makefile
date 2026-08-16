SHELL := /usr/bin/env bash
UNAME_S := $(shell uname -s)

GCP_PROJECT_ID ?= runable-505508
GCP_STATE_BUCKET ?= $(GCP_PROJECT_ID)-firemig-tfstate
GCLOUD_BIN ?= gcloud
TF_BOOTSTRAP := infra/gcp/environments/bootstrap-state
TF_SINGLE := infra/gcp/environments/single-host

.PHONY: setup assets build local-up gcp-up demo test down infra-bootstrap infra-init infra-plan infra-apply infra-deploy infra-profile infra-demo infra-up infra-status infra-logs infra-destroy infra-destroy-all

setup:
	./scripts/setup/preflight.sh
	pnpm install --frozen-lockfile
	$(MAKE) assets
	cd services/coordinator && mix deps.get
	cd services/proxy && mix deps.get

assets:
	./scripts/setup/setup-assets.sh

build:
	pnpm build
	cd services/coordinator && mix compile --warnings-as-errors
	cd services/proxy && mix compile --warnings-as-errors

local-up:
ifeq ($(UNAME_S),Darwin)
	./scripts/local/docker-local-up.sh
else
	./scripts/setup/preflight.sh
	test -f assets/firecracker -a -f assets/vmlinux-6.1.155 -a -f assets/rootfs.ext4 -a -f assets/MANIFEST.json || $(MAKE) assets
	$(MAKE) build
	sudo --preserve-env=PATH ./scripts/local/local-up.sh
endif

gcp-up: infra-deploy

demo:
ifeq ($(UNAME_S),Darwin)
	docker compose exec -T runtime node /opt/firemig/packages/demo/dist/cli.js
else
	set -a && source .run/runtime.env && set +a && pnpm --filter @firemig/demo start
endif

test:
	shopt -s globstar nullglob; scripts=(scripts/**/*.sh); (($${#scripts[@]})); bash -n "$${scripts[@]}"
	pnpm typecheck
	pnpm test
	cd services/coordinator && mix precommit
	cd services/proxy && mix format --check-formatted && mix compile --warnings-as-errors && mix test
	python3 -m py_compile guest/agent.py
	terraform -chdir=infra/gcp/environments/single-host validate

down:
ifeq ($(UNAME_S),Darwin)
	./scripts/local/docker-down.sh
else
	sudo ./scripts/local/down.sh
endif

infra-plan:
	terraform -chdir=$(TF_SINGLE) plan

infra-apply:
	terraform -chdir=$(TF_SINGLE) apply

infra-bootstrap:
	terraform -chdir=$(TF_BOOTSTRAP) init
	terraform -chdir=$(TF_BOOTSTRAP) apply

infra-init:
	terraform -chdir=$(TF_SINGLE) init -reconfigure \
		-backend-config="bucket=$(GCP_STATE_BUCKET)" \
		-backend-config="prefix=runable/single-host"

infra-deploy:
	GCLOUD_BIN="$(GCLOUD_BIN)" GCP_PROJECT_ID="$(GCP_PROJECT_ID)" ./scripts/gcp/gcp-deploy.sh

infra-profile:
	PROFILE_MIGRATION=1 GCLOUD_BIN="$(GCLOUD_BIN)" GCP_PROJECT_ID="$(GCP_PROJECT_ID)" ./scripts/gcp/gcp-deploy.sh

infra-demo:
	set -a && source .run/gcp.env && set +a && pnpm --filter @firemig/demo start

infra-up: infra-bootstrap infra-init infra-apply infra-deploy

infra-status:
	terraform -chdir=$(TF_SINGLE) output

infra-logs:
	GCLOUD_BIN="$(GCLOUD_BIN)" GCP_PROJECT_ID="$(GCP_PROJECT_ID)" ./scripts/gcp/gcp-logs.sh

infra-destroy:
	terraform -chdir=$(TF_SINGLE) destroy

infra-destroy-all:
	GCLOUD_BIN="$(GCLOUD_BIN)" GCP_PROJECT_ID="$(GCP_PROJECT_ID)" ./scripts/gcp/gcp-destroy-all.sh
