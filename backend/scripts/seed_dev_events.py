"""DEVELOPMENT ONLY: writes sample events to Datastore.

Every entity is marked is_seed_data=True and goes into the "dev" namespace by
default, so it stays separate from real data. Key names are fixed, so running
this again overwrites the same events instead of duplicating them.

Run from backend/:  python -m scripts.seed_dev_events [--namespace dev]
"""
import argparse
from datetime import datetime, timezone

from google.cloud import datastore

from models import EVENT_KIND
from repositories.dev_sample_events import build_sample_events


def build_entities(client, now):
    entities = []
    for event in build_sample_events(now):
        entity = datastore.Entity(
            key=client.key(EVENT_KIND, event.id),
            exclude_from_indexes=("description",),
        )
        entity.update({
            "title": event.title,
            "description": event.description,
            "start_time": event.start_time,
            "end_time": event.end_time,
            "location_name": event.location_name,
            "latitude": event.latitude,
            "longitude": event.longitude,
            "category": event.category,
            "image_url": event.image_url,
            "is_seed_data": True,
        })
        entities.append(entity)
    return entities


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--namespace", default="dev")
    args = parser.parse_args()

    client = datastore.Client(namespace=args.namespace)
    entities = build_entities(client, datetime.now(timezone.utc))
    client.put_multi(entities)
    print(f"Wrote {len(entities)} seed events to project={client.project} namespace={args.namespace}")


if __name__ == "__main__":
    main()
