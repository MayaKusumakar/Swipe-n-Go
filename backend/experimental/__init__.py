"""Experimental features: on main, but OFF unless someone turns them on.

Nothing in this package runs, and none of its routes exist, unless it is named
in the EXPERIMENTS environment variable (comma-separated), for example:

    EXPERIMENTS=event_parse,status flask --app main run --port 8080

With EXPERIMENTS unset (the default locally, and app.yaml doesn't set it) the
app's routes and behavior are exactly what they would be without this package;
tests/test_experimental.py checks that.

Available experiments:
- event_parse: POST /api/experimental/events/parse. Claude turns a typed
  description ("pickup soccer sat 3pm at the ARC fields, free") into the same
  fields the flyer reader returns. Costs money per call once ANTHROPIC_API_KEY
  is set, and is rate limited per user.
- status: GET /api/experimental/status. Server health (Datastore reachable,
  whether Claude is configured, which experiments are on). Never calls Claude.

To adopt one for real: move its route into the matching Blueprint under api/,
add it to docs/API.md's main sections, and delete it from here.
"""
import logging
import os

KNOWN = ("event_parse", "status")

log = logging.getLogger(__name__)


def enabled_experiments(raw=None):
    """The experiments switched on, from `raw` or the EXPERIMENTS variable. Unknown names are ignored."""
    raw = os.environ.get("EXPERIMENTS", "") if raw is None else raw
    names = [n.strip().lower() for n in raw.split(",") if n.strip()]
    unknown = [n for n in names if n not in KNOWN]
    if unknown:
        log.warning("Ignoring unknown EXPERIMENTS: %s (known: %s)", ", ".join(unknown), ", ".join(KNOWN))
    return tuple(n for n in KNOWN if n in names)


def register_experiments(app, experiments=None):
    """Called at the end of create_app(). Does nothing when no experiment is on."""
    on = enabled_experiments(experiments)
    app.extensions["experiments"] = on
    if not on:
        return

    # Imported only when needed, so a default start never loads this code.
    from experimental.rate_limit import RateLimiter
    from experimental.routes import experimental_bp

    log.warning("EXPERIMENTS on: %s. These routes are not part of the stable API.", ", ".join(on))
    app.extensions["experimental_rate_limiter"] = RateLimiter()
    if "event_parse" in on and "event_text_parser" not in app.extensions:
        from experimental.event_parse import EventTextParser
        app.extensions["event_text_parser"] = EventTextParser()
    app.register_blueprint(experimental_bp)
