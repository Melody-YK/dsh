/// 复用型会话列表组件：可用于独立页面或抽屉中。
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