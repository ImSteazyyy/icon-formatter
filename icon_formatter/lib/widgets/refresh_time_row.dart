import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../services/platform_service.dart';

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
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(
        S.comodoOrarioGiorno,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hour >= 0)
            IconButton(
              tooltip: S.comodoOrarioGiornoAzzera,
              icon: const Icon(Icons.close, size: 18),
              onPressed: busy ? null : () => load(() => PlatformService.calendarHourSet(-1)),
            ),
          TextButton(
            onPressed: busy ? null : () => _pick(context, hour),
            child: Text(
              hour < 0 ? S.comodoAllaPrimaOccasione : TimeOfDay(hour: hour, minute: 0).format(context),
            ),
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
