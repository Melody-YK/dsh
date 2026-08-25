/// 全局状态：服务地址、连接生命周期、会话列表。
///
/// 单例 [AppState.of(context)] 获取。连接成功/失败、host 流事件都会刷新
/// [sessions]，UI 用 [ListenableBuilder] / AnimatedBuilder 订阅。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../core/api/sessions_api.dart';
import '../core/protocol/connection.dart';
import '../core/protocol/host_frame.dart';
import '../core/protocol/rpc_client.dart';
import '../main.dart';
import '../navigation.dart';

class AppState extends ChangeNotifier {
  AppState._();

  static final AppState instance = AppState._();

  static const _prefBase = 'dsh_mobile.base';
  static const _prefLastSession = 'dsh_mobile.last_session';

  /// 服务地址（http://host:port），未配置为空。
  String baseUrl = '';

  DshConnection? _conn;
  DshConnection? get conn => _conn;

  /// 会话列表（按 updatedAt 倒序）。
  List<SessionSummary> sessions = [];
  List<SessionSummary> get runningSessions => sessions.where((s) => s.running).toList();

  /// 工作区（文件夹）列表。
  List<WorkspaceView> workspaces = [];

  /// 已归档的会话 id。
  List<String> archivedSessionIds = [];

  /// 工作区列表是否已加载。
  bool get workspacesLoaded => workspaces.isNotEmpty || _workspacesLoaded;
  bool _workspacesLoaded = false;

  DshConnectionState get connectionState => _conn?.state ?? DshConnectionState.disconnected;
  HostDescribe? get describe => _conn?.describe;

  /// 连接失败/重连时的提示信息。
  String? lastError;
  int reconnectAttempt = 0;

  bool get isConfigured => baseUrl.isNotEmpty;

  /// 启动时从本地恢复配置。
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    baseUrl = prefs.getString(_prefBase) ?? '';
    notifyListeners();
  }

  Future<String?> loadLastSession() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefLastSession);
  }

  Future<void> saveLastSession(String sessionId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefLastSession, sessionId);
  }

  /// 设置服务地址并连接（已连接则先断开）。
  Future<void> configureAndConnect(String raw) async {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || uri.host.isEmpty) {
      throw ArgumentError('地址格式不正确，示例：http://192.168.1.5:3080');
    }
    final normalized = RpcClient.normalizeBase(raw);
    baseUrl = normalized.toString();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefBase, baseUrl);

    disconnect();
    final conn = DshConnection(normalized);
    _conn = conn;
    _bind(conn);
    conn.start();
    notifyListeners();
  }

  void _bind(DshConnection conn) {
    conn.onConnected = (describe) {
      lastError = null;
      reconnectAttempt = 0;
      notifyListeners();
      refreshSessions();
      refreshWorkspaces();
    };
    conn.onReconnecting = (attempt) {
      reconnectAttempt = attempt;
      lastError = '连接断开，正在重连（第 $attempt 次）…';
      notifyListeners();
    };
    conn.onHostFrame = (frame) {
      switch (frame) {
        case SessionAddedFrame f:
          _upsertSession(f.sessionId,
              running: true, blank: f.blank, cwd: f.cwd, agentPreset: f.agentPreset, parentSessionId: f.parentSessionId);
        case SessionRemovedFrame f:
          sessions.removeWhere((s) => s.sessionId == f.sessionId);
        case SessionStatusFrame f:
          _updateRunning(f.sessionId, f.running);
        case AgentErrorFrame f:
          lastError = '会话 ${f.sessionId} 出错: ${f.message}';
        case WorkspaceChangedFrame _:
        case WorkspaceRemovedFrame _:
        case WorkspaceOrderChangedFrame _:
        case ArchivedSessionsChangedFrame _:
          // 工作区/归档变化：重拉工作区与会话列表
          unawaited(refreshWorkspaces());
        default:
          break;
      }
      notifyListeners();
    };
  }

  void _upsertSession(
    String sessionId, {
    required bool running,
    required bool blank,
    String? cwd,
    String? agentPreset,
    String? parentSessionId,
  }) {
    final idx = sessions.indexWhere((s) => s.sessionId == sessionId);
    if (idx >= 0) {
      final old = sessions[idx];
      sessions[idx] = SessionSummary(
        sessionId: sessionId,
        updatedAt: old.updatedAt,
        running: running,
        blank: blank,
        cwd: cwd ?? old.cwd,
        agentPreset: agentPreset ?? old.agentPreset,
        parentSessionId: parentSessionId ?? old.parentSessionId,
        title: old.title,
      );
    } else {
      sessions.insert(
        0,
        SessionSummary(
          sessionId: sessionId,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
          running: running,
          blank: blank,
          cwd: cwd,
          agentPreset: agentPreset,
          parentSessionId: parentSessionId,
        ),
      );
    }
    _sortSessions();
  }

  void _updateRunning(String sessionId, bool running) {
    final idx = sessions.indexWhere((s) => s.sessionId == sessionId);
    if (idx < 0) return;
    final old = sessions[idx];
    final wasRunning = old.running;
    sessions[idx] = SessionSummary(
      sessionId: old.sessionId,
      updatedAt: old.updatedAt,
      running: running,
      blank: old.blank,
      cwd: old.cwd,
      agentPreset: old.agentPreset,
      parentSessionId: old.parentSessionId,
      title: old.title,
    );
    // 会话完成 → 发通知
    if (wasRunning && !running) {
      _notifyCompleted(sessionId);
    }
  }

  void _sortSessions() {
    sessions.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  // ---------- 通知 ----------

  static const _channelId = 'dsh_session';
  static const _channelName = '会话完成';
  static const _channelDesc = 'DSH 会话回复完成时通知';

  /// 会话完成通知：App 在后台 / 不在该会话页时弹通知。
  void _notifyCompleted(String sessionId) {
    // 判断是否需要通知：当前正在看的会话不弹
    final nav = appNavigatorKey.currentState;
    final currentRoute = nav != null
        ? ModalRoute.of(nav.context)?.settings
        : null;
    if (currentRoute?.name == '/chat' && currentRoute?.arguments == sessionId) {
      return; // 用户正在看这个会话，不弹
    }

    final session = sessions.firstWhere((s) => s.sessionId == sessionId,
        orElse: () => SessionSummary(sessionId: sessionId, updatedAt: 0, running: false, blank: false));
    final title = session.title ?? session.agentPreset ?? session.cwd ?? sessionId;
    final shortTitle = title.length > 30 ? '${title.substring(0, 30)}…' : title;

    flutterLocalNotificationsPlugin.show(
      sessionId.hashCode.abs(),
      'DSH 回复完成',
      shortTitle,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDesc,
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
      ),
      payload: sessionId,
    );
  }

  /// 拉取会话列表（连接后、或手动刷新时调用）。
  Future<void> refreshSessions() async {
    final conn = _conn;
    if (conn == null) return;
    try {
      final api = SessionsApi(_conn!.rpc);
      sessions = await api.list();
      _sortSessions();
      lastError = null;
    } catch (e) {
      lastError = '拉取会话列表失败: $e';
    }
    notifyListeners();
  }

  /// 拉取工作区列表 + 归档集合。
  Future<void> refreshWorkspaces() async {
    final conn = _conn;
    if (conn == null) return;
    try {
      final api = SessionsApi(_conn!.rpc);
      final result = await api.workspaceList();
      workspaces = result.items;
      archivedSessionIds = result.archivedSessionIds;
      _workspacesLoaded = true;
      lastError = null;
    } catch (e) {
      lastError = '拉取工作区列表失败: $e';
    }
    notifyListeners();
  }

  /// 新建会话并返回 sessionId。cwd 为空时由服务端使用默认工作区。
  Future<String> createSession({String? cwd}) async {
    final api = SessionsApi(_conn!.rpc);
    final id = await api.create(cwd: cwd);
    await refreshSessions();
    await refreshWorkspaces();
    return id;
  }

  /// 新建工作区（path 为目录路径）。
  Future<void> createWorkspace(String path) async {
    final api = SessionsApi(_conn!.rpc);
    await api.workspaceCreate(path);
    await refreshWorkspaces();
  }

  /// 重命名工作区。
  Future<void> renameWorkspace(String workspaceId, String title) async {
    final api = SessionsApi(_conn!.rpc);
    await api.workspaceRename(workspaceId, title);
    await refreshWorkspaces();
  }

  /// 删除工作区（会话保留，归入未分组）。
  Future<void> deleteWorkspace(String workspaceId) async {
    final api = SessionsApi(_conn!.rpc);
    await api.workspaceDelete(workspaceId);
    await refreshWorkspaces();
  }

  /// 重命名会话。
  Future<void> renameSession(String sessionId, String title) async {
    final api = SessionsApi(_conn!.rpc);
    await api.renameSession(sessionId, title);
    await refreshSessions();
  }

  /// 归档会话。
  Future<void> archiveSession(String sessionId) async {
    final api = SessionsApi(_conn!.rpc);
    final archived = await api.workspaceArchiveSession(sessionId);
    archivedSessionIds = archived;
    await refreshWorkspaces();
  }

  /// 把会话移入工作区（归档会话也用它恢复）。
  Future<void> moveSessionToWorkspace(String workspaceId, String sessionId) async {
    final api = SessionsApi(_conn!.rpc);
    await api.workspaceInsertSessionBefore(workspaceId, sessionId);
    await refreshWorkspaces();
  }

  void disconnect() {
    _conn?.dispose();
    _conn = null;
    sessions = [];
    workspaces = [];
    archivedSessionIds = [];
    _workspacesLoaded = false;
    lastError = null;
    reconnectAttempt = 0;
    notifyListeners();
  }
}
