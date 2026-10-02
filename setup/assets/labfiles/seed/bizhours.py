"""Business-hours arithmetic for the Relecloud service desk calendar.

The calendar is deliberately simple so that attendees can verify SLA figures by hand:
Monday to Friday, 08:00 to 18:00 UTC, ten business hours per day, no holidays.
Every SLA value in the seed data is computed with these functions, so the seeded
Opened On, SLA Due On, Elapsed and Remaining figures are arithmetically consistent.
"""
from __future__ import annotations

from datetime import datetime, timedelta, timezone

DAY_START_HOUR = 8
DAY_END_HOUR = 18
HOURS_PER_DAY = DAY_END_HOUR - DAY_START_HOUR
WORKDAYS = {0, 1, 2, 3, 4}  # Monday=0 .. Friday=4
CALENDAR_NAME = "Relecloud Standard Business Hours"
CALENDAR_DESCRIPTION = (
    "Monday to Friday, 08:00 to 18:00 UTC (10 business hours per day). No public holidays "
    "are configured for the current period. All SLA clocks for every tier and priority run "
    "in these business hours only; P1 incidents outside business hours are worked by the "
    "on-call engineer but the SLA clock does not run."
)


def _utc(dt: datetime) -> datetime:
    if dt.tzinfo is None:
        return dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc)


def is_business_time(dt: datetime) -> bool:
    dt = _utc(dt)
    if dt.weekday() not in WORKDAYS:
        return False
    start = dt.replace(hour=DAY_START_HOUR, minute=0, second=0, microsecond=0)
    end = dt.replace(hour=DAY_END_HOUR, minute=0, second=0, microsecond=0)
    return start <= dt < end


def snap_anchor(now: datetime) -> datetime:
    """Return the SLA snapshot instant used for a seed run.

    Inside business hours: `now` rounded down to the whole hour.
    Outside business hours: the end (18:00) of the most recent business day.
    The result is always a whole hour, which keeps hand verification easy.
    """
    now = _utc(now).replace(minute=0, second=0, microsecond=0)
    if is_business_time(now):
        return now
    cursor = now
    # Walk back to the most recent business-day close.
    if cursor.weekday() in WORKDAYS and cursor.hour >= DAY_END_HOUR:
        return cursor.replace(hour=DAY_END_HOUR)
    cursor = cursor.replace(hour=DAY_END_HOUR) - timedelta(days=1)
    while cursor.weekday() not in WORKDAYS:
        cursor -= timedelta(days=1)
    return cursor


def add_business_hours(start: datetime, hours: float) -> datetime:
    """Move forward `hours` business hours from `start` (start is snapped forward first)."""
    if hours < 0:
        return subtract_business_hours(start, -hours)
    cursor = _utc(start)
    remaining = timedelta(hours=hours)
    cursor = _next_business_instant(cursor)
    while remaining > timedelta(0):
        day_end = cursor.replace(hour=DAY_END_HOUR, minute=0, second=0, microsecond=0)
        available = day_end - cursor
        if remaining <= available:
            return cursor + remaining
        remaining -= available
        cursor = _next_business_instant(day_end)
    return cursor


def subtract_business_hours(end: datetime, hours: float) -> datetime:
    """Move backward `hours` business hours from `end`."""
    cursor = _utc(end)
    remaining = timedelta(hours=hours)
    cursor = _prev_business_instant(cursor)
    while remaining > timedelta(0):
        day_start = cursor.replace(hour=DAY_START_HOUR, minute=0, second=0, microsecond=0)
        available = cursor - day_start
        if remaining <= available:
            return cursor - remaining
        remaining -= available
        cursor = _prev_business_instant(day_start)
    return cursor


def business_hours_between(start: datetime, end: datetime) -> float:
    """Business hours elapsed from `start` to `end` (negative if end < start)."""
    start, end = _utc(start), _utc(end)
    if end < start:
        return -business_hours_between(end, start)
    total = timedelta(0)
    day = start.replace(hour=0, minute=0, second=0, microsecond=0)
    while day <= end:
        if day.weekday() in WORKDAYS:
            window_start = max(start, day.replace(hour=DAY_START_HOUR))
            window_end = min(end, day.replace(hour=DAY_END_HOUR))
            if window_end > window_start:
                total += window_end - window_start
        day += timedelta(days=1)
    return round(total.total_seconds() / 3600.0, 2)


def _next_business_instant(dt: datetime) -> datetime:
    """Snap forward to the next instant that is inside business hours."""
    dt = _utc(dt)
    while True:
        if dt.weekday() in WORKDAYS:
            day_start = dt.replace(hour=DAY_START_HOUR, minute=0, second=0, microsecond=0)
            day_end = dt.replace(hour=DAY_END_HOUR, minute=0, second=0, microsecond=0)
            if dt < day_start:
                return day_start
            if dt < day_end:
                return dt
        dt = (dt + timedelta(days=1)).replace(hour=DAY_START_HOUR, minute=0, second=0, microsecond=0)


def _prev_business_instant(dt: datetime) -> datetime:
    """Snap backward to the latest instant that is inside (or at the close of) business hours."""
    dt = _utc(dt)
    while True:
        if dt.weekday() in WORKDAYS:
            day_start = dt.replace(hour=DAY_START_HOUR, minute=0, second=0, microsecond=0)
            day_end = dt.replace(hour=DAY_END_HOUR, minute=0, second=0, microsecond=0)
            if dt > day_end:
                return day_end
            if dt > day_start:
                return dt
        dt = (dt - timedelta(days=1)).replace(hour=DAY_END_HOUR, minute=0, second=0, microsecond=0)


def sla_status(target_hours: float, elapsed_hours: float, resolved: bool) -> str:
    """Return the seeded SLA status label.

    Open tickets: Breached when remaining < 0, At Risk when remaining is 25 percent of the
    target or less, otherwise On Track. Resolved or closed tickets: Met or Breached.
    """
    remaining = round(target_hours - elapsed_hours, 2)
    if resolved:
        return "Met" if remaining >= 0 else "Breached"
    if remaining < 0:
        return "Breached"
    if remaining <= 0.25 * target_hours:
        return "At Risk"
    return "On Track"
