# small-gcp

Учебный FastAPI-сервис `demo-api`. На нём отрабатываем trunk-based CI/CD на Cloud Run до переноса в `calculations-api`.
Репо живёт в GitHub-организации `gcp-aghica` с двумя участниками: A = `toha-livs` (Owner/Admin) и B = `anton-finbert` (Member/Write). Подробности в [docs/setup-github-ui.md](docs/setup-github-ui.md).

```bash
make install && make test
```
```bash
make build && docker run --rm -p 8000:8000 -e API_TOKEN=local local/demo-api:dev
```

## Как поднять с нуля
1. [GCP руками в Console](docs/setup-gcp-ui.md) и проверка в Cloud Shell.
2. [GitHub org, репо, environment, variables](docs/setup-github-ui.md), bootstrap push `main`.
3. PR с `.github/workflows/`, после первого прогона включить ruleset на `main`.
4. Merge = первый автодеплой.

Удаление: [docs/teardown-ui.md](docs/teardown-ui.md).

## Сценарии проверок
**Flow**
1. **Обычный деплой.** После merge трафик 100% на ревизии `sha-xxxxxxx`, `/health` показывает новый `git_sha`.
2. **Падающий smoke.** Job `deploy` красный, трафик остаётся на старой ревизии. Чиним новым PR.
3. **WIF из PR.** PR с временным шагом `auth@v2` под `app-ci` падает на auth (`sub=…:pull_request` не привязан). Не мержим.
4. **Два merge подряд.** У более раннего коммита job `newest` пишет «Skipped». При трёх быстрых merge средний run будет *cancelled* из-за `concurrency`, а не skipped.

**Роли (от лица B)**

5. B может открыть PR, но `git push origin main` отклоняется ruleset-ом.
6. Merge без зелёных `lint`/`test` или с устаревшей веткой невозможен.
7. B не видит Settings: environments, variables и rulesets не открываются и не меняются.
8. (Опционально) Environment `prod-like` с required reviewer: B мержит, деплой ждёт approve от A. Self-review запрещён.
9. (Опционально) У B в GCP есть только Viewer: `gcloud run services update-traffic` → `PERMISSION_DENIED`. Деплоить можно только через WIF.

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
- Вместо UI-кликов: скрипт или IaC для GCP-части.
- Hardening: добавить в condition провайдера `repository_id` / `repository_owner_id`, чтобы переименование репо не открывало доступ.
