# Песочница calculations-api в GCP

Проект `anton-cd-lab` повторяет то, что есть или будет на DEV (`resilens-app-staging`).

| На DEV | В песочнице | Кто создаёт |
|---|---|---|
| Artifact Registry `rosebud-apps` | `rosebud-apps`, `europe-west6` | Terraform |
| Runtime SA сервисов | `<service>-runtime` для всех четырёх сервисов | Terraform |
| `calculations-api-cicd` (пока нет) | `calculations-api-cicd`: `artifactregistry.writer`, `serviceAccountUser` на `calculations-api-runtime`, `workloadIdentityUser` для `sub` ветки `main` | Terraform |
| WIF-пул `github` в `resilens-internal` | пул `github-actions`, условие по числовым ID org и репо | Terraform |
| `observation-store-api`: свой репо, staging и prod, деплой руками `make staging`, сам создаёт `observation-api-token` | заглушка `observation-store-api` (`upstreams/`), деплой руками `make upstreams`, секрет создаёт `make upstream-secrets` | руками |
| Metadata API (`metadata-store`) | заглушка `metadata-api` | руками |
| Workspace Supabase (JWKS) | заглушка `workspace-auth` | руками |
| Секреты `supabase-key`, `gcs-hmac-*`, `metadata-api-token` | те же имена, случайные значения | `make app-secrets` (≈ `ensure-secrets.sh`) |
| Cloud Run `calculations-api`, env и секреты выставлены руками | то же | `make app-bootstrap` один раз |
| `run.developer` для CI/CD SA на сервис | то же | `make cicd-access` |
| Деплой `calculations-api` | только образ, через CD | GitHub Actions |

Terraform не знает про секреты и сервисы, поэтому в state нет ни одного значения секрета.

## Первый запуск (Cloud Shell)

В Cloud Shell есть `gcloud`, `terraform` и `docker`, вход под Owner проекта.

```bash
gcloud config set project anton-cd-lab
git clone -b feat/sandbox-calculations-like https://github.com/gcp-aghica/small_gcp && cd small_gcp
cp .env.example .env
```

1. **Terraform: аккаунты, WIF, registry.** Бакет для state один раз руками (Terraform не хранит state в бакете, который сам создаёт):
   ```bash
   gcloud storage buckets create gs://anton-cd-lab-tfstate --location=europe-west6 --uniform-bucket-level-access
   gcloud storage buckets update gs://anton-cd-lab-tfstate --versioning
   cd infra
   terraform init -backend-config=bucket=anton-cd-lab-tfstate
   terraform apply -var-file=sandbox.tfvars
   cd ..
   ```
   Если первый apply упал на только что включённом API (`SERVICE_DISABLED`), подождать минуту и повторить.
2. **Upstream-ы**, как их поднимают владельцы на DEV:
   ```bash
   gcloud auth configure-docker europe-west6-docker.pkg.dev --quiet
   make upstream-secrets   # observation-api-token, gcs-hmac-*, metadata-api-token, workspace-jwt-private-key
   make upstreams          # build, push, deploy трёх заглушек, curl /health
   ```
3. **calculations-api**, разово (на DEV это уже сделано):
   ```bash
   make app-secrets        # supabase-key; общие создаёт, только если их нет; доступ runtime SA ко всем пяти
   make app-bootstrap      # первый деплой с env (URL upstream-ов, CORS_ORIGINS) и секретами
   make cicd-access        # run.developer для calculations-api-cicd на сервис
   ```
4. **GitHub variables** на уровне репозитория (нужен admin, т.е. A):
   ```bash
   cd infra
   for v in GCP_WORKLOAD_IDENTITY_PROVIDER GCP_SERVICE_ACCOUNT REGISTRY; do
     gh variable set "$v" --repo gcp-aghica/small_gcp --body "$(terraform output -raw $v)"
   done
   gh variable delete GCP_CI_SERVICE_ACCOUNT --repo gcp-aghica/small_gcp
   ```
   Environment `dev` (`DEPLOY_ENV`, `GCP_SERVICE_ACCOUNT`) новым CD не используется: удалить после первого зелёного деплоя.
5. Required checks на `main`: `lint`, `test`, `build-pr` (имена не менялись). Merge в `main` = первый деплой через CD.

Старые ресурсы, созданные руками (`apps`, `demo-api`, `app-*`, пул `github`, секрет `api-token`), не трогаются.
Удалить по [docs/teardown-ui.md](../docs/teardown-ui.md) после первого зелёного деплоя через новый CD.

Удалить песочницу: сервисы и секреты через `gcloud run services delete` / `gcloud secrets delete`, затем `terraform destroy -var-file=sandbox.tfvars`.
WIF-пул после удаления 30 дней держит ID `github-actions`.

## Сценарии

Тестовый JWT пользователя, подписанный ключом `workspace-auth`:
```bash
TOKEN=$(gcloud secrets versions access latest --secret=workspace-jwt-private-key | uv run python -m scripts.mint_jwt)
APP=$(gcloud run services describe calculations-api --region europe-west6 --format='value(status.url)')
curl -s -H "Authorization: Bearer $TOKEN" "$APP/risk/site?site_id=s1"
```

1. **Деплой только образа сохраняет env и секреты, выставленные руками.** Перед merge добавить руками переменную:
   `gcloud run services update calculations-api --region europe-west6 --update-env-vars=MANUAL_MARKER=1`.
   После CD в `gcloud run services describe calculations-api --region europe-west6` остались `MANUAL_MARKER`,
   URL upstream-ов и все пять секретов, а `/health` показывает новый `git_sha`.
2. **Ревизия без обязательной переменной не стартует.** PR добавляет в `Settings` обязательное поле
   (например `new_required_var: str`) и задаёт его в `tests/conftest.py`, но не на сервисе. Тесты зелёные.
   После merge `make deploy` красный: ревизия не прошла startup probe. В `describe` трафик 100% на прежней ревизии,
   `/health` показывает старый `git_sha`. Чинить: `--update-env-vars` и перезапуск run, либо revert.
3. **Рассинхрон общего токена — ошибка upstream, а не 401.** Как ротация на стороне observation-store-api,
   о которой не знает calculations-api:
   ```bash
   openssl rand -hex 32 | tr -d '\n' | gcloud secrets versions add observation-api-token --data-file=-
   gcloud run services update observation-store-api --region europe-west6 --update-labels=rotated=1  # читает новую версию
   gcloud run services update calculations-api --region europe-west6 --update-secrets=OBSERVATION_STORE_API_BEARER_TOKEN=observation-api-token:1
   ```
   Запрос с `$TOKEN` → `502 {"detail":"observation-store-api: HTTP 401"}`. Вернуть calculations-api на `:latest`.
   Вывод для DEV: `observation-api-token` общий с `observation-store-api`, и `:latest` читается только при старте инстанса.
   После ротации нужно перезапустить оба сервиса.
4. **Два быстрых merge подряд.** Второй run ждёт первого в группе `cd-dev`. При трёх merge средний run будет
   *cancelled*: в очереди остаётся только последний. Итог: `/health` показывает SHA последнего merge.
5. **PR-прогон не получает токен GCP.** PR с временным шагом `google-github-actions/auth@v2` и `id-token: write` в `ci.yml`.
   `sub` = `repo:…:pull_request` не привязан к `calculations-api-cicd`, поэтому шаг auth падает с 403. Не мержить.
