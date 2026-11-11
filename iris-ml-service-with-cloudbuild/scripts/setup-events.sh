#!/usr/bin/env bash
# One-time setup AFTER the first pipeline run (the two Cloud Run services must exist):
#   - lets the trainer service account call the (private) trainer service
#   - creates the Eventarc trigger "new file in the bucket -> trainer"
# Later code updates go through the pipeline: this script is not needed again.
# Optional variables: PROJECT_ID, REGION (default: from gcloud config).
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project)}"
REGION="${REGION:-$(gcloud config get-value compute/region 2>/dev/null)}"
REGION="${REGION:-europe-west1}"
BUCKET="${PROJECT_ID}-iris-data"
TRAINER_SERVICE="iris-trainer"
TRAINER_SA="iris-trainer@${PROJECT_ID}.iam.gserviceaccount.com"

echo "==> Project: ${PROJECT_ID}  Region: ${REGION}  Bucket: ${BUCKET}"

# Eventarc calls the trainer with the trainer service account identity
gcloud run services add-iam-policy-binding "${TRAINER_SERVICE}" \
  --region "${REGION}" \
  --member "serviceAccount:${TRAINER_SA}" \
  --role roles/run.invoker

# Right after enabling the Eventarc API its service agent may need a few minutes
# to get its permissions, so we retry for up to ~5 minutes.
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

API_URL="$(gcloud run services describe iris-api --region "${REGION}" --format 'value(status.url)')"
echo "==> API URL: ${API_URL}"
echo "==> Now upload a CSV:  gcloud storage cp sample-data/iris-small.csv gs://${BUCKET}/data/"
