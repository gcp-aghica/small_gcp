#!/usr/bin/env bash
# Дать CI/CD-аккаунту право выкатывать ревизии одного сервиса Cloud Run.
# Остальные права (WIF, запись в registry, actAs на runtime SA) выдаёт Terraform.
# На DEV это же войдёт в скрипт разовой настройки SA и WIF.
# Usage: scripts/grant-cicd-deploy.sh <PROJECT_ID> <REGION> <SERVICE>
set -euo pipefail
PROJECT_ID=${1:?PROJECT_ID} REGION=${2:?REGION} SERVICE=${3:?SERVICE}
CICD_SA="${SERVICE}-cicd@${PROJECT_ID}.iam.gserviceaccount.com"

gcloud run services add-iam-policy-binding "$SERVICE" \
  --project="$PROJECT_ID" --region="$REGION" \
  --member="serviceAccount:$CICD_SA" --role=roles/run.developer >/dev/null
echo "$CICD_SA -> roles/run.developer on $SERVICE"
