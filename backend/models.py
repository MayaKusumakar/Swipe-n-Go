"""Data models and their Datastore / JSON representations."""
from dataclasses import dataclass, field
from datetime import datetime

from services import geo

EVENT_KIND = "Event"
# One cover photo per event, stored apart from the event so lists stay small.
COVER_KIND = "Cover"
ATTENDEE_KIND = "Attendee"
USER_KIND = "User"

# Attendee.status values.
PENDING = "pending"
APPROVED = "approved"

# Long text that is never filtered on. Unindexed properties can be longer than
# 1,500 bytes and don't add index entries (fewer Datastore writes).
UNINDEXED_EVENT_PROPERTIES = ("description", "summary")

# Allowed values for Event.level. None means "not specified".
LEVELS = ("anyone", "beginner", "intermediate", "advanced")


@dataclass
class Event:
    id: str
    title: str
    description: str
    start_time: datetime
    end_time: datetime | None
    location_name: str
    latitude: float | None
    longitude: float | None
    category: str
    image_url: str | None = None
    # Optional details used by the iOS client. Events stored before these
    # existed fall back to the defaults, so older clients are unaffected.
    host_name: str | None = None
    address: str | None = None
    capacity: int | None = None
    attendee_count: int = 0
    cost: str | None = None
    tags: list[str] = field(default_factory=list)
    level: str | None = None
    requires_approval: bool = False
    # Private location: hidden from GET /api/events, shown only to the host and
    # to approved attendees through GET /api/events/<id>/location.
    location_private: bool = False
    # Account id (Google "sub") of the signed-in @ucdavis.edu user who created it.
    host_id: str | None = None
    # Short "what is this / what to bring" blurb, rewritten by the
    # /tasks/summarize-stale cron job whenever summary_stale is set.
    summary: str | None = None
    summary_stale: bool = False
    summary_updated_at: datetime | None = None

    @property
    def geohash(self):
        """Stored so nearby searches can use prefix range queries (see services/geo.py)."""
        if self.latitude is None or self.longitude is None:
            return None
        return geo.encode(self.latitude, self.longitude)

    @property
    def is_full(self):
        # Capacity counts the host, like the iOS app's spotsLeft.
        return self.capacity is not None and self.attendee_count >= self.capacity - 1

    @classmethod
    def from_entity(cls, entity):
        return cls(
            id=str(entity.key.id_or_name),
            title=entity.get("title", ""),
            description=entity.get("description", ""),
            start_time=entity["start_time"],
            end_time=entity.get("end_time"),
            location_name=entity.get("location_name", ""),
            latitude=entity.get("latitude"),
            longitude=entity.get("longitude"),
            category=entity.get("category", ""),
            image_url=entity.get("image_url"),
            host_name=entity.get("host_name"),
            address=entity.get("address"),
            capacity=entity.get("capacity"),
            attendee_count=entity.get("attendee_count", 0),
            cost=entity.get("cost"),
            tags=list(entity.get("tags") or []),
            level=entity.get("level"),
            requires_approval=bool(entity.get("requires_approval", False)),
            location_private=bool(entity.get("location_private", False)),
            host_id=entity.get("host_id"),
            summary=entity.get("summary"),
            summary_stale=bool(entity.get("summary_stale", False)),
            summary_updated_at=entity.get("summary_updated_at"),
        )

    def to_entity_properties(self):
        """Datastore properties for this event (the entity key holds the id)."""
        return {
            "title": self.title,
            "description": self.description,
            "start_time": self.start_time,
            "end_time": self.end_time,
            "location_name": self.location_name,
            "latitude": self.latitude,
            "longitude": self.longitude,
            "category": self.category,
            "image_url": self.image_url,
            "host_name": self.host_name,
            "address": self.address,
            "capacity": self.capacity,
            "attendee_count": self.attendee_count,
            "cost": self.cost,
            "tags": self.tags,
            "level": self.level,
            "requires_approval": self.requires_approval,
            "location_private": self.location_private,
            "host_id": self.host_id,
            "geohash": self.geohash,
            "summary": self.summary,
            "summary_stale": self.summary_stale,
            "summary_updated_at": self.summary_updated_at,
        }

    def to_dict(self):
        """Public JSON. A private event's location fields are null here."""
        hidden = self.location_private
        return {
            "id": self.id,
            "title": self.title,
            "description": self.description,
            "start_time": self.start_time.isoformat(),
            "end_time": self.end_time.isoformat() if self.end_time else None,
            "location_name": None if hidden else self.location_name,
            "latitude": None if hidden else self.latitude,
            "longitude": None if hidden else self.longitude,
            "category": self.category,
            "image_url": self.image_url,
            "host_id": self.host_id,
            "host_name": self.host_name,
            "address": None if hidden else self.address,
            "capacity": self.capacity,
            "attendee_count": self.attendee_count,
            "cost": self.cost,
            "tags": self.tags,
            "level": self.level,
            "requires_approval": self.requires_approval,
            "location_private": self.location_private,
            "summary": self.summary,
        }

    def location_dict(self):
        """The full location, for the host and approved attendees only."""
        return {
            "location_name": self.location_name,
            "address": self.address,
            "latitude": self.latitude,
            "longitude": self.longitude,
        }


@dataclass
class Attendee:
    """A signed-in user who asked to join an event. `id` is their account id,
    so each person has at most one attendee entry per event."""
    id: str
    event_id: str
    name: str
    status: str
    created_at: datetime

    @classmethod
    def from_entity(cls, entity):
        return cls(
            id=str(entity.key.id_or_name),
            event_id=str(entity.key.parent.id_or_name),
            name=entity.get("name", ""),
            status=entity.get("status", PENDING),
            created_at=entity["created_at"],
        )

    def to_entity_properties(self):
        return {
            "name": self.name,
            "status": self.status,
            "created_at": self.created_at,
        }

    def to_dict(self):
        return {"id": self.id, "name": self.name, "status": self.status}


@dataclass
class User:
    """A signed-in @ucdavis.edu account. Saved on sign-in; requests are checked
    from the Google token alone, so normal requests never read this."""
    id: str
    email: str
    name: str
    picture_url: str | None
    created_at: datetime
    last_sign_in_at: datetime
    # The name they chose in the app's profile. Shown on their events and join
    # requests instead of the sign-in name when set.
    display_name: str | None = None

    @property
    def shown_name(self):
        return self.display_name or self.name

    @classmethod
    def from_entity(cls, entity):
        return cls(
            id=str(entity.key.id_or_name),
            email=entity.get("email", ""),
            name=entity.get("name", ""),
            picture_url=entity.get("picture_url"),
            created_at=entity["created_at"],
            last_sign_in_at=entity["last_sign_in_at"],
            display_name=entity.get("display_name"),
        )

    def to_entity_properties(self):
        return {
            "email": self.email,
            "name": self.name,
            "picture_url": self.picture_url,
            "created_at": self.created_at,
            "last_sign_in_at": self.last_sign_in_at,
            "display_name": self.display_name,
        }

    def to_dict(self):
        return {"id": self.id, "email": self.email, "name": self.shown_name, "picture_url": self.picture_url}
