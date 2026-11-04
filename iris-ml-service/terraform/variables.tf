variable "project_id" {
  description = "Google Cloud project id"
  type        = string
}

variable "region" {
  description = "Region for Artifact Registry and Cloud Run"
  type        = string
  default     = "europe-west1"
}

variable "repository" {
  description = "Artifact Registry repository name"
  type        = string
  default     = "iris-repo"
}
