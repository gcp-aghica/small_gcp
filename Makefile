# Workflows вызывают только эти цели. Конфиг окружения берётся из .env.$(ENV) (в .gitignore).
SHELL := /bin/bash
.SHELLFLAGS := -euo pipefail -c
.ONESHELL:
.DEFAULT_GOAL := help

IMAGE_NAME ?= demo-api
IMAGE_TAG ?= dev
REGISTRY ?= local
IMAGE = $(REGISTRY)/$(IMAGE_NAME):$(IMAGE_TAG)

ifdef ENV
-include .env.$(ENV)
endif

SHORT_SHA = $(shell echo '$(IMAGE_TAG)' | cut -c1-7)
REV_TAG = sha-$(SHORT_SHA)
GCLOUD_FLAGS = --project=$(PROJECT_ID) --region=$(REGION) --quiet

# $(call require,VAR1 VAR2): упасть с понятной ошибкой, если переменная пустая.
require = $(foreach v,$(1),$(if $(strip $($(v))),,$(error $(v) is required)))

.PHONY: help install dev lint format format-check test build push deploy smoke switch-traffic

help: ## Список целей
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-16s %s\n", $$1, $$2}'

install: ## Установить зависимости (вкл. dev)
	uv sync --frozen

dev: ## Локальный сервер с autoreload
	API_TOKEN=$${API_TOKEN:-local-token} uv run uvicorn app.main:app --reload --port 8000

lint: ## ruff check
	uv run ruff check .

format: ## ruff format (правит файлы)
	uv run ruff format .

format-check: ## ruff format --check
	uv run ruff format --check .

test: ## pytest
	uv run pytest -q

build: ## docker build (REGISTRY, IMAGE_TAG)
	docker build --build-arg GIT_SHA=$(IMAGE_TAG) -t $(IMAGE) .

push: ## docker push (REGISTRY, IMAGE_TAG)
	$(call require,REGISTRY IMAGE_TAG)
	docker push $(IMAGE)

deploy: ## Новая ревизия без трафика с тегом sha-xxxxxxx (ENV, IMAGE_TAG, REGISTRY)
	$(call require,ENV IMAGE_TAG REGISTRY PROJECT_ID REGION SERVICE RUNTIME_SA SECRET_NAME)
	gcloud run deploy $(SERVICE) $(GCLOUD_FLAGS) \
	  --image=$(IMAGE) \
	  --no-traffic \
	  --tag=$(REV_TAG) \
	  --port=8000 \
	  --service-account=$(RUNTIME_SA) \
	  --update-env-vars=APP_VERSION=$(APP_VERSION) \
	  --update-secrets=API_TOKEN=$(SECRET_NAME):latest \
	  --min-instances=0

smoke: ## Проверить ревизию по URL её тега (ENV, IMAGE_TAG)
	$(call require,ENV IMAGE_TAG PROJECT_ID REGION SERVICE)
	url=$$(gcloud run services describe $(SERVICE) $(GCLOUD_FLAGS) --format=json \
	  | jq -r '.status.traffic[] | select(.tag == "$(REV_TAG)") | .url')
	if [[ -z "$$url" || "$$url" == "null" ]]; then echo "URL for tag $(REV_TAG) not found"; exit 1; fi
	echo "Smoke URL: $$url"
	code=000
	for i in $$(seq 1 10); do
	  code=$$(curl -s -o /tmp/health.json -w '%{http_code}' "$$url/health" || true)
	  if [[ "$$code" == "200" ]]; then break; fi
	  echo "attempt $$i: /health -> $$code, retrying"; sleep 3
	done
	if [[ "$$code" != "200" ]]; then echo "FAIL: /health -> $$code"; exit 1; fi
	echo "/health -> 200: $$(cat /tmp/health.json)"
	jq -e --arg sha '$(IMAGE_TAG)' '.git_sha == $$sha' /tmp/health.json >/dev/null \
	  || { echo "FAIL: git_sha mismatch"; exit 1; }
	code=$$(curl -s -o /dev/null -w '%{http_code}' "$$url/items")
	if [[ "$$code" != "401" ]]; then echo "FAIL: /items without token -> $$code (want 401)"; exit 1; fi
	echo "/items without token -> 401"
	echo "Smoke OK"

switch-traffic: ## 100% трафика на ревизию sha-xxxxxxx (ENV, IMAGE_TAG)
	$(call require,ENV IMAGE_TAG PROJECT_ID REGION SERVICE)
	gcloud run services update-traffic $(SERVICE) $(GCLOUD_FLAGS) --to-tags=$(REV_TAG)=100
