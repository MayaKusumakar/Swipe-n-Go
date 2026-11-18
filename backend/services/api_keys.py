"""Loads the Claude API key from Secret Manager on App Engine.

Locally the key comes from backend/.env. On App Engine nothing secret goes in
app.yaml: if this project has a secret named `anthropic-api-key`, it's copied
into ANTHROPIC_API_KEY at startup. No secret means the AI features stay off
(they answer 503 and the app falls back on-device), which costs nothing.
See infra/README.md for turning it on.
"""
import logging
import os

SECRET_NAME = "anthropic-api-key"

log = logging.getLogger(__name__)


def _access_secret(name):
    # Imported here so local runs and tests never need Secret Manager.
    from google.cloud import secretmanager
    return secretmanager.SecretManagerServiceClient().access_secret_version(name=name).payload.data.decode()


def load_anthropic_key(access_secret=_access_secret):
    """Sets ANTHROPIC_API_KEY from Secret Manager. Only on App Engine, and only if it isn't set already.
    Returns True if a key was loaded."""
    if os.environ.get("ANTHROPIC_API_KEY") or not os.environ.get("GAE_ENV"):
        return False
    project = os.environ.get("GOOGLE_CLOUD_PROJECT")
    try:
        key = access_secret(f"projects/{project}/secrets/{SECRET_NAME}/versions/latest").strip()
    except Exception as e:  # noqa: BLE001 - no secret (the default) or no access: AI stays off
        log.warning("No Claude API key from Secret Manager (%s); AI features stay off.", type(e).__name__)
        return False
    if not key:
        return False
    os.environ["ANTHROPIC_API_KEY"] = key
    return True
