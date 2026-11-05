"""DEVELOPMENT ONLY sample events.

Used by scripts/seed_dev_events.py (writes them to Datastore) and by the
in-memory store (EVENT_STORE=memory). Never real data. Start times are
relative to `now` so the events stay "upcoming". Coordinates are approximate.
"""
from datetime import timedelta

from models import Event

# (title, description, days ahead, start hour UTC, hours long, location, lat, lng, category)
SAMPLE_EVENTS = [
    ("Davis Farmers Market", "Local produce, food trucks, and live music.",
     1, 16, 4, "Central Park, Davis", 38.5449, -121.7405, "food"),
    ("Trivia Night", "Teams of up to 6. Prizes for the top 3.",
     1, 3, 2, "Memorial Union", 38.5424, -121.7494, "social"),
    ("Pickup Soccer", "All skill levels welcome. Bring water.",
     2, 0, 2, "ARC Fields", 38.5430, -121.7590, "sports"),
    ("Club Fair on the Quad", "Meet 100+ student orgs.",
     3, 18, 3, "The Quad", 38.5422, -121.7495, "clubs"),
    ("Open Mic Night", "Sign up at the door to perform.",
     4, 3, 3, "The Coffee House", 38.5425, -121.7490, "music"),
    ("Arboretum Sunset Walk", "Easy 2-mile walk, meet at the gazebo.",
     5, 1, 1, "UC Davis Arboretum", 38.5332, -121.7566, "outdoors"),
    ("Hackathon Info Session", "Learn about this quarter's hackathon.",
     6, 2, 1, "Kemper Hall", 38.5375, -121.7546, "tech"),
    ("Board Game Night", "Games provided, snacks welcome.",
     7, 2, 3, "Shields Library", 38.5395, -121.7495, "social"),
]


def build_sample_events(now):
    events = []
    for i, (title, description, days, hour, hours, location, lat, lng, category) in enumerate(SAMPLE_EVENTS, 1):
        start = (now + timedelta(days=days)).replace(hour=hour, minute=0, second=0, microsecond=0)
        events.append(Event(
            id=f"seed-{i:03d}",
            title=title,
            description=description,
            start_time=start,
            end_time=start + timedelta(hours=hours),
            location_name=location,
            latitude=lat,
            longitude=lng,
            category=category,
            image_url=None,
        ))
    return events
