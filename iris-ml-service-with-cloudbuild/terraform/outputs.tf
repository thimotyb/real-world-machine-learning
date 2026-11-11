output "bucket" {
  value = google_storage_bucket.data.name
}

output "image_prefix" {
  value = "${var.region}-docker.pkg.dev/${var.project_id}/${var.repository}"
}

output "cloudbuild_service_account" {
  value = google_service_account.cloudbuild.email
}
