"""Pluggable data-provider interfaces (ctp-core §5.2 `providers/`).

Interfaces only, per Architecture §10.2 — a plugin implements the same
protocol a built-in lookup does. FR5 (art/history) and FR14 (lodging) are
implemented here against these protocols now, before any plugin needs them,
so the extension point is proven rather than assumed (Roadmap Leg 1).
"""

from __future__ import annotations

from typing import Protocol

import osmnx as ox

from .types import BBox, Coord, Graph, LodgingOption


class NodeDataProvider(Protocol):
    """Produces a per-node score keyed by graph node id."""

    def node_scores(self, graph: Graph, bbox: BBox) -> dict[int, float]: ...


def _snap_pois_to_nodes(graph: Graph, bbox: BBox, tags: dict) -> dict[int, float]:
    try:
        pois = ox.features_from_bbox(bbox.as_tuple(), tags=tags)
    except Exception:
        return {}
    if pois.empty:
        return {}

    # representative_point() (not centroid) — correct for a geographic CRS
    # without needing to project first, and always lies within the geometry.
    points = pois.geometry.representative_point()
    nearest = ox.distance.nearest_nodes(graph, points.x.tolist(), points.y.tolist())

    scores: dict[int, float] = {}
    for node_id in nearest:
        scores[node_id] = scores.get(node_id, 0.0) + 1.0
    return scores


class OsmArtHistoryProvider:
    """FR5 — most-art/history theme. Scores nodes near art/historic POIs by
    snapping OSM POI tags to the nearest graph node."""

    TAGS = {"tourism": "artwork", "historic": True}

    def node_scores(self, graph: Graph, bbox: BBox) -> dict[int, float]:
        return _snap_pois_to_nodes(graph, bbox, self.TAGS)


class OsmLodgingProvider:
    """FR14 — lodging/campground data along a route (M5). `node_scores` was
    built at M1 to prove the provider extension point before a future plugin
    needed the same shape (Roadmap Leg 1); `options_near` is M5's real use —
    surfacing actual named options to the rider, not just biasing a solve."""

    TAGS = {"tourism": ["hotel", "motel", "guest_house", "camp_site"]}

    def node_scores(self, graph: Graph, bbox: BBox) -> dict[int, float]:
        return _snap_pois_to_nodes(graph, bbox, self.TAGS)

    def options_near(self, coord: Coord, radius_m: float) -> list[LodgingOption]:
        """Lodging/campground options within radius_m of coord (typically a
        day's end point), nearest first. Never raises — an upstream/query
        failure or an empty result both resolve to an empty list, same
        void-fallback posture as `elevation.py`'s 0.0m fallback."""
        try:
            pois = ox.features_from_point((coord.lat, coord.lon), tags=self.TAGS, dist=radius_m)
        except Exception:
            return []
        if pois.empty:
            return []

        options = []
        for _idx, row in pois.iterrows():
            point = row.geometry.representative_point()
            kind = next((row.get(key) for key in ("tourism",) if row.get(key)), "lodging")
            if isinstance(kind, list):
                kind = kind[0] if kind else "lodging"
            distance_m = ox.distance.great_circle(coord.lat, coord.lon, point.y, point.x)
            options.append(
                LodgingOption(
                    name=str(row.get("name") or "Unnamed"),
                    kind=str(kind),
                    coord=Coord(lat=point.y, lon=point.x),
                    distance_from_day_end_m=float(distance_m),
                )
            )
        options.sort(key=lambda opt: opt.distance_from_day_end_m)
        return options
