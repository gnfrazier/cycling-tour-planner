"""Shared fixtures. Tests fetch a real (small) OSMnx graph over the network
for the Marion, NC dev bbox — the same default `ctp_service.config.Settings`
uses — so OSMnx's own on-disk cache keeps repeat runs fast."""

from __future__ import annotations

from pathlib import Path

import pytest

from ctp_core.elevation import GedtmElevationProvider, enrich_elevation
from ctp_core.graph import build_graph
from ctp_core.types import BBox

BACKEND_DIR = Path(__file__).parent.parent
CACHE_DIR = BACKEND_DIR / ".cache"
GRAPH_CACHE_DIR = CACHE_DIR / "graph"
ELEVATION_TILE = CACHE_DIR / "elevation" / "nc_gedtm30.tif"
TEST_BBOX = BBox(west=-82.030, south=35.675, east=-82.000, north=35.700)


@pytest.fixture(scope="session")
def bbox() -> BBox:
    return TEST_BBOX


@pytest.fixture(scope="session")
def base_graph(bbox: BBox):
    graph = build_graph(bbox, "bike", GRAPH_CACHE_DIR)
    if ELEVATION_TILE.exists():
        graph = enrich_elevation(graph, GedtmElevationProvider([ELEVATION_TILE]))
    else:
        for _node_id, data in graph.nodes(data=True):
            data["elevation"] = 0.0
        for _u, _v, _key, data in graph.edges(keys=True, data=True):
            data["elev_gain"] = 0.0
    return graph
