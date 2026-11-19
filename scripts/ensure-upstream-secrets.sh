#!/usr/bin/env bash
# Сторона upstream-ов. На DEV: make ensure-secrets в observation-store-api и metadata-store.
# observation-api-token создаёт именно observation-store-api, calculations-api его только читает.
# Usage: scripts/ensure-upstream-secrets.sh <PROJECT_ID>
set -euo pipefail
PROJECT_ID=${1:?PROJECT_ID}
source "$(dirname "$0")/_secrets.sh"

ensure_secret observation-api-token random_token
ensure_secret gcs-hmac-key-id dummy_hmac_id
ensure_secret gcs-hmac-secret random_token
ensure_secret metadata-api-token random_token
# Только в песочнице: ключ, которым workspace-auth «подписывает» токены вместо Supabase Auth.
ensure_secret workspace-jwt-private-key rsa_key

echo "Access:"
for s in observation-api-token gcs-hmac-key-id gcs-hmac-secret; do
  grant_access "$s" "$(sa observation-store-api)"
done
grant_access metadata-api-token "$(sa metadata-api)"
grant_access workspace-jwt-private-key "$(sa workspace-auth)"
