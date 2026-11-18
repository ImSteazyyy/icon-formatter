import 'dart:io';

import 'package:flutter/foundation.dart' show LicenseRegistry, LicenseEntryWithLineBreaks;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:window_manager/window_manager.dart';

import 'app/models.dart' show UiStyle;
import 'app/shell.dart';
import 'services/platform_service.dart';
import 'screens/setup_screen.dart';
import 'app/state.dart';
import 'app/storage.dart';
import 'app/theme.dart';
import 'widgets/theme_reveal.dart';
import 'widgets/toasts.dart';
import 'src/rust/api/engine.dart';
import 'src/rust/frb_generated.dart';
import 'l10n/strings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // fonts bundled with the app (SIL Open Font License)
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(const ['Inter', 'Instrument Serif'], await rootBundle.loadString('assets/fonts/OFL.txt'));
  });
  await LiquidGlassWidgets.initialize(enablePerformanceMonitor: false);
  await RustLib.init();
  await AppPaths.init();
  await AppState.I.load();
  // phones: 4 Rust workers by default (a mid-range phone: 2 big + 6
  // little cores; all 8 at full load mostly adds heat and battery drain)
  if (Platform.isAndroid) setWorkerThreads(n: AppState.I.threads > 0 ? AppState.I.threads : 4);
  if (Platform.isWindows) {
    await windowManager.ensureInitialized();
    final options = WindowOptions(
      title: S.iconFormatter,
      size: Size(1440, 900),
      minimumSize: Size(980, 640),
      center: true,
      backgroundColor: Color(0xFF0E0E0F),
      titleBarStyle: TitleBarStyle.hidden,
      windowButtonVisibility: false,
    );
    windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }
  if (Platform.isAndroid) {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarContrastEnforced: false,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarIconBrightness: Brightness.light,
    ));
  }
  runApp(LiquidGlassWidgets.wrap(
    child: ThemeReveal.wrap(const IconFormatterApp()),
    brightnessResolver: Theme.maybeBrightnessOf,
    adaptiveQuality: false,
  ));
}

/// Language last sent to the Android side.
String? _nativeLang;

class IconFormatterApp extends StatelessWidget {
  const IconFormatterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppState.I,
      builder: (context, _) {
        final lang = AppState.I.appearance.languageCode;
        S.current = stringsFor(lang);
        if (Platform.isAndroid && lang != _nativeLang) {
          _nativeLang = lang;
          PlatformService.setLanguage(lang);
        }
        return MaterialApp(
        // a new language rebuilds every screen (pages are kept alive)
        key: ValueKey(lang),
        locale: Locale(lang),
        supportedLocales: [for (final c in appLanguages.keys) Locale(c)],
        localizationsDelegates: const [GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
        title: S.iconFormatter,
        debugShowCheckedModeBanner: false,
        theme: buildTheme(AppState.I.appearance, AppState.I.glass),
        // notices live at the top, above dialogs and sheets
        builder: (context, child) {
          // status and navigation bar icons follow light / dark
          final light = AppState.I.appearance.light;
          final page = AnnotatedRegion<SystemUiOverlayStyle>(
            value: (light ? SystemUiOverlayStyle.dark : SystemUiOverlayStyle.light).copyWith(
              statusBarColor: Colors.transparent,
              systemNavigationBarColor: Colors.transparent,
              systemNavigationBarContrastEnforced: false,
            ),
            child: ToastHost(child: child ?? const SizedBox()),
          );
          if (AppState.I.appearance.style != UiStyle.nothing) return page;
          final mq = MediaQuery.of(context);
          return MediaQuery(data: mq.copyWith(textScaler: _Scaled(mq.textScaler, 0.93)), child: page);
        },
        // first launch on Android: the short setup, then the app
        home: Platform.isAndroid && !AppState.I.setupDone ? const SetupScreen() : const Shell(),
      );
      },
    );
  }
}

/// The system text size times [factor] (user accessibility settings kept).
class _Scaled extends TextScaler {
  const _Scaled(this.base, this.factor);

  final TextScaler base;
  final double factor;

  @override
  double scale(double fontSize) => base.scale(fontSize) * factor;

  @override
  double get textScaleFactor => base.scale(1) * factor;

  @override
  bool operator ==(Object other) => other is _Scaled && other.base == base && other.factor == factor;

  @override
  int get hashCode => Object.hash(base, factor);
}
