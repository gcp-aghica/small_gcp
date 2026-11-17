# GitHub: настройка руками в UI

Схема: **организация с двумя пользователями**, чтобы отработать разделение ролей как в Resilens.

| Вариант | Цена | Environments + branch policy | Rulesets | Required reviewers на environment |
|---|---|---|---|---|
| **Free org, public репо** (выбрано) | $0 | ✅ | ✅ | ✅ |
| Team org, private репо | $4 × 2 = $8/мес | ✅ | ✅ | ❌ (для private нужен Enterprise) |

Секретов в репо нет: доступ через WIF, токен лежит в Secret Manager. Поэтому public безопасен.
Чтобы отработать сценарий с required reviewer, нужен public.

**Участники:**

| Аккаунт | Роль в org | Роль в репо | Что делает |
|---|---|---|---|
| A = `toha-livs` | Owner | Admin | настраивает org, environments, variables, rulesets |
| B = `anton-finbert` | Member | Write | открывает PR и мержит, как обычный разработчик |

Про второй аккаунт: GitHub ToS разрешают одному человеку только один бесплатный личный аккаунт (исключение — machine account). Поэтому B — это существующий аккаунт (свой второй рабочий или коллеги), а не новый «второй я».

OIDC `sub` в этой org идёт в формате с ID: `repo:<ORG>@<org_id>/<REPO>@<repo_id>:…`. Под него и записаны principal-строки в [setup-gcp-ui.md](setup-gcp-ui.md) (шаг 6, «Формат `sub`»).

**Значения переменных вводите одной строкой, без Enter в конце и в середине.** Лишний перевод строки в `GCP_SERVICE_ACCOUNT` превратил ID проекта в `anton-cd-lab\n`, и `setup-gcloud` упал с `is not a valid project ID`. И проверяйте, что в `GCP_CI_SERVICE_ACCOUNT` стоит именно `app-ci`, а не `app-deployer`: иначе 403 `getAccessToken denied`, хотя все привязки в GCP верны.

---

## 1. Организация и участники (под A)
1. **+ → New organization** → план **Free**, имя `<ORG>`.
2. **Org → People → Invite member** → аккаунт B, роль **Member**. B принимает приглашение из письма или с github.com/orgs/<ORG>.
3. (Опционально) **Org → Teams → New team** `developers`, добавить туда B. Права в репо тогда выдаются команде, а не человеку, как в рабочей org.
4. **Org Settings → Member privileges**:
   - *Base permissions* → **No permission** (или Read);
   - *Repository creation* → снять галочки, чтобы члены org не создавали репо.

## 2. Actions на уровне org (под A)
**Org Settings → Actions → General**:
- *Policies* → **Allow `<ORG>`, and select non-`<ORG>`, actions and reusable workflows**:
  - ✅ Allow actions created by GitHub (это `actions/checkout`);
  - в поле allowlist добавить:
    ```
    google-github-actions/auth@*,
    google-github-actions/setup-gcloud@*,
    astral-sh/setup-uv@*
    ```
- *Workflow permissions* → **Read repository contents and packages permissions**; галочку *Allow GitHub Actions to create and approve pull requests* не ставить.
- *Approval for running fork pull request workflows from contributors* → **Require approval for all external contributors** → Save. Без approval workflows из чужих форков в public репо не стартуют.
- *Fork pull request workflows in private and internal repositories* → оставить выключенным (для public репо не действует).

*Зачем:* в Resilens allowlist actions почти наверняка уже есть. Здесь видно, что любое новое action придётся согласовывать с админами org.

## 3. Репозиторий (под A)
1. **Org → Repositories → New** → `<REPO>`, **Public**, без README, .gitignore и license.
2. **Repo → Settings → Collaborators and teams → Add people/team** → B (или team `developers`) с ролью **Write**.
3. **Repo → Settings → Actions → General** → проверить, что workflow permissions = Read: org-уровень наследуется.

## 4. Environment `dev` (под A)
**Repo → Settings → Environments → New environment** → `dev`:
1. **Deployment branches and tags** → *Selected branches and tags* → Add rule → `main`.
   *Зачем:* job с `environment: dev` получает OIDC `sub=repo:<ORG>@<org_id>/<REPO>@<repo_id>:environment:dev`, а именно этот sub привязан к `app-deployer`. Ограничение по ветке не даёт другим веткам получить такой токен.
2. Required reviewers и wait timer **не включать**: деплой в DEV полностью автоматический.
3. **Environment variables → Add variable**:
   - `GCP_SERVICE_ACCOUNT` = `app-deployer@<PROJECT_ID>.iam.gserviceaccount.com`
   - `DEPLOY_ENV` (многострочное значение, без кавычек и пробелов вокруг `=`; это `include` в Makefile):
     ```
     PROJECT_ID=<PROJECT_ID>
     REGION=<REGION>
     SERVICE=demo-api
     RUNTIME_SA=app-runtime@<PROJECT_ID>.iam.gserviceaccount.com
     SECRET_NAME=api-token
     APP_VERSION=0.1.0
     ```

Environment secrets не создаём: секретов в GitHub нет.

(Опционально) Environment `prod-like`:
- deployment branches `main`;
- **Required reviewers** = A;
- ✅ *Prevent self-review*.

Он нужен только для сценария «автор merge ≠ тот, кто одобряет деплой». Workflow для него добавим отдельным PR.

## 5. Repository variables (под A)
**Repo → Settings → Secrets and variables → Actions → вкладка Variables → New repository variable**:

| Name | Value |
|---|---|
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | `projects/<PROJECT_NUMBER>/locations/global/workloadIdentityPools/github/providers/github` |
| `GCP_CI_SERVICE_ACCOUNT` | `app-ci@<PROJECT_ID>.iam.gserviceaccount.com` |
| `REGISTRY` | `<REGION>-docker.pkg.dev/<PROJECT_ID>/apps` |

## 6. Bootstrap push (под A)
Локально коммиты уже есть. Сначала проверьте, под каким аккаунтом работает SSH:
```bash
ssh -T git@github.com
```
Push в пустой `main` делает A. Если SSH-ключ на этой машине принадлежит другому аккаунту (у нас дефолтный ключ был от `anton-olivson-resilens`), сделайте одно из двух:
- временно дайте B роль Admin;
- заведите для A host-алиас в `~/.ssh/config` (например `github-a`) и remote `git@github-a:<ORG>/<REPO>.git`.
```bash
git remote add origin git@github.com:<ORG>/<REPO>.git
```
```bash
git push -u origin main
```

## 7. Ruleset на `main` (под A, после первого прогона CI на PR)
Проверки `lint` и `test` появятся в списке только после того, как хотя бы раз отработают. Поэтому этот пункт делается, когда открыт PR с workflows.

**Repo → Settings → Rules → Rulesets → New branch ruleset**:
- Name `main`, Enforcement **Active**, Target branches → *Include default branch*.
- ✅ Restrict deletions, ✅ Block force pushes.
- ✅ **Require a pull request before merging**. Approvals 0 или 1 (при 1 PR от B одобряет A и наоборот).
- ✅ **Require status checks to pass** → ✅ *Require branches to be up to date before merging* → Add checks: `lint`, `test`.
- **Bypass list пустой**, admin bypass не включать: иначе A сможет обходить правила, и проверка будет нечестной.

То же правило можно завести на уровне org (**Org Settings → Rules**), как это обычно сделано в рабочей org.
