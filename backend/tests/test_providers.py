import logging

from ctp_core.providers import OsmArtHistoryProvider
from ctp_core.types import BBox

BBOX = BBox(west=-82.03, south=35.675, east=-82.0, north=35.7)


def test_poi_lookup_failure_is_logged_not_silently_swallowed(monkeypatch, caplog):
    """A genuine Overpass outage/timeout must leave a diagnostic trail —
    previously this was indistinguishable from "no POIs here" (an empty
    dict returned either way), with nothing logged for the failure case."""
    import ctp_core.providers as providers_module

    def _boom(*args, **kwargs):
        raise RuntimeError("simulated Overpass outage")

    monkeypatch.setattr(providers_module.ox, "features_from_bbox", _boom)

    with caplog.at_level(logging.WARNING):
        result = OsmArtHistoryProvider().node_scores(graph=None, bbox=BBOX)

    assert result == {}
    assert any("POI lookup failed" in record.message for record in caplog.records)
