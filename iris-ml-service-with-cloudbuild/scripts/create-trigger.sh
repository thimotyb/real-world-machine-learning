#!/usr/bin/env bash
# Creates the Cloud Build trigger "push on main -> pipeline", with MANUAL APPROVAL before the build runs.
# Run it AFTER connecting your GitHub repository to Cloud Build (one-time authorization in the console:
# Cloud Build -> Repositories (2nd gen) -> Create host connection -> GitHub -> Link repository).
#
# Usage:  CONNECTION=<connection name> GITHUB_REPO=<repository name as shown in Cloud Build> ./scripts/create-trigger.sh
# Optional: PROJECT_ID, REGION (default: from gcloud config), BRANCH (default main)
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project)}"
REGION="${REGION:-$(gcloud config get-value compute/region 2>/dev/null)}"
REGION="${REGION:-europe-west1}"
: "${CONNECTION:?set CONNECTION to the name of the Cloud Build host connection}"
: "${GITHUB_REPO:?set GITHUB_REPO to the linked repository name}"
BRANCH="${BRANCH:-main}"
SA="projects/${PROJECT_ID}/serviceAccounts/iris-cloudbuild@${PROJECT_ID}.iam.gserviceaccount.com"
REPO_RESOURCE="projects/${PROJECT_ID}/locations/${REGION}/connections/${CONNECTION}/repositories/${GITHUB_REPO}"

# Push on the branch: needs approval, then test + build + push + deploy
gcloud builds triggers create github \
  --name iris-deploy \
  --region "${REGION}" \
  --repository "${REPO_RESOURCE}" \
  --branch-pattern "^${BRANCH}\$" \
  --build-config cloudbuild.yaml \
  --service-account "${SA}" \
  --require-approval \
  --substitutions "_REGION=${REGION},_DEPLOY=true"

# Pull request: tests and build only (nothing is deployed), no approval needed
gcloud builds triggers create github \
  --name iris-pull-request \
  --region "${REGION}" \
  --repository "${REPO_RESOURCE}" \
  --pull-request-pattern "^${BRANCH}\$" \
  --build-config cloudbuild.yaml \
  --service-account "${SA}" \
  --substitutions "_REGION=${REGION},_DEPLOY=false"

echo "==> Done. Push to ${BRANCH}: the build waits in Cloud Build -> History until someone approves it"
echo "    (console, or: gcloud builds approve <BUILD_ID> --project ${PROJECT_ID} --region ${REGION})"
