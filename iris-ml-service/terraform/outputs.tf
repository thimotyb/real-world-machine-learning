# Handy value to copy: the prefix of every image pushed to this repository
output "image_prefix" {
  value = "${var.region}-docker.pkg.dev/${var.project_id}/${var.repository}"
}
