/// Which images of an opened source become icons of the Pack builder.
///
/// [componentOf] maps a drawable name (lower case) to the (package, activity)
/// its appfilter.xml links it to. When it is empty the source is a plain
/// folder of images and every image is kept. When it is not, the source is an
/// icon pack and only one icon per component is kept: the human-readable
/// copies in icons/ and the calendar day drawables (the app's plain icon
/// stands for the calendar) are left out, and a component listed by several
/// drawables keeps the first one. Returns the indexes of [rels] to keep.
List<int> packIconIndexes(List<String> rels, Map<String, (String, String)> componentOf) {
  if (componentOf.isEmpty) return [for (var i = 0; i < rels.length; i++) i];
  final dayDrawable = RegExp(r'^calendar_.+_\d{1,2}$');
  final seen = <String>{};
  final keep = <int>[];
  for (var i = 0; i < rels.length; i++) {
    final rel = rels[i].replaceAll('\\', '/');
    if (rel.startsWith('icons/')) continue;
    final stem = rel.split('/').last.replaceFirst(RegExp(r'\.[^.]*$'), '').toLowerCase();
    if (dayDrawable.hasMatch(stem)) continue;
    final c = componentOf[stem];
    if (c == null || !seen.add('${c.$1}/${c.$2}')) continue;
    keep.add(i);
  }
  return keep;
}

/// Whether a bulk render ("Crea con lo Studio", the change check) may render
/// the original [originalId]. Icons of a pack (ids "pk...") and icons already
/// made in the Studio are finished and never rendered again by a bulk action.
bool renderOnBulk({required String originalId, required bool hasStudioIcon, required bool rowFinished}) =>
    !originalId.startsWith('pk') && !hasStudioIcon && !rowFinished;

final _dayDrawable = RegExp(r'^calendar_(.+)_(\d{1,2})$');

/// A calendar day drawable of an icon pack, with the app it belongs to.
typedef PackDayRef = ({int index, int day, String package, String activity});

/// Calendar day drawables (calendar_<drawable of the app>_N) of an icon pack.
/// The app is the component whose package gives the same drawable prefix as
/// the build (Rust sanitize_drawable). Empty for a plain folder of images.
List<PackDayRef> packCalendarDays(List<String> rels, Map<String, (String, String)> componentOf) {
  if (componentOf.isEmpty) return const [];
  final byPrefix = <String, (String, String)>{};
  for (final c in componentOf.values) {
    byPrefix.putIfAbsent(sanitizeDrawableKey(c.$1), () => c);
  }
  final out = <PackDayRef>[];
  for (var i = 0; i < rels.length; i++) {
    final rel = rels[i].replaceAll('\\', '/');
    if (rel.startsWith('icons/')) continue;
    final stem = rel.split('/').last.replaceFirst(RegExp(r'\.[^.]*$'), '').toLowerCase();
    final m = _dayDrawable.firstMatch(stem);
    if (m == null) continue;
    final c = byPrefix[m.group(1)!];
    final day = int.parse(m.group(2)!);
    if (c == null || day < 1 || day > 31) continue;
    out.add((index: i, day: day, package: c.$1, activity: c.$2));
  }
  return out;
}

/// Rust sanitize_drawable: a valid drawable name from a package name.
String sanitizeDrawableKey(String s) {
  var o = s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_');
  while (o.contains('__')) {
    o = o.replaceAll('__', '_');
  }
  o = o.replaceAll(RegExp(r'^_+|_+$'), '');
  return o.isEmpty || !RegExp(r'^[a-z]').hasMatch(o) ? 'ic_$o' : o;
}

/// The days of each calendar app, by package, sorted by day; one per day
/// (the first one listed wins). Days outside 1..31 and without package go.
Map<String, List<T>> groupCalendarDays<T>(Iterable<T> days, {required String Function(T) packageOf, required int Function(T) dayOf}) {
  final sorted = days.toList()..sort((a, b) => dayOf(a).compareTo(dayOf(b)));
  final out = <String, List<T>>{};
  final seen = <String>{};
  for (final d in sorted) {
    final day = dayOf(d);
    final pkg = packageOf(d);
    if (day < 1 || day > 31 || pkg.isEmpty || !seen.add('$pkg/$day')) continue;
    out.putIfAbsent(pkg, () => []).add(d);
  }
  return out;
}

final _humanCopy = RegExp(r'^.+ \([a-z0-9_]+(\.[a-z0-9_]+)+\)\.[a-z]+$');
final _templateImage = RegExp(r'^(app|pack)_icon');

/// Sources saved by an older build as "from file" originals: keeps the ones
/// that are real, drops calendar days, the human-readable copies
/// "Name (pkg.name).png", template images and repeats of the same app.
/// Shortcut: the rules match file names, so a user file named like a copy
/// would be dropped from the list too (the file itself stays on disk).
List<int> savedSourceIndexes(List<({String file, String package, String activity})> items) {
  final seen = <String>{};
  final keep = <int>[];
  for (var i = 0; i < items.length; i++) {
    final f = items[i].file.toLowerCase();
    final stem = f.replaceFirst(RegExp(r'\.[^.]*$'), '');
    if (_dayDrawable.hasMatch(stem) || _humanCopy.hasMatch(f) || _templateImage.hasMatch(stem)) continue;
    final pkg = items[i].package;
    if (pkg.isNotEmpty && !seen.add('$pkg/${items[i].activity}')) continue;
    keep.add(i);
  }
  return keep;
}
