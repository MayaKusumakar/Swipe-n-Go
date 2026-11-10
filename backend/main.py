"""App entry point: builds the Flask app and registers the API Blueprints.

App Engine runs this through gunicorn as `main:app` (see app.yaml).
"""
import logging
import os
from datetime import datetime, timezone

from flask import Flask

from api.errors import register_error_handlers
from api.events import events_bp
from api.health import health_bp
from repositories.dev_sample_events import build_sample_events
from repositories.event_repository import EventRepository
from repositories.memory_event_repository import InMemoryEventRepository
from services.event_service import EventService


def _default_event_service():
    # EVENT_STORE=memory is for local dev only: serves sample events without Datastore.
    if os.environ.get("EVENT_STORE") == "memory":
        logging.warning("EVENT_STORE=memory: serving DEVELOPMENT sample events, not Datastore")
        repository = InMemoryEventRepository(build_sample_events(datetime.now(timezone.utc)))
    else:
        # DATASTORE_NAMESPACE lets local dev read the seeded "dev" namespace.
        namespace = os.environ.get("DATASTORE_NAMESPACE") or None
        repository = EventRepository(namespace=namespace)
    return EventService(repository)


def create_app(event_service=None):
    app = Flask(__name__)

    # Tests pass in their own service.
    app.extensions["event_service"] = event_service or _default_event_service()

    app.register_blueprint(health_bp)
    app.register_blueprint(events_bp)
    register_error_handlers(app)
    return app


app = create_app()
