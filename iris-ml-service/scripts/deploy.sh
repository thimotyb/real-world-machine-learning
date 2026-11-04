#!/usr/bin/env bash
# Build the Docker image, push it to Artifact Registry and deploy it to Cloud Run.
#
# Usage:  ./scripts/deploy.sh
# Optional environment variables (defaults in brackets):
#   PROJECT_ID  [current gcloud project]
#   REGION      [europe-west1]
#   REPOSITORY  [iris-repo]       must match the Terraform repository
#   SERVICE     [iris-ml-service] Cloud Run service name
#   TAG         [current timestamp]
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project)}"
REGION="${REGION:-europe-west1}"
REPOSITORY="${REPOSITORY:-iris-repo}"
SERVICE="${SERVICE:-iris-ml-service}"
TAG="${TAG:-$(date +%Y%m%d-%H%M%S)}"

IMAGE="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPOSITORY}/${SERVICE}:${TAG}"

# Run from the project root, whatever the current folder is
cd "$(dirname "$0")/.."

echo "==> Project: ${PROJECT_ID}  Region: ${REGION}"
echo "==> Image:   ${IMAGE}"

# 1. Let Docker authenticate to Artifact Registry with our gcloud credentials
gcloud auth configure-docker "${REGION}-docker.pkg.dev" --quiet

# 2. Build the image (linux/amd64 is the architecture Cloud Run needs)
docker build --platform linux/amd64 -t "${IMAGE}" .

# 3. Push it to Artifact Registry
docker push "${IMAGE}"

# 4. Deploy to Cloud Run. Each deploy creates a new revision.
#    --allow-unauthenticated makes the URL public (fine for the demo).
gcloud run deploy "${SERVICE}" \
  --image "${IMAGE}" \
  --region "${REGION}" \
  --project "${PROJECT_ID}" \
  --allow-unauthenticated

# 5. Print the service URL, to paste into Postman as base_url
URL="$(gcloud run services describe "${SERVICE}" --region "${REGION}" --project "${PROJECT_ID}" --format 'value(status.url)')"
echo "==> Service URL: ${URL}"
