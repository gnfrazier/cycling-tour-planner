import xml.etree.ElementTree as ET

import gpxpy
import pytest
from fit_tool.fit_file import FitFile
from fit_tool.profile.messages.record_message import RecordMessage

from ctp_core.export import export_route
from ctp_core.types import Coord, ExportFormat, Route, RouteShape, Theme

SAMPLE_ROUTE = Route(
    id="test-route",
    theme=Theme.FLATTEST,
    shape=RouteShape.LOOP,
    coords=[
        Coord(lat=35.68, lon=-82.01),
        Coord(lat=35.685, lon=-82.015),
        Coord(lat=35.68, lon=-82.01),
    ],
    distance_m=1200.0,
    elevation_gain_m=15.0,
)


def test_gpx_round_trips_with_expected_points():
    data = export_route(SAMPLE_ROUTE, ExportFormat.GPX)
    parsed = gpxpy.parse(data.decode("utf-8"))
    points = parsed.tracks[0].segments[0].points

    assert len(points) == len(SAMPLE_ROUTE.coords)
    assert points[0].latitude == SAMPLE_ROUTE.coords[0].lat
    assert points[0].longitude == SAMPLE_ROUTE.coords[0].lon


def test_tcx_is_well_formed_with_expected_trackpoints():
    data = export_route(SAMPLE_ROUTE, ExportFormat.TCX)
    root = ET.fromstring(data)  # raises if malformed
    ns = {"tcx": "http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2"}

    trackpoints = root.findall(".//tcx:Trackpoint", ns)
    assert len(trackpoints) == len(SAMPLE_ROUTE.coords)

    distance = root.find(".//tcx:DistanceMeters", ns)
    assert float(distance.text) == SAMPLE_ROUTE.distance_m


def test_fit_round_trips_with_expected_record_count():
    data = export_route(SAMPLE_ROUTE, ExportFormat.FIT)
    parsed = FitFile.from_bytes(bytearray(data))

    records = [r.message for r in parsed.records if isinstance(r.message, RecordMessage)]
    assert len(records) == len(SAMPLE_ROUTE.coords)
    assert records[0].position_lat == pytest.approx(SAMPLE_ROUTE.coords[0].lat, abs=1e-4)
