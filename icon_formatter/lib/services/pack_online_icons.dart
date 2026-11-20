import 'dart:typed_data';

/// Online fallback for a single poorly generated icon. Design and legal limits
/// are in docs/ONLINE_ICONS.md. Nothing here runs by itself: the UI calls
/// [OnlineIconService.fetchForUserAction] once per tap, on one icon.
abstract class OnlineIconProvider {
  /// Name shown in the UI and the docs.
  String get name;

  /// False when the provider must not be used (its terms or the licence of the
  /// icons do not allow it). A disabled provider is never called.
  bool get enabled;

  /// PNG bytes of the icon of [package], or null when there is none.
  /// Throws [OnlineIconException] on network or protocol errors.
  Future<Uint8List?> fetchPng(String package);
}

class OnlineIconException implements Exception {
  const OnlineIconException(this.message);
  final String message;

  @override
  String toString() => 'OnlineIconException: $message';
}

/// Google Play listing icon. Disabled: Play offers no icon API, and fetching
/// listing pages or their images automatically is against the Google Play
/// terms. Kept only as the place where a licensed source would plug in.
class PlayListingIconProvider implements OnlineIconProvider {
  const PlayListingIconProvider();

  @override
  String get name => 'Google Play listing';

  @override
  bool get enabled => false;

  // shortcut: no network code on purpose, a licensed icon source replaces this body
  @override
  Future<Uint8List?> fetchPng(String package) =>
      throw const OnlineIconException('provider disabled');
}

/// Gatekeeper in front of a provider: checks the package name, enforces one
/// request per user action and a minimum gap between requests (no bulk use).
class OnlineIconService {
  OnlineIconService(
    this.provider, {
    DateTime Function()? clock,
    this.minGap = const Duration(seconds: 2),
  }) : _clock = clock ?? DateTime.now;

  final OnlineIconProvider provider;
  final Duration minGap;
  final DateTime Function() _clock;
  DateTime? _last;

  /// Android package name: at least two dot-separated identifiers.
  static final RegExp _package = RegExp(r'^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$');

  /// Returns the icon, or null when the provider is off, the package is not a
  /// valid name, the request is throttled, or there is no icon.
  Future<Uint8List?> fetchForUserAction(String package) async {
    if (!provider.enabled || !_package.hasMatch(package)) return null;
    final now = _clock();
    if (_last != null && now.difference(_last!) < minGap) return null;
    _last = now;
    return provider.fetchPng(package);
  }
}
