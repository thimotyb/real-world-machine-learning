#!/usr/bin/env bash
# Build and push the two images, deploy the two Cloud Run services,
# and create the Eventarc trigger "new file in the bucket -> trainer".
#
# Run it AFTER "terraform apply" (bucket, registry and service accounts must exist).
# Optional variables: PROJECT_ID, REGION (default: from gcloud config), REPOSITORY.
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project)}"
REGION="${REGION:-$(gcloud config get-value compute/region 2>/dev/null)}"
REGION="${REGION:-europe-west1}"
REPOSITORY="${REPOSITORY:-iris-repo}"
BUCKET="${PROJECT_ID}-iris-data"
API_SERVICE="iris-api"
TRAINER_SERVICE="iris-trainer"
API_SA="iris-api@${PROJECT_ID}.iam.gserviceaccount.com"
TRAINER_SA="iris-trainer@${PROJECT_ID}.iam.gserviceaccount.com"
TAG="$(date +%Y%m%d-%H%M%S)"
PREFIX="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPOSITORY}"

cd "$(dirname "$0")/.."
echo "==> Project: ${PROJECT_ID}  Region: ${REGION}  Bucket: ${BUCKET}"

# 1. Build and push both images
gcloud auth configure-docker "${REGION}-docker.pkg.dev" --quiet
for NAME in api trainer; do
  docker build --platform linux/amd64 -t "${PREFIX}/iris-${NAME}:${TAG}" "./${NAME}"
  docker push "${PREFIX}/iris-${NAME}:${TAG}"
done

# 2. API: public. At the beginning it has no model (MODEL_URI is set by the trainer).
#    Later deploys keep the MODEL_URI already set.
gcloud run deploy "${API_SERVICE}" \
  --image "${PREFIX}/iris-api:${TAG}" \
  --region "${REGION}" \
  --service-account "${API_SA}" \
  --allow-unauthenticated

# 3. Trainer: private (only Eventarc can call it). It needs to know which API to update.
gcloud run deploy "${TRAINER_SERVICE}" \
  --image "${PREFIX}/iris-trainer:${TAG}" \
  --region "${REGION}" \
  --service-account "${TRAINER_SA}" \
  --no-allow-unauthenticated \
  --memory 1Gi \
  --timeout 600 \
  --set-env-vars "PROJECT_ID=${PROJECT_ID},REGION=${REGION},API_SERVICE=${API_SERVICE}"

# 4. Eventarc calls the trainer with the trainer service account identity
gcloud run services add-iam-policy-binding "${TRAINER_SERVICE}" \
  --region "${REGION}" \
  --member "serviceAccount:${TRAINER_SA}" \
  --role roles/run.invoker

# 5. The trigger: "an object was created in the bucket" -> trainer service.
#    Right after enabling the Eventarc API its service agent may need a few minutes
#    to get its permissions, so we retry for up to ~5 minutes.
if ! gcloud eventarc triggers describe iris-new-file --location "${REGION}" >/dev/null 2>&1; then
  for ATTEMPT in 1 2 3 4 5 6 7 8 9 10; do
    if gcloud eventarc triggers create iris-new-file \
      --location "${REGION}" \
      --event-filters "type=google.cloud.storage.object.v1.finalized" \
      --event-filters "bucket=${BUCKET}" \
      --destination-run-service "${TRAINER_SERVICE}" \
      --destination-run-region "${REGION}" \
      --service-account "${TRAINER_SA}"; then
      break
    fi
    [ "${ATTEMPT}" -eq 10 ] && { echo "Trigger creation failed: see the README troubleshooting table"; exit 1; }
    echo "==> Eventarc permissions are probably still propagating: retry ${ATTEMPT}/10 in 30 seconds"
    sleep 30
  done
fi

API_URL="$(gcloud run services describe "${API_SERVICE}" --region "${REGION}" --format 'value(status.url)')"
echo "==> API URL: ${API_URL}"
echo "==> Now upload a CSV:  gcloud storage cp sample-data/iris-small.csv gs://${BUCKET}/data/"
