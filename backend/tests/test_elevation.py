import numpy as np
import pytest
import rasterio
from rasterio.transform import from_origin

from ctp_core.elevation import GedtmElevationProvider
from ctp_core.types import Coord

from .conftest import ELEVATION_TILE


def test_missing_tile_file_falls_back_to_zero_without_raising(tmp_path):
    provider = GedtmElevationProvider([tmp_path / "does-not-exist.tif"])
    assert provider.elevation_at(Coord(lat=35.68, lon=-82.01)) == 0.0


def test_nan_nodata_sentinel_falls_back_to_zero(tmp_path):
    """`value == ds.nodata` alone misses a NaN nodata sentinel (NaN never
    equals anything under IEEE754) — a real scenario for float32/64
    rasters, which would otherwise leak a raw NaN elevation instead of the
    documented 0.0 flat-earth fallback."""
    path = tmp_path / "nan_nodata.tif"
    transform = from_origin(-82.02, 35.70, 0.01, 0.01)  # west, north, pixel size x, y (degrees)
    data = np.full((1, 10, 10), np.nan, dtype="float32")
    with rasterio.open(
        path,
        "w",
        driver="GTiff",
        height=10,
        width=10,
        count=1,
        dtype="float32",
        crs="EPSG:4326",
        transform=transform,
        nodata=np.nan,
    ) as dst:
        dst.write(data)

    provider = GedtmElevationProvider([path])
    # Comfortably inside the raster's lon/lat bounds (west..west+0.1, north-0.1..north).
    assert provider.elevation_at(Coord(lat=35.65, lon=-81.97)) == 0.0


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
