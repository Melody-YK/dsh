/// DSH /api 下行事件流（WebSocket 载体）。
///
/// 官方浏览器平台实现用 WebSocket 打开两条下行通道，服务端→客户端单向推送，
/// 客户端消息是协议违规（上行一律走 HTTP）。帧格式：文本 JSON 的 server-request
/// 信封，payload 是 mux/host 帧（判别联合，见 `mux_frame.dart` / `host_frame.dart`）。
library;

import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'envelope.dart';

/// 一条下行流的处理结果：正常结束（服务端关闭）或异常。
sealed class DownlinkEnd {}

/// 服务端关闭（或本地取消）。
class DownlinkClosed extends DownlinkEnd {
  DownlinkClosed([this.reason]);
  final String? reason;
}

/// 流级错误（帧解析失败会跳过单帧，不终止流；此处是传输级错误）。
class DownlinkFailed extends DownlinkEnd {
  DownlinkFailed(this.error);
  final Object error;
}

/// 单条下行流：连接、逐帧 yield、取消。
class DownlinkStream {
  DownlinkStream({required this.path, required this.baseUri});

  /// 如 `/api/events.mux`。
  final String path;
  final Uri baseUri;

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  final _controller = StreamController<ServerRequest>.broadcast();
  bool _closed = false;

  Stream<ServerRequest> get frames => _controller.stream;

  /// 打开连接并开始泵帧。返回的 Future 在该流结束（关闭或失败）时完成，
  /// 携带结束原因；调用方负责重连策略。
  Future<DownlinkEnd> open() async {
    final wsUri = Uri(
      scheme: baseUri.scheme == 'https' ? 'wss' : 'ws',
      host: baseUri.host,
      port: baseUri.port,
      path: path,
    );
    _channel = WebSocketChannel.connect(wsUri);
    _sub = _channel!.stream.listen(
      _onFrame,
      onError: _onError,
      onDone: _onDone,
      cancelOnError: true,
    );
    return _endCompleter.future;
  }

  final _endCompleter = Completer<DownlinkEnd>();

  void _onFrame(dynamic raw) {
    if (_closed) return;
    if (raw is! String) return; // 二进制帧：协议未使用，丢弃
    Map<String, Object?> json;
    try {
      json = jsonDecode(raw) as Map<String, Object?>;
    } on FormatException {
      return; // 坏帧跳过，不终止流（与官方行为一致）
    }
    final Envelope envelope;
    try {
      envelope = Envelope.fromJson(json);
    } catch (_) {
      return;
    }
    if (envelope is ServerRequest && !_controller.isClosed) {
      _controller.add(envelope);
    }
  }

  void _onError(Object error, StackTrace stack) {
    if (_closed) return;
    _closed = true;
    _controller.close();
    if (!_endCompleter.isCompleted) _endCompleter.complete(DownlinkFailed(error));
  }

  void _onDone() {
    if (_closed) return;
    _closed = true;
    _controller.close();
    if (!_endCompleter.isCompleted) _endCompleter.complete(DownlinkClosed());
  }

  /// 本地主动关闭。
  void close() {
    _closed = true;
    _sub?.cancel();
    _channel?.sink.close();
    _controller.close();
    if (!_endCompleter.isCompleted) _endCompleter.complete(DownlinkClosed('closed by client'));
  }
}
