#!/usr/bin/env bash
# Deploys backend/ to App Engine (project swipe-n-go-app), after checks that stop
# a broken or unsafe deploy. Run from anywhere: infra/deploy.sh
# gcloud shows what it will deploy and asks before uploading.
set -euo pipefail

PROJECT=swipe-n-go-app
BACKEND="$(cd "$(dirname "$0")/../backend" && pwd)"
cd "$BACKEND"

fail() { echo "Not deploying: $*" >&2; exit 1; }

# Sign-in must be set up, or every /api request answers 401.
grep -q 'REPLACE_WITH_IOS_CLIENT_ID' app.yaml && fail "set GOOGLE_CLIENT_IDS in backend/app.yaml first"

# Free-tier caps must still be there.
grep -q 'max_instances: 1' app.yaml || fail "app.yaml must keep max_instances: 1 (free tier)"
grep -q 'instance_class: F1' app.yaml || fail "app.yaml must keep instance_class: F1 (free tier)"

# The live app must not read the seeded sample events (scripts/seed_dev_events.py).
grep -q 'DATASTORE_NAMESPACE: *"\?dev' app.yaml && fail "app.yaml points at the seeded \"dev\" namespace"

# Never ship a key in app.yaml; it comes from Secret Manager.
grep -q 'ANTHROPIC_API_KEY' app.yaml && fail "remove ANTHROPIC_API_KEY from app.yaml (use Secret Manager)"

# Billing must be on (it's off if the kill switch fired: see infra/README.md).
[ "$(gcloud billing projects describe "$PROJECT" --format='value(billingEnabled)')" = "True" ] \
  || fail "billing is off for $PROJECT (did the kill switch fire? see infra/README.md)"

if gcloud secrets versions list anthropic-api-key --project="$PROJECT" --filter=state=enabled \
     --format='value(name)' 2>/dev/null | grep -q .; then
  echo "AI: on (Claude key found in Secret Manager)"
else
  echo "AI: off (no enabled anthropic-api-key secret; AI routes will answer 503)"
fi

echo "Running tests..."
.venv/bin/python -m pytest -q

gcloud app deploy app.yaml cron.yaml --project="$PROJECT"

# Old versions stay reachable at their own <version>-dot-... address; remove them.
OLD=$(gcloud app versions list --project="$PROJECT" --filter="traffic_split=0" --format="value(version.id)")
[ -n "$OLD" ] && gcloud app versions delete $OLD --project="$PROJECT" --quiet

URL="https://$(gcloud app describe --project="$PROJECT" --format='value(defaultHostname)')"
echo "Checking $URL/health ..."
curl -fsS "$URL/health" && echo
echo "Logs: gcloud app logs tail --project=$PROJECT"
