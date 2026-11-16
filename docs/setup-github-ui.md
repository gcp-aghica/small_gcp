# GitHub: настройка руками в UI

Нужен личный аккаунт с **GitHub Pro**. На Free у приватных репозиториев нет Environments с deployment branch policy и нет branch protection.

## 1. Pro и репозиторий
1. **Settings → Billing and plans → Plans** → Upgrade to **Pro**.
2. **New repository** → `<REPO>`, **Private**, без README, .gitignore и license (содержимое придёт из bootstrap-коммита).

## 2. Actions: права по умолчанию
**Repo → Settings → Actions → General**:
- *Workflow permissions* → **Read repository contents and packages permissions**.
- Галочку *Allow GitHub Actions to create and approve pull requests* не ставить.

*Зачем:* `GITHUB_TOKEN` по умолчанию только читает. Workflows явно просят `id-token: write` там, где он нужен.

## 3. Environment `dev`
**Settings → Environments → New environment** → `dev`:
1. **Deployment branches and tags** → *Selected branches and tags* → Add rule → `main`.
   *Зачем:* job с `environment: dev` получает OIDC `sub=repo:<OWNER>/<REPO>:environment:dev`, а именно он привязан к `app-deployer`. Ограничение по ветке не даёт никакой другой ветке получить такой токен.
2. Required reviewers / wait timer **не включать**: деплой в DEV полностью автоматический.
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

## 4. Repository variables
**Settings → Secrets and variables → Actions → вкладка Variables → New repository variable**:

| Name | Value |
|---|---|
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | `projects/<PROJECT_NUMBER>/locations/global/workloadIdentityPools/github/providers/github` |
| `GCP_CI_SERVICE_ACCOUNT` | `app-ci@<PROJECT_ID>.iam.gserviceaccount.com` |
| `REGISTRY` | `<REGION>-docker.pkg.dev/<PROJECT_ID>/apps` |

## 5. Bootstrap push
Локально коммит уже сделан. Сначала проверьте, под каким аккаунтом работает SSH:
```bash
ssh -T git@github.com
```
Если ответ «Hi anton-olivson-resilens», это рабочий аккаунт, и в личный приватный репо он не пустит. Тогда добавьте SSH-ключ в личный аккаунт и host-алиас в `~/.ssh/config`, например `github-personal`, и используйте remote `git@github-personal:<OWNER>/<REPO>.git`.
```bash
git remote add origin git@github.com:<OWNER>/<REPO>.git
```
```bash
git push -u origin main
```

## 6. Защита `main` (после первого прогона CI на PR)
Проверки `lint` и `test` можно выбрать в списке только после того, как они хотя бы раз отработали. Поэтому этот пункт делается, когда открыт PR с workflows.

**Settings → Rules → Rulesets → New branch ruleset** (или классический **Branches → Add rule**):
- Name `main`, Enforcement **Active**, Target branches → *Include default branch*.
- ✅ Restrict deletions, ✅ Block force pushes.
- ✅ **Require a pull request before merging** (approvals 0: вы работаете один).
- ✅ **Require status checks to pass** → ✅ *Require branches to be up to date before merging* → Add checks: `lint`, `test`.
- Bypass list оставить пустым.
