"""ctp-service configuration.

Mode is selected by an env var at startup (Architecture §6.1) — sidecar
mode is the only mode this milestone implements; hosted mode (auth/sync,
Postgres) is Leg 4/M6.
"""

from __future__ import annotations

import os
from dataclasses import dataclass, field
from pathlib import Path

from ctp_core.types import BBox

_BACKEND_DIR = Path(__file__).resolve().parent.parent


def _bbox_from_env() -> BBox:
    raw = os.environ.get("CTP_BBOX")
    if raw:
        west, south, east, north = (float(v) for v in raw.split(","))
        return BBox(west=west, south=south, east=east, north=north)
    # Default dev bundle: a small area around Marion, NC (PRD's own stated
    # default start / FR38 region), small enough to fetch quickly from
    # Overpass for local development.
    return BBox(west=-82.030, south=35.675, east=-82.000, north=35.700)


@dataclass
class Settings:
    mode: str = field(default_factory=lambda: os.environ.get("CTP_MODE", "sidecar"))
    cache_dir: Path = field(
        default_factory=lambda: Path(os.environ.get("CTP_CACHE_DIR", str(_BACKEND_DIR / ".cache")))
    )
    elevation_tile_path: Path = field(
        default_factory=lambda: Path(
            os.environ.get(
                "CTP_ELEVATION_TILE",
                str(_BACKEND_DIR / ".cache" / "elevation" / "nc_gedtm30.tif"),
            )
        )
    )
    bbox: BBox = field(default_factory=_bbox_from_env)
    network_type: str = field(default_factory=lambda: os.environ.get("CTP_NETWORK_TYPE", "bike"))

    @property
    def graph_cache_dir(self) -> Path:
        return self.cache_dir / "graph"
