# small-gcp

Учебный FastAPI-сервис `demo-api`. На нём отрабатываем trunk-based CI/CD на Cloud Run до переноса в `calculations-api`.
Репо живёт в GitHub-организации с двумя участниками: A (Owner/Admin) и B (Member/Write). Подробности в [docs/setup-github-ui.md](docs/setup-github-ui.md).

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
_Заполняется по ходу._

## Что переносить в `calculations-api`
_Дополняется по ходу._ Вопросы к админам Resilens:
- Allowlist actions в org: разрешены ли `google-github-actions/auth`, `setup-gcloud`, `astral-sh/setup-uv`.
- Кастомизирован ли шаблон OIDC `sub` в org (`/orgs/{org}/actions/oidc/customization/sub`). От этого зависят principal://-строки для `workloadIdentityUser`.
- Публичный доступ к DEV: разрешён ли `allUsers` (часто запрещено org policy *Domain Restricted Sharing*) или флаг `--no-invoker-iam-check`. Если нет, smoke должен ходить с ID-токеном, а деплоеру нужен `run.invoker`.
- Вместо UI-кликов: скрипт или IaC для GCP-части.
- Hardening: добавить в condition провайдера `repository_id` / `repository_owner_id`, чтобы переименование репо не открывало доступ.
