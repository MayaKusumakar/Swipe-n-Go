"""Data models and their Datastore / JSON representations."""
from dataclasses import dataclass, field
from datetime import datetime

EVENT_KIND = "Event"
ATTENDEE_KIND = "Attendee"

# Attendee.status values.
PENDING = "pending"
APPROVED = "approved"

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
    # SHA-256 of the secret host token returned once when the event is created.
    # Never sent to clients.
    host_token_hash: str | None = None

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
            host_token_hash=entity.get("host_token_hash"),
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
            "host_token_hash": self.host_token_hash,
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
            "host_name": self.host_name,
            "address": None if hidden else self.address,
            "capacity": self.capacity,
            "attendee_count": self.attendee_count,
            "cost": self.cost,
            "tags": self.tags,
            "level": self.level,
            "requires_approval": self.requires_approval,
            "location_private": self.location_private,
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
    """Someone who asked to join an event. Holds a hash of their secret token."""
    id: str
    event_id: str
    name: str
    status: str
    token_hash: str
    created_at: datetime

    @classmethod
    def from_entity(cls, entity):
        return cls(
            id=str(entity.key.id_or_name),
            event_id=str(entity.key.parent.id_or_name),
            name=entity.get("name", ""),
            status=entity.get("status", PENDING),
            token_hash=entity.get("token_hash", ""),
            created_at=entity["created_at"],
        )

    def to_entity_properties(self):
        return {
            "name": self.name,
            "status": self.status,
            "token_hash": self.token_hash,
            "created_at": self.created_at,
        }

    def to_dict(self):
        return {"id": self.id, "name": self.name, "status": self.status}
