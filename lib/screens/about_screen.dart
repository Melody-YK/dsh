/// 关于页：版本信息 + 检查更新 + App 内下载安装。
library;

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:open_filex/open_filex.dart';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  static const _currentVersion = '0.5.0';
  static const _repoOwner = 'Melody-YK';
  static const _repoName = 'dsh';
  static const _primary = Color(0xFF4D6BFE);

  bool _checking = false;
  String? _latestVersion;
  String? _latestUrl;
  String? _downloadUrl;
  String? _error;
  bool _noRelease = false;

  // 下载状态
  bool _downloading = false;
  double _downloadProgress = 0;
  String? _downloadError;

  Future<void> _checkUpdate() async {
    setState(() {
      _checking = true;
      _latestVersion = null;
      _latestUrl = null;
      _downloadUrl = null;
      _error = null;
      _noRelease = false;
    });

    try {
      final response = await http.get(
        Uri.parse('https://api.github.com/repos/$_repoOwner/$_repoName/releases/latest'),
        headers: {'Accept': 'application/vnd.github+json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 404) {
        setState(() { _noRelease = true; _checking = false; });
        return;
      }
      if (response.statusCode != 200) {
        setState(() { _error = 'GitHub API 返回 ${response.statusCode}'; _checking = false; });
        return;
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      final tag = (data['tag_name'] as String?)?.replaceFirst(RegExp(r'^v'), '');
      final htmlUrl = data['html_url'] as String?;
      final assets = (data['assets'] as List?) ?? [];
      String? apkUrl;
      for (final a in assets) {
        if ((a as Map)['name'] == 'app-release.apk') {
          apkUrl = a['browser_download_url'] as String?;
          break;
        }
      }

      if (tag == null) {
        setState(() { _error = '未找到版本信息'; _checking = false; });
        return;
      }

      setState(() {
        _latestVersion = tag;
        _latestUrl = htmlUrl ?? 'https://github.com/$_repoOwner/$_repoName/releases';
        _downloadUrl = apkUrl;
        _checking = false;
      });
    } catch (e) {
      setState(() { _error = e.toString(); _checking = false; });
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

  Future<void> _downloadAndInstall() async {
    if (_downloadUrl == null) return;
    setState(() { _downloading = true; _downloadProgress = 0; _downloadError = null; });

    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/dsh-mobile-update.apk');
      final client = http.Client();
      final request = http.Request('GET', Uri.parse(_downloadUrl!));
      final streamedResp = await client.send(request);
      final total = streamedResp.contentLength;
      final sink = file.openWrite();
      int received = 0;
      await streamedResp.stream.listen(
        (chunk) {
          sink.add(chunk);
          received += chunk.length;
          if (total != null && total > 0 && mounted) {
            setState(() => _downloadProgress = received / total);
          }
        },
        onDone: () async {
          await sink.close();
          client.close();
          if (mounted) {
            setState(() => _downloading = false);
            try {
              final result = await OpenFilex.open(file.path);
              if (result.type != ResultType.done) {
                setState(() => _downloadError = '无法打开安装器（${result.message}），请在文件管理器中手动安装:\n${file.path}');
              }
            } catch (_) {
              setState(() => _downloadError = '无法打开安装器，请在文件管理器中手动安装:\n${file.path}');
            }
          }
        },
        onError: (e) {
          sink.close();
          client.close();
          if (mounted) setState(() { _downloading = false; _downloadError = '下载失败: $e'; });
        },
        cancelOnError: true,
      ).asFuture();
    } catch (e) {
      if (mounted) setState(() { _downloading = false; _downloadError = '$e'; });
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
          const SizedBox(height: 16),
          Container(
            width: 80, height: 80,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _primary.withAlpha(30),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(Icons.phone_android, size: 40, color: _primary),
          ),
          const SizedBox(height: 20),
          const Text('DSH Mobile', textAlign: TextAlign.center, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('版本 $_currentVersion', textAlign: TextAlign.center, style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          Text('DeepSeek Harness 手机端', textAlign: TextAlign.center, style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 32),

          // 检查更新
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _checking ? null : _checkUpdate,
              icon: _checking ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.system_update),
              label: Text(_checking ? '检查中…' : '检查更新'),
            ),
          ),
          const SizedBox(height: 16),

          if (_error != null) ...[
            Card(
              color: theme.colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  Icon(Icons.error_outline, color: theme.colorScheme.error),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_error!, style: TextStyle(color: theme.colorScheme.error))),
                ]),
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
                    Row(children: [
                      Icon(Icons.new_releases, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text('新版本可用：$_latestVersion', style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.primary)),
                    ]),
                    const SizedBox(height: 12),
                    // 下载进度
                    if (_downloading) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(value: _downloadProgress, minHeight: 8),
                      ),
                      const SizedBox(height: 8),
                      Text('下载中 ${(_downloadProgress * 100).toInt()}%', style: const TextStyle(fontSize: 12)),
                      const SizedBox(height: 12),
                    ],
                    if (_downloadError != null) ...[
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(_downloadError!, style: TextStyle(color: theme.colorScheme.error, fontSize: 12)),
                      ),
                    ],
                    // 下载并安装按钮
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _downloading ? null : _downloadAndInstall,
                        icon: const Icon(Icons.download),
                        label: const Text('下载并安装'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // 备用：浏览器打开
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          if (_latestUrl != null) launchUrl(Uri.parse(_latestUrl!), mode: LaunchMode.externalApplication);
                        },
                        icon: const Icon(Icons.open_in_browser),
                        label: const Text('在浏览器中打开'),
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
                child: Row(children: [
                  Icon(Icons.check_circle, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  const Text('已是最新版本'),
                ]),
              ),
            ),
          ] else if (_noRelease) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  Icon(Icons.info_outline, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 8),
                  const Text('暂无发布版本'),
                ]),
              ),
            ),
          ],
        ],
      ),
    );
  }
}