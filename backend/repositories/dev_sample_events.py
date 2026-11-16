"""DEVELOPMENT ONLY sample events.

Used by scripts/seed_dev_events.py (writes them to Datastore) and by the
in-memory store (EVENT_STORE=memory). Never real data. Start times are
relative to `now` so the events stay "upcoming". Coordinates are approximate.
"""
from datetime import timedelta

from models import Event

# (title, description, days ahead, start hour UTC, hours long, location, lat, lng, category)
# Club events: club names are generic examples, not real organizations.
SAMPLE_EVENTS = [
    ("Fall Club Showcase on the Quad", "Meet dozens of student clubs in one afternoon. Free snacks.",
     1, 19, 3, "The Quad", 38.5422, -121.7495, "social"),
    ("Running Club: Arboretum 5K", "Weekly club run at a conversational pace. New members welcome.",
     1, 14, 1, "UC Davis Arboretum", 38.5372, -121.7531, "sports"),
    ("Developer Club: Intro to iOS Workshop", "Build your first SwiftUI app. Bring a laptop if you have one.",
     2, 2, 2, "Kemper Hall", 38.5375, -121.7546, "tech"),
    ("Diwali Night Potluck", "Hosted by the South Asian student association. Bring a dish or just yourself.",
     3, 2, 3, "Student Community Center", 38.5398, -121.7540, "cultural"),
    ("Resume Review Night", "Club officers and alumni review resumes 1:1 before internship season.",
     3, 1, 2, "Student Community Center", 38.5398, -121.7545, "career"),
    ("Music Collective Open Mic", "Sign up at the door to play, sing or read.",
     4, 4, 3, "The Coffee House", 38.5425, -121.7490, "music"),
    ("Arboretum Restoration Volunteer Day", "Plant natives along Putah Creek. Gloves and tools provided.",
     5, 17, 3, "UC Davis Arboretum", 38.5332, -121.7566, "service"),
    ("Outdoors Club: Cold Canyon Hike", "5.5 mi club hike. Carpools leave the ARC at 7:30.",
     6, 15, 4, "Stebbins Cold Canyon", 38.5076, -122.0966, "outdoors"),
    ("Esports Club: Smash Tournament", "Bracket starts at 6:30. Casual pools for first-timers.",
     6, 2, 4, "Memorial Union", 38.5427, -121.7496, "gaming"),
    ("Fall Recruitment Open House", "Meet chapters and learn how Greek recruitment works.",
     7, 1, 2, "Memorial Union", 38.5422, -121.7492, "greek"),
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
            summary_stale=True,  # so a /tasks/summarize-stale run fills them in
        ))
    return events
