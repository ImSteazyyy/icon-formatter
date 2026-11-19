// Pure glue between the Pack screens and the pack services. No Flutter, no I/O.

import 'pack_conflicts.dart';
import 'pack_mapping_import.dart';
import 'pack_suggest.dart';

/// The entry an app writes into the pack (see buildIconPack): component,
/// package, label and drawable. [drawableOf] names the drawable from the
/// package, or from the label when there is no package.
PackEntryInfo packEntryFor({
  required String package,
  required String activity,
  required String label,
  required String Function(String key) drawableOf,
}) {
  final component = package.isEmpty
      ? ''
      : (activity.isEmpty ? package : '$package/$activity');
  final key = package.isEmpty ? label : package;
  return PackEntryInfo(
    component: component,
    package: package,
    label: label,
    drawable: key.isEmpty ? '' : drawableOf(key),
  );
}

/// Icons that no other app uses, and that are not [ownId] (the row's own).
List<CandidateIcon> freeCandidates({
  required Iterable<CandidateIcon> icons,
  required Set<String> usedIds,
  String? ownId,
}) => [
  for (final c in icons)
    if (c.id != ownId && !usedIds.contains(c.id)) c,
];

/// Source entries from another pack's icons: each icon with a package becomes
/// a component -> drawable pair, the drawable being the icon's file stem.
List<AppFilterEntry> mappingSourceEntries(
  List<({String package, String activity, String drawable})> icons,
) => [
  for (final i in icons)
    if (i.package.isNotEmpty && i.drawable.isNotEmpty)
      AppFilterEntry(
        component: i.activity.isEmpty
            ? i.package
            : '${i.package}/${i.activity}',
        drawable: i.drawable.toLowerCase(),
      ),
];
