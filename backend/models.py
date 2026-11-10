"""Data models and their Datastore / JSON representations."""
from dataclasses import dataclass
from datetime import datetime

EVENT_KIND = "Event"


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
        )

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
        }
