import '../l10n/strings.dart';
import 'models.dart';

/// Name shown for a style preset. Built-in presets get their localised text
/// (the stored name is Italian); user presets keep the name they were given.
String presetDisplayName(StylePreset p) {
  if (!p.builtIn) return p.name;
  return switch (p.id) {
    'sqColour' => S.ux2cPresetSqColour,
    'sqMono' => S.ux2cPresetSqMono,
    'ciColour' => S.ux2cPresetCiColour,
    'ciMono' => S.ux2cPresetCiMono,
    _ => p.name,
  };
}
