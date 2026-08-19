/// 单个会话的聊天状态：事件缓冲、surface 折叠、渲染消息列表。
///
/// 数据流：
/// - 进入页面：`session.history` 拉取历史 → 按 seq 排序进 [events]
/// - 常驻期间：mux 流 `session/event` 增量追加（seq 严格递增去重）
/// - `surfaceOp: append` 直接追加；`surfaceOp: replace`（含 start/end）
///   替换区间内被遮蔽的事件（assistant 消息改写 / tool-result 修订）
/// - 断线恢复：`session/subscribed.lastSeq` 与本地最大 seq 比较，落后则用
///   `session.history(beforeSeq: null, maxMessages: 大)` 补拉，再按 seq 合并
library;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api/sessions_api.dart';
import '../core/protocol/connection.dart';
import '../core/protocol/mux_frame.dart';

/// 渲染用消息（由事件投影而来，非持久模型）。
class ChatMessage {
  ChatMessage({
    required this.seq,
    required this.role,
    this.text,
    this.reasoning,
    this.toolName,
    this.isError = false,
    this.isStreaming = false,
    this.model,
  });

  final int seq;

  /// user | assistant | tool
  final String role;

  /// 正式回答内容（assistant 的 text 块合并）。
  final String? text;

  /// 思考过程（assistant 的 reasoning 块合并，折叠展示）。
  final String? reasoning;

  final String? toolName;
  final bool isError;
  final bool isStreaming;
  final String? model;

  Map<String, Object?> toJson() => {
        'seq': seq,
        'role': role,
        if (text != null) 'text': text,
        if (reasoning != null) 'reasoning': reasoning,
        if (model != null) 'model': model,
      };

  static ChatMessage fromJson(Map<String, Object?> json) => ChatMessage(
        seq: (json['seq'] as num?)?.toInt() ?? -1,
        role: json['role'] as String,
        text: json['text'] as String?,
        reasoning: json['reasoning'] as String?,
        model: json['model'] as String?,
      );
}

class ChatController extends ChangeNotifier {
  ChatController({required this.sessionId, required this.connection});

  final String sessionId;
  final DshConnection connection;

  final SplayTreeMap<int, SessionEvent> _events = SplayTreeMap();
  StreamSubscription? _muxSub;

  /// 乐观回显：发消息后立即加入、真实 user/message 事件到达后移除的待确认消息。
  final List<ChatMessage> _optimistic = [];

  /// 本地缓存：进入会话时秒显上次的渲染结果，后台刷新真实历史。
  List<ChatMessage>? _cache;
  bool _usingCache = false;

  bool _loading = true;
  bool _hasMore = false;
  bool _initialLoaded = false;
  String? _error;

  bool get loading => _loading;
  bool get hasMore => _hasMore;
  String? get error => _error;

  /// 按 seq 升序的消息列表。
  ///
  /// 手机上只显示模型对话内容（user + assistant），工具调用/结果
  /// （tool/result）不渲染——工具历史是开发细节，手机端只看回复。
  List<ChatMessage> get messages {
    if (_usingCache && _cache != null) {
      // 秒显阶段：缓存 + 乐观回显合并
      final result = <ChatMessage>[..._cache!];
      for (final o in _optimistic) {
        final dup = _cache!.any((c) => c.role == 'user' && c.text == o.text);
        if (!dup) result.add(o);
      }
      return result;
    }
    final real = _events.values
        .map(_project)
        .whereType<ChatMessage>()
        .where((m) => m.role != 'tool')
        .toList();
    // 合并乐观消息：真实 user 消息到达后（文本匹配）移除对应乐观项，避免重复
    final result = <ChatMessage>[...real];
    for (final o in _optimistic) {
      final alreadyReal = real.any((r) => r.role == 'user' && r.text == o.text);
      if (!alreadyReal) result.add(o);
    }
    return result;
  }

  /// 发消息前调用：立即在界面显示这条 user 消息（乐观回显）。
  void addOptimistic(String text) {
    _optimistic.add(ChatMessage(seq: -1, role: 'user', text: text));
    notifyListeners();
  }

  /// 发送失败时调用：移除乐观回显。
  void removeOptimistic(String text) {
    _optimistic.removeWhere((m) => m.text == text);
    notifyListeners();
  }

  int get lastSeq => _events.isEmpty ? -1 : _events.keys.last;

  /// 会话就绪后调用（历史已加载 + 订阅已挂）。
  void Function()? onReady;

  void _ensureSubscribed() {
    if (_muxSub != null) return;
    _muxSub = connection.muxFrames.listen(_handleFrame);
  }

  /// 进入会话：先读本地缓存秒显，再后台拉真实历史。
  Future<void> start() async {
    _ensureSubscribed();
    final cached = await _readCache();
    if (cached != null && cached.isNotEmpty) {
      _cache = cached;
      _usingCache = true;
      _loading = false;
      notifyListeners();
    }
    await _loadInitial();
  }

  static String get _cacheKey => 'dsh_msg_cache_';

  Future<List<ChatMessage>?> _readCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey + sessionId);
      if (raw == null || raw.isEmpty) return null;
      final list = jsonDecode(raw) as List<Object?>;
      return list
          .map((e) => ChatMessage.fromJson(e as Map<String, Object?>))
          .toList();
    } catch (_) {
      return null;
    }
  }

  /// 把最近的真实消息写入本地缓存（异步，不阻塞）。
  Future<void> _writeCache() async {
    try {
      final real = _events.values
          .map(_project)
          .whereType<ChatMessage>()
          .where((m) => m.role != 'tool')
          .toList();
      if (real.isEmpty) return;
      final tail = real.length > 30 ? real.sublist(real.length - 30) : real;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _cacheKey + sessionId,
        jsonEncode(tail.map((m) => m.toJson()).toList()),
      );
    } catch (_) {
      // 缓存失败不影响主流程
    }
  }

  Future<void> _loadInitial({int? beforeSeq}) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final api = SessionsApi(connection.rpc);
      // 首次只拉 12 条消息：响应约 700KB、服务端 ~0.5s（30 条要 2.4s/2.9MB）。
      // 本地缓存负责秒显，这里只做增量刷新。
      final (entries, hasMore) = await api.history(sessionId, beforeSeq: beforeSeq, maxMessages: 12);
      for (final entry in entries) {
        // 只保留 surface 事件（user/message、assistant/message、tool/result）：
        // chunk/边界/日志事件数量可达数万，渲染层不需要
        if (_isSurface(entry.event)) {
          _events[entry.event.seq] = entry.event;
        }
      }
      _hasMore = hasMore;
      _initialLoaded = true;
      // 真实历史到达，切换为真实数据
      _usingCache = false;
      _cache = null;
      // 仅首次加载（非向上翻页）触发就绪回调（滚动到底部）
      if (beforeSeq == null) onReady?.call();
      // 后台写缓存
      unawaited(_writeCache());
    } catch (e) {
      _error = '加载历史失败: $e';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  bool _isSurface(SessionEvent event) => _surfaceOpOf(event) is! _NoneOp;

  /// 加载更早的历史（向上翻页）。
  Future<void> loadMore() async {
    if (!_hasMore || _loading) return;
    final before = _events.isEmpty ? null : _events.keys.first;
    await _loadInitial(beforeSeq: before);
  }

  void _handleFrame(MuxFrame frame) {
    switch (frame) {
      case SessionEventFrame f:
        if (f.sessionId != sessionId) return;
        _applyEvent(f.event);
        notifyListeners();
      case SessionSubscribedFrame f:
        if (f.sessionId != sessionId) return;
        final remoteLast = f.lastSeq.toInt();
        if (_initialLoaded && remoteLast > lastSeq) {
          // 断线期间漏了事件，补拉
          _catchUp(remoteLast);
        }
      default:
        break;
    }
  }

  Future<void> _catchUp(int remoteLast) async {
    try {
      final api = SessionsApi(connection.rpc);
      final (entries, _) = await api.history(sessionId, maxMessages: 12);
      for (final entry in entries) {
        if (_isSurface(entry.event)) {
          _events[entry.event.seq] = entry.event;
        }
      }
      notifyListeners();
    } catch (e) {
      _error = '断线补拉失败: $e';
    }
  }

  /// 应用一条会话事件：surfaceOp append 追加，replace 替换区间。
  void _applyEvent(SessionEvent event) {
    final op = _surfaceOpOf(event);
    switch (op) {
      case _AppendOp():
        _events[event.seq] = event;
      case _ReplaceOp(start: final start, end: final end):
        _events.removeWhere((seq, _) => seq >= start && seq <= end);
        _events[event.seq] = event;
      case _NoneOp():
        // 非 surface 事件（chunk/boundary/日志）不进入渲染列表
        return;
    }
  }

  // surfaceOp 编码：append 为 "append"，replace 为 {op, start, end}。
  _SurfaceOp _surfaceOpOf(SessionEvent event) {
    if (event.ignorable) return const _NoneOp();
    final raw = event.surfaceOp;
    if (raw == null) return _legacySurfaceOp(event);
    if (raw == 'append') return const _AppendOp();
    if (raw is Map<String, Object?>) {
      final start = (raw['start'] as num?)?.toInt();
      final end = (raw['end'] as num?)?.toInt();
      if (raw['op'] == 'replace' && start != null && end != null) {
        return _ReplaceOp(start: start, end: end);
      }
    }
    return const _NoneOp();
  }

  /// 兜底：事件没有 surfaceOp 时按类型推断（append 语义）。
  _SurfaceOp _legacySurfaceOp(SessionEvent event) {
    switch (event.type) {
      case 'user/message':
      case 'assistant/message':
      case 'tool/result':
        return const _AppendOp();
      default:
        return const _NoneOp();
    }
  }

  /// 事件 → 渲染消息。
  ChatMessage? _project(SessionEvent event) {
    final data = event.data;
    if (data is! Map<String, Object?>) return null;
    switch (event.type) {
      case 'user/message':
        final message = data['message'];
        if (message is! Map<String, Object?>) return null;
        final content = _textOf(message['content']);
        return ChatMessage(seq: event.seq, role: 'user', text: content, isStreaming: false);
      case 'assistant/message':
        final message = data['message'];
        if (message is! Map<String, Object?>) return null;
        final blocks = _blocksOf(message['content']);
        if (blocks.isEmpty) return null;
        // 拆分 reasoning（思考）与 text（正式回答），思考内容折叠展示
        final reasoningParts = <String>[];
        final textParts = <String>[];
        for (final b in blocks) {
          final t = b['type'];
          if (t == 'reasoning' && b['text'] is String) reasoningParts.add(b['text'] as String);
          if (t == 'text' && b['text'] is String) textParts.add(b['text'] as String);
        }
        if (reasoningParts.isEmpty && textParts.isEmpty) return null;
        final source = message['source'] is Map<String, Object?>
            ? message['source'] as Map<String, Object?>
            : const {};
        return ChatMessage(
          seq: event.seq,
          role: 'assistant',
          text: textParts.isEmpty ? null : textParts.join('\n'),
          reasoning: reasoningParts.isEmpty ? null : reasoningParts.join('\n'),
          model: source['model'] as String?,
        );
      case 'tool/result':
        final message = data['message'];
        if (message is! Map<String, Object?>) return null;
        final blocks = _blocksOf(message['content']);
        String? text;
        var isError = false;
        for (final b in blocks) {
          final t = b['type'];
          if (t == 'tool-result') {
            isError = b['isError'] == true;
            text = _stringify(b['content']);
            if (text == null && b['content'] is List) {
              text = (b['content'] as List).map(_stringify).whereType<String>().join('\n');
            }
          }
        }
        if (text == null) return null;
        return ChatMessage(seq: event.seq, role: 'tool', text: text, isError: isError);
      default:
        return null;
    }
  }

  List<Map<String, Object?>> _blocksOf(Object? content) {
    if (content is! List) return const [];
    return content.whereType<Map<String, Object?>>().toList();
  }

  /// 提取文本块（text / reasoning 合并）。
  String? _textOf(Object? content) {
    final blocks = _blocksOf(content);
    final parts = <String>[];
    for (final b in blocks) {
      final t = b['type'];
      if (t == 'text' && b['text'] is String) parts.add(b['text'] as String);
      if (t == 'reasoning' && b['text'] is String) parts.add(b['text'] as String);
    }
    return parts.isEmpty ? null : parts.join('\n');
  }

  String? _stringify(Object? value) {
    if (value == null) return null;
    if (value is String) return value;
    if (value is num || value is bool) return '$value';
    if (value is Map || value is List) {
      try {
        return const JsonEncoder.withIndent(null).convert(value);
      } catch (_) {
        return value.toString();
      }
    }
    return value.toString();
  }

  @override
  void dispose() {
    _muxSub?.cancel();
    super.dispose();
  }
}

/// surfaceOp 折叠结果。
sealed class _SurfaceOp {
  const _SurfaceOp();
}

class _AppendOp extends _SurfaceOp {
  const _AppendOp();
}

class _NoneOp extends _SurfaceOp {
  const _NoneOp();
}

class _ReplaceOp extends _SurfaceOp {
  const _ReplaceOp({required this.start, required this.end});
  final int start;
  final int end;
}
