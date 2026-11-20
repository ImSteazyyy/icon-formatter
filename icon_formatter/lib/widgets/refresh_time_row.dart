import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../services/platform_service.dart';
import 'pack_rows.dart';

/// Row for the hour of the daily calendar-day refresh of the installed pack.
/// `status` is the map from PlatformService.autoSyncStatus(); -1 means "at the first check".
class RefreshTimeRow extends StatelessWidget {
  const RefreshTimeRow({
    super.key,
    required this.status,
    required this.busy,
    required this.load,
  });

  final Map<String, dynamic> status;
  final bool busy;
  final Future<void> Function(Future<Map<String, dynamic>> Function()) load;

  @override
  Widget build(BuildContext context) {
    final hour = (status['calendarHour'] as num?)?.toInt() ?? -1;
    return PackRow(
      icon: Icons.schedule_rounded,
      title: S.comodoOrarioBreve,
      onTap: busy ? null : () => _pick(context, hour),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hour >= 0)
            IconButton(
              tooltip: S.comodoOrarioGiornoAzzera,
              constraints: const BoxConstraints.tightFor(width: 48, height: 48),
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.close_rounded, size: 18),
              onPressed: busy ? null : () => load(() => PlatformService.calendarHourSet(-1)),
            ),
          PackValue(
            hour < 0 ? S.comodoAllaPrimaOccasione : TimeOfDay(hour: hour, minute: 0).format(context),
            chevron: true,
          ),
        ],
      ),
    );
  }

  Future<void> _pick(BuildContext context, int hour) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: hour < 0 ? 0 : hour, minute: 0),
      helpText: S.comodoOrarioGiorno,
    );
    if (picked == null) return;
    final h = picked.hour;
    await load(() => PlatformService.calendarHourSet(h));
  }
}
