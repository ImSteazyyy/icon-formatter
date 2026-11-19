/// Lets a progress event through at most once per [interval]. Batches emit one
/// event per icon (thousands): a rebuild per event stalls the UI thread, so
/// the callers ask [allow] first and pass [force] on the last event.
class ProgressThrottle {
  ProgressThrottle(this.interval);

  final Duration interval;
  DateTime? _last;

  bool allow(DateTime now, {bool force = false}) {
    final last = _last;
    if (!force && last != null && now.difference(last) < interval) return false;
    _last = now;
    return true;
  }

  void reset() => _last = null;
}
