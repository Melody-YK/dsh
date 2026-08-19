/// host 流帧模型（`/api/events.host` 的 payload 判别联合）。
///
/// 字段与官方 `hostFrameSchema` 对齐：会话列表实时刷新、工作区变更等。
library;

import 'envelope.dart';

/// host 流中的一帧（判别联合）。
sealed class HostFrame {
  const HostFrame({required this.rpcId});
  final String rpcId;

  static HostFrame fromEnvelope(ServerRequest envelope) {
    final payload = envelope.payload as Map<String, Object?>? ?? const {};
    return switch (payload['type']) {
      'host/session-added' => SessionAddedFrame.fromJson(payload, envelope.rpcId),
      'host/session-removed' => SessionRemovedFrame.fromJson(payload, envelope.rpcId),
      'host/session-status' => SessionStatusFrame.fromJson(payload, envelope.rpcId),
      'host/agent-error' => AgentErrorFrame.fromJson(payload, envelope.rpcId),
      'host/workspace-changed' => WorkspaceChangedFrame.fromJson(payload, envelope.rpcId),
      'host/workspace-removed' => WorkspaceRemovedFrame.fromJson(payload, envelope.rpcId),
      'host/workspace-order-changed' => WorkspaceOrderChangedFrame.fromJson(payload, envelope.rpcId),
      'host/archived-sessions-changed' => ArchivedSessionsChangedFrame.fromJson(payload, envelope.rpcId),
      'host/remote-event' => RemoteEventFrame.fromJson(payload, envelope.rpcId),
      'stream/error' => StreamErrorHostFrame.fromJson(payload, envelope.rpcId),
      _ => UnknownHostFrame(payload, rpcId: envelope.rpcId),
    };
  }
}

/// 新会话出现（子代理会话 origin: "subagent"）。
class SessionAddedFrame extends HostFrame {
  SessionAddedFrame({
    required super.rpcId,
    required this.sessionId,
    required this.blank,
    this.parentSessionId,
    this.origin,
    this.cwd,
    this.agentPreset,
  });

  factory SessionAddedFrame.fromJson(Map<String, Object?> json, String rpcId) => SessionAddedFrame(
        rpcId: rpcId,
        sessionId: json['sessionId'] as String,
        blank: json['blank'] as bool,
        parentSessionId: json['parentSessionId'] as String?,
        origin: json['origin'] as String?,
        cwd: json['cwd'] as String?,
        agentPreset: json['agentPreset'] as String?,
      );

  final String sessionId;
  final bool blank;
  final String? parentSessionId;
  final String? origin;
  final String? cwd;
  final String? agentPreset;
}

/// 会话被移除。
class SessionRemovedFrame extends HostFrame {
  SessionRemovedFrame({required super.rpcId, required this.sessionId});

  factory SessionRemovedFrame.fromJson(Map<String, Object?> json, String rpcId) =>
      SessionRemovedFrame(rpcId: rpcId, sessionId: json['sessionId'] as String);

  final String sessionId;
}

/// 会话运行状态变更（running 用于列表刷新）。
class SessionStatusFrame extends HostFrame {
  SessionStatusFrame({required super.rpcId, required this.sessionId, required this.running});

  factory SessionStatusFrame.fromJson(Map<String, Object?> json, String rpcId) =>
      SessionStatusFrame(rpcId: rpcId, sessionId: json['sessionId'] as String, running: json['running'] as bool);

  final String sessionId;
  final bool running;
}

/// agent 出错（列表上展示错误）。
class AgentErrorFrame extends HostFrame {
  AgentErrorFrame({required super.rpcId, required this.sessionId, required this.message});

  factory AgentErrorFrame.fromJson(Map<String, Object?> json, String rpcId) =>
      AgentErrorFrame(rpcId: rpcId, sessionId: json['sessionId'] as String, message: json['message'] as String);

  final String sessionId;
  final String message;
}

/// 工作区整体变更（快照替换）。
class WorkspaceChangedFrame extends HostFrame {
  WorkspaceChangedFrame({required super.rpcId, required this.workspace});

  factory WorkspaceChangedFrame.fromJson(Map<String, Object?> json, String rpcId) =>
      WorkspaceChangedFrame(rpcId: rpcId, workspace: json['workspace'] as Map<String, Object?>);

  final Map<String, Object?> workspace;
}

/// 工作区被删除。
class WorkspaceRemovedFrame extends HostFrame {
  WorkspaceRemovedFrame({required super.rpcId, required this.workspaceId});

  factory WorkspaceRemovedFrame.fromJson(Map<String, Object?> json, String rpcId) =>
      WorkspaceRemovedFrame(rpcId: rpcId, workspaceId: json['workspaceId'] as String);

  final String workspaceId;
}

/// 工作区排序变更。
class WorkspaceOrderChangedFrame extends HostFrame {
  WorkspaceOrderChangedFrame({required super.rpcId, required this.workspaceIds});

  factory WorkspaceOrderChangedFrame.fromJson(Map<String, Object?> json, String rpcId) => WorkspaceOrderChangedFrame(
        rpcId: rpcId,
        workspaceIds: (json['workspaceIds'] as List<Object?>).cast<String>(),
      );

  final List<String> workspaceIds;
}

/// 已归档会话集合变更。
class ArchivedSessionsChangedFrame extends HostFrame {
  ArchivedSessionsChangedFrame({required super.rpcId, required this.archivedSessionIds});

  factory ArchivedSessionsChangedFrame.fromJson(Map<String, Object?> json, String rpcId) => ArchivedSessionsChangedFrame(
        rpcId: rpcId,
        archivedSessionIds: (json['archivedSessionIds'] as List<Object?>).cast<String>(),
      );

  final List<String> archivedSessionIds;
}

/// 宿主远程事件（api remotes 转发）。
class RemoteEventFrame extends HostFrame {
  RemoteEventFrame({required super.rpcId, required this.event, required this.args});

  factory RemoteEventFrame.fromJson(Map<String, Object?> json, String rpcId) => RemoteEventFrame(
        rpcId: rpcId,
        event: json['event'] as String,
        args: (json['args'] as List<Object?>?) ?? const [],
      );

  final String event;
  final List<Object?> args;
}

/// `stream/error` 帧（host 载体）。
class StreamErrorHostFrame extends HostFrame {
  StreamErrorHostFrame({required super.rpcId, required this.error});

  factory StreamErrorHostFrame.fromJson(Map<String, Object?> json, String rpcId) =>
      StreamErrorHostFrame(rpcId: rpcId, error: json['error'] as Map<String, Object?>);

  final Map<String, Object?> error;
}

/// 未识别帧。
class UnknownHostFrame extends HostFrame {
  UnknownHostFrame(this.payload, {required super.rpcId});
  final Map<String, Object?> payload;
}
