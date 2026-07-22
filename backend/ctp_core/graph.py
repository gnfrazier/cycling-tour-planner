"""OSMnx graph construction and caching (ctp-core §5.2 `graph/`)."""

from __future__ import annotations

from pathlib import Path

import osmnx as ox

from .types import BBox, Graph


def build_graph(bbox: BBox, network_type: str, cache_dir: Path) -> Graph:
    """Fetch (or load from OSMnx's own on-disk cache) a simplified street
    graph for bbox.

    Uses OSMnx's built-in caching mechanism (`use_cache` + a cache folder)
    rather than a separately managed `.osm.pbf` extract pipeline — one tool
    for both fetch and cache (PRD §5.1).
    """
    cache_dir = Path(cache_dir)
    cache_dir.mkdir(parents=True, exist_ok=True)
    ox.settings.use_cache = True
    ox.settings.cache_folder = str(cache_dir)
    ox.settings.log_console = False

    graph = ox.graph_from_bbox(bbox.as_tuple(), network_type=network_type)
    if not graph.graph.get("simplified"):
        graph = ox.simplify_graph(graph)
    return graph
