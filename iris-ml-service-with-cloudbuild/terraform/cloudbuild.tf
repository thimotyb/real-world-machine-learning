# Identity used by the Cloud Build pipeline. The trigger itself is created by scripts/create-trigger.sh
# (the GitHub connection needs a manual authorization in the console).

# --- Service account used by the pipeline (the default Cloud Build account is too powerful)
resource "google_service_account" "cloudbuild" {
  account_id   = "iris-cloudbuild"
  display_name = "Iris Cloud Build pipeline"
}

locals {
  build_project_roles = [
    "roles/run.admin",         # deploy iris-api and iris-trainer
    "roles/logging.logWriter", # build logs in Cloud Logging
  ]
  # Cloud Run needs "act as" on the identities of the services it deploys
  build_acts_as = {
    api     = google_service_account.api.name
    trainer = google_service_account.trainer.name
  }
}

resource "google_project_iam_member" "cloudbuild_roles" {
  for_each = toset(local.build_project_roles)
  project  = var.project_id
  role     = each.key
  member   = "serviceAccount:${google_service_account.cloudbuild.email}"
}

resource "google_service_account_iam_member" "cloudbuild_acts_as" {
  for_each           = local.build_acts_as
  service_account_id = each.value
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.cloudbuild.email}"
}

# Push the images
resource "google_artifact_registry_repository_iam_member" "cloudbuild_pushes_images" {
  repository = google_artifact_registry_repository.docker.name
  location   = google_artifact_registry_repository.docker.location
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${google_service_account.cloudbuild.email}"
}

# Manual runs ("gcloud builds submit") upload the source to the data bucket (folder source/):
# the pipeline identity must be able to read it. Builds started by a git trigger do not need this.
resource "google_storage_bucket_iam_member" "cloudbuild_reads_source" {
  bucket = google_storage_bucket.data.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.cloudbuild.email}"
}
