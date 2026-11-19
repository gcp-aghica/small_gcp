variable "project_id" {
  description = "ID проекта песочницы (не номер)."
  type        = string
}

variable "region" {
  type    = string
  default = "europe-west6"
}

variable "registry_repository" {
  description = "Artifact Registry repo, как на DEV."
  type        = string
  default     = "rosebud-apps"
}

variable "github_repository_owner_id" {
  description = "Числовой ID GitHub-организации: gh api orgs/<org> --jq .id"
  type        = string
}

variable "github_repository_id" {
  description = "Числовой ID репозитория: gh api repos/<org>/<repo> --jq .id"
  type        = string
}

variable "ci_subjects" {
  description = <<-EOT
    OIDC sub, которым разрешено impersonate CI/CD SA. Только push в main:
    PR-прогоны (sub ...:pull_request) токен GCP не получают.
    Формат с неизменяемыми ID: repo:<org>@<org_id>/<repo>@<repo_id>:ref:refs/heads/main
  EOT
  type        = list(string)
}
