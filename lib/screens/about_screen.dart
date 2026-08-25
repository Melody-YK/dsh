/// 关于页：版本信息 + 检查更新 + 历史版本回退 + App 内下载安装。
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
  static const _currentVersion = '0.5.1';
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
  String? _downloadingVersion;

  // 历史版本列表
  List<_ReleaseInfo> _releases = [];
  bool _loadingReleases = false;

  @override
  void initState() {
    super.initState();
    _loadReleases();
  }

  Future<void> _loadReleases() async {
    setState(() => _loadingReleases = true);
    try {
      final response = await http.get(
        Uri.parse('https://api.github.com/repos/$_repoOwner/$_repoName/releases?per_page=20'),
        headers: {'Accept': 'application/vnd.github+json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final list = json.decode(response.body) as List;
        final releases = <_ReleaseInfo>[];
        for (final item in list) {
          final m = item as Map<String, dynamic>;
          final tag = (m['tag_name'] as String?)?.replaceFirst(RegExp(r'^v'), '') ?? '?';
          final htmlUrl = m['html_url'] as String?;
          final assets = (m['assets'] as List?) ?? [];
          String? apkUrl;
          for (final a in assets) {
            if ((a as Map)['name'] == 'app-release.apk') {
              apkUrl = a['browser_download_url'] as String?;
              break;
            }
          }
          releases.add(_ReleaseInfo(version: tag, url: htmlUrl ?? '', apkUrl: apkUrl));
        }
        if (mounted) setState(() { _releases = releases; _loadingReleases = false; });
      } else {
        if (mounted) setState(() => _loadingReleases = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loadingReleases = false);
    }
  }

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

  Future<void> _downloadAndInstall(String url, String version) async {
    setState(() {
      _downloading = true;
      _downloadingVersion = version;
      _downloadProgress = 0;
      _downloadError = null;
    });

    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/dsh-mobile-$version.apk');
      final client = http.Client();
      final request = http.Request('GET', Uri.parse(url));
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
                    if (_downloading && _downloadingVersion == _latestVersion) ...[
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
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: (_downloading || _downloadUrl == null) ? null : () => _downloadAndInstall(_downloadUrl!, _latestVersion!),
                        icon: const Icon(Icons.download),
                        label: const Text('下载并安装'),
                      ),
                    ),
                    const SizedBox(height: 8),
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

          // 历史版本（回退）
          const SizedBox(height: 32),
          Row(
            children: [
              const Icon(Icons.history, size: 18, color: _primary),
              const SizedBox(width: 8),
              Text('历史版本', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurface)),
              const Spacer(),
              if (_loadingReleases)
                const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          ),
          const SizedBox(height: 8),
          if (_releases.isEmpty && !_loadingReleases)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text('暂无历史版本', style: TextStyle(color: theme.colorScheme.outline, fontSize: 13)),
            ),
          for (final r in _releases) ...[
            _buildReleaseRow(r, theme),
            const SizedBox(height: 4),
          ],
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildReleaseRow(_ReleaseInfo r, ThemeData theme) {
    final isCurrent = r.version == _currentVersion;
    final isDownloading = _downloading && _downloadingVersion == r.version;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Icon(
              isCurrent ? Icons.check_circle : Icons.circle_outlined,
              size: 16,
              color: isCurrent ? _primary : theme.colorScheme.outline,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'v${r.version}${isCurrent ? '（当前）' : ''}',
                style: TextStyle(
                  fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
                  color: isCurrent ? _primary : null,
                ),
              ),
            ),
            if (isDownloading)
              SizedBox(
                width: 100,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(value: _downloadProgress, minHeight: 4),
                ),
              )
            else if (!isCurrent && r.apkUrl != null)
              TextButton.icon(
                onPressed: _downloading ? null : () => _downloadAndInstall(r.apkUrl!, r.version),
                icon: const Icon(Icons.download, size: 16),
                label: const Text('安装', style: TextStyle(fontSize: 13)),
              )
            else if (!isCurrent && r.apkUrl == null)
              TextButton(
                onPressed: () => launchUrl(Uri.parse(r.url), mode: LaunchMode.externalApplication),
                child: const Text('查看', style: TextStyle(fontSize: 13)),
              ),
          ],
        ),
      ),
    );
  }
}

class _ReleaseInfo {
  _ReleaseInfo({required this.version, required this.url, this.apkUrl});
  final String version;
  final String url;
  final String? apkUrl;
}