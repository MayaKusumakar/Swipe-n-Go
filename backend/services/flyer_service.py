"""Flyer reader: Claude looks at a photo of an event flyer and fills in the event.

The app sends the image (re-encoded on the phone, so photo location data is
gone) plus the text Apple's on-device recognizer found, which helps with small
print. Claude returns structured fields; the app shows them for the host to
check before anything is posted. Images are never stored.
"""
import base64
import re
from dataclasses import dataclass, field
from datetime import datetime, time

from pydantic import BaseModel, Field

from services import claude_call
from services.claude_call import MODEL, clip

# The app's categories (ios/Partner/Models/Models.swift, ActivityCategory).
# Club types, modeled on how UC Davis groups its registered student organizations.
CATEGORIES = ("sports", "outdoors", "wellness", "cultural", "arts", "music", "academic", "career",
              "tech", "service", "greek", "faith", "gaming", "social")
FIELDS = ("title", "date", "time", "location", "cost")


class _FlyerOutput(BaseModel):
    is_event_flyer: bool = Field(description="True only if the image advertises a specific event.")
    title: str = Field(description="The event's name as the flyer says it, in normal capitalization. Empty if not found.")
    start_time: str = Field(description="When it starts, ISO-8601 with the UTC offset given in 'now'. Empty if the date isn't on the flyer.")
    end_time: str = Field(description="When it ends, same format. Empty if not on the flyer.")
    location_name: str = Field(description="The venue or place name. Empty if not found.")
    address: str = Field(description="Street address or building/room if printed. Empty if not found.")
    description: str = Field(description="1-3 plain sentences about the event using only what the flyer says.")
    cost: str = Field(description='"Free", a price like "$5", or empty if not mentioned.')
    category: str = Field(description="The best fit from: " + ", ".join(CATEGORIES) + ". Empty if none fits.")
    organizer: str = Field(default="", description="The club or organization hosting the event, as printed. Empty if not found.")
    missing: list[str] = Field(description="Which of title, date, time, location, cost you could not read or are unsure about.")


@dataclass(frozen=True)
class FlyerReading:
    is_event_flyer: bool
    title: str
    start_time: datetime | None
    end_time: datetime | None
    location_name: str
    address: str
    description: str
    cost: str
    category: str
    missing: list[str] = field(default_factory=list)
    model: str = MODEL
    organizer: str = ""

    def to_dict(self):
        return {
            "is_event_flyer": self.is_event_flyer,
            "title": self.title,
            "start_time": self.start_time.isoformat() if self.start_time else None,
            "end_time": self.end_time.isoformat() if self.end_time else None,
            "location_name": self.location_name,
            "address": self.address,
            "description": self.description,
            "cost": self.cost,
            "category": self.category,
            "organizer": self.organizer or None,
            "missing": self.missing,
            "model": self.model,
        }


SYSTEM_PROMPT = """\
You read photos of event flyers for Swipe-n-Go, a UC Davis app, and fill in the event so a host \
only has to check it. Read the image itself; the recognized text you're given may have mistakes \
or the wrong order, so use it only to help with small print.

Rules:
- Only use what's on the flyer. Never invent a date, place, price, or detail. If something isn't \
there or you can't read it, leave it empty and list it in `missing`.
- Dates: flyers often skip the year. Use the next date on or after `now` that matches (and its \
weekday, if one is printed). Times are local, so use the UTC offset from `now`. If a time range \
is given ("7-9pm"), fill both start and end.
- Location: put only the venue or building name in location_name. Put the printed street address \
and room or suite in address. Leave either field empty when the flyer omits it.
- Cost: read the price of admission. Free food, parking, or giveaways do not mean free admission.
- Organizer: the club or group putting on the event, if printed (not a sponsor).
- Title: the event's name, not the club's slogan or a sponsor. Fix ALL-CAPS into normal \
capitalization.
- Description: 1-3 short sentences a student would find useful (what it is, who it's for, what to \
bring), no hashtags or emojis.
- If the image isn't an event flyer (a menu, a meme, a random photo), set is_event_flyer to false \
and leave the other fields empty.
"""


class FlyerService:
    def __init__(self, client=None, model=MODEL):
        self._client = client
        self._model = model

    @property
    def client(self):
        if self._client is None:
            self._client = claude_call.make_client()
        return self._client

    def read(self, image, media_type, now, ocr_text=""):
        """`image` is the raw image bytes (already validated by api/flyer_input.py)."""
        context = (f"now: {now.isoformat()} ({now.strftime('%A')})\n"
                   f"Recognized text (may contain mistakes):\n{ocr_text or '(none)'}")
        output = claude_call.parse(
            self.client,
            model=self._model,
            system=SYSTEM_PROMPT,
            content=[
                {"type": "image", "source": {"type": "base64", "media_type": media_type,
                                             "data": base64.b64encode(image).decode("ascii")}},
                {"type": "text", "text": context},
            ],
            output_format=_FlyerOutput,
        )
        return self._clean(output, now)

    def _clean(self, o, now):
        """Trust nothing blindly: real times only, known categories, short text."""
        if not o.is_event_flyer:
            return FlyerReading(False, "", None, None, "", "", "", "", "", list(FIELDS), self._model)
        start, start_has_time = _parse_time(o.start_time, now)
        end, end_has_time = _parse_time(o.end_time, now)
        if not end_has_time or (start and end and end <= start):
            end = None
        missing = [f for f in dict.fromkeys(m.strip().lower() for m in o.missing) if f in FIELDS]
        if start is None:
            missing = list(dict.fromkeys(missing + ["date", "time"]))
        elif not start_has_time:
            missing = list(dict.fromkeys(missing + ["time"]))
        return FlyerReading(
            is_event_flyer=True,
            title=clip(o.title, 120),
            start_time=start,
            end_time=end,
            location_name=clip(o.location_name, 120),
            address=clip(o.address, 120),
            description=clip(o.description, 600),
            cost=clip(o.cost, 40),
            category=o.category if o.category in CATEGORIES else "",
            missing=missing,
            model=self._model,
            organizer=clip(o.organizer, 120),
        )


_DATE_ONLY = re.compile(r"^\d{4}-\d{2}-\d{2}$")


def _parse_time(value, now):
    """Claude's time → (an aware datetime or None, whether it had a time of day).

    Claude is asked for ISO-8601 with the UTC offset from `now`, but sometimes leaves the offset
    off ("2026-11-23T18:00:00") or gives only the day ("2026-11-23"). Those used to be thrown away,
    so a flyer's date never reached the app. Now a missing offset means the host's time zone (from
    `now`), and a bare day is kept at noon with the time flagged for the host to fill in.
    """
    text = (value or "").strip().replace("Z", "+00:00")
    if not text:
        return None, False
    try:
        parsed = datetime.fromisoformat(text)
    except ValueError:
        return None, False
    has_time = not _DATE_ONLY.match(text)
    if not has_time:
        parsed = datetime.combine(parsed.date(), time(12, 0))
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=now.tzinfo)
    return parsed, has_time
