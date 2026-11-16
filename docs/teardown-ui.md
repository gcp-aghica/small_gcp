# Teardown

## Вариант A: удалить весь проект (рекомендуется)
**IAM & Admin → Settings → Shut down** → ввести `<PROJECT_ID>`.

- Все ресурсы останавливаются сразу, billing прекращается.
- 30 дней проект можно восстановить (**Resource Manager → Pending deletion → Restore**), потом он удаляется навсегда.
- Project ID после этого занят навсегда, повторно его не взять.

## Вариант B: удалить ресурсы по одному (проект остаётся)
Удалять в таком порядке, чтобы не оставлять висящих привязок:

1. **Cloud Run** → `demo-api` → Delete. Ревизии и теги удалятся вместе с сервисом.
2. **Artifact Registry** → `apps` → Delete. Удалятся все образы.
3. **Secret Manager** → `api-token` → Delete.
4. **Workload Identity Federation** → пул `github` → Delete.
   - Пул переходит в состояние *deleted* на 30 дней.
   - ID `github` в это время занят. Чтобы пересоздать раньше, сделайте **Undelete** вместо создания нового.
5. **Service Accounts** → `app-deployer`, `app-ci`, `app-runtime` → Delete.
6. (Опционально) **APIs & Services** → Disable включённые API.
7. Проверка в Cloud Shell:
   ```bash
   gcloud run services list; gcloud artifacts repositories list; gcloud secrets list
   gcloud iam service-accounts list; gcloud iam workload-identity-pools list --location=global
   ```

## GitHub
- Settings → Environments → `dev` → Delete.
- Удалить repository variables и правило защиты ветки, либо весь репозиторий: Settings → Danger zone.
- Целиком: **Org Settings → Delete this organization** (удаляет и репо).
- Если второму участнику выдавали Viewer в GCP-проекте, убрать его в **IAM → IAM** (при варианте A уходит вместе с проектом).
