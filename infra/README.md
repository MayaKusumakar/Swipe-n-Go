# Google Cloud setup and cost safeguards

Project `swipe-n-go-app`, region `us-west2`, on the Google Cloud **free trial**.
App address: `https://swipe-n-go-app.wl.r.appspot.com`.
Goal: $0, hard-stopped. Never click "Activate full account" / "Upgrade" in Billing.

## What exists

- App Engine app (`us-west2`) and Firestore in **Datastore mode** (`(default)` database).
- Free-tier caps in `backend/app.yaml`: one F1 instance at most.
- Per-user request limits in the backend (`backend/services/rate_limiter.py`, listed in `docs/API.md`).
- Budget **"Swipe-n-Go $10 cap (swipe-n-go-app)"** (raised from $1 on 2026-11-25, for ~20 testers) on the project's billing account (Billing → Budgets),
  scoped to this project. It counts cost *before* trial credits. Emails billing admins at 50%,
  90%, 100%, and sends every update to the Pub/Sub topic `budget-alerts`.
- **Kill switch** (`budget_kill_switch/`): a Cloud Run function on `budget-alerts`. When cost
  passes the budget it unlinks the billing account from the project, which stops App Engine
  and everything else that costs money. It runs as the `budget-kill-switch` service account,
  which has only `roles/billing.projectManager` (and `roles/run.invoker` for the trigger).

Budget data lags real usage by hours, so the cap is "stops soon after $10", not to the cent.
The kill switch doesn't cover the Claude API: Anthropic bills separately (see below).

The project is in the university's Google Cloud organization. A new project there takes a few
minutes before Pub/Sub topics and function triggers can be created; retry if that fails.

## If the kill switch fires

The app goes offline. Find out what cost money (Billing → Reports) and fix it first, then
Billing → Account management → link `swipe-n-go-app` to the billing account again.
Datastore data is kept for a while after billing is turned off, but not forever.

## Deploying the backend

```sh
infra/deploy.sh
```

It refuses to deploy if `GOOGLE_CLIENT_IDS` in `backend/app.yaml` is still the placeholder, if the
free-tier caps were removed, if an API key was put in `app.yaml`, or if billing is off. Then it
runs the tests, deploys `app.yaml` and `cron.yaml` (gcloud asks before uploading), deletes old
versions (each one stays reachable at its own `<version>-dot-...` address otherwise), and checks
`/health`. Logs: `gcloud app logs tail --project=swipe-n-go-app`.

- The app is HTTPS only: `app.yaml`'s `secure: always` redirects `http://` to `https://`, so a
  sign-in token is never sent unencrypted. Keep it when editing `app.yaml`.
- The cron job (`cron.yaml`) runs on Cloud Scheduler, whose API must be on (it is; one job is
  within the free tier). On a new project: `gcloud services enable cloudscheduler.googleapis.com`.
- You need to be a project owner (or have App Engine deploy rights) to run it.

## AI features (on since 2026-11-16)

The Claude key is the Secret Manager secret `anthropic-api-key` (only App Engine and project
owners can read it). `backend/app.yaml` sets `AI_SUMMARIES=on` (Claude writes event summaries)
and `EXPERIMENTS=event_parse` ("Describe your plan"). The key comes from class resources and is
rate limited there; the backend also limits each user (`docs/API.md`). Without the secret, the
AI routes answer `503 ai_unavailable` and the app works on-device.

Turn AI off: `gcloud secrets versions disable 1 --secret=anthropic-api-key --project=swipe-n-go-app`,
then redeploy. To set the key up from scratch, store it in Secret Manager (never in `app.yaml`,
never pasted into a chat). `read -rs` hides the key and keeps it out of your shell history:

```sh
read -rs KEY   # paste the key, press Enter (nothing shows)
printf %s "$KEY" | gcloud secrets create anthropic-api-key --data-file=- --project=swipe-n-go-app
unset KEY
gcloud secrets add-iam-policy-binding anthropic-api-key --project=swipe-n-go-app \
  --member=serviceAccount:swipe-n-go-app@appspot.gserviceaccount.com --role=roles/secretmanager.secretAccessor
```

To replace the key later, add a new version the same way with
`gcloud secrets versions add anthropic-api-key --data-file=- --project=swipe-n-go-app`.
The backend reads it at startup (`backend/services/api_keys.py`), so redeploy or restart
after adding it. If it can't read the key, the startup log says
"No Claude API key from Secret Manager".

## Redeploy the kill switch

From `infra/budget_kill_switch/`:

```sh
gcloud functions deploy budget-kill-switch --gen2 --runtime=python313 --region=us-west2 --source=. \
  --entry-point=stop_billing --trigger-topic=budget-alerts \
  --service-account=budget-kill-switch@swipe-n-go-app.iam.gserviceaccount.com \
  --trigger-service-account=budget-kill-switch@swipe-n-go-app.iam.gserviceaccount.com \
  --set-env-vars=PROJECT_ID=swipe-n-go-app --max-instances=1 --memory=256Mi \
  --no-allow-unauthenticated --project=swipe-n-go-app
```

Safe test (under budget, changes nothing), then check the function's logs:

```sh
gcloud pubsub topics publish budget-alerts --project=swipe-n-go-app \
  --message='{"costAmount": 0.01, "budgetAmount": 1.0}'
```

Don't publish a message with `costAmount` over `budgetAmount`: that really turns billing off.
