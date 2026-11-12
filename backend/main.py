"""App entry point: builds the Flask app and registers the API Blueprints.

App Engine runs this through gunicorn as `main:app` (see app.yaml).
"""
import logging
import os
from datetime import datetime, timezone

from flask import Flask

from api.auth import auth_bp, require_signed_in_user
from api.errors import register_error_handlers
from api.events import events_bp
from api.health import health_bp
from api.planner import planner_bp
from api.tasks import tasks_bp
from repositories.dev_sample_events import build_sample_events
from repositories.event_repository import EventRepository
from repositories.memory_event_repository import InMemoryEventRepository
from repositories.user_repository import InMemoryUserRepository, UserRepository
from services.auth_service import AuthService
from services.event_service import EventService
from services.planner_service import PlannerService
from services.summary_service import SummaryService


def _default_repository():
    # EVENT_STORE=memory is for local dev only: serves sample events without Datastore.
    if os.environ.get("EVENT_STORE") == "memory":
        logging.warning("EVENT_STORE=memory: serving DEVELOPMENT sample events, not Datastore")
        repository = InMemoryEventRepository(build_sample_events(datetime.now(timezone.utc)))
    else:
        # DATASTORE_NAMESPACE lets local dev read the seeded "dev" namespace.
        namespace = os.environ.get("DATASTORE_NAMESPACE") or None
        repository = EventRepository(namespace=namespace)
    return repository


def _default_user_repository():
    if os.environ.get("EVENT_STORE") == "memory":
        return InMemoryUserRepository()
    return UserRepository(namespace=os.environ.get("DATASTORE_NAMESPACE") or None)


def create_app(event_service=None, planner_service=None, summary_service=None,
               auth_service=None, user_repository=None):
    app = Flask(__name__)

    # Only verified @ucdavis.edu Google accounts (GOOGLE_CLIENT_IDS); see services/auth_service.py.
    app.extensions["auth_service"] = auth_service or AuthService()
    app.extensions["user_repository"] = user_repository or _default_user_repository()
    app.before_request(require_signed_in_user)

    # Tests pass in their own services.
    event_service = event_service or EventService(_default_repository())
    app.extensions["event_service"] = event_service
    # Same store as the events. Free template summaries unless AI_SUMMARIES=on.
    if summary_service is None and isinstance(event_service, EventService):
        summary_service = SummaryService(event_service.repository)
    app.extensions["summary_service"] = summary_service
    # Reads ANTHROPIC_API_KEY on first use, so the server starts without one.
    app.extensions["planner_service"] = planner_service or PlannerService()

    app.register_blueprint(health_bp)
    app.register_blueprint(auth_bp)
    app.register_blueprint(events_bp)
    app.register_blueprint(planner_bp)
    app.register_blueprint(tasks_bp)
    register_error_handlers(app)
    return app


app = create_app()
