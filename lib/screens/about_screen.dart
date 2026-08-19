/// 关于页：版本信息 + 检查更新按钮。
///
/// - 显示当前版本号（来自 pubspec.yaml）
/// - "检查更新" 按钮请求 GitHub Releases API，比对版本号
/// - 有新版本时打开浏览器跳转到 GitHub Releases 下载页
/// - 不实现 App 内下载/安装 APK（Android 需要用户授权"安装未知来源"）
library;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  static const _currentVersion = '0.1.0';
  static const _repoOwner = 'Melody-YK';
  static const _repoName = 'dsh';

  bool _checking = false;
  String? _latestVersion;
  String? _latestUrl;
  String? _error;

  Future<void> _checkUpdate() async {
    setState(() {
      _checking = true;
      _latestVersion = null;
      _latestUrl = null;
      _error = null;
    });

    try {
      final uri = Uri.parse(
        'https://api.github.com/repos/$_repoOwner/$_repoName/releases/latest',
      );
      final response = await http.get(
        uri,
        headers: {'Accept': 'application/vnd.github+json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        setState(() {
          _error = 'GitHub API 返回 ${response.statusCode}';
          _checking = false;
        });
        return;
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      final tag = (data['tag_name'] as String?)?.replaceFirst(RegExp(r'^v'), '');
      final htmlUrl = data['html_url'] as String?;

      if (tag == null) {
        setState(() {
          _latestVersion = null;
          _error = '未找到版本信息';
          _checking = false;
        });
        return;
      }

      setState(() {
        _latestVersion = tag;
        _latestUrl = htmlUrl ?? 'https://github.com/$_repoOwner/$_repoName/releases';
        _checking = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _checking = false;
      });
    }
  }

  bool get _hasUpdate {
    if (_latestVersion == null) return false;
    try {
      return _compareVersions(_latestVersion!, _currentVersion) > 0;
    } catch (_) {
      return false;
    }
  }

  /// 简单语义版本比较：a > b 返回 1，a == b 返回 0，a < b 返回 -1。
  static int _compareVersions(String a, String b) {
    final aParts = a.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final bParts = b.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    for (int i = 0; i < 3; i++) {
      final av = i < aParts.length ? aParts[i] : 0;
      final bv = i < bParts.length ? bParts[i] : 0;
      if (av > bv) return 1;
      if (av < bv) return -1;
    }
    return 0;
  }

  Future<void> _openUrl(String url) async {
    try {
      await http.get(Uri.parse(url)).timeout(const Duration(seconds: 1));
    } catch (_) {
      // 忽略；直接在浏览器打开
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasUpdate = _hasUpdate;

    return Scaffold(
      appBar: AppBar(title: const Text('关于')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Icon(Icons.phone_android, size: 64, color: Color(0xFF4D6BFE)),
          const SizedBox(height: 16),
          const Text(
            'DSH Mobile',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            '版本 $_currentVersion',
            textAlign: TextAlign.center,
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Text(
            'DeepSeek Harness 手机端',
            textAlign: TextAlign.center,
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 32),

          // 检查更新按钮
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _checking ? null : _checkUpdate,
              icon: _checking
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.system_update),
              label: Text(_checking ? '检查中…' : '检查更新'),
            ),
          ),
          const SizedBox(height: 16),

          if (_error != null) ...[
            Card(
              color: theme.colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: theme.colorScheme.error),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_error!, style: TextStyle(color: theme.colorScheme.error))),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],

          if (hasUpdate) ...[
            Card(
              color: theme.colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.new_releases, color: theme.colorScheme.primary),
                        const SizedBox(width: 8),
                        Text(
                          '新版本可用：$_latestVersion',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          if (_latestUrl != null) {
                            _openUrl(_latestUrl!);
                          }
                        },
                        icon: const Icon(Icons.open_in_browser),
                        label: const Text('前往下载'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ] else if (_latestVersion != null) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    const Text('已是最新版本'),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}