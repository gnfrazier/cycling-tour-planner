import pytest

from ctp_core.elevation import GedtmElevationProvider
from ctp_core.types import Coord

from .conftest import ELEVATION_TILE


def test_missing_tile_file_falls_back_to_zero_without_raising(tmp_path):
    provider = GedtmElevationProvider([tmp_path / "does-not-exist.tif"])
    assert provider.elevation_at(Coord(lat=35.68, lon=-82.01)) == 0.0


def test_coordinate_outside_every_tile_falls_back_to_zero():
    tiles = [ELEVATION_TILE] if ELEVATION_TILE.exists() else []
    provider = GedtmElevationProvider(tiles)
    # (0, 0) is in the Gulf of Guinea — nowhere near the NC raster's bounds.
    assert provider.elevation_at(Coord(lat=0.0, lon=0.0)) == 0.0


@pytest.mark.skipif(not ELEVATION_TILE.exists(), reason="local GEDTM30 raster not extracted (see backend README)")
def test_real_raster_returns_a_plausible_elevation_for_marion_nc():
    provider = GedtmElevationProvider([ELEVATION_TILE])
    elevation = provider.elevation_at(Coord(lat=35.6841, lon=-82.0091))
    # Marion, NC sits in the NC foothills — sanity-bound, not a precise fixture.
    assert 200.0 < elevation < 1500.0
