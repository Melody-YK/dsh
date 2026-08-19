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

  /// 打开扫码页，扫到 URL 后自动填进地址框。
  Future<void> _scan() async {
    final url = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const ScannerScreen()),
    );
    if (url != null && url.isNotEmpty && mounted) {
      setState(() => _controller.text = url);
    }
  }

  /// 握手成功后自动进入会话列表。
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
    return Scaffold(
      appBar: AppBar(title: const Text('连接 DeepSeek Harness')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Icon(Icons.hub_outlined, size: 72, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              '输入你的 DSH 服务地址',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              '局域网：http://电脑IP:3080\n远程：http://<Tailscale IP>:3080',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _controller,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: '服务地址',
                hintText: 'http://192.168.1.5:3080',
                prefixIcon: const Icon(Icons.dns_outlined),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.qr_code_scanner),
                  tooltip: '扫码填写地址',
                  onPressed: _scan,
                ),
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) => _connect(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _busy ? null : _connect,
              icon: _busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.link),
              label: Text(_busy ? '连接中…' : '连接'),
            ),
            const SizedBox(height: 12),
            Text(
              '提示：DSH 服务端需以 --host 0.0.0.0 启动，并保证手机与电脑网络互通。',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
