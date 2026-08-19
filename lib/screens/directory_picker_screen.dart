/// 目录选择页：浏览电脑上的目录（host.listDirectory），选中后返回路径。
///
/// 返回方式：Navigator.pop(context, 选中的路径字符串)；取消返回 null。
library;

import 'package:flutter/material.dart';

import '../core/api/sessions_api.dart';
import '../state/app_state.dart';

class DirectoryPickerScreen extends StatefulWidget {
  const DirectoryPickerScreen({super.key});

  @override
  State<DirectoryPickerScreen> createState() => _DirectoryPickerScreenState();
}

class _DirectoryPickerScreenState extends State<DirectoryPickerScreen> {
  DirectoryListing? _listing;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load(null);
  }

  Future<void> _load(String? path) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final conn = AppState.instance.conn;
      if (conn == null) throw StateError('未连接');
      final api = SessionsApi(conn.rpc);
      final listing = await api.listDirectory(path: path);
      setState(() => _listing = listing);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      setState(() => _loading = false);
    }
  }

  /// 在电脑上弹系统文件夹选择框（需要人在电脑前）。
  Future<void> _pickOnComputer() async {
    try {
      final conn = AppState.instance.conn;
      if (conn == null) throw StateError('未连接');
      final api = SessionsApi(conn.rpc);
      final path = await api.pickDirectory();
      if (!mounted) return;
      if (path != null && path.isNotEmpty) {
        Navigator.pop(context, path);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('未选择目录')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('选择失败: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final listing = _listing;
    return Scaffold(
      appBar: AppBar(
        title: const Text('选择工作目录'),
        actions: [
          IconButton(
            icon: const Icon(Icons.desktop_windows_outlined),
            tooltip: '在电脑上弹框选择',
            onPressed: _pickOnComputer,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_loading) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: _error != null
                  ? Center(child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)))
                  : listing == null
                      ? const Center(child: CircularProgressIndicator())
                      : _buildListing(listing),
            ),
            if (listing != null && !_loading)
              Padding(
                padding: const EdgeInsets.all(12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    icon: const Icon(Icons.check),
                    label: Text('使用此目录\n${listing.path}', textAlign: TextAlign.center),
                    onPressed: () => Navigator.pop(context, listing.path),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildListing(DirectoryListing listing) {
    final theme = Theme.of(context);
    return ListView(
      children: [
        // 面包屑
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Wrap(
            spacing: 4,
            children: [
              ...listing.crumbs.map((c) => ActionChip(
                    label: Text(c.name, style: theme.textTheme.labelSmall),
                    onPressed: () => _load(c.path),
                  )),
            ],
          ),
        ),
        if (listing.truncated)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text('目录项过多，已截断显示', style: theme.textTheme.bodySmall),
          ),
        ...listing.entries.where((e) => !e.hidden).map(
              (e) => ListTile(
                dense: true,
                leading: const Icon(Icons.folder_outlined),
                title: Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: const Icon(Icons.chevron_right, size: 18),
                onTap: () => _load(e.path),
              ),
            ),
      ],
    );
  }
}
