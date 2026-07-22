"""Elevation sourcing — GEDTM30 via local GeoTIFF reads (ctp-core §5.2
`elevation/`).

Implements the elevation interface seam (PRD §5.2, Architecture §9.1):
callers go through one interface from day one. What varies between MVP
(direct local tile reads, this module) and post-MVP (shared Render cache) is
solely where the interface resolves data from — never the caller's contract.
"""

from __future__ import annotations

import logging
import warnings
from pathlib import Path
from typing import Protocol

import rasterio

from .types import Coord, Graph

logger = logging.getLogger(__name__)


class ElevationProvider(Protocol):
    """One interface for elevation lookups, regardless of where the data
    actually lives (PRD §5.2's two-phase model)."""

    def elevation_at(self, coord: Coord) -> float:
        """Elevation in meters. Never raises — a data void or missing tile
        resolves to a flat-earth 0.0 fallback (Architecture §5.4)."""
        ...


class GedtmElevationProvider:
    """MVP resolution of ElevationProvider: local GEDTM30 GeoTIFF tiles read
    directly via rasterio. No secondary/fallback elevation service — GEDTM30
    is already a single best-available source (PRD §5.2)."""

    def __init__(self, tile_paths: list[Path]):
        self._tile_paths = [Path(p) for p in tile_paths]
        self._datasets: list | None = None
        self._warned_missing: set[Path] = set()

    def _open_datasets(self):
        if self._datasets is None:
            opened = []
            for path in self._tile_paths:
                if not path.exists():
                    if path not in self._warned_missing:
                        logger.warning("elevation tile missing on disk: %s", path)
                        self._warned_missing.add(path)
                    continue
                opened.append(rasterio.open(path))
            self._datasets = opened
        return self._datasets

    def elevation_at(self, coord: Coord) -> float:
        for ds in self._open_datasets():
            bounds = ds.bounds
            if not (bounds.left <= coord.lon <= bounds.right and bounds.bottom <= coord.lat <= bounds.top):
                continue
            try:
                row, col = ds.index(coord.lon, coord.lat)
                if row < 0 or col < 0 or row >= ds.height or col >= ds.width:
                    continue
                with warnings.catch_warnings():
                    # rasterio's single-pixel windowed read trips a NumPy 2.5
                    # in-place-reshape deprecation internally; harmless here
                    # (we only ever read a 1x1 window), not worth a full-band
                    # read (~1.6GB for the NC raster) to silence properly.
                    warnings.simplefilter("ignore", DeprecationWarning)
                    value = ds.read(1, window=((row, row + 1), (col, col + 1)))[0, 0]
                if ds.nodata is not None and value == ds.nodata:
                    return 0.0
                return float(value)
            except Exception:
                logger.warning("elevation read failed for %s", coord, exc_info=True)
                return 0.0
        # No tile covers this coordinate — void fallback, never stalls/errors.
        return 0.0


def enrich_elevation(graph: Graph, provider: ElevationProvider) -> Graph:
    """Annotate every node with elevation and every edge with its positive
    elevation gain (Architecture §5.1 contract shape)."""
    for _node_id, data in graph.nodes(data=True):
        data["elevation"] = provider.elevation_at(Coord(lat=data["y"], lon=data["x"]))

    for u, v, _key, data in graph.edges(keys=True, data=True):
        gain = graph.nodes[v]["elevation"] - graph.nodes[u]["elevation"]
        data["elev_gain"] = max(0.0, gain)

    return graph
