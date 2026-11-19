#!/usr/bin/env bash
# Сторона calculations-api (аналог scripts/ensure-secrets.sh в calculations-api).
# gcs-hmac-* и metadata-api-token общие: создаются, только если их ещё нет.
# observation-api-token не создаётся: его владелец observation-store-api (make upstream-secrets).
# Usage: scripts/ensure-secrets.sh <PROJECT_ID>
set -euo pipefail
PROJECT_ID=${1:?PROJECT_ID}
source "$(dirname "$0")/_secrets.sh"

ensure_secret supabase-key random_token
ensure_secret gcs-hmac-key-id dummy_hmac_id
ensure_secret gcs-hmac-secret random_token
ensure_secret metadata-api-token random_token
require_secret observation-api-token "Run make upstream-secrets first (owned by observation-store-api)."

echo "Access:"
for s in supabase-key gcs-hmac-key-id gcs-hmac-secret metadata-api-token observation-api-token; do
  grant_access "$s" "$(sa calculations-api)"
done
