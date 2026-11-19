# Общие функции для ensure-*-secrets.sh. Подключается через source.
# Значения секретов не печатаются и не попадают в аргументы командной строки.

# ensure_secret <name> <generator command...>: создать секрет с первой версией, если его нет.
ensure_secret() {
  local name=$1; shift
  if gcloud secrets describe "$name" --project="$PROJECT_ID" >/dev/null 2>&1; then
    echo "= $name: exists"
  else
    "$@" | gcloud secrets create "$name" --project="$PROJECT_ID" \
      --replication-policy=automatic --data-file=- >/dev/null
    echo "+ $name: created"
  fi
}

# grant_access <secret> <service account email>
grant_access() {
  gcloud secrets add-iam-policy-binding "$1" --project="$PROJECT_ID" \
    --member="serviceAccount:$2" --role=roles/secretmanager.secretAccessor \
    --condition=None >/dev/null
  echo "  $1 -> $2"
}

require_secret() {
  gcloud secrets describe "$1" --project="$PROJECT_ID" >/dev/null 2>&1 \
    || { echo "Secret $1 is missing. $2" >&2; exit 1; }
}

# Без перевода строки: он попал бы в env и в заголовок Authorization.
random_token() { printf '%s' "$(openssl rand -hex 32)"; }
dummy_hmac_id() { printf 'GOOG1E%s' "$(openssl rand -hex 16 | tr a-f A-F)"; }
rsa_key() { openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 2>/dev/null; }
sa() { echo "$1-runtime@$PROJECT_ID.iam.gserviceaccount.com"; }
