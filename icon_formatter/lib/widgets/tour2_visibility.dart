import 'package:flutter/foundation.dart';

/// True while the tour is on screen: the floating bars step aside so they
/// never sit on top of its controls. Set by OnboardingScreen after the frame.
final ValueNotifier<bool> tourOpen = ValueNotifier<bool>(false);
