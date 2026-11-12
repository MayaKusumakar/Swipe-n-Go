"""Event summaries ("TL;DR: what it is, who's going, what to bring").

Never written inline when an event is created or joined. Those only mark the
event `summary_stale`; the /tasks/summarize-stale route (App Engine cron, see
cron.yaml) rewrites stale summaries in batches.

Free by default: TemplateSummaryWriter builds the summary from the event's own
fields. ClaudeSummaryWriter is used only when AI_SUMMARIES=on AND an
ANTHROPIC_API_KEY is set, because every Claude call costs money. If Claude
fails for any reason the template is used, so the job never fails.
Event chats aren't on the server yet; once they are, add recent messages here.
"""
import json
import logging
import os

import anthropic

from services.planner_service import MODEL

# Most summaries one run writes, so a run stays short and Claude spend stays bounded.
BATCH_SIZE = 20
MAX_SUMMARY_LENGTH = 280

log = logging.getLogger(__name__)


def _first_sentence(text):
    text = " ".join((text or "").split())
    for end in (". ", "! ", "? "):
        if end in text:
            return text[: text.index(end) + 1]
    return text


def _clip(text, limit=MAX_SUMMARY_LENGTH):
    text = " ".join((text or "").split())
    return text if len(text) <= limit else text[: limit - 1].rstrip() + "…"


class TemplateSummaryWriter:
    """No AI, no cost. Never mentions the place, so private locations stay private."""

    def write(self, event):
        parts = []
        if event.description:
            parts.append(_first_sentence(event.description))
        going = event.attendee_count + 1  # the host is going too
        people = f"{going} going" if going > 1 else "Just the host so far"
        if event.capacity is not None:
            spots = max(0, event.capacity - going)
            people += f", {spots} spot{'' if spots == 1 else 's'} left" if spots else ", full"
        parts.append(people + ".")
        if event.level and event.level != "anyone":
            parts.append(f"Best for {event.level} level.")
        if event.cost:
            parts.append(f"Cost: {event.cost}.")
        if event.requires_approval:
            parts.append("The host approves each request.")
        return _clip(" ".join(parts))


SYSTEM_PROMPT = """\
You write the one-paragraph summary shown on an event card in Swipe-n-Go, a UC Davis app for \
finding things to do with other students. Using only the event details given, say what the plan \
is, who it suits, and what to bring if the details say. At most 2 short sentences, under 40 words, \
no emojis, no hashtags. Never invent details. Never mention or guess the location."""


class ClaudeSummaryWriter:
    def __init__(self, client=None, model=MODEL, fallback=None):
        self._client = client
        self._model = model
        self._fallback = fallback or TemplateSummaryWriter()

    def write(self, event):
        details = {
            "title": event.title,
            "category": event.category,
            "description": event.description,
            "people_going": event.attendee_count + 1,
            "capacity": event.capacity,
            "level": event.level,
            "cost": event.cost,
            "tags": event.tags,
            "host_approves_requests": event.requires_approval,
        }
        try:
            if self._client is None:
                self._client = anthropic.Anthropic(timeout=30.0, max_retries=1)
            response = self._client.beta.messages.create(
                model=self._model,
                max_tokens=1000,
                betas=["server-side-fallback-2026-07-01"],
                fallbacks="default",
                output_config={"effort": "low"},
                system=SYSTEM_PROMPT,
                messages=[{"role": "user", "content": json.dumps(details, ensure_ascii=False)}],
            )
        except (anthropic.AnthropicError, TypeError) as e:
            # TypeError: the SDK raises it at request time when there are no credentials.
            log.warning("Claude summary failed for %s, using the template: %s", event.id, e)
            return self._fallback.write(event)
        text = "".join(block.text for block in response.content if block.type == "text")
        if response.stop_reason == "refusal" or not text.strip():
            return self._fallback.write(event)
        return _clip(text)


def default_writer():
    """Claude only when explicitly switched on; otherwise the free template."""
    if os.environ.get("AI_SUMMARIES") == "on" and os.environ.get("ANTHROPIC_API_KEY"):
        return ClaudeSummaryWriter()
    return TemplateSummaryWriter()


class SummaryService:
    def __init__(self, repository, writer=None):
        self._repository = repository
        self._writer = writer or default_writer()

    def summarize_stale(self, now, batch_size=BATCH_SIZE):
        """Rewrites up to batch_size stale summaries. Returns how many were written."""
        written = 0
        for event in self._repository.list_stale_summaries(batch_size):
            if event.start_time < now:
                # Past events are never shown again; just clear the flag.
                self._repository.save_summary(event.id, event.summary, now, event.attendee_count)
                continue
            seen_count = event.attendee_count  # before writing, in case someone joins meanwhile
            summary = self._writer.write(event)
            self._repository.save_summary(event.id, summary, now, seen_count)
            written += 1
        return written
