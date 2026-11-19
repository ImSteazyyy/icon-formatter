import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../services/platform_service.dart';
import 'liquid_glass.dart';

/// Checklist of the apps the auto-update check leaves out. Returns the new
/// list of packages on "Salva", or null when the sheet is dismissed.
Future<List<String>?> showIgnoredAppsSheet(
  BuildContext context, {
  required List<String> current,
  required List<InstalledApp> apps,
}) {
  return showAppSheet<List<String>>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _IgnoredAppsSheet(current: current, apps: apps),
  );
}

class _IgnoredAppsSheet extends StatefulWidget {
  const _IgnoredAppsSheet({required this.current, required this.apps});

  final List<String> current;
  final List<InstalledApp> apps;

  @override
  State<_IgnoredAppsSheet> createState() => _IgnoredAppsSheetState();
}

class _IgnoredAppsSheetState extends State<_IgnoredAppsSheet> {
  late final Set<String> _ignored = {...widget.current};
  late final List<(String, String)> _rows = _buildRows();
  String _query = '';

  /// One row per package (label, package): launcher apps first, then packages
  /// that are ignored but no longer installed, so they can be unticked.
  List<(String, String)> _buildRows() {
    final seen = <String>{};
    final rows = <(String, String)>[];
    for (final a in widget.apps) {
      if (seen.add(a.package)) {
        rows.add((a.label.isEmpty ? a.package : a.label, a.package));
      }
    }
    for (final p in widget.current) {
      if (seen.add(p)) rows.add((p, p));
    }
    rows.sort((a, b) => a.$1.toLowerCase().compareTo(b.$1.toLowerCase()));
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final q = _query.toLowerCase();
    final shown = [
      for (final r in _rows)
        if (q.isEmpty ||
            r.$1.toLowerCase().contains(q) ||
            r.$2.toLowerCase().contains(q))
          r,
    ];
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.75,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(S.androidIgnorateTitolo, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(S.androidIgnorateSub, style: theme.textTheme.bodySmall),
            const SizedBox(height: 10),
            TextField(
              decoration: InputDecoration(
                hintText: S.androidIgnorateCerca,
                prefixIcon: const Icon(Icons.search),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v.trim()),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: shown.isEmpty
                  ? Center(child: Text(S.androidIgnorateNessuna))
                  : ListView.builder(
                      itemCount: shown.length,
                      itemBuilder: (_, i) {
                        final (label, pkg) = shown[i];
                        return CheckboxListTile(
                          dense: true,
                          controlAffinity: ListTileControlAffinity.trailing,
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            pkg,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall,
                          ),
                          value: _ignored.contains(pkg),
                          onChanged: (on) => setState(() {
                            if (on == true) {
                              _ignored.add(pkg);
                            } else {
                              _ignored.remove(pkg);
                            }
                          }),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    S.androidIgnorateConteggio(_ignored.length),
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(S.annulla),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () =>
                      Navigator.pop(context, [..._ignored]..sort()),
                  child: Text(S.androidIgnorateSalva),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
