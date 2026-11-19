/// Day-of-month numbers the calendar apps will show for the next [count] days,
/// starting today. Plain date arithmetic: the installed pack's status only
/// reports whether calendars exist and whether today is applied, not per-day data.
List<int> calendarPreviewDays({DateTime? today, int count = 7}) {
  final start = today ?? DateTime.now();
  // DateTime normalizes days past the month end, so no month table is needed.
  return [for (var n = 0; n < count; n++) DateTime(start.year, start.month, start.day + n).day];
}
