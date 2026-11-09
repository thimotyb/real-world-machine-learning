output "bucket" {
  value = google_storage_bucket.data.name
}

output "image_prefix" {
  value = "${var.region}-docker.pkg.dev/${var.project_id}/${var.repository}"
}
