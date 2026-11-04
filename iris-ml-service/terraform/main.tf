# Infrastructure needed by the course demo:
#   1. the Google Cloud APIs we use
#   2. an Artifact Registry repository for the Docker image
# The image push and the Cloud Run deploy are done by scripts/deploy.sh

terraform {
  required_version = ">= 1.5"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# Enable the APIs (Artifact Registry to store images, Cloud Run to run them)
resource "google_project_service" "apis" {
  for_each = toset(["artifactregistry.googleapis.com", "run.googleapis.com"])

  service            = each.key
  disable_on_destroy = false # do not switch the API off when we run "terraform destroy"
}

# Docker repository: images will be named
#   REGION-docker.pkg.dev/PROJECT/REPOSITORY/IMAGE:TAG
resource "google_artifact_registry_repository" "docker" {
  repository_id = var.repository
  location      = var.region
  format        = "DOCKER"
  description   = "Docker images for the Iris ML service"

  depends_on = [google_project_service.apis]
}
