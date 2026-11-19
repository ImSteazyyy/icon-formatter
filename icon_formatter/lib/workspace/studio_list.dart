import 'workspace_controller.dart';

/// Order of the Studio list. [added] is the order of import.
enum StudioSort { added, name, state }

/// Which icons the Studio list shows (display only).
enum StudioFilter { all, modified, errors, excluded }

bool studioMatchesFilter(WorkItem i, StudioFilter f) => switch (f) {
      StudioFilter.all => true,
      StudioFilter.modified => i.hasOverride,
      StudioFilter.errors => i.result?.ok == false,
      StudioFilter.excluded => i.excluded,
    };

bool _matchesQuery(WorkItem i, String q) => i.name.toLowerCase().contains(q) || (i.label?.toLowerCase().contains(q) ?? false) || (i.path?.toLowerCase().contains(q) ?? false);

/// Errors first, then corrected by hand, then the rest, excluded last.
int _stateRank(WorkItem i) => i.excluded
    ? 3
    : i.result?.ok == false
        ? 0
        : i.hasOverride
            ? 1
            : 2;

/// The icons to show: filtered by [filter] and [query] (name, app name or
/// path), then sorted. Ties keep the import order.
List<WorkItem> studioArrange(List<WorkItem> items, {String query = '', StudioSort sort = StudioSort.added, StudioFilter filter = StudioFilter.all}) {
  final q = query.trim().toLowerCase();
  final out = [for (final i in items) if (studioMatchesFilter(i, filter) && (q.isEmpty || _matchesQuery(i, q))) i];
  if (sort == StudioSort.added) return out;
  final order = {for (var k = 0; k < items.length; k++) items[k]: k};
  out.sort((a, b) {
    final c = sort == StudioSort.name ? (a.label ?? a.name).toLowerCase().compareTo((b.label ?? b.name).toLowerCase()) : _stateRank(a).compareTo(_stateRank(b));
    return c != 0 ? c : order[a]!.compareTo(order[b]!);
  });
  return out;
}
