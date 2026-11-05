import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:window_manager/window_manager.dart';

import 'app/shell.dart';
import 'app/state.dart';
import 'app/storage.dart';
import 'app/theme.dart';
import 'widgets/toasts.dart';
import 'src/rust/api/engine.dart';
import 'src/rust/frb_generated.dart';
import 'l10n/strings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LiquidGlassWidgets.initialize(enablePerformanceMonitor: false);
  await RustLib.init();
  await AppPaths.init();
  await AppState.I.load();
  // phones: 4 Rust workers by default (Nothing Phone (2a) Plus: 2 big + 6
  // little cores; all 8 at full load mostly adds heat and battery drain)
  if (Platform.isAndroid) setWorkerThreads(n: AppState.I.threads > 0 ? AppState.I.threads : 4);
  if (Platform.isWindows) {
    await windowManager.ensureInitialized();
    const options = WindowOptions(
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
    child: const IconFormatterApp(),
    brightnessResolver: Theme.maybeBrightnessOf,
    adaptiveQuality: false,
  ));
}

class IconFormatterApp extends StatelessWidget {
  const IconFormatterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppState.I,
      builder: (context, _) => MaterialApp(
        title: S.iconFormatter,
        debugShowCheckedModeBanner: false,
        theme: buildTheme(AppState.I.appearance, AppState.I.glass),
        // notices live at the top, above dialogs and sheets
        builder: (context, child) => ToastHost(child: child ?? const SizedBox()),
        home: const Shell(),
      ),
    );
  }
}
