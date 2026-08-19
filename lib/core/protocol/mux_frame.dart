/// mux 流帧模型（`/api/events.mux` 的 payload 判别联合）。
///
/// 字段与官方 `muxFrameSchema` 对齐。未知类型保留原始 JSON，保证前向兼容。
/// 每帧携带所在 server-request 信封的 rpcId（应答 question 时需要回填）。
library;

import 'envelope.dart';

/// 一条会话日志事件（`session/event` 帧的 event 槽）。
///
/// 上层协议 `sessionEventSchema`：严格信封 `{type, seq, time}` + 宽 data，
/// 可选 surface 元数据（`surfaceOp` / `sourceEventSeqs` / `ignorable`）。
class SessionEvent {
  SessionEvent({
    required this.type,
    required this.seq,
    required this.time,
    required this.data,
    this.sourceEventSeqs,
    this.surfaceOp,
    this.ignorable = false,
  });

  factory SessionEvent.fromJson(Map<String, Object?> json) => SessionEvent(
        type: json['type'] as String,
        seq: (json['seq'] as num).toInt(),
        time: (json['time'] as num).toInt(),
        data: json['data'],
        sourceEventSeqs: (json['sourceEventSeqs'] as List<Object?>?)?.map((s) => (s as num).toInt()).toList(),
        surfaceOp: json['surfaceOp'],
        ignorable: json['ignorable'] == true,
      );

  final String type;
  final int seq;
  final int time;
  final Object? data;

  /// 被本事件遮蔽（替换）的源事件 seq。
  final List<int>? sourceEventSeqs;

  /// `"append"` 或 `{op:"replace", start, end}`；缺失时由上层按类型推断。
  final Object? surfaceOp;

  /// 纯日志事件（不产生 surface 节点）。
  final bool ignorable;

  Map<String, Object?> toJson() => {
        'type': type,
        'seq': seq,
        'time': time,
        'data': data,
        if (sourceEventSeqs != null) 'sourceEventSeqs': sourceEventSeqs,
        if (surfaceOp != null) 'surfaceOp': surfaceOp,
        if (ignorable) 'ignorable': true,
      };
}

/// `stream/error` 帧：流级错误（通常随后断开）。
class StreamErrorFrame {
  StreamErrorFrame({required this.code, required this.message});

  factory StreamErrorFrame.fromJson(Map<String, Object?> json) {
    final error = json['error'] as Map<String, Object?>;
    return StreamErrorFrame(code: error['code'] as String, message: error['message'] as String);
  }

  final String code;
  final String message;
}

/// mux 流中的一帧（判别联合）。
sealed class MuxFrame {
  const MuxFrame({required this.rpcId});

  /// 所在 server-request 信封的 rpcId。
  final String rpcId;

  static MuxFrame fromEnvelope(ServerRequest envelope) {
    final payload = envelope.payload as Map<String, Object?>? ?? const {};
    return switch (payload['type']) {
      'session/event' => SessionEventFrame.fromJson(payload, envelope.rpcId),
      'session/subscribed' => SessionSubscribedFrame.fromJson(payload, envelope.rpcId),
      'approval/requested' => ApprovalRequestedFrame.fromJson(payload, envelope.rpcId),
      'approval/resolved' => ApprovalResolvedFrame.fromJson(payload, envelope.rpcId),
      'question/requested' => QuestionRequestedFrame.fromJson(payload, envelope.rpcId),
      'question/resolved' => QuestionResolvedFrame.fromJson(payload, envelope.rpcId),
      'stream/error' => StreamErrorMuxFrame.fromJson(payload, envelope.rpcId),
      _ => UnknownFrame(payload, rpcId: envelope.rpcId),
    };
  }
}

/// `session/event` 帧：会话日志增量。
class SessionEventFrame extends MuxFrame {
  SessionEventFrame({required super.rpcId, required this.sessionId, required this.event, this.view});

  factory SessionEventFrame.fromJson(Map<String, Object?> json, String rpcId) => SessionEventFrame(
        rpcId: rpcId,
        sessionId: json['sessionId'] as String,
        event: SessionEvent.fromJson(json['event'] as Map<String, Object?>),
        view: json['view'] as Map<String, Object?>?,
      );

  final String sessionId;
  final SessionEvent event;
  final Map<String, Object?>? view;
}

/// `session/subscribed` 帧：订阅确认 + 断线续传锚点（lastSeq）。
class SessionSubscribedFrame extends MuxFrame {
  SessionSubscribedFrame({required super.rpcId, required this.sessionId, required this.lastSeq});

  factory SessionSubscribedFrame.fromJson(Map<String, Object?> json, String rpcId) => SessionSubscribedFrame(
        rpcId: rpcId,
        sessionId: json['sessionId'] as String,
        lastSeq: json['lastSeq'] as num,
      );

  final String sessionId;
  final num lastSeq;
}

/// `approval/requested` 帧：工具执行待批准。
class ApprovalRequestedFrame extends MuxFrame {
  ApprovalRequestedFrame({
    required super.rpcId,
    required this.sessionId,
    required this.approvalId,
    required this.toolName,
    this.callId,
    this.reason,
  });

  factory ApprovalRequestedFrame.fromJson(Map<String, Object?> json, String rpcId) => ApprovalRequestedFrame(
        rpcId: rpcId,
        sessionId: json['sessionId'] as String,
        approvalId: json['approvalId'] as String,
        toolName: json['toolName'] as String,
        callId: json['callId'] as String?,
        reason: json['reason'] as String?,
      );

  final String sessionId;
  final String approvalId;
  final String toolName;
  final String? callId;
  final String? reason;
}

/// `approval/resolved` 帧。
class ApprovalResolvedFrame extends MuxFrame {
  ApprovalResolvedFrame({required super.rpcId, required this.sessionId, required this.approvalId, required this.outcome});

  factory ApprovalResolvedFrame.fromJson(Map<String, Object?> json, String rpcId) => ApprovalResolvedFrame(
        rpcId: rpcId,
        sessionId: json['sessionId'] as String,
        approvalId: json['approvalId'] as String,
        outcome: json['outcome'] as String,
      );

  final String sessionId;
  final String approvalId;

  /// allowed-once | rejected | cancelled | unavailable
  final String outcome;
}

/// `question/requested` 帧中的一个提问项。
class QuestionItem {
  QuestionItem({required this.id, required this.question, this.header, this.options = const [], this.multiSelect = false});

  factory QuestionItem.fromJson(Map<String, Object?> json) => QuestionItem(
        id: json['id'] as String,
        question: json['question'] as String,
        header: json['header'] as String?,
        options: (json['options'] as List<Object?>?)?.cast<Map<String, Object?>>() ?? const [],
        multiSelect: json['multiSelect'] == true,
      );

  final String id;
  final String question;
  final String? header;
  final List<Map<String, Object?>> options;
  final bool multiSelect;
}

/// `question/requested` 帧：模型向用户提问（用 /api/respond 回答）。
class QuestionRequestedFrame extends MuxFrame {
  QuestionRequestedFrame({required super.rpcId, required this.sessionId, required this.questions});

  factory QuestionRequestedFrame.fromJson(Map<String, Object?> json, String rpcId) => QuestionRequestedFrame(
        rpcId: rpcId,
        sessionId: json['sessionId'] as String,
        questions: (json['questions'] as List<Object?>)
            .map((q) => QuestionItem.fromJson(q as Map<String, Object?>))
            .toList(),
      );

  final String sessionId;
  final List<QuestionItem> questions;
}

/// `question/resolved` 帧。
class QuestionResolvedFrame extends MuxFrame {
  QuestionResolvedFrame({required super.rpcId, required this.sessionId, required this.questionRpcId, required this.outcome});

  factory QuestionResolvedFrame.fromJson(Map<String, Object?> json, String rpcId) => QuestionResolvedFrame(
        rpcId: rpcId,
        sessionId: json['sessionId'] as String,
        questionRpcId: json['questionRpcId'] as String,
        outcome: json['outcome'] as String,
      );

  final String sessionId;
  final String questionRpcId;

  /// answered | cancelled
  final String outcome;
}

/// `stream/error` 帧（mux 载体内的错误帧）。
class StreamErrorMuxFrame extends MuxFrame {
  StreamErrorMuxFrame({required super.rpcId, required this.error});

  factory StreamErrorMuxFrame.fromJson(Map<String, Object?> json, String rpcId) =>
      StreamErrorMuxFrame(rpcId: rpcId, error: StreamErrorFrame.fromJson(json));

  final StreamErrorFrame error;
}

/// 未识别帧：保留原始 payload，向前兼容。
class UnknownFrame extends MuxFrame {
  UnknownFrame(this.payload, {required super.rpcId});
  final Map<String, Object?> payload;
}
