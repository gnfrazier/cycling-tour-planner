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
    # Default shipped region: ~80km square around Marion, NC (PRD's own
    # stated default start / FR38 region) — covers real western-NC riding
    # terrain (Blue Ridge Parkway, Black Mountain, Lake James, Morganton),
    # not just enough road network to prove routing works. Comfortably
    # within the bundled GEDTM30 elevation tile's coverage. Tests and CI
    # pin CTP_BBOX to a much smaller box so they stay fast and cached —
    # see tests/conftest.py's TEST_BBOX and desktop-build.yml.
    return BBox(west=-82.450, south=35.320, east=-81.550, north=36.050)


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
