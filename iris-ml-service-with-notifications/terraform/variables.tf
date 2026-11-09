variable "project_id" {
  description = "Google Cloud project id (in a lab: qwiklabs-gcp-...)"
  type        = string
}

variable "region" {
  description = "Region for the bucket, Artifact Registry and Cloud Run"
  type        = string
  default     = "europe-west1"
}

variable "repository" {
  description = "Artifact Registry repository name"
  type        = string
  default     = "iris-repo"
}

variable "enable_apis" {
  description = "Let Terraform enable the needed APIs (set false in labs, enable them with gcloud)"
  type        = bool
  default     = true
}
