/// DSH Mobile — DeepSeek Harness 手机端。
library;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'navigation.dart';
import 'screens/chat_screen.dart';
import 'screens/server_config_screen.dart';
import 'screens/session_list_screen.dart';
import 'screens/about_screen.dart';
import 'screens/settings_screen.dart';
import 'state/app_state.dart';
import 'widgets/respond_handler.dart';

/// 全局主题通知器，设置页修改后触发重建
final themeNotifier = ValueNotifier<ThemeMode>(ThemeMode.dark);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppState.instance.load();
  // 恢复保存的主题
  final prefs = await SharedPreferences.getInstance();
  final saved = prefs.getString('theme_mode') ?? 'dark';
  themeNotifier.value = saved == 'light' ? ThemeMode.light
      : saved == 'dark' ? ThemeMode.dark
      : ThemeMode.system;
  runApp(const DshMobileApp());
}

class DshMobileApp extends StatelessWidget {
  const DshMobileApp({super.key});

  static const _primary = Color(0xFF4D6BFE);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (ctx, mode, _) {
        return MaterialApp(
          title: 'DSH Mobile',
          navigatorKey: appNavigatorKey,
          themeMode: mode,
          darkTheme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: _primary, brightness: Brightness.dark),
            scaffoldBackgroundColor: const Color(0xFF0F1115),
            cardTheme: const CardThemeData(
              color: Color(0xFF202124),
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
            ),
            appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xFF151517),
              foregroundColor: Colors.white,
              elevation: 0,
              scrolledUnderElevation: 1,
              centerTitle: false,
            ),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: const Color(0xFF232325),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _primary, width: 1.5)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
            dialogTheme: const DialogThemeData(backgroundColor: Color(0xFF202124)),
            bottomSheetTheme: const BottomSheetThemeData(backgroundColor: Color(0xFF202124), modalBackgroundColor: Color(0xFF202124)),
            floatingActionButtonTheme: const FloatingActionButtonThemeData(backgroundColor: _primary, foregroundColor: Colors.white),
            snackBarTheme: SnackBarThemeData(
              backgroundColor: const Color(0xFF2C2C2E),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            useMaterial3: true,
          ),
          theme: ThemeData(colorSchemeSeed: _primary, brightness: Brightness.light, useMaterial3: true),
          initialRoute: AppState.instance.isConfigured ? '/sessions' : '/config',
          onGenerateRoute: (settings) {
            switch (settings.name) {
              case '/config':
                return MaterialPageRoute(builder: (_) => const ServerConfigScreen());
              case '/sessions':
                return MaterialPageRoute(builder: (_) => const SessionListScreen());
              case '/chat':
                final id = settings.arguments as String?;
                return MaterialPageRoute(builder: (_) => ChatScreen(sessionId: id ?? ''));
              case '/about':
                return MaterialPageRoute(builder: (_) => const AboutScreen());
              case '/settings':
                return MaterialPageRoute(builder: (_) => const SettingsScreen());
              default:
                return MaterialPageRoute(builder: (_) => const SessionListScreen());
            }
          },
          builder: (ctx, child) => RespondHandler(child: child ?? const SizedBox.shrink()),
        );
      },
    );
  }
}