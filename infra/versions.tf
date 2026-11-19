terraform {
  required_version = ">= 1.6"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 6.20, < 8"
    }
  }

  # Бакет создаётся один раз руками (см. infra/README.md):
  #   terraform init -backend-config="bucket=<PROJECT_ID>-tfstate"
  backend "gcs" {
    prefix = "sandbox"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}
