/// DSH Mobile — DeepSeek Harness 手机端。
///
/// 启动流程：恢复本地配置 → 未配置进配置页；已配置且可连接则自动连上。
library;

import 'package:flutter/material.dart';

import 'navigation.dart';
import 'screens/chat_screen.dart';
import 'screens/server_config_screen.dart';
import 'screens/session_list_screen.dart';
import 'screens/about_screen.dart';
import 'state/app_state.dart';
import 'widgets/respond_handler.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppState.instance.load();
  runApp(const DshMobileApp());
}

class DshMobileApp extends StatelessWidget {
  const DshMobileApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DSH Mobile',
      navigatorKey: appNavigatorKey,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF4D6BFE),
        brightness: Brightness.light,
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFF4D6BFE),
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
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
          default:
            return MaterialPageRoute(builder: (_) => const SessionListScreen());
        }
      },
      builder: (ctx, child) => RespondHandler(child: child ?? const SizedBox.shrink()),
    );
  }
}
