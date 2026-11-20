import '../src/rust/api/engine.dart' show LucentShape, LucentStrategy, PlacementSettings, SegmentSettings;

/// The corrections of one icon, as values only (no images), for undo/redo.
class ItemCorrection {
  const ItemCorrection({this.seg, this.placement, this.strategy, this.shape, this.backdrop, this.matchPlate = false, this.excluded = false});

  final SegmentSettings? seg;
  final PlacementSettings? placement;
  final LucentStrategy? strategy;

  /// Per-icon plate shape and colour (ARGB), Lightnt only; null = global.
  final LucentShape? shape;
  final int? backdrop;
  final bool matchPlate;
  final bool excluded;

  /// Same look: the override objects are the same and the flags match.
  /// Settings are copied on write, so identity tells a change.
  bool sameLook(ItemCorrection o) =>
      identical(seg, o.seg) &&
      identical(placement, o.placement) &&
      identical(strategy, o.strategy) &&
      shape == o.shape &&
      backdrop == o.backdrop &&
      matchPlate == o.matchPlate;

  bool sameAs(ItemCorrection o) => sameLook(o) && excluded == o.excluded;
}

class _Step<T> {
  _Step(this.tag, this.before, this.after, this.at);

  final String tag;
  final T before;
  T after;
  DateTime at;
}

/// Bounded undo/redo stack. A push with the same [tag] within [mergeWindow]
/// of the last one is merged into it (a slider drag is one step).
class StudioHistory<T> {
  StudioHistory({this.limit = 30, this.mergeWindow = const Duration(milliseconds: 900)});

  final int limit;
  final Duration mergeWindow;
  final List<_Step<T>> _undo = [];
  final List<_Step<T>> _redo = [];

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  void push(String tag, T before, T after, DateTime at) {
    _redo.clear();
    if (_undo.isNotEmpty) {
      final last = _undo.last;
      if (last.tag == tag && at.difference(last.at) < mergeWindow) {
        last.after = after;
        last.at = at;
        return;
      }
    }
    _undo.add(_Step(tag, before, after, at));
    if (_undo.length > limit) _undo.removeAt(0);
  }

  /// The state to restore for an undo, or null when there is nothing to undo.
  T? undo() {
    if (_undo.isEmpty) return null;
    final s = _undo.removeLast();
    _redo.add(s);
    return s.before;
  }

  /// The state to restore for a redo, or null when there is nothing to redo.
  T? redo() {
    if (_redo.isEmpty) return null;
    final s = _redo.removeLast();
    _undo.add(s);
    return s.after;
  }

  void clear() {
    _undo.clear();
    _redo.clear();
  }
}
