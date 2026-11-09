# Infrastructure for the "new CSV in the bucket -> train -> redeploy" example.
#   - bucket for the CSV files and for the trained models
#   - Artifact Registry repository for the two images (api, trainer)
#   - two service accounts, with only the permissions they need
# The Cloud Run services and the Eventarc trigger are created by scripts/deploy.sh

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

locals {
  apis = ["artifactregistry.googleapis.com", "run.googleapis.com", "eventarc.googleapis.com",
  "pubsub.googleapis.com", "storage.googleapis.com"]
}

# In labs the student account cannot enable APIs: use enable_apis = false
resource "google_project_service" "apis" {
  for_each           = var.enable_apis ? toset(local.apis) : toset([])
  service            = each.key
  disable_on_destroy = false
}

# Bucket: data/ holds the CSV files, models/ holds the trained models.
# The location must be the same as the Eventarc trigger (the region).
resource "google_storage_bucket" "data" {
  name                        = "${var.project_id}-iris-data"
  location                    = var.region
  uniform_bucket_level_access = true
  force_destroy               = true # lets "terraform destroy" delete a bucket that is not empty

  depends_on = [google_project_service.apis]
}

resource "google_artifact_registry_repository" "docker" {
  repository_id = var.repository
  location      = var.region
  format        = "DOCKER"

  depends_on = [google_project_service.apis]
}

# --- Service account of the API: it can only READ models from the bucket
resource "google_service_account" "api" {
  account_id   = "iris-api"
  display_name = "Iris API"
}

resource "google_storage_bucket_iam_member" "api_reads_models" {
  bucket = google_storage_bucket.data.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.api.email}"
}

# --- Service account of the trainer: reads the CSV, writes the models,
#     updates the API service, receives the events
resource "google_service_account" "trainer" {
  account_id   = "iris-trainer"
  display_name = "Iris trainer"
}

resource "google_storage_bucket_iam_member" "trainer_bucket" {
  bucket = google_storage_bucket.data.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.trainer.email}"
}

# Update Cloud Run services (creates the new revision of the API)
resource "google_project_iam_member" "trainer_run" {
  project = var.project_id
  role    = "roles/run.developer"
  member  = "serviceAccount:${google_service_account.trainer.email}"
}

# Updating a Cloud Run service also checks that the caller can read the image:
# the trainer needs read access to the Artifact Registry repository
resource "google_artifact_registry_repository_iam_member" "trainer_reads_images" {
  repository = google_artifact_registry_repository.docker.name
  location   = google_artifact_registry_repository.docker.location
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${google_service_account.trainer.email}"
}

# Cloud Run requires "act as" permission on the identity used by the API
resource "google_service_account_iam_member" "trainer_acts_as_api" {
  service_account_id = google_service_account.api.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.trainer.email}"
}

# Receive events from Eventarc
resource "google_project_iam_member" "trainer_events" {
  project = var.project_id
  role    = "roles/eventarc.eventReceiver"
  member  = "serviceAccount:${google_service_account.trainer.email}"
}

# Cloud Storage publishes the notifications through Pub/Sub: its service agent needs this role
data "google_storage_project_service_account" "gcs" {}

resource "google_project_iam_member" "gcs_publishes_events" {
  project = var.project_id
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${data.google_storage_project_service_account.gcs.email_address}"
}
