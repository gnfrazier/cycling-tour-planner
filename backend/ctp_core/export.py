"""Route export — GPX, TCX, FIT (ctp-core §5.2 `export/`)."""

from __future__ import annotations

import datetime
from xml.sax.saxutils import escape

import gpxpy
import gpxpy.gpx
from fit_tool.fit_file_builder import FitFileBuilder
from fit_tool.profile.messages.course_message import CourseMessage
from fit_tool.profile.messages.file_id_message import FileIdMessage
from fit_tool.profile.messages.record_message import RecordMessage
from fit_tool.profile.profile_type import FileType, Sport

from .types import ExportFormat, Route

_TCX_NAMESPACE = "http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2"


def export_route(route: Route, fmt: ExportFormat) -> bytes:
    if fmt is ExportFormat.GPX:
        return _to_gpx(route)
    if fmt is ExportFormat.TCX:
        return _to_tcx(route)
    if fmt is ExportFormat.FIT:
        return _to_fit(route)
    raise ValueError(f"unknown export format: {fmt}")


def _to_gpx(route: Route) -> bytes:
    gpx = gpxpy.gpx.GPX()
    gpx.name = f"{route.theme.value} {route.shape.value}"

    track = gpxpy.gpx.GPXTrack(name=gpx.name)
    gpx.tracks.append(track)
    segment = gpxpy.gpx.GPXTrackSegment()
    track.segments.append(segment)
    for coord in route.coords:
        segment.points.append(gpxpy.gpx.GPXTrackPoint(latitude=coord.lat, longitude=coord.lon))

    return gpx.to_xml().encode("utf-8")


def _to_tcx(route: Route) -> bytes:
    name = escape(f"{route.theme.value} {route.shape.value}")
    trackpoints = "\n".join(
        f"        <Trackpoint>\n"
        f"          <Position>\n"
        f"            <LatitudeDegrees>{coord.lat}</LatitudeDegrees>\n"
        f"            <LongitudeDegrees>{coord.lon}</LongitudeDegrees>\n"
        f"          </Position>\n"
        f"        </Trackpoint>"
        for coord in route.coords
    )
    xml = f"""<?xml version="1.0" encoding="UTF-8"?>
<TrainingCenterDatabase xmlns="{_TCX_NAMESPACE}">
  <Courses>
    <Course>
      <Name>{name}</Name>
      <Lap>
        <TotalTimeSeconds>0</TotalTimeSeconds>
        <DistanceMeters>{route.distance_m}</DistanceMeters>
      </Lap>
      <Track>
{trackpoints}
      </Track>
    </Course>
  </Courses>
</TrainingCenterDatabase>
"""
    return xml.encode("utf-8")


def _to_fit(route: Route) -> bytes:
    builder = FitFileBuilder(auto_define=True, min_string_size=50)

    file_id = FileIdMessage()
    file_id.type = FileType.COURSE
    file_id.time_created = round(datetime.datetime.now(tz=datetime.timezone.utc).timestamp() * 1000)
    builder.add(file_id)

    course = CourseMessage()
    course.course_name = f"{route.theme.value} {route.shape.value}"[:50]
    course.sport = Sport.CYCLING
    builder.add(course)

    start_ms = round(datetime.datetime.now(tz=datetime.timezone.utc).timestamp() * 1000)
    cumulative_m = 0.0
    for i, coord in enumerate(route.coords):
        record = RecordMessage()
        record.timestamp = start_ms + i * 1000
        record.position_lat = coord.lat
        record.position_long = coord.lon
        record.distance = cumulative_m
        builder.add(record)
        # Distance-per-point isn't tracked on Route (only the aggregate is),
        # so spread it evenly — good enough for a course file's monotonic
        # distance field, not a claim of per-point accuracy.
        if len(route.coords) > 1:
            cumulative_m += route.distance_m / (len(route.coords) - 1)

    return builder.build().to_bytes()
