"""Instagram handles for events: "@davisclimbing", "davisclimbing" or an instagram.com link.

Stored and returned as the bare handle ("davisclimbing"); the app builds the links.
Same rules as the iOS app's InstagramHandle (ios/Partner/Models/Models.swift).
"""
import re

# Instagram usernames: 1-30 letters, digits, periods and underscores; no leading,
# trailing or doubled period.
_HANDLE = re.compile(r"^(?!\.)(?!.*\.\.)(?!.*\.$)[A-Za-z0-9._]{1,30}$")
_LINK = re.compile(r"^(?:https?://)?(?:www\.|m\.)?(?:instagram\.com|instagr\.am)/([^/?#]+)/?(?:[?#].*)?$", re.I)
# Paths on instagram.com that aren't profiles.
_NOT_PROFILES = {"p", "reel", "reels", "explore", "stories", "accounts", "tv", "direct"}


def normalize(value):
    """The bare, lowercase handle, or None if `value` isn't a handle or profile link.

    Empty input is also None; callers decide whether that's allowed.
    """
    text = (value or "").strip()
    if not text:
        return None
    link = _LINK.match(text)
    if link:
        text = link.group(1)
        if text.lower() in _NOT_PROFILES:
            return None
    elif "/" in text or " " in text:
        return None
    text = text.removeprefix("@")
    return text.lower() if _HANDLE.match(text) else None
