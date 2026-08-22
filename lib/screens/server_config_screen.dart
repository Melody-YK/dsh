/// 服务地址配置页：输入 DSH 的 base URL 并连接。
///
/// 地址示例：`http://192.168.1.5:3080`（局域网）或
/// `http://100.x.y.z:3080`（Tailscale）。
library;

import 'package:flutter/material.dart';

import '../core/protocol/connection.dart';
import '../state/app_state.dart';
import 'scanner_screen.dart';

class ServerConfigScreen extends StatefulWidget {
  const ServerConfigScreen({super.key});

  @override
  State<ServerConfigScreen> createState() => _ServerConfigScreenState();
}

class _ServerConfigScreenState extends State<ServerConfigScreen> {
  final _controller = TextEditingController();
  bool _busy = false;
  String? _error;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _controller.text = AppState.instance.baseUrl;
    AppState.instance.addListener(_onStateChanged);
  }

  @override
  void dispose() {
    AppState.instance.removeListener(_onStateChanged);
    _controller.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    final url = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const ScannerScreen()),
    );
    if (url != null && url.isNotEmpty && mounted) {
      setState(() => _controller.text = url);
    }
  }

  void _onStateChanged() {
    final state = AppState.instance;
    if (!mounted || _navigated) return;
    if (state.connectionState == DshConnectionState.connected) {
      _navigated = true;
      Navigator.of(context).pushReplacementNamed('/sessions');
    } else if (state.connectionState == DshConnectionState.reconnecting) {
      setState(() {
        _busy = false;
        _error = state.lastError;
      });
    }
  }

  Future<void> _connect() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AppState.instance.configureAndConnect(_controller.text);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    return Scaffold(
      appBar: AppBar(title: const Text('DSH Mobile')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 图标
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: primary.withAlpha(30),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Icon(Icons.hub_outlined, size: 44, color: primary),
                ),
                const SizedBox(height: 24),
                // 标题
                Text(
                  '连接 DeepSeek Harness',
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  '输入 DSH 服务地址，或扫码自动填入',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 28),
                // 地址输入框
                TextField(
                  controller: _controller,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  style: const TextStyle(fontSize: 15, fontFamily: 'monospace'),
                  decoration: InputDecoration(
                    hintText: 'http://192.168.1.5:3080',
                    labelText: '服务地址',
                    prefixIcon: const Icon(Icons.dns_outlined),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.qr_code_scanner),
                      tooltip: '扫码填写地址',
                      onPressed: _scan,
                    ),
                  ),
                  onSubmitted: (_) => _connect(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.errorContainer.withAlpha(80),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline, size: 18, color: theme.colorScheme.error),
                        const SizedBox(width: 8),
                        Expanded(child: Text(_error!, style: TextStyle(color: theme.colorScheme.error, fontSize: 13))),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                // 连接按钮
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _connect,
                    icon: _busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.link),
                    label: Text(_busy ? '连接中…' : '连接', style: const TextStyle(fontSize: 16)),
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                // 提示
                Text(
                  '局域网：http://电脑IP:3080\n远程：http://<Tailscale IP>:3080',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}