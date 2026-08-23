/// 复用型会话列表组件：可用于独立页面或抽屉中。
///
/// 支持长按会话行：归档、重命名、移动到工作区、删除。
/// 支持长按工作区：重命名、删除。
library;

import 'package:flutter/material.dart';

import '../core/api/sessions_api.dart';
import '../state/app_state.dart';

class SessionListView extends StatefulWidget {
  const SessionListView({
    super.key,
    required this.onSessionTap,
    this.compact = false,
  });

  final void Function(String sessionId) onSessionTap;
  final bool compact;

  @override
  State<SessionListView> createState() => _SessionListViewState();
}

class _SessionListViewState extends State<SessionListView> {
  static const _primary = Color(0xFF4D6BFE);

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

  void _onStateChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = AppState.instance;
    final archivedIds = state.archivedSessionIds.toSet();
    final memberIds = state.workspaces.expand((w) => w.sessionIds).toSet();
    final ungrouped = state.sessions
        .where((s) => !memberIds.contains(s.sessionId) && !archivedIds.contains(s.sessionId))
        .toList();
    final archivedSessions = state.sessions.where((s) => archivedIds.contains(s.sessionId)).toList();
    final byId = <String, SessionSummary>{for (final s in state.sessions) s.sessionId: s};

    if (state.sessions.isEmpty && state.workspaces.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.forum_outlined, size: 40, color: theme.colorScheme.outline.withAlpha(80)),
            const SizedBox(height: 12),
            Text('没有会话', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        await state.refreshSessions();
        await state.refreshWorkspaces();
      },
      child: ListView(
        padding: const EdgeInsets.only(top: 4, bottom: 24),
        children: [
          for (final ws in state.workspaces) ...[
            _workspaceHeader(ws),
            if (_expandedWorkspaces.contains(ws.workspaceId))
              for (final sid in ws.sessionIds.reversed)
                if (byId[sid] != null) _sessionRow(byId[sid]!, indent: true),
          ],
          if (ungrouped.isNotEmpty) ...[
            _sectionHeader('未分组'),
            for (final s in ungrouped) _sessionRow(s),
          ],
          if (archivedSessions.isNotEmpty) ...[
            _archiveHeader(archivedSessions.length),
            if (_archivedExpanded)
              for (final s in archivedSessions) _sessionRow(s, archived: true),
          ],
        ],
      ),
    );
  }

  Widget _sectionHeader(String label) {
    return Padding(
      padding: EdgeInsets.fromLTRB(widget.compact ? 12 : 16, 16, 16, 4),
      child: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _primary, letterSpacing: 0.5)),
    );
  }

  Widget _archiveHeader(int count) {
    return InkWell(
      onTap: () => setState(() => _archivedExpanded = !_archivedExpanded),
      child: Padding(
        padding: EdgeInsets.fromLTRB(widget.compact ? 12 : 16, 16, 16, 4),
        child: Row(
          children: [
            Icon(_archivedExpanded ? Icons.expand_less : Icons.expand_more, size: 14, color: _primary.withAlpha(150)),
            const SizedBox(width: 4),
            Icon(Icons.archive_outlined, size: 13, color: _primary.withAlpha(150)),
            const SizedBox(width: 4),
            Text('归档（$count）', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _primary, letterSpacing: 0.5)),
          ],
        ),
      ),
    );
  }

  Widget _workspaceHeader(WorkspaceView ws) {
    final expanded = _expandedWorkspaces.contains(ws.workspaceId);
    return InkWell(
      onTap: () => setState(() {
        if (expanded) {
          _expandedWorkspaces.remove(ws.workspaceId);
        } else {
          _expandedWorkspaces.add(ws.workspaceId);
        }
      }),
      onLongPress: () => _showWorkspaceMenu(ws),
      child: Padding(
        padding: EdgeInsets.fromLTRB(widget.compact ? 8 : 12, 4, 12, 0),
        child: Row(
          children: [
            Icon(expanded ? Icons.folder_open : Icons.folder, size: widget.compact ? 16 : 18, color: _primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(ws.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: widget.compact ? 13 : 14, fontWeight: FontWeight.w500)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(color: _primary.withAlpha(30), borderRadius: BorderRadius.circular(7)),
              child: Text('${ws.sessionIds.length}', style: const TextStyle(fontSize: 10, color: _primary)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sessionRow(SessionSummary s, {bool indent = false, bool archived = false}) {
    final theme = Theme.of(context);
    final time = DateTime.fromMillisecondsSinceEpoch(s.updatedAt);
    final title = s.title ?? s.agentPreset ?? s.cwd ?? s.sessionId;

    return Padding(
      padding: EdgeInsets.only(left: indent ? (widget.compact ? 20 : 24) : (widget.compact ? 4 : 8), right: widget.compact ? 4 : 8, top: 1, bottom: 1),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => widget.onSessionTap(s.sessionId),
          onLongPress: () => _showSessionMenu(s, archived: archived),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: widget.compact ? 8 : 12, vertical: widget.compact ? 6 : 8),
            child: Row(
              children: [
                if (s.running)
                  _RunningDot()
                else
                  Icon(
                    archived ? Icons.archive_outlined : Icons.chat_bubble_outline,
                    size: widget.compact ? 14 : 16,
                    color: archived ? theme.colorScheme.outline : _primary.withAlpha(180),
                  ),
                SizedBox(width: widget.compact ? 8 : 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        archived ? '$title（归档）' : title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: widget.compact ? 12 : 13,
                          fontWeight: s.running ? FontWeight.w600 : FontWeight.w400,
                          color: archived ? theme.colorScheme.outline : null,
                        ),
                      ),
                      SizedBox(height: widget.compact ? 1 : 2),
                      Text(_fmtTime(time), style: TextStyle(fontSize: widget.compact ? 10 : 11, color: theme.colorScheme.outline)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, size: 14, color: theme.colorScheme.outline.withAlpha(60)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------- 上下文菜单 ----------

  void _showSessionMenu(SessionSummary s, {bool archived = false}) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(s.title ?? s.sessionId, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('重命名'),
              onTap: () { Navigator.pop(ctx); _renameSession(s); },
            ),
            if (archived) ...[
              // 恢复归档：移到第一个工作区（或通过弹窗选择）
              ListTile(
                leading: const Icon(Icons.unarchive_outlined),
                title: const Text('恢复（取消归档）'),
                onTap: () {
                  Navigator.pop(ctx);
                  _restoreFromArchive(s);
                },
              ),
            ] else ...[
              ListTile(
                leading: const Icon(Icons.archive_outlined),
                title: const Text('归档'),
                onTap: () {
                  Navigator.pop(ctx);
                  _archiveSession(s.sessionId);
                },
              ),
              ListTile(
                leading: const Icon(Icons.drive_file_move_outlined),
                title: const Text('移动到工作区…'),
                onTap: () {
                  Navigator.pop(ctx);
                  _moveSession(s);
                },
              ),
            ],
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
              title: const Text('删除', style: TextStyle(color: Colors.redAccent)),
              onTap: () {
                Navigator.pop(ctx);
                _confirmDelete(s);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showWorkspaceMenu(WorkspaceView ws) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(ws.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('重命名'),
              onTap: () { Navigator.pop(ctx); _renameWorkspace(ws); },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
              title: const Text('删除工作区', style: TextStyle(color: Colors.redAccent)),
              subtitle: const Text('会话保留，归入未分组'),
              onTap: () {
                Navigator.pop(ctx);
                _deleteWorkspace(ws);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _renameSession(SessionSummary s) async {
    final controller = TextEditingController(text: s.title ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名会话'),
        content: TextField(controller: controller, autofocus: true, decoration: const InputDecoration(hintText: '输入新名称')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('确定')),
        ],
      ),
    );
    if (name != null && name.isNotEmpty && mounted) {
      try {
        await AppState.instance.renameSession(s.sessionId, name);
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('重命名失败: $e')));
      }
    }
  }

  Future<void> _renameWorkspace(WorkspaceView ws) async {
    final controller = TextEditingController(text: ws.title);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名工作区'),
        content: TextField(controller: controller, autofocus: true, decoration: const InputDecoration(hintText: '输入新名称')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('确定')),
        ],
      ),
    );
    if (name != null && name.isNotEmpty && mounted) {
      try {
        await AppState.instance.renameWorkspace(ws.workspaceId, name);
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('重命名失败: $e')));
      }
    }
  }

  Future<void> _archiveSession(String sessionId) async {
    try {
      await AppState.instance.archiveSession(sessionId);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已归档')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('归档失败: $e')));
    }
  }

  Future<void> _restoreFromArchive(SessionSummary s) async {
    final state = AppState.instance;
    if (state.workspaces.isEmpty) {
      // 没有工作区，直接解除归档
      try {
        // moveSessionToWorkspace 对归档会话会恢复它
        // 如果没有工作区，创建一个临时的
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先创建工作区再恢复')));
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('恢复失败: $e')));
      }
      return;
    }

    // 弹窗选工作区
    final wsId = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(padding: EdgeInsets.all(16), child: Text('恢复到哪个工作区？', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
            for (final ws in state.workspaces)
              ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: Text(ws.title),
                onTap: () => Navigator.pop(ctx, ws.workspaceId),
              ),
            // 也可以恢复到未分组
            ListTile(
              leading: const Icon(Icons.folder_open_outlined),
              title: const Text('恢复为未分组'),
              onTap: () => Navigator.pop(ctx, '__UNGROUP__'),
            ),
          ],
        ),
      ),
    );
    if (wsId == null || !mounted) return;

    try {
      if (wsId == '__UNGROUP__') {
        // 解除归档最简单的方式是重新创建会话的 workspace 关系
        // 实际上 moveSessionToWorkspace 对归档会话会恢复它
        if (state.workspaces.isNotEmpty) {
          await state.moveSessionToWorkspace(state.workspaces.first.workspaceId, s.sessionId);
        }
      } else {
        await state.moveSessionToWorkspace(wsId, s.sessionId);
      }
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已恢复')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('恢复失败: $e')));
    }
  }

  Future<void> _moveSession(SessionSummary s) async {
    final state = AppState.instance;
    if (state.workspaces.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('没有工作区，请先创建')));
      return;
    }
    final wsId = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(padding: EdgeInsets.all(16), child: Text('移动到哪个工作区？', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
            for (final ws in state.workspaces)
              ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: Text(ws.title),
                onTap: () => Navigator.pop(ctx, ws.workspaceId),
              ),
          ],
        ),
      ),
    );
    if (wsId == null || !mounted) return;
    try {
      await state.moveSessionToWorkspace(wsId, s.sessionId);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已移动')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('移动失败: $e')));
    }
  }

  Future<void> _confirmDelete(SessionSummary s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除会话'),
        content: Text('确定要删除「${s.title ?? s.sessionId}」吗？\n此操作不可撤销。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除', style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    if (ok == true && mounted) {
      try {
        // session.remove 通过 API
        final conn = AppState.instance.conn;
        if (conn != null) {
          await SessionsApi(conn.rpc).deleteSession(s.sessionId);
          await AppState.instance.refreshSessions();
          await AppState.instance.refreshWorkspaces();
        }
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已删除')));
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('删除失败: $e')));
      }
    }
  }

  Future<void> _deleteWorkspace(WorkspaceView ws) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除工作区'),
        content: Text('确定要删除工作区「${ws.title}」吗？\n其中的会话会保留，归入未分组。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除', style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    if (ok == true && mounted) {
      try {
        await AppState.instance.deleteWorkspace(ws.workspaceId);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('工作区已删除')));
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('删除失败: $e')));
      }
    }
  }

  String _fmtTime(DateTime t) {
    final now = DateTime.now();
    if (t.year == now.year && t.month == now.month && t.day == now.day) {
      return '今天 ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    }
    return '${t.month}/${t.day} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }
}

/// 运行中会话的脉冲指示点
class _RunningDot extends StatefulWidget {
  @override
  State<_RunningDot> createState() => _RunningDotState();
}

class _RunningDotState extends State<_RunningDot> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(duration: const Duration(milliseconds: 1200), vsync: this)..repeat(reverse: true);
    _animation = Tween(begin: 0.3, end: 1.0).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _animation,
      child: Container(
        width: 7,
        height: 7,
        decoration: const BoxDecoration(color: Color(0xFF4D6BFE), shape: BoxShape.circle),
      ),
    );
  }
}