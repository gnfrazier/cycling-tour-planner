"""Historical weather — seasonal norms via Open-Meteo (ctp-core §5.2
`weather/`, FR15, ROADMAP Leg 3 / PRD M5).

Same seam shape as `elevation.py`'s ElevationProvider: one interface,
resolved via Open-Meteo's archive (observed) API now, swappable later
without `ctp_core/trips.py`'s caller contract changing. This is FR15's
**Historical Weather** half only — "typical for this date," averaged over
several past years. The 10-day/hourly Weather Forecast is a separate
feature shipping later, at M7, across all clients simultaneously.
"""

from __future__ import annotations

import datetime
import logging
import statistics
from typing import Protocol

import httpx

from .types import Coord, WeatherSummary

logger = logging.getLogger(__name__)

_ARCHIVE_URL = "https://archive-api.open-meteo.com/v1/archive"
_AIR_QUALITY_URL = "https://air-quality-api.open-meteo.com/v1/air-quality"
_YEARS_BACK = 10
_TIMEOUT = httpx.Timeout(10.0, connect=5.0)

# Coarse quarters of the day used to derive a "typical timing" for
# precipitation from hourly archive data -- Open-Meteo's archive is
# observed/hourly, not itself a "time it usually rains" statistic.
_TIME_BUCKETS: dict[str, range] = {
    "overnight": range(0, 6),
    "morning": range(6, 12),
    "afternoon": range(12, 18),
    "evening": range(18, 24),
}


class WeatherProvider(Protocol):
    """One interface for seasonal-norms weather lookups (PRD §5.2's
    two-phase model, mirrored from `ElevationProvider`)."""

    def seasonal_norms_at(self, coord: Coord, month: int, day: int) -> WeatherSummary:
        """Never raises — an upstream failure resolves to an all-empty
        WeatherSummary, the same void-fallback posture as elevation's 0.0m
        fallback (never a stall or error)."""
        ...


def _empty_summary(month: int, day: int) -> WeatherSummary:
    return WeatherSummary(
        month=month,
        day=day,
        temp_min_c=0.0,
        temp_max_c=0.0,
        apparent_temp_c=0.0,
        wind_speed_kph=0.0,
        wind_direction_deg=0.0,
        precip_probability_pct=0.0,
        precip_timing=None,
        years_averaged=0,
        pm2_5=None,
        pm10=None,
        o3=None,
        no2=None,
        uv_index=None,
        pollen=None,
    )


def _first(values: list | None) -> float | None:
    if not values:
        return None
    return values[0]


def _mean(values) -> float | None:
    vals = [v for v in values if v is not None]
    return statistics.mean(vals) if vals else None


def _bucket_for_hour(hour: int) -> str:
    for name, hours in _TIME_BUCKETS.items():
        if hour in hours:
            return name
    return "overnight"


class OpenMeteoHistoricalWeatherProvider:
    """Averages Open-Meteo's archive (observed) API over the same calendar
    day across the last `years_back` years for a seasonal-norms estimate."""

    def __init__(self, http_client: httpx.Client | None = None, years_back: int = _YEARS_BACK):
        self._http = http_client or httpx.Client(timeout=_TIMEOUT)
        self._years_back = years_back

    def seasonal_norms_at(self, coord: Coord, month: int, day: int) -> WeatherSummary:
        try:
            return self._seasonal_norms_at(coord, month, day)
        except Exception:
            logger.warning("historical weather lookup failed for %s %d/%d", coord, month, day, exc_info=True)
            return _empty_summary(month, day)

    def _sample_years(self) -> range:
        this_year = datetime.date.today().year
        return range(this_year - self._years_back, this_year)

    def _seasonal_norms_at(self, coord: Coord, month: int, day: int) -> WeatherSummary:
        daily_samples: list[dict[str, float | None]] = []
        hourly_precip_by_bucket = {name: 0.0 for name in _TIME_BUCKETS}
        rainy_years = 0

        for year in self._sample_years():
            try:
                sample_date = datetime.date(year, month, day)
            except ValueError:
                continue  # e.g. Feb 29 in a non-leap year -- skip, don't fabricate

            resp = self._http.get(
                _ARCHIVE_URL,
                params={
                    "latitude": coord.lat,
                    "longitude": coord.lon,
                    "start_date": sample_date.isoformat(),
                    "end_date": sample_date.isoformat(),
                    "daily": ",".join(
                        [
                            "temperature_2m_max",
                            "temperature_2m_min",
                            "apparent_temperature_max",
                            "apparent_temperature_min",
                            "precipitation_sum",
                            "windspeed_10m_max",
                            "winddirection_10m_dominant",
                        ]
                    ),
                    "hourly": "precipitation",
                    "timezone": "auto",
                },
            )
            if resp.status_code != 200:
                continue
            body = resp.json()
            daily = body.get("daily") or {}
            if not daily.get("time"):
                continue

            precip_mm = _first(daily.get("precipitation_sum")) or 0.0
            if precip_mm > 0:
                rainy_years += 1
            daily_samples.append(
                {
                    "temp_max": _first(daily.get("temperature_2m_max")),
                    "temp_min": _first(daily.get("temperature_2m_min")),
                    "apparent_max": _first(daily.get("apparent_temperature_max")),
                    "apparent_min": _first(daily.get("apparent_temperature_min")),
                    "wind_speed": _first(daily.get("windspeed_10m_max")),
                    "wind_dir": _first(daily.get("winddirection_10m_dominant")),
                }
            )

            for hour_idx, mm in enumerate(body.get("hourly", {}).get("precipitation") or []):
                if mm:
                    hourly_precip_by_bucket[_bucket_for_hour(hour_idx % 24)] += mm

        if not daily_samples:
            return _empty_summary(month, day)

        years_sampled = len(daily_samples)
        precip_timing = (
            max(hourly_precip_by_bucket, key=hourly_precip_by_bucket.get)
            if any(hourly_precip_by_bucket.values())
            else None
        )
        air_quality = self._air_quality_at(coord, month, day)

        return WeatherSummary(
            month=month,
            day=day,
            temp_min_c=_mean(s["temp_min"] for s in daily_samples) or 0.0,
            temp_max_c=_mean(s["temp_max"] for s in daily_samples) or 0.0,
            apparent_temp_c=_mean(
                [s["apparent_max"] for s in daily_samples] + [s["apparent_min"] for s in daily_samples]
            )
            or 0.0,
            wind_speed_kph=_mean(s["wind_speed"] for s in daily_samples) or 0.0,
            wind_direction_deg=_mean(s["wind_dir"] for s in daily_samples) or 0.0,
            precip_probability_pct=100.0 * rainy_years / years_sampled,
            precip_timing=precip_timing,
            years_averaged=years_sampled,
            **air_quality,
        )

    def _air_quality_at(self, coord: Coord, month: int, day: int) -> dict:
        # Air-quality/pollen history is much shorter (and pollen is
        # Europe-only) than weather's -- average whatever's available and
        # degrade any variable with no data to None rather than failing the
        # whole lookup (same graceful-degradation posture as elevation
        # voids: never stall or error over a missing signal).
        fields = {
            "pm2_5": "pm2_5",
            "pm10": "pm10",
            "o3": "ozone",
            "no2": "nitrogen_dioxide",
            "uv_index": "uv_index",
        }
        pollen_fields = {
            "grass": "grass_pollen",
            "birch": "birch_pollen",
            "ragweed": "ragweed_pollen",
        }
        samples: dict[str, list[float]] = {name: [] for name in fields}
        pollen_samples: dict[str, list[float]] = {name: [] for name in pollen_fields}

        for year in self._sample_years():
            try:
                sample_date = datetime.date(year, month, day)
            except ValueError:
                continue
            try:
                resp = self._http.get(
                    _AIR_QUALITY_URL,
                    params={
                        "latitude": coord.lat,
                        "longitude": coord.lon,
                        "start_date": sample_date.isoformat(),
                        "end_date": sample_date.isoformat(),
                        "hourly": ",".join([*fields.values(), *pollen_fields.values()]),
                    },
                )
            except httpx.HTTPError:
                continue
            if resp.status_code != 200:
                continue
            hourly = resp.json().get("hourly") or {}
            for name, key in fields.items():
                values = [v for v in (hourly.get(key) or []) if v is not None]
                if values:
                    samples[name].append(statistics.mean(values))
            for name, key in pollen_fields.items():
                values = [v for v in (hourly.get(key) or []) if v is not None]
                if values:
                    pollen_samples[name].append(statistics.mean(values))

        result = {name: (statistics.mean(vals) if vals else None) for name, vals in samples.items()}
        pollen_result = {name: statistics.mean(vals) for name, vals in pollen_samples.items() if vals}
        result["pollen"] = pollen_result or None
        return result
