# small-gcp

Песочница для CD `calculations-api`: та же конфигурация (имена переменных, секретов, ресурсов), та же схема CI/CD,
но в своём GCP-проекте `anton-cd-lab` и репо `gcp-aghica/small_gcp`. Отлаживаем здесь, потом переносим на DEV (`resilens-app-staging`).
Участники org: A = `toha-livs` (Owner/Admin), B = `anton-finbert` (Member/Write), см. [docs/setup-github-ui.md](docs/setup-github-ui.md).

| Путь | Что | Деплой |
|---|---|---|
| `app/` | аналог `calculations-api`: `Settings` с теми же env, `/health` с `git_sha`, `/risk/site` под JWT → Observation с bearer-токеном | CD |
| `upstreams/` | заглушки `observation-store-api`, `metadata-api`, `workspace-auth` (JWKS вместо Workspace Supabase) | руками, `make upstreams` |
| `scripts/` | секреты (`ensure-*secrets.sh`), `run.developer` для CI/CD SA, выпуск тестового JWT | руками |
| `infra/` | Terraform: API, registry, сервисные аккаунты, WIF. [Инструкция и сценарии](infra/README.md) | руками |
| `Dockerfile` | один файл, target на каждый сервис | |
| `.github/workflows/ci.yml` | PR: `lint`, `test`, `build-pr` (без доступа к GCP) | |
| `.github/workflows/cd.yml` | `main`: test → build → push (тег = SHA) → `gcloud run deploy --image` → smoke, группа `cd-dev` | |

```bash
make install && make test
make build   # local/calculations-api:dev
make help    # все цели, включая ручные
```

Проект и регион `Makefile` выводит из `REGISTRY`, поэтому в GitHub нужны только `GCP_WORKLOAD_IDENTITY_PROVIDER`, `GCP_SERVICE_ACCOUNT`, `REGISTRY`.

## Как поднять с нуля
1. GCP-проект с billing ([docs/setup-gcp-ui.md](docs/setup-gcp-ui.md), шаг 1).
2. [GitHub org, репо](docs/setup-github-ui.md), required checks `lint`, `test`, `build-pr` на `main`.
3. [infra/README.md](infra/README.md): Terraform (аккаунты, WIF), upstream-ы и секреты, первый деплой calculations-api, GitHub variables. Merge = деплой через CD.

Сценарии проверок (деплой только образа, ревизия без обязательной переменной, общий токен, два merge подряд, PR без GCP): [infra/README.md](infra/README.md#сценарии).

Ещё не перенесено из `calculations-api`: приватная git-зависимость (аналог `research-sdk`) с токеном через BuildKit-секрет `research_sdk_repo_token`.

История ниже относится к первой версии (`demo-api`, ресурсы руками, два SA, `newest` + no-traffic/switch-traffic).

## Что пошло не так и как починили
Первый автодеплой (run #4, `2787a3b`) прошёл после шести исправлений:

1. **В WIF попал пример вместо реального репо.** В condition провайдера и в двух principal-строках оказался `my-lab-org/small-gcp` из таблицы-примера, а реальное имя `gcp-aghica/small_gcp` (с подчёркиванием). Нашли до первого запуска, сверив `describe` провайдера с именем org на GitHub. Вывод: сначала создавать org/репо, потом WIF, и сверять `assertion.repository` побуквенно.
2. **В IAM сервиса нет `allUsers`, хотя сервис публичный.** Это не ошибка: новая Console при «Allow public access» выключает invoker IAM check на сервисе, а не выдаёт `run.invoker` для `allUsers`.
3. **404 `Gaia id not found for app-ci@429361059391…`.** В `GCP_CI_SERVICE_ACCOUNT` стоял номер проекта вместо ID. Email SA всегда `…@<PROJECT_ID>.iam.gserviceaccount.com`.
4. **403 `getAccessToken denied`: другой формат `sub`.** Новая org выдаёт `sub` с неизменяемыми ID: `repo:gcp-aghica@357501158/small_gcp@1460380554:ref:refs/heads/main`. `repository` остаётся прежним, поэтому condition проходил, а привязка по классической строке — нет. Policy Troubleshooter федеративных принципалов не разбирает. Реальный `sub` увидели временным шагом, который печатает claims токена (PR #2). Переписали principal-строки у `app-ci` и `app-deployer`.
5. **403 `getAccessToken denied`: не тот SA.** Даже с верным `sub` и временной широкой привязкой `principalSet` на `app-ci` — 403. Причина: в `GCP_CI_SERVICE_ACCOUNT` при исправлении п. 3 попал `app-deployer@…`. Нашли по блоку `with:` шага `auth`. Сразу после вернули точную привязку и удалили широкую. Там же: перевод строки в `GCP_SERVICE_ACCOUNT` дал `project ID [anton-cd-lab\n]` в `setup-gcloud`.
6. **`artifactregistry.repositories.downloadArtifacts denied` на `gcloud run deploy`.** Cloud Run проверяет, что деплоящий сам может читать образ. Дали `app-deployer` роль Artifact Registry Reader на репозиторий `apps`.

Почему п. 3–5 так долго искали: `auth@v2` без `token_format` только пишет credentials-файл и всегда зелёный, а настоящий обмен токена происходит позже, в `docker push`. Теперь в обоих `auth` стоит `token_format: access_token`, и такие ошибки падают сразу на шаге auth.

## Что переносить в `calculations-api`
_Дополняется по ходу._ Вопросы к админам Resilens:
- Allowlist actions в org: разрешены ли `google-github-actions/auth`, `setup-gcloud`, `astral-sh/setup-uv`.
- Какой формат OIDC `sub` выдаёт org Resilens: классический `repo:<org>/<repo>:…`, с ID (`repo:<org>@<id>/<repo>@<id>:…`, как у нас) или кастомный шаблон (`/orgs/{org}/actions/oidc/customization/sub`). От этого зависят principal://-строки для `workloadIdentityUser`. Проверить первым деплоем с debug-шагом claims.
- Деплоеру, кроме `run.developer` на сервис и `serviceAccountUser` на runtime SA, нужен `artifactregistry.reader` на репозиторий с образами.
- В `auth@v2` сразу ставить `token_format: access_token`.
- Публичный доступ к DEV: разрешён ли `allUsers` (часто запрещено org policy *Domain Restricted Sharing*) или флаг `--no-invoker-iam-check`. Если нет, smoke должен ходить с ID-токеном, а деплоеру нужен `run.invoker`.
- Вместо UI-кликов: скрипт или IaC для GCP-части. В песочнице аккаунты и WIF в Terraform (`infra/`), сервисы и секреты скриптами, как на DEV.
- Hardening: condition провайдера по `repository_id` / `repository_owner_id`, чтобы переименование репо не открывало доступ (в песочнице сделано).
