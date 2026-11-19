# Только аккаунты и права без привязки к сервисам и секретам.
# Сервисы Cloud Run и секреты создаются руками/скриптами, как на DEV (см. infra/README.md),
# поэтому права на них выдают scripts/ensure-*secrets.sh и scripts/grant-cicd-deploy.sh.

# Runtime-аккаунты: без ролей на проект, только доступ к своим секретам.
resource "google_service_account" "runtime" {
  for_each = toset([
    "calculations-api",
    "observation-store-api",
    "metadata-api",
    "workspace-auth",
  ])
  account_id   = "${each.value}-runtime"
  display_name = "Cloud Run runtime: ${each.value}"
  depends_on   = [google_project_service.this]
}

# Единый CI/CD-аккаунт (на DEV: calculations-api-cicd в resilens-app-staging).
# run.developer на сервис выдаёт scripts/grant-cicd-deploy.sh: сервиса на момент apply ещё нет.
resource "google_service_account" "cicd" {
  account_id   = "calculations-api-cicd"
  display_name = "GitHub Actions: build, push, deploy"
  depends_on   = [google_project_service.this]
}

resource "google_artifact_registry_repository_iam_member" "cicd_writer" {
  location   = google_artifact_registry_repository.apps.location
  repository = google_artifact_registry_repository.apps.name
  role       = "roles/artifactregistry.writer" # writer включает reader: deploy проверяет чтение образа
  member     = google_service_account.cicd.member
}

# Деплой ревизии «от имени» runtime SA требует actAs на него. CD катит только calculations-api.
resource "google_service_account_iam_member" "cicd_act_as_runtime" {
  service_account_id = google_service_account.runtime["calculations-api"].name
  role               = "roles/iam.serviceAccountUser"
  member             = google_service_account.cicd.member
}

# --- Workload Identity Federation ---
# На DEV пул общий, в resilens-internal; здесь свой. Имя не "github": тот пул создан руками раньше.
resource "google_iam_workload_identity_pool" "github" {
  workload_identity_pool_id = "github-actions"
  display_name              = "GitHub Actions"
  depends_on                = [google_project_service.this]
}

resource "google_iam_workload_identity_pool_provider" "github" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github"
  display_name                       = "GitHub OIDC"

  attribute_mapping = {
    "google.subject"                = "assertion.sub"
    "attribute.repository"          = "assertion.repository"
    "attribute.repository_id"       = "assertion.repository_id"
    "attribute.repository_owner_id" = "assertion.repository_owner_id"
    "attribute.ref"                 = "assertion.ref"
  }

  # По числовым ID: переименование или пересоздание репо с тем же именем доступ не откроет.
  attribute_condition = join(" && ", [
    "assertion.repository_owner_id == '${var.github_repository_owner_id}'",
    "assertion.repository_id == '${var.github_repository_id}'",
  ])

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

resource "google_service_account_iam_member" "cicd_wif" {
  for_each           = toset(var.ci_subjects)
  service_account_id = google_service_account.cicd.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principal://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/subject/${each.value}"
}
