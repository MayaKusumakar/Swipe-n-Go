"""Budget kill switch: turns off billing on the project once spending passes the budget.

Cloud Billing sends budget updates to the `budget-alerts` Pub/Sub topic a few
times a day; this function reads each one. When cost (before free-trial
credits) is over the budget amount, it unlinks the project's billing account.
That stops App Engine and everything else that costs money. To turn the app
back on: Console → Billing → link the billing account to the project again.

Deployed separately from the backend; see infra/README.md.
"""
import base64
import json
import os

import functions_framework
from google.cloud import billing_v1

PROJECT_ID = os.environ["PROJECT_ID"]


def log(severity, message):
    # One JSON line on stdout becomes a log entry with this severity in Cloud Logging.
    print(json.dumps({"severity": severity, "message": message}), flush=True)


def over_budget(update):
    return update.get("costAmount", 0) > update.get("budgetAmount", 0)


@functions_framework.cloud_event
def stop_billing(cloud_event):
    update = json.loads(base64.b64decode(cloud_event.data["message"]["data"]))
    cost, budget = update.get("costAmount", 0), update.get("budgetAmount", 0)
    if not over_budget(update):
        log("INFO", f"Cost {cost} is within the {budget} budget; nothing to do.")
        return

    client = billing_v1.CloudBillingClient()
    name = f"projects/{PROJECT_ID}"
    if not client.get_project_billing_info(name=name).billing_enabled:
        log("INFO", f"Billing is already off for {PROJECT_ID}.")
        return
    # An empty billing account name unlinks the account, which turns billing off.
    client.update_project_billing_info(name=name, project_billing_info=billing_v1.ProjectBillingInfo())
    log("WARNING", f"Cost {cost} passed the {budget} budget: billing turned OFF for {PROJECT_ID}.")
