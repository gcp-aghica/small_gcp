# GCP: настройка руками в Console

Всё делается в [console.cloud.google.com](https://console.cloud.google.com) под личным Google-аккаунтом (роль Owner в проекте).
Проверки в конце — в **Cloud Shell** (иконка `>_` справа вверху в Console).

Обозначения (заполните по ходу и держите под рукой):

| Плейсхолдер | Пример | Где взять |
|---|---|---|
| `<PROJECT_ID>` | `anton-cd-lab` | при создании проекта |
| `<PROJECT_NUMBER>` | `123456789012` | Dashboard → Project info |
| `<REGION>` | `europe-west6` | |
| `<ORG>/<REPO>` | `gcp-aghica/small_gcp` | организация GitHub и репо **побуквенно** (регистр, `_` vs `-`) |
| `<SUB_REPO>` | `gcp-aghica@357501158/small_gcp@1460380554` | часть `sub` после `repo:`; см. «Формат `sub`» в шаге 6 |

Email сервисного аккаунта всегда строится из **ID** проекта: `app-ci@<PROJECT_ID>.iam.gserviceaccount.com`. Номер проекта (`<PROJECT_NUMBER>`) нужен только в имени WIF-провайдера и в `principal://`-строках. Если их перепутать, будет 404 `Gaia id not found`.

Имена ресурсов (менять не нужно, на них опираются Makefile и workflows):
Artifact Registry `apps`, сервис Cloud Run `demo-api`, секрет `api-token`,
SA `app-runtime`, `app-ci`, `app-deployer`, WIF-пул и провайдер `github`.

---

## 1. Проект и billing
1. Селектор проектов вверху → **New project** → имя/ID `<PROJECT_ID>`, Organization: *No organization*.
2. **Billing** → привязать billing account к проекту. Для нового аккаунта это Free Trial ($300 кредитов).
3. (Рекомендую) **Billing → Budgets & alerts → Create budget** на $5 с письмами на 50/90/100%.

*Зачем:* без billing Cloud Run и Artifact Registry не включаются. Бюджет не ограничивает расходы, только предупреждает.

## 2. Включить API
**APIs & Services → Library**, по очереди найти и нажать **Enable**:
- Cloud Run Admin API — `run.googleapis.com`
- Artifact Registry API — `artifactregistry.googleapis.com`
- IAM Service Account Credentials API — `iamcredentials.googleapis.com` (выдача короткоживущих токенов SA при impersonation)
- Security Token Service API — `sts.googleapis.com` (обмен GitHub OIDC-токена на федеративный токен Google)
- Secret Manager API — `secretmanager.googleapis.com`
- Identity and Access Management (IAM) API — `iam.googleapis.com` (обычно уже включён; нужен для WIF-пулов)

## 3. Artifact Registry
**Artifact Registry → Repositories → Create repository**:
- Name `apps`, Format **Docker**, Mode **Standard**, Location type **Region** → `<REGION>`.
- Остальное по умолчанию → **Create**.

*Зачем:* сюда CI пушит образ `<REGION>-docker.pkg.dev/<PROJECT_ID>/apps/demo-api:<sha>`.

## 4. Runtime SA и секрет
1. **IAM & Admin → Service Accounts → Create service account**: ID `app-runtime`, описание «Cloud Run runtime». На шаге *Grant this service account access to project* **ничего не выбирать** → Done.
   *Зачем:* отдельная identity, под которой работает контейнер. Без ролей на проект, только точечные права.
2. В Cloud Shell сгенерировать токен (вывод не сохраняйте, понадобится только для ручного теста `/items`):
   ```bash
   openssl rand -hex 32
   ```
3. **Security → Secret Manager → Create secret**: Name `api-token`, Secret value — вставить токен, Replication — automatic → **Create**.
4. Открыть секрет `api-token` → вкладка **Permissions** → **Grant access** → New principals `app-runtime@<PROJECT_ID>.iam.gserviceaccount.com`, Role **Secret Manager Secret Accessor** → Save.
   *Зачем:* читать секрет может только runtime SA и только этот секрет. Деплоеру доступ к значению не нужен.

## 5. Bootstrap сервиса Cloud Run
**Cloud Run → Deploy container → Service**:
- Container image URL: `us-docker.pkg.dev/cloudrun/container/hello`
- Service name `demo-api`, Region `<REGION>`
- Authentication: **Allow public access**. Новая Console включает это не привязкой `allUsers` → `run.invoker`, а флагом сервиса *Invoker IAM check: disabled* (`run.googleapis.com/invoker-iam-disabled: true`). Результат тот же: URL сервиса и его тегов отвечает без Google-аутентификации, поэтому в `get-iam-policy` сервиса `allUsers` не будет.
- Billing: Request-based, Scaling: **Min instances 0**
- Раскрыть **Containers, Volumes, Networking, Security → Security** → Service account `app-runtime`
- **Create**

*Зачем:* роли `run.developer` выдаются на сервис, поэтому сервис должен уже существовать. Публичный доступ ставим здесь один раз под Owner: флаг `--allow-unauthenticated` в CI потребовал бы у деплоера `run.admin`.
Порт hello-контейнера 8080, наш образ слушает 8000. `make deploy` передаёт `--port=8000`, руками менять ничего не нужно.

## 6. Workload Identity Federation
**IAM & Admin → Workload Identity Federation → Create pool**:
1. Name `github`, Pool ID `github` → Continue.
2. Provider: **OpenID Connect (OIDC)**, Name/ID `github`, Issuer URL `https://token.actions.githubusercontent.com`, Audiences: **Default audience** → Continue.
3. Attribute mapping:
   - `google.subject` = `assertion.sub`
   - `attribute.repository` = `assertion.repository`
4. Attribute conditions → Add condition:
   ```
   assertion.repository == '<ORG>/<REPO>'
   ```
5. **Save**.

*Зачем:* GitHub выдаёт job OIDC-токен с claim `sub`. Condition отсекает токены всех чужих репозиториев ещё на обмене в STS. Какой SA можно имперсонировать, решают привязки в шагах 7–8 по точному `sub`.

**Формат `sub`.** Классический формат — `repo:<ORG>/<REPO>:ref:refs/heads/main`. Но в нашей новой org GitHub выдаёт формат с **неизменяемыми ID** организации и репозитория:
```
repo:gcp-aghica@357501158/small_gcp@1460380554:ref:refs/heads/main
repo:gcp-aghica@357501158/small_gcp@1460380554:environment:dev
```
`repository` при этом остаётся `gcp-aghica/small_gcp`, поэтому condition проходит, а привязка по классической строке — нет (403 `getAccessToken denied`). Узнать реальный `sub` надёжно можно только из самого токена. Для этого во workflow временно добавляется шаг, который печатает claims токена с `audience=debug`:
```yaml
      - name: Debug OIDC claims (temporary)
        run: |
          tok=$(curl -sS -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
            "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=debug" | jq -r .value)
          p=$(echo "$tok" | cut -d. -f2 | tr '_-' '/+')
          while [ $(( ${#p} % 4 )) -ne 0 ]; do p="$p="; done
          echo "$p" | base64 -d | jq '{sub, repository, ref, event_name, environment}'
```
Policy Troubleshooter федеративных принципалов не разбирает («principal not found»), поэтому на него не рассчитывайте.

Полное имя провайдера (пойдёт в GitHub variable `GCP_WORKLOAD_IDENTITY_PROVIDER`):
```
projects/<PROJECT_NUMBER>/locations/global/workloadIdentityPools/github/providers/github
```

## 7. CI SA `app-ci` (только пуш образов)
1. **Service Accounts → Create**: ID `app-ci`, без ролей на проект.
2. **Artifact Registry → Repositories** (именно список репозиториев, не страница «Images for apps»):
   - поставить **галочку** слева от `apps`;
   - справа вверху **Show info panel**, если панель скрыта;
   - в панели вкладка **Permissions → Add principal** → `app-ci@<PROJECT_ID>.iam.gserviceaccount.com`, Role **Artifact Registry Writer** → Save.

   То же из Cloud Shell:
   ```bash
   gcloud artifacts repositories add-iam-policy-binding apps --location=<REGION> \
     --member=serviceAccount:app-ci@<PROJECT_ID>.iam.gserviceaccount.com --role=roles/artifactregistry.writer
   ```
3. **Service Accounts → `app-ci` → вкладка Principals with access → Grant access**:
   - New principals:
     ```
     principal://iam.googleapis.com/projects/<PROJECT_NUMBER>/locations/global/workloadIdentityPools/github/subject/repo:<SUB_REPO>:ref:refs/heads/main
     ```
   - Role **Workload Identity User** → Save.

*Зачем:* стать `app-ci` может только job, запущенный push-ом в `main` (без environment). PR даёт `sub=repo:…:pull_request` и сюда не попадает.

## 8. Deployer SA `app-deployer`
1. **Service Accounts → Create**: ID `app-deployer`, без ролей на проект.
2. **Cloud Run → поставить галочку у `demo-api` → Permissions** (или в сервисе вкладка Security/Permissions) → **Add principal** `app-deployer@…`, Role **Cloud Run Developer** → Save.
3. **Service Accounts → `app-runtime` → Principals with access → Grant access** → `app-deployer@…`, Role **Service Account User** → Save.
   *Зачем:* деплой ревизии «под» `app-runtime` требует `iam.serviceAccounts.actAs` на этот SA и только на него.
4. **Service Accounts → `app-deployer` → Principals with access → Grant access**:
   - New principals:
     ```
     principal://iam.googleapis.com/projects/<PROJECT_NUMBER>/locations/global/workloadIdentityPools/github/subject/repo:<SUB_REPO>:environment:dev
     ```
   - Role **Workload Identity User** → Save.
5. **Artifact Registry → Repositories** → галочка у `apps` → **Permissions → Add principal** → `app-deployer@…`, Role **Artifact Registry Reader** → Save.
   *Зачем:* перед созданием ревизии Cloud Run проверяет, что **тот, кто деплоит**, может прочитать образ. Без этой роли `gcloud run deploy` падает с `artifactregistry.repositories.downloadArtifacts denied`.

*Зачем:* деплоить может только job с `environment: dev`. GitHub пускает в этот environment только ветку `main`.

**Ключи SA (вкладка Keys) не создаём вообще.**

## 9. (Опционально) Второй человек в проекте
**IAM & Admin → IAM → Grant access** → Google-аккаунт второго участника, роль **Viewer** (или уже: **Cloud Run Viewer** `roles/run.viewer`).

*Зачем:* он видит ревизии, трафик и логи, но задеплоить руками не может. Менять DEV можно только через merge в `main`: WIF → `app-deployer`. Попробуйте от его имени `gcloud run services update-traffic …` в Cloud Shell, ответ должен быть `PERMISSION_DENIED`.

---

## Проверка в Cloud Shell (read-only)
Выполните и пришлите вывод целиком:
```bash
export P=<PROJECT_ID> R=<REGION>
gcloud config set project $P
gcloud services list --enabled --format='value(config.name)' | grep -E 'run|artifactregistry|iamcredentials|sts|secretmanager|^iam\.'
gcloud artifacts repositories describe apps --location=$R --format='value(name,format)'
gcloud artifacts repositories get-iam-policy apps --location=$R --format=json
gcloud secrets get-iam-policy api-token --format=json
gcloud run services describe demo-api --region=$R --format='value(status.url,spec.template.spec.serviceAccountName)'
gcloud run services get-iam-policy demo-api --region=$R --format=json
gcloud run services describe demo-api --region=$R --format=json | jq '.metadata.annotations["run.googleapis.com/invoker-iam-disabled"]'
gcloud iam workload-identity-pools providers describe github --location=global --workload-identity-pool=github --format='yaml(name,attributeMapping,attributeCondition,oidc)'
for sa in app-runtime app-ci app-deployer; do echo "== $sa"; gcloud iam service-accounts get-iam-policy $sa@$P.iam.gserviceaccount.com --format=json; done
gcloud iam service-accounts keys list --iam-account=app-ci@$P.iam.gserviceaccount.com --managed-by=user
gcloud iam service-accounts keys list --iam-account=app-deployer@$P.iam.gserviceaccount.com --managed-by=user
gcloud projects get-iam-policy $P --format=json
```
Последняя команда нужна, чтобы убедиться, что ни у одного SA нет ролей на уровне проекта.
