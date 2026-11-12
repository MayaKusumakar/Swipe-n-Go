"""Free, local interest matching for GET /api/events/recommended.

Exact tag matching is too rigid ("hiking and backpacking" should match
"Arboretum Sunset Walk"), but embedding APIs cost money (Vertex AI has no free
tier) and Claude can't produce embeddings. So each text becomes a small vector
of related-word groups plus its own words, and events are ranked by cosine
similarity to the student's interests. Runs in microseconds, no network.

To swap in real embeddings later (e.g. Voyage AI), replace `vectorize`.
"""
import math
import re

# Most events `rank` looks at for one request.
MAX_CANDIDATES = 50

# Words that mean roughly the same kind of plan. A word can sit in several
# groups ("active" counts for every way of moving).
RELATED = {
    "outdoors": {"outdoors", "outdoor", "nature", "hike", "hiking", "backpacking", "trail", "walk",
                 "walking", "arboretum", "park", "sunset", "camping", "climbing", "explore", "active"},
    "running": {"run", "running", "jog", "jogging", "5k", "10k", "marathon", "track", "active"},
    "fitness": {"gym", "workout", "lift", "lifting", "fitness", "weights", "exercise", "active"},
    "cycling": {"cycling", "bike", "biking", "bicycle", "active"},
    "sports": {"sports", "sport", "soccer", "basketball", "volleyball", "tennis", "frisbee", "pickup",
               "football", "baseball", "active"},
    "yoga": {"yoga", "pilates", "stretch", "stretching", "meditation", "mindfulness"},
    "food": {"food", "eat", "eating", "dinner", "lunch", "brunch", "taco", "pizza", "market", "farmers",
             "cooking", "restaurant", "snack", "foodie"},
    "coffee": {"coffee", "cafe", "tea", "boba"},
    "drinks": {"drinks", "drink", "bar", "beer", "wine", "cocktail"},
    "music": {"music", "concert", "band", "mic", "jazz", "dj", "sing", "singing", "karaoke", "perform"},
    "movies": {"movies", "movie", "film", "cinema", "screening"},
    "art": {"art", "arts", "painting", "drawing", "museum", "gallery", "craft", "photography"},
    "study": {"study", "studying", "homework", "library", "tech", "coding", "hackathon", "programming",
              "engineering"},
    "games": {"games", "game", "board", "trivia", "gaming", "chess", "cards"},
    "social": {"social", "meet", "meetup", "party", "friends", "hangout", "club", "clubs", "fair", "mixer"},
}

# A shared group counts for more than a shared word: the point is to match
# different words for the same thing.
GROUP_WEIGHT = 1.0
WORD_WEIGHT = 0.5

STOPWORDS = {"a", "an", "and", "the", "of", "to", "in", "on", "at", "for", "with", "up", "all",
             "is", "are", "be", "or", "by", "your", "you", "my", "i", "we", "our", "this", "that",
             "it", "its", "from", "into", "after", "about", "welcome", "bring"}

_WORD = re.compile(r"[a-z0-9]+")
_GROUPS_BY_WORD = {}
for _group, _words in RELATED.items():
    for _word in _words:
        _GROUPS_BY_WORD.setdefault(_word, set()).add(_group)


def _stem(word):
    return word[:-1] if len(word) > 3 and word.endswith("s") and not word.endswith("ss") else word


def vectorize(text):
    vector = {}
    for word in _WORD.findall(text.lower()):
        if word in STOPWORDS:
            continue
        stem = _stem(word)
        vector["w:" + stem] = vector.get("w:" + stem, 0.0) + WORD_WEIGHT
        for group in _GROUPS_BY_WORD.get(word, set()) | _GROUPS_BY_WORD.get(stem, set()):
            vector["g:" + group] = vector.get("g:" + group, 0.0) + GROUP_WEIGHT
    return vector


def similarity(a, b):
    dot = sum(value * b[key] for key, value in a.items() if key in b)
    if not dot:
        return 0.0
    norm = math.sqrt(sum(v * v for v in a.values())) * math.sqrt(sum(v * v for v in b.values()))
    return dot / norm


def event_text(event):
    return " ".join([event.title, event.category, " ".join(event.tags), event.description or ""])


def rank(interests, candidates):
    """candidates: (event, distance_miles) pairs. Returns (event, score, distance_miles)
    for events with any match, best first, soonest first on ties."""
    wanted = vectorize(" ".join(interests))
    ranked = []
    for event, distance in candidates:
        score = similarity(wanted, vectorize(event_text(event)))
        if score > 0:
            ranked.append((event, round(score, 3), distance))
    ranked.sort(key=lambda item: (-item[1], item[0].start_time))
    return ranked
