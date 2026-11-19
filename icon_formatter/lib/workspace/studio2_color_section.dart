import 'package:flutter/material.dart';

import '../app/state.dart';
import '../app/theme.dart';
import '../l10n/strings.dart';
import '../widgets/color_picker.dart';
import '../widgets/common.dart';
import 'workspace_controller.dart';

/// Collapsed "Colore" block of the adjust panel: global look options that
/// apply to every icon and to the preview. Slider drags only re-render the
/// preview (debounced), never the batch.
class Studio2ColorSection extends StatefulWidget {
  const Studio2ColorSection({super.key, required this.c});

  final WorkspaceController c;

  @override
  State<Studio2ColorSection> createState() => _Studio2ColorSectionState();
}

class _Studio2ColorSectionState extends State<Studio2ColorSection> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppState.I,
      builder: (context, _) {
        final st = AppState.I;
        final l = st.look;
        void set(VoidCallback f) => st.update(f);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => setState(() => _open = !_open),
              child: SectionTitle(
                S.colore,
                trailing: Icon(
                  _open ? Icons.expand_less : Icons.expand_more,
                  color: Palette.text2,
                ),
              ),
            ),
            if (_open) ...[
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => set(l.resetColor),
                  child: Text(S.ripristina),
                ),
              ),
              SliderRow(
                label: S.luminosita,
                value: l.brightness,
                min: -1,
                max: 1,
                onChanged: (v) => set(() => l.brightness = v),
              ),
              SliderRow(
                label: S.saturazione,
                value: l.saturation,
                min: -1,
                max: 1,
                onChanged: (v) => set(() => l.saturation = v),
              ),
              SliderRow(
                label: S.tinta,
                value: l.hue,
                min: -180,
                max: 180,
                format: (v) => '${v.round()}°',
                onChanged: (v) => set(() => l.hue = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(S.studio2Ricolora, style: TextStyle(fontSize: 13)),
                value: l.recolorOn,
                onChanged: (v) => set(() => l.recolorOn = v),
              ),
              if (l.recolorOn)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(
                    S.studio2ColoreSimbolo,
                    style: TextStyle(fontSize: 13),
                  ),
                  trailing: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(l.recolor),
                    ),
                  ),
                  onTap: () => showColorPicker(
                    context,
                    initial: l.recolor,
                    title: S.studio2ColoreSimbolo,
                    onChanged: (v) => set(() => l.recolor = v),
                  ),
                ),
              if (widget.c.mode == StudioMode.translucent)
                SliderRow(
                  label: S.studio2PiattoDalSimbolo,
                  value: l.plateTint,
                  onChanged: (v) => set(() => l.plateTint = v),
                ),
              SliderRow(
                label: S.studio2Nitidezza,
                value: l.sharpen,
                onChanged: (v) => set(() => l.sharpen = v),
              ),
            ],
          ],
        );
      },
    );
  }
}
