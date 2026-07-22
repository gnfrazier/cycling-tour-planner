"""Pluggable data-provider interfaces (ctp-core §5.2 `providers/`).

Interfaces only, per Architecture §10.2 — a plugin implements the same
protocol a built-in lookup does. FR5 (art/history) and FR14 (lodging) are
implemented here against these protocols now, before any plugin needs them,
so the extension point is proven rather than assumed (Roadmap Leg 1).
"""

from __future__ import annotations

from typing import Protocol

import osmnx as ox

from .types import BBox, Graph


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
    """FR14 — lodging/campground data along a route (M5). Not wired into
    routing at M1; exists to prove the provider extension point is real
    before a future plugin needs the same shape (Roadmap Leg 1)."""

    TAGS = {"tourism": ["hotel", "motel", "guest_house", "camp_site"]}

    def node_scores(self, graph: Graph, bbox: BBox) -> dict[int, float]:
        return _snap_pois_to_nodes(graph, bbox, self.TAGS)
