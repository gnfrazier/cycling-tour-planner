"""FR15 -- the one place mocking is warranted (every other test in this
suite hits real OSMnx/network); hitting the real Open-Meteo API in CI is
neither desired nor reliable."""

from __future__ import annotations

import httpx
import pytest

from ctp_core.types import Coord
from ctp_core.weather import OpenMeteoHistoricalWeatherProvider

COORD = Coord(lat=35.6841, lon=-82.0091)


class _StubTransport(httpx.BaseTransport):
    """Routes requests to a caller-supplied handler instead of the network."""

    def __init__(self, handler):
        self._handler = handler

    def handle_request(self, request: httpx.Request) -> httpx.Response:
        return self._handler(request)


def _provider(handler, years_back: int = 3) -> OpenMeteoHistoricalWeatherProvider:
    client = httpx.Client(transport=_StubTransport(handler))
    return OpenMeteoHistoricalWeatherProvider(http_client=client, years_back=years_back)


def _archive_body(temp_max=20.0, temp_min=10.0, precip=0.0, wind_speed=5.0, wind_dir=180.0, hourly_precip=None):
    return {
        "daily": {
            "time": ["2020-06-01"],
            "temperature_2m_max": [temp_max],
            "temperature_2m_min": [temp_min],
            "apparent_temperature_max": [temp_max - 1],
            "apparent_temperature_min": [temp_min - 1],
            "precipitation_sum": [precip],
            "windspeed_10m_max": [wind_speed],
            "winddirection_10m_dominant": [wind_dir],
        },
        "hourly": {"precipitation": hourly_precip or [0.0] * 24},
    }


def _air_quality_body(**hourly_overrides):
    hourly = {
        "pm2_5": [5.0] * 24,
        "pm10": [8.0] * 24,
        "ozone": [30.0] * 24,
        "nitrogen_dioxide": [12.0] * 24,
        "uv_index": [3.0] * 24,
    }
    hourly.update(hourly_overrides)
    return {"hourly": hourly}


def test_seasonal_norms_averages_across_sampled_years():
    def handler(request: httpx.Request) -> httpx.Response:
        if "archive-api" in str(request.url):
            return httpx.Response(200, json=_archive_body(temp_max=25.0, temp_min=15.0))
        return httpx.Response(200, json=_air_quality_body())

    provider = _provider(handler)
    summary = provider.seasonal_norms_at(COORD, month=6, day=1)

    assert summary.month == 6
    assert summary.day == 1
    assert summary.temp_max_c == pytest.approx(25.0)
    assert summary.temp_min_c == pytest.approx(15.0)
    assert summary.years_averaged == 3
    assert summary.pm2_5 == pytest.approx(5.0)


def test_precip_probability_reflects_fraction_of_rainy_sampled_years():
    call_count = {"n": 0}

    def handler(request: httpx.Request) -> httpx.Response:
        if "archive-api" not in str(request.url):
            return httpx.Response(200, json=_air_quality_body())
        call_count["n"] += 1
        # every other sampled year was rainy
        precip = 5.0 if call_count["n"] % 2 == 0 else 0.0
        return httpx.Response(200, json=_archive_body(precip=precip))

    provider = _provider(handler, years_back=4)
    summary = provider.seasonal_norms_at(COORD, month=6, day=1)

    assert summary.precip_probability_pct == pytest.approx(50.0)


def test_precip_timing_picks_the_bucket_with_the_most_rain():
    def handler(request: httpx.Request) -> httpx.Response:
        if "archive-api" not in str(request.url):
            return httpx.Response(200, json=_air_quality_body())
        hourly = [0.0] * 24
        hourly[14] = 10.0  # 2pm -- afternoon bucket
        return httpx.Response(200, json=_archive_body(precip=10.0, hourly_precip=hourly))

    provider = _provider(handler)
    summary = provider.seasonal_norms_at(COORD, month=6, day=1)

    assert summary.precip_timing == "afternoon"


def test_precip_timing_is_none_when_no_sampled_year_had_rain():
    def handler(request: httpx.Request) -> httpx.Response:
        if "archive-api" not in str(request.url):
            return httpx.Response(200, json=_air_quality_body())
        return httpx.Response(200, json=_archive_body(precip=0.0))

    provider = _provider(handler)
    summary = provider.seasonal_norms_at(COORD, month=6, day=1)

    assert summary.precip_timing is None


def test_pollen_is_none_outside_europe_when_absent_from_response():
    def handler(request: httpx.Request) -> httpx.Response:
        if "archive-api" in str(request.url):
            return httpx.Response(200, json=_archive_body())
        # air-quality response with no pollen fields at all (e.g. NC, US)
        return httpx.Response(200, json=_air_quality_body())

    provider = _provider(handler)
    summary = provider.seasonal_norms_at(COORD, month=6, day=1)

    assert summary.pollen is None


def test_pollen_is_populated_when_present_in_response():
    def handler(request: httpx.Request) -> httpx.Response:
        if "archive-api" in str(request.url):
            return httpx.Response(200, json=_archive_body())
        return httpx.Response(200, json=_air_quality_body(grass_pollen=[42.0] * 24))

    provider = _provider(handler)
    summary = provider.seasonal_norms_at(COORD, month=6, day=1)

    assert summary.pollen == {"grass": pytest.approx(42.0)}


def test_upstream_failure_degrades_to_an_empty_summary_never_raises():
    def handler(request: httpx.Request) -> httpx.Response:
        raise httpx.ConnectError("simulated network failure", request=request)

    provider = _provider(handler)
    summary = provider.seasonal_norms_at(COORD, month=6, day=1)

    assert summary.years_averaged == 0
    assert summary.temp_max_c == 0.0
    assert summary.pollen is None


def test_non_200_upstream_response_is_skipped_not_raised():
    def handler(request: httpx.Request) -> httpx.Response:
        if "archive-api" in str(request.url):
            return httpx.Response(500)
        return httpx.Response(200, json=_air_quality_body())

    provider = _provider(handler)
    summary = provider.seasonal_norms_at(COORD, month=6, day=1)

    assert summary.years_averaged == 0
