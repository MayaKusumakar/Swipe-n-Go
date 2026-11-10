"""Data models and their Datastore / JSON representations."""
from dataclasses import dataclass, field
from datetime import datetime

EVENT_KIND = "Event"

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
        }

    def to_dict(self):
        return {
            "id": self.id,
            "title": self.title,
            "description": self.description,
            "start_time": self.start_time.isoformat(),
            "end_time": self.end_time.isoformat() if self.end_time else None,
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
        }
