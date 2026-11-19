# Проект и регион выводятся из REGISTRY (<region>-docker.pkg.dev/<project>/<repo>), как в calculations-api,
# где в GitHub заведены только GCP_WORKLOAD_IDENTITY_PROVIDER, GCP_SERVICE_ACCOUNT и REGISTRY.
# Для ручных целей REGISTRY и CORS_ORIGINS берутся из .env (шаблон .env.example).
SHELL := /bin/bash
.SHELLFLAGS := -euo pipefail -c
.ONESHELL:
.DEFAULT_GOAL := help

-include .env

REGISTRY ?= local
IMAGE_TAG ?= dev

APP := calculations-api
UPSTREAMS := observation-store-api metadata-api workspace-auth

REGION     = $(firstword $(subst -docker.pkg.dev/, ,$(REGISTRY)))
PROJECT_ID = $(word 2,$(subst /, ,$(REGISTRY)))
GCLOUD_FLAGS = --project=$(PROJECT_ID) --region=$(REGION) --quiet
runtime_sa = $(1)-runtime@$(PROJECT_ID).iam.gserviceaccount.com
service_url = $$(gcloud run services describe $(1) $(GCLOUD_FLAGS) --format='value(status.url)')

# Ручные деплои помечаем коротким SHA (как make staging в observation-store-api), CD — полным.
LOCAL_TAG := $(shell git rev-parse --short HEAD 2>/dev/null || echo dev)

# Секреты каждого upstream: ENV=секрет. Имена как на DEV.
secrets_observation-store-api := OBSERVATION_STORE_API_BEARER_TOKEN=observation-api-token:latest,GCS_HMAC_KEY_ID=gcs-hmac-key-id:latest,GCS_HMAC_SECRET=gcs-hmac-secret:latest
secrets_metadata-api          := METADATA_API_BEARER_TOKEN=metadata-api-token:latest
secrets_workspace-auth        := JWT_PRIVATE_KEY=workspace-jwt-private-key:latest
secrets_calculations-api      := SUPABASE_KEY=supabase-key:latest,OBSERVATION_STORE_API_BEARER_TOKEN=observation-api-token:latest,METADATA_API_BEARER_TOKEN=metadata-api-token:latest,GCS_HMAC_KEY_ID=gcs-hmac-key-id:latest,GCS_HMAC_SECRET=gcs-hmac-secret:latest

# $(call require,VAR1 VAR2): упасть с понятной ошибкой, если переменная пустая.
require = $(foreach v,$(1),$(if $(strip $($(v))),,$(error $(v) is required)))
require_registry = $(if $(filter local,$(REGISTRY)),$(error REGISTRY must be an Artifact Registry path (see .env.example)))

# $(call build_push,<docker target>,<image>,<tag>)
define build_push
docker build --target $(1) --build-arg GIT_SHA=$(3) -t $(REGISTRY)/$(2):$(3) .
docker push $(REGISTRY)/$(2):$(3)
endef

.PHONY: help install lint format format-check test build push deploy smoke \
        upstream-secrets upstreams app-secrets app-bootstrap cicd-access

help: ## Список целей
	@awk 'BEGIN {FS = ":.*## "} /^### / {printf "\n%s\n", substr($$0, 5)} \
	  /^[a-z-]+:.*## / {printf "  %-18s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

### Разработка
install: ## Установить зависимости (вкл. dev)
	uv sync --frozen

lint: ## ruff check
	uv run ruff check .

format: ## ruff format (правит файлы)
	uv run ruff format .

format-check: ## ruff format --check
	uv run ruff format --check .

test: ## pytest
	uv run pytest -q

### CD: calculations-api (вызывают workflows)
build: ## docker build calculations-api (REGISTRY, IMAGE_TAG)
	docker build --target app --build-arg GIT_SHA=$(IMAGE_TAG) -t $(REGISTRY)/$(APP):$(IMAGE_TAG) .

push: ## docker push calculations-api (REGISTRY, IMAGE_TAG)
	$(call require_registry)
	docker push $(REGISTRY)/$(APP):$(IMAGE_TAG)

# Только образ: env, секреты, runtime SA и публичный доступ выставлены при app-bootstrap (на DEV: руками),
# gcloud run deploy --image их сохраняет. Ревизия, которая не стартовала, трафик не получает.
deploy: ## Новая ревизия calculations-api с этим образом (REGISTRY, IMAGE_TAG)
	$(call require_registry)
	gcloud run deploy $(APP) $(GCLOUD_FLAGS) --image=$(REGISTRY)/$(APP):$(IMAGE_TAG)

smoke: ## Запущен нужный коммит, без JWT 401 (REGISTRY, IMAGE_TAG)
	$(call require_registry)
	url=$(call service_url,$(APP))
	body=$$(curl -sf --retry 5 --retry-all-errors --retry-delay 3 "$$url/health") \
	  || { echo "FAIL: /health"; exit 1; }
	jq -e --arg sha '$(IMAGE_TAG)' '.git_sha == $$sha' <<<"$$body" >/dev/null \
	  || { echo "FAIL: git_sha mismatch: $$body"; exit 1; }
	echo "/health OK: $$body"
	code=$$(curl -s -o /dev/null -w '%{http_code}' "$$url/risk/site?site_id=smoke")
	[[ "$$code" == "401" ]] || { echo "FAIL: /risk/site without JWT -> $$code (want 401)"; exit 1; }
	echo "/risk/site without JWT -> 401"
	echo "Smoke OK"

### Upstream-ы (руками, как make staging в observation-store-api)
upstream-secrets: ## Создать секреты upstream-ов, если их нет, и дать доступ их runtime SA
	$(call require_registry)
	scripts/ensure-upstream-secrets.sh $(PROJECT_ID)

upstreams: ## Собрать и задеплоить observation-store-api, metadata-api, workspace-auth
	$(call require_registry)
	$(foreach s,$(UPSTREAMS),
	$(call build_push,$(s),$(s),$(LOCAL_TAG))
	gcloud run deploy $(s) $(GCLOUD_FLAGS) \
	  --image=$(REGISTRY)/$(s):$(LOCAL_TAG) \
	  --port=8000 \
	  --service-account=$(call runtime_sa,$(s)) \
	  --set-secrets=$(secrets_$(s)) \
	  --no-invoker-iam-check \
	  --min-instances=0 --max-instances=2
	curl -sf --retry 5 --retry-all-errors --retry-delay 3 "$(call service_url,$(s))/health"; echo
	)

### Первичная настройка calculations-api (руками, один раз)
app-secrets: ## Секреты calculations-api (как scripts/ensure-secrets.sh на DEV) + доступ runtime SA
	$(call require_registry)
	scripts/ensure-secrets.sh $(PROJECT_ID)

# Аналог того, что на DEV уже сделано руками через make staging: полный конфиг сервиса.
# Дальше CD меняет только образ. SUPABASE_URL (каталог) в песочнице никуда не ходит.
app-bootstrap: ## Первый деплой calculations-api с env и секретами
	$(call require_registry)
	$(call build_push,app,$(APP),$(LOCAL_TAG))
	obs=$(call service_url,observation-store-api)
	meta=$(call service_url,metadata-api)
	auth=$(call service_url,workspace-auth)
	# ^@^: разделитель @ вместо запятой, CORS_ORIGINS сам через запятую.
	gcloud run deploy $(APP) $(GCLOUD_FLAGS) \
	  --image=$(REGISTRY)/$(APP):$(LOCAL_TAG) \
	  --port=8000 \
	  --service-account=$(call runtime_sa,$(APP)) \
	  --set-env-vars="^@^SUPABASE_URL=$$auth@WORKSPACE_SUPABASE_URL=$$auth@OBSERVATION_STORE_API_BASE_URL=$$obs@METADATA_API_BASE_URL=$$meta@CORS_ORIGINS=$(CORS_ORIGINS)" \
	  --set-secrets=$(secrets_$(APP)) \
	  --no-invoker-iam-check \
	  --min-instances=0 --max-instances=2

cicd-access: ## Дать CI/CD SA run.developer на calculations-api (сервис должен существовать)
	$(call require_registry)
	scripts/grant-cicd-deploy.sh $(PROJECT_ID) $(REGION) $(APP)
