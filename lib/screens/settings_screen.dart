/// 设置页面：主题偏好、服务地址、关于。
library;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../state/app_state.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _primary = Color(0xFF4D6BFE);
  String _themeMode = 'dark';

  @override
  void initState() {
    super.initState();
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _themeMode = prefs.getString('theme_mode') ?? 'dark');
  }

  Future<void> _setTheme(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme_mode', mode);
    setState(() => _themeMode = mode);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseUrl = AppState.instance.baseUrl;

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          // 外观
          const _SectionHeader('外观'),
          ListTile(
            leading: const Icon(Icons.brightness_6, color: _primary),
            title: const Text('主题'),
            subtitle: Text(_themeMode == 'dark' ? '深色' : _themeMode == 'light' ? '浅色' : '跟随系统'),
            trailing: DropdownButton<String>(
              value: _themeMode,
              underline: const SizedBox(),
              items: const [
                DropdownMenuItem(value: 'dark', child: Text('深色')),
                DropdownMenuItem(value: 'light', child: Text('浅色')),
                DropdownMenuItem(value: 'system', child: Text('跟随系统')),
              ],
              onChanged: (v) => _setTheme(v!),
            ),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),

          // 连接
          const _SectionHeader('连接'),
          ListTile(
            leading: const Icon(Icons.dns_outlined, color: _primary),
            title: const Text('服务地址'),
            subtitle: Text(baseUrl, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).pushNamed('/config'),
          ),

          const Divider(height: 1, indent: 16, endIndent: 16),

          // 关于
          const _SectionHeader('关于'),
          ListTile(
            leading: const Icon(Icons.info_outline, color: _primary),
            title: const Text('关于 DSH Mobile'),
            subtitle: const Text('版本 0.3.0 · 检查更新'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).pushNamed('/about'),
          ),

          const SizedBox(height: 32),
          Center(
            child: Text(
              'DSH Mobile v0.3.0',
              style: TextStyle(fontSize: 12, color: theme.colorScheme.outline),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 4),
      child: Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF4D6BFE), letterSpacing: 0.5)),
    );
  }
}