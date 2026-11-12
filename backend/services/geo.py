"""Geohash and distance helpers for "events near me" on Datastore.

Datastore has no geo queries. Each event stores a geohash of its coordinates;
a nearby search finds the geohash cell around the searcher (plus its 8
neighbours) at a size at least as big as the radius, runs one prefix range
query per cell, then checks the exact distance in Python.
"""
import math

BASE32 = "0123456789bcdefghjkmnpqrstuvwxyz"
STORED_PRECISION = 9  # ~5 m cells; any shorter prefix still matches
EARTH_RADIUS_KM = 6371.0088
KM_PER_DEGREE = 111.32
KM_PER_MILE = 1.609344


def encode(latitude, longitude, precision=STORED_PRECISION):
    lat_range, lng_range = [-90.0, 90.0], [-180.0, 180.0]
    chars, bits, value, even = [], 0, 0, True
    while len(chars) < precision:
        # Bits alternate longitude, latitude, longitude, ...
        rng, coordinate = (lng_range, longitude) if even else (lat_range, latitude)
        mid = (rng[0] + rng[1]) / 2
        if coordinate >= mid:
            value = value * 2 + 1
            rng[0] = mid
        else:
            value *= 2
            rng[1] = mid
        even = not even
        bits += 1
        if bits == 5:
            chars.append(BASE32[value])
            bits, value = 0, 0
    return "".join(chars)


def cell_size_degrees(precision):
    """(height, width) of a cell in degrees."""
    total_bits = 5 * precision
    lat_bits, lng_bits = total_bits // 2, total_bits - total_bits // 2
    return 180.0 / 2 ** lat_bits, 360.0 / 2 ** lng_bits


def covering_cells(latitude, longitude, radius_km):
    """Geohash prefixes whose cells together contain every point within radius_km.

    Picks the smallest cells that are still at least radius_km tall and wide,
    so the cell around the point plus its 8 neighbours always cover the circle.
    """
    precision = 1
    for p in range(STORED_PRECISION, 0, -1):
        height, width = cell_size_degrees(p)
        width_km = width * KM_PER_DEGREE * math.cos(math.radians(latitude))
        if height * KM_PER_DEGREE >= radius_km and width_km >= radius_km:
            precision = p
            break
    height, width = cell_size_degrees(precision)
    cells = set()
    for dlat in (-height, 0.0, height):
        for dlng in (-width, 0.0, width):
            lat = max(-90.0, min(90.0, latitude + dlat))
            lng = (longitude + dlng + 180.0) % 360.0 - 180.0
            cells.add(encode(lat, lng, precision))
    return sorted(cells)


def distance_km(lat1, lng1, lat2, lng2):
    """Great-circle (haversine) distance."""
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    dphi, dlmb = phi2 - phi1, math.radians(lng2 - lng1)
    a = math.sin(dphi / 2) ** 2 + math.cos(phi1) * math.cos(phi2) * math.sin(dlmb / 2) ** 2
    return 2 * EARTH_RADIUS_KM * math.asin(math.sqrt(a))
