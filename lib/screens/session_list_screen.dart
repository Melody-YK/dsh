/// 会话列表页：工作区（文件夹）树 + 未分组 + 归档区，对齐 Web 端。
library;

import 'package:flutter/material.dart';

import '../core/protocol/connection.dart';
import '../state/app_state.dart';
import '../widgets/session_list_view.dart';
import 'directory_picker_screen.dart';

class SessionListScreen extends StatefulWidget {
  const SessionListScreen({super.key});

  @override
  State<SessionListScreen> createState() => _SessionListScreenState();
}

class _SessionListScreenState extends State<SessionListScreen> {
  bool _creating = false;

  static const _primary = Color(0xFF4D6BFE);

  @override
  void initState() {
    super.initState();
    final state = AppState.instance;
    state.addListener(_onStateChanged);
    if (state.conn != null) {
      state.refreshSessions();
      state.refreshWorkspaces();
    }
  }

  @override
  void dispose() {
    AppState.instance.removeListener(_onStateChanged);
    super.dispose();
  }

  void _onStateChanged() {
    if (!mounted) return;
    setState(() {});
    if (AppState.instance.connectionState == DshConnectionState.disconnected &&
        AppState.instance.isConfigured == false) {
      Navigator.of(context).pushReplacementNamed('/config');
    }
  }

  // ---------- 新建会话 ----------

  Future<void> _createSession() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('新建会话', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
            ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: const Text('默认工作区'),
              subtitle: const Text('使用 DSH 默认目录'),
              onTap: () => Navigator.pop(ctx, ''),
            ),
            ListTile(
              leading: const Icon(Icons.folder_open_outlined),
              title: const Text('选择目录…'),
              subtitle: const Text('浏览电脑上的文件夹'),
              onTap: () => Navigator.pop(ctx, '__PICK__'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;

    setState(() => _creating = true);
    try {
      String? pickedCwd;
      if (choice == '__PICK__') {
        pickedCwd = await Navigator.of(context).push<String>(
          MaterialPageRoute(builder: (_) => const DirectoryPickerScreen()),
        );
        if (pickedCwd == null) {
          setState(() => _creating = false);
          return;
        }
      } else if (choice.isNotEmpty) {
        pickedCwd = choice;
      }
      final id = await AppState.instance.createSession(cwd: pickedCwd);
      if (!mounted) return;
      await AppState.instance.saveLastSession(id);
      _openSession(id);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('新建失败: $e')));
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _createWorkspace() async {
    final path = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const DirectoryPickerScreen()),
    );
    if (path == null || !mounted) return;
    try {
      await AppState.instance.createWorkspace(path);
      await AppState.instance.refreshWorkspaces();
      await AppState.instance.refreshSessions();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('创建工作区失败: $e')));
    }
  }

  void _openSession(String id) {
    Navigator.of(context).pushNamed('/chat', arguments: id);
  }

  void _showAddMenu() {
    showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.add_comment_outlined),
              title: const Text('新建会话'),
              onTap: () => Navigator.pop(ctx, 'session'),
            ),
            ListTile(
              leading: const Icon(Icons.create_new_folder_outlined),
              title: const Text('新建工作区（选目录）'),
              onTap: () => Navigator.pop(ctx, 'workspace'),
            ),
          ],
        ),
      ),
    ).then((v) {
      if (v == 'session') _createSession();
      if (v == 'workspace') _createWorkspace();
    });
  }

  // ---------- 渲染 ----------

  @override
  Widget build(BuildContext context) {
    final state = AppState.instance;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: _primary.withAlpha(30),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.auto_awesome, size: 16, color: _primary),
            ),
            const SizedBox(width: 10),
            const Text('DSH Mobile', style: TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined, size: 20),
            tooltip: '设置',
            onPressed: () => Navigator.of(context).pushNamed('/settings'),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'disconnect') {
                AppState.instance.disconnect();
                Navigator.of(context).pushReplacementNamed('/config');
              } else if (v == 'about') {
                Navigator.of(context).pushNamed('/about');
              }
            },
            itemBuilder: (ctx) => const [
              PopupMenuItem(value: 'about', child: Text('关于')),
              PopupMenuItem(value: 'disconnect', child: Text('断开连接')),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _creating ? null : _showAddMenu,
        child: _creating
            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.add),
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (state.connectionState == DshConnectionState.reconnecting ||
                state.connectionState == DshConnectionState.connecting)
              const LinearProgressIndicator(minHeight: 2, backgroundColor: Colors.transparent),
            Expanded(
              child: SessionListView(
                onSessionTap: (id) => _openSession(id),
              ),
            ),
          ],
        ),
      ),
    );
  }}
