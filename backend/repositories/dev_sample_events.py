"""DEVELOPMENT ONLY sample events: student club meetups around UC Davis.

Used by scripts/seed_dev_events.py (writes them to Datastore) and by the
in-memory store (EVENT_STORE=memory). Never real data: the clubs are generic
made-up ones, not real student orgs. Start times are relative to `now` so the
events stay "upcoming"; hours are UTC (19:00 in Davis is 03:00 UTC in winter).
Coordinates are approximate. Categories are the iOS app's own, so they map
directly (see ActivityCategory in ios/Partner/Models/Models.swift).
"""
from datetime import timedelta

from models import Event

# `days` ahead, start `hour` (UTC) and `hours` long become start_time/end_time;
# everything else is passed to Event as is.
SAMPLE_EVENTS = [
    dict(title="Chess Club Casual Night", host_name="Chess Club",
         description="Open boards, clocks provided. New players get a quick lesson from club officers.",
         days=1, hour=3, hours=2, location_name="Memorial Union", latitude=38.5424, longitude=-121.7494,
         category="games", tags=["chess", "casual"], cost="Free", capacity=30, level="anyone"),
    dict(title="Running Club Arboretum Loop", host_name="Running Club",
         description="3.5-mile easy-pace loop through the Arboretum. No one gets left behind.",
         days=1, hour=15, hours=1, location_name="UC Davis Arboretum (Wyatt Deck)",
         latitude=38.5330, longitude=-121.7520,
         category="run", tags=["easy pace", "morning"], cost="Free", capacity=25, level="beginner"),
    dict(title="Climbing Club Bouldering Social", host_name="Climbing Club",
         description="Bouldering at the ARC wall. Shoes and chalk to borrow; we'll teach you the basics.",
         days=2, hour=2, hours=2, location_name="ARC Climbing Wall", latitude=38.5427, longitude=-121.7593,
         category="gym", tags=["bouldering", "gear provided"], cost="Free with ARC access",
         capacity=16, level="beginner"),
    dict(title="Coffee Club Latte Art Workshop", host_name="Coffee Club",
         description="Learn to pour a heart (or try). Milk alternatives available.",
         days=2, hour=20, hours=1, location_name="The Silo", latitude=38.5385, longitude=-121.7530,
         category="coffee", tags=["workshop"], cost="$3", capacity=12, level="anyone"),
    dict(title="Coding Club Hack Night", host_name="Coding Club",
         description="Bring a project or homework. Mentors on hand for Python, Swift, and web.",
         days=3, hour=2, hours=3, location_name="Kemper Hall", latitude=38.5375, longitude=-121.7546,
         category="study", tags=["coding", "pizza"], cost="Free", capacity=40, level="anyone"),
    dict(title="Ultimate Frisbee Club Pickup", host_name="Ultimate Frisbee Club",
         description="Pickup games, teams picked on the field. Bring a light and a dark shirt.",
         days=3, hour=0, hours=2, location_name="Russell Field", latitude=38.5390, longitude=-121.7650,
         category="sports", tags=["pickup", "outdoors"], cost="Free", capacity=28, level="anyone"),
    dict(title="Yoga Club Sunrise Flow", host_name="Yoga Club",
         description="Gentle 45-minute flow on the grass. Bring a mat or towel.",
         days=4, hour=15, hours=1, location_name="The Quad", latitude=38.5422, longitude=-121.7495,
         category="yoga", tags=["morning", "bring a mat"], cost="Free", capacity=30, level="beginner"),
    dict(title="Cooking Club Potluck", host_name="Cooking Club",
         description="Bring a dish from home (or a bag of chips). Recipe swap afterwards.",
         days=4, hour=2, hours=2, location_name="Student Community Center",
         latitude=38.5397, longitude=-121.7586,
         category="food", tags=["potluck", "vegetarian friendly"], cost="Bring a dish",
         capacity=35, level="anyone"),
    dict(title="Cycling Club Saturday Ride", host_name="Cycling Club",
         description="20-mile no-drop ride out to the countryside and back. Helmet required.",
         days=5, hour=17, hours=2, location_name="The Silo bike racks", latitude=38.5387, longitude=-121.7533,
         category="cycling", tags=["no-drop", "helmet required"], cost="Free", capacity=20,
         level="intermediate"),
    dict(title="Film Club Screening Night", host_name="Film Club",
         description="Student-picked classic plus a short discussion. Popcorn on us.",
         days=5, hour=3, hours=3, location_name="Sciences Lecture Hall", latitude=38.5385, longitude=-121.7518,
         category="movies", tags=["popcorn", "discussion"], cost="Free", capacity=80, level="anyone"),
    dict(title="Hiking Club Day Trip", host_name="Hiking Club",
         description="Moderate 5-mile hike in the hills west of Davis. Carpools leave from campus; "
                     "bring water and snacks.",
         days=6, hour=16, hours=5, location_name="Meet at the Memorial Union", latitude=38.5424,
         longitude=-121.7494, category="hike", tags=["carpool", "bring water"], cost="$5 gas money",
         capacity=15, level="intermediate", requires_approval=True),
    dict(title="Art Club Museum Sketch Session", host_name="Art Club",
         description="Sketch from the current exhibition. Paper and pencils provided.",
         days=7, hour=22, hours=2, location_name="Manetti Shrem Museum", latitude=38.5343, longitude=-121.7476,
         category="art", tags=["sketching", "supplies provided"], cost="Free", capacity=20, level="anyone"),
    dict(title="A Cappella Club Fall Showcase", host_name="A Cappella Club",
         description="Three student groups, one night. Doors open 15 minutes early.",
         days=8, hour=3, hours=2, location_name="Wellman Hall", latitude=38.5413, longitude=-121.7500,
         category="concert", tags=["live music"], cost="Free", capacity=120, level="anyone"),
    dict(title="Photography Club Campus Photo Walk", host_name="Photography Club",
         description="Golden-hour walk from the Arboretum to the Quad. Phones welcome.",
         days=9, hour=0, hours=2, location_name="UC Davis Arboretum (Wyatt Deck)",
         latitude=38.5330, longitude=-121.7520,
         category="explore", tags=["golden hour", "phones welcome"], cost="Free", capacity=20,
         level="anyone"),
]


def build_sample_events(now):
    events = []
    for i, sample in enumerate(SAMPLE_EVENTS, 1):
        fields = dict(sample)
        days, hour, hours = fields.pop("days"), fields.pop("hour"), fields.pop("hours")
        start = (now + timedelta(days=days)).replace(hour=hour, minute=0, second=0, microsecond=0)
        events.append(Event(
            id=f"seed-{i:03d}",
            start_time=start,
            end_time=start + timedelta(hours=hours),
            summary_stale=True,  # so a /tasks/summarize-stale run fills them in
            **fields,
        ))
    return events
