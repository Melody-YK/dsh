/// 设置页面：外观、权限、Agent 预设、连接、关于。
library;

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../state/app_state.dart';
import '../../main.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _primary = Color(0xFF4D6BFE);
  String _themeMode = 'dark';
  String _permissionPreset = '…';
  List<String> _permissionOptions = [];
  String _agentPreset = '…';
  List<Map<String, String>> _agentOptions = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _themeMode = prefs.getString('theme_mode') ?? 'dark');
    await Future.wait([_loadPermissions(), _loadAgentPresets()]);
    setState(() => _loading = false);
  }

  Future<void> _setTheme(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme_mode', mode);
    themeNotifier.value = mode == 'light' ? ThemeMode.light
        : mode == 'dark' ? ThemeMode.dark
        : ThemeMode.system;
    setState(() => _themeMode = mode);
  }

  // ---------- 权限预设 ----------

  Future<void> _loadPermissions() async {
    final conn = AppState.instance.conn;
    if (conn == null) return;
    try {
      // 执行 /permission 命令获取当前和可用预设
      final result = await http.post(
        Uri.parse('${conn.rpc.baseUri}/api/commands/execute'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'type': 'client-request',
          'rpcId': 'settings-perm',
          'method': 'commands/execute',
          'payload': {'args': {'agentId': _getAgentId(), 'line': '/permission'}},
        }),
      ).timeout(const Duration(seconds: 10));
      final data = jsonDecode(result.body) as Map<String, dynamic>;
      final text = ((data['result'] as Map)['value'] as Map)['result'] as Map;
      final msg = text['text'] as String;
      // 格式: "current preset danger-full-access (available: read-only, workspace-write, danger-full-access)"
      final current = RegExp(r'current preset (\S+)').firstMatch(msg)?.group(1) ?? '?';
      final available = RegExp(r'available: (.+)\)').firstMatch(msg)?.group(1)?.split(', ') ?? [];
      if (mounted) {
        setState(() {
          _permissionPreset = current;
          _permissionOptions = available;
        });
      }
    } catch (_) {}
  }

  Future<void> _switchPermission(String preset) async {
    final conn = AppState.instance.conn;
    if (conn == null) return;
    try {
      await http.post(
        Uri.parse('${conn.rpc.baseUri}/api/commands/execute'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'type': 'client-request',
          'rpcId': 'settings-perm-switch',
          'method': 'commands/execute',
          'payload': {'args': {'agentId': _getAgentId(), 'line': '/permission $preset'}},
        }),
      ).timeout(const Duration(seconds: 10));
      setState(() => _permissionPreset = preset);
    } catch (_) {}
  }

  // ---------- Agent 预设 ----------

  Future<void> _loadAgentPresets() async {
    final conn = AppState.instance.conn;
    if (conn == null) return;
    try {
      final result = await http.post(
        Uri.parse('${conn.rpc.baseUri}/api/agentPreset.list'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'type': 'client-request', 'rpcId': 'settings-ap', 'method': 'agentPreset.list', 'payload': {}}),
      ).timeout(const Duration(seconds: 10));
      final data = jsonDecode(result.body) as Map<String, dynamic>;
      final presets = ((data['result'] as Map)['value'] as Map)['presets'] as List;
      final options = <Map<String, String>>[];
      String? current;
      for (final p in presets) {
        final id = p['id'] as String;
        final name = (p['name'] as String?) ?? id;
        final desc = (p['description'] as String?) ?? '';
        final isDefault = (p['isDefault'] as bool?) ?? false;
        options.add({'id': id, 'name': name, 'desc': desc});
        if (isDefault) current = id;
      }
      if (mounted) {
        setState(() {
          _agentOptions = options;
          _agentPreset = current ?? options.firstOrNull?['id'] ?? '?';
        });
      }
    } catch (_) {}
  }

  String _getAgentId() {
    // 用当前活跃会话的 agentId
    final state = AppState.instance;
    final running = state.sessions.where((s) => s.running).firstOrNull;
    return running?.sessionId ?? 'session-unknown';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseUrl = AppState.instance.baseUrl;

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
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

                // 权限预设
                const _SectionHeader('权限预设'),
                if (_permissionOptions.isNotEmpty)
                  ListTile(
                    leading: const Icon(Icons.security, color: _primary),
                    title: const Text('沙箱模式'),
                    subtitle: Text(_permissionPreset),
                    trailing: DropdownButton<String>(
                      value: _permissionPreset,
                      underline: const SizedBox(),
                      items: _permissionOptions.map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
                      onChanged: (v) => _switchPermission(v!),
                    ),
                  ),
                const Divider(height: 1, indent: 16, endIndent: 16),

                // Agent 预设
                const _SectionHeader('Agent 预设'),
                if (_agentOptions.isNotEmpty)
                  ListTile(
                    leading: const Icon(Icons.smart_toy_outlined, color: _primary),
                    title: const Text('默认预设'),
                    subtitle: Text(_agentOptions.firstWhere((o) => o['id'] == _agentPreset, orElse: () => {'name': _agentPreset})['name'] ?? _agentPreset),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _pickAgentPreset(),
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
                  subtitle: const Text('版本 0.4.0 · 检查更新'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).pushNamed('/about'),
                ),

                const SizedBox(height: 32),
                Center(
                  child: Text('DSH Mobile v0.4.0', style: TextStyle(fontSize: 12, color: theme.colorScheme.outline)),
                ),
                const SizedBox(height: 32),
              ],
            ),
    );
  }

  Future<void> _pickAgentPreset() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('选择 Agent 预设', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
            for (final o in _agentOptions)
              ListTile(
                leading: Icon(
                  o['id'] == _agentPreset ? Icons.radio_button_checked : Icons.radio_button_off,
                  color: _primary,
                ),
                title: Text(o['name'] ?? o['id']!),
                subtitle: (o['desc']?.isNotEmpty ?? false) ? Text(o['desc']!, maxLines: 2, overflow: TextOverflow.ellipsis) : null,
                onTap: () => Navigator.pop(ctx, o['id']),
              ),
          ],
        ),
      ),
    );
    if (picked != null) setState(() => _agentPreset = picked);
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