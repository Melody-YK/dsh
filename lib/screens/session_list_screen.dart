/// 会话列表页：工作区（文件夹）树 + 未分组 + 归档区，对齐 Web 端。
///
/// - 工作区可折叠/展开，长按可重命名/删除
/// - 会话长按可重命名/归档/移动到工作区
/// - 归档会话可恢复到工作区
library;

import 'package:flutter/material.dart';

import '../core/protocol/connection.dart';
import '../core/api/sessions_api.dart';
import '../state/app_state.dart';
import 'directory_picker_screen.dart';

class SessionListScreen extends StatefulWidget {
  const SessionListScreen({super.key});

  @override
  State<SessionListScreen> createState() => _SessionListScreenState();
}

class _SessionListScreenState extends State<SessionListScreen> {
  bool _creating = false;
  final Set<String> _expandedWorkspaces = {};
  bool _archivedExpanded = false;

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
      if (!mounted) return;
      Navigator.of(context).pushNamed('/chat', arguments: id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('创建会话失败: $e')));
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  // ---------- 新建工作区 ----------

  Future<void> _createWorkspace() async {
    final path = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const DirectoryPickerScreen()),
    );
    if (path == null || !mounted) return;
    try {
      await AppState.instance.createWorkspace(path);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('工作区已创建')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('创建工作区失败: $e')));
    }
  }

  // ---------- 工作区操作 ----------

  Future<void> _workspaceMenu(WorkspaceView ws) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(ws.title, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(ws.path, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline),
              title: const Text('重命名'),
              onTap: () => Navigator.pop(ctx, 'rename'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('删除（会话保留，归入未分组）'),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;

    try {
      if (action == 'rename') {
        final title = await _promptText('重命名工作区', initial: ws.title);
        if (title != null && title.isNotEmpty) {
          await AppState.instance.renameWorkspace(ws.workspaceId, title);
        }
      } else if (action == 'delete') {
        final ok = await _confirm('删除工作区', '删除「${ws.title}」？其中的会话会保留并归入未分组。');
        if (ok) await AppState.instance.deleteWorkspace(ws.workspaceId);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('操作失败: $e')));
    }
  }

  // ---------- 会话操作 ----------

  Future<void> _sessionMenu(SessionSummary s, {bool archived = false}) async {
    final actions = <String>[
      'rename',
      if (!archived) 'archive',
      'move',
      if (archived) 'unarchive',
    ];
    final labels = <String, String>{
      'rename': '重命名',
      'archive': '归档',
      'move': '移动到工作区',
      'unarchive': '恢复到工作区',
    };
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(s.title ?? s.sessionId, style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            const Divider(height: 1),
            for (final a in actions)
              ListTile(
                leading: Icon(
                  a == 'rename'
                      ? Icons.drive_file_rename_outline
                      : a == 'archive'
                          ? Icons.archive_outlined
                          : a == 'unarchive'
                              ? Icons.unarchive_outlined
                              : Icons.drive_file_move_outline,
                ),
                title: Text(labels[a]!),
                onTap: () => Navigator.pop(ctx, a),
              ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;

    try {
      switch (action) {
        case 'rename':
          final title = await _promptText('重命名会话', initial: s.title ?? '');
          if (title != null && title.isNotEmpty) {
            await AppState.instance.renameSession(s.sessionId, title);
          }
        case 'archive':
          await AppState.instance.archiveSession(s.sessionId);
        case 'move':
        case 'unarchive':
          final ws = await _pickWorkspace();
          if (ws != null) {
            await AppState.instance.moveSessionToWorkspace(ws.workspaceId, s.sessionId);
          }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('操作失败: $e')));
    }
  }

  /// 弹出一个工作区选择列表，返回选中项。
  Future<WorkspaceView?> _pickWorkspace() async {
    final state = AppState.instance;
    if (state.workspaces.isEmpty) {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('还没有工作区，先新建一个')));
      return null;
    }
    return showModalBottomSheet<WorkspaceView>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('选择工作区', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final ws in state.workspaces)
                    ListTile(
                      leading: const Icon(Icons.folder_outlined),
                      title: Text(ws.title),
                      subtitle: Text(ws.path, maxLines: 1, overflow: TextOverflow.ellipsis),
                      onTap: () => Navigator.pop(ctx, ws),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 文本输入对话框。
  Future<String?> _promptText(String title, {String initial = ''}) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('确定')),
        ],
      ),
    );
  }

  /// 确认对话框。
  Future<bool> _confirm(String title, String message) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确定')),
        ],
      ),
    );
    return ok ?? false;
  }

  void _openSession(String sessionId) async {
    await AppState.instance.saveLastSession(sessionId);
    if (!mounted) return;
    Navigator.of(context).pushNamed('/chat', arguments: sessionId);
  }

  @override
  Widget build(BuildContext context) {
    final state = AppState.instance;
    final theme = Theme.of(context);

    // 会话归属：工作区成员 / 未分组 / 归档
    final memberIds = <String>{for (final ws in state.workspaces) ...ws.sessionIds};
    final archivedIds = state.archivedSessionIds.toSet();
    final ungrouped = state.sessions
        .where((s) => !memberIds.contains(s.sessionId) && !archivedIds.contains(s.sessionId))
        .toList();
    final archivedSessions = state.sessions.where((s) => archivedIds.contains(s.sessionId)).toList();
    final byId = <String, SessionSummary>{for (final s in state.sessions) s.sessionId: s};

    return Scaffold(
      appBar: AppBar(
        title: const Text('会话'),
        actions: [
          IconButton(
            icon: const Icon(Icons.dns_outlined),
            tooltip: '服务地址',
            onPressed: () => Navigator.of(context).pushNamed('/config'),
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
        onPressed: _creating ? null : () => _showAddMenu(),
        tooltip: '新建',
        child: _creating
            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.add),
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (state.connectionState == DshConnectionState.reconnecting ||
                state.connectionState == DshConnectionState.connecting)
              LinearProgressIndicator(minHeight: 2, backgroundColor: theme.colorScheme.surfaceContainerHighest),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  await state.refreshSessions();
                  await state.refreshWorkspaces();
                },
                child: state.sessions.isEmpty && state.workspaces.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          const SizedBox(height: 120),
                          Icon(Icons.forum_outlined, size: 56, color: theme.colorScheme.outline),
                          const SizedBox(height: 12),
                          Center(child: Text('没有会话', style: theme.textTheme.bodyMedium)),
                        ],
                      )
                    : ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          // ---- 工作区树 ----
                          for (final ws in state.workspaces) ...[
                            _workspaceHeader(ws),
                            if (_expandedWorkspaces.contains(ws.workspaceId))
                              for (final sid in ws.sessionIds.reversed)
                                if (byId[sid] != null)
                                  _sessionRow(byId[sid]!, indent: true),
                          ],
                          // ---- 未分组 ----
                          if (ungrouped.isNotEmpty) ...[
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                              child: Text(
                                '未分组',
                                style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.outline),
                              ),
                            ),
                            for (final s in ungrouped) _sessionRow(s),
                          ],
                          // ---- 归档 ----
                          if (archivedSessions.isNotEmpty) ...[
                            InkWell(
                              onTap: () => setState(() => _archivedExpanded = !_archivedExpanded),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                                child: Row(
                                  children: [
                                    Icon(
                                      _archivedExpanded ? Icons.expand_less : Icons.expand_more,
                                      size: 16,
                                      color: theme.colorScheme.outline,
                                    ),
                                    const SizedBox(width: 4),
                                    Icon(Icons.archive_outlined, size: 16, color: theme.colorScheme.outline),
                                    const SizedBox(width: 4),
                                    Text(
                                      '归档（${archivedSessions.length}）',
                                      style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.outline),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            if (_archivedExpanded)
                              for (final s in archivedSessions) _sessionRow(s, archived: true),
                          ],
                          const SizedBox(height: 88),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
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
      if (v == 'session') {
        _createSession();
      } else if (v == 'workspace') {
        _createWorkspace();
      }
    });
  }

  /// 工作区标题行（可折叠 + 长按菜单）。
  Widget _workspaceHeader(WorkspaceView ws) {
    final theme = Theme.of(context);
    final expanded = _expandedWorkspaces.contains(ws.workspaceId);
    return InkWell(
      onTap: () => setState(() {
        if (expanded) {
          _expandedWorkspaces.remove(ws.workspaceId);
        } else {
          _expandedWorkspaces.add(ws.workspaceId);
        }
      }),
      onLongPress: () => _workspaceMenu(ws),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: Row(
          children: [
            Icon(
              expanded ? Icons.folder_open : Icons.folder,
              size: 20,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                ws.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall,
              ),
            ),
            Text(
              '${ws.sessionIds.length}',
              style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline),
            ),
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'rename' || v == 'delete') _workspaceMenu(ws);
              },
              itemBuilder: (ctx) => const [
                PopupMenuItem(value: 'rename', child: Text('重命名')),
                PopupMenuItem(value: 'delete', child: Text('删除')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 会话行（indent 缩进显示在工作区下）。
  Widget _sessionRow(SessionSummary s, {bool indent = false, bool archived = false}) {
    final theme = Theme.of(context);
    final time = DateTime.fromMillisecondsSinceEpoch(s.updatedAt);
    final title = s.title ?? s.agentPreset ?? s.cwd ?? s.sessionId;

    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.only(left: indent ? 36 : 16, right: 8),
      leading: CircleAvatar(
        radius: 14,
        backgroundColor: s.running ? theme.colorScheme.primaryContainer : theme.colorScheme.surfaceContainerHighest,
        child: s.running
            ? const Icon(Icons.auto_awesome, size: 14)
            : archived
                ? const Icon(Icons.archive_outlined, size: 14)
                : const Icon(Icons.chat_bubble_outline, size: 14),
      ),
      title: Text(
        archived ? '$title（归档）' : title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyMedium?.copyWith(color: archived ? theme.colorScheme.outline : null),
      ),
      subtitle: Text(_fmtTime(time), style: theme.textTheme.bodySmall),
      trailing: s.running
          ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))
          : null,
      onTap: () => _openSession(s.sessionId),
      onLongPress: () => _sessionMenu(s, archived: archived),
    );
  }

  String _fmtTime(DateTime t) {
    final now = DateTime.now();
    if (t.year == now.year && t.month == now.month && t.day == now.day) {
      return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    }
    return '${t.month}/${t.day}';
  }
}
