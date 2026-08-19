/// DSH 连接管理器：mux/host 两条下行流 + 指数退避重连 + 握手。
///
/// 重连策略与官方 `dsh-client-connection` 对齐：
/// - 退避：`base 500ms × 2^(attempt-1)`，上限 10s，实际延迟取 `[cap/2, cap)` 随机抖动
/// - 每代（generation）先打开两条流，再 `host.describe` 握手
/// - 握手失败/流断开 → 记一次 attempt，退避后重连
/// - 断线恢复后由上层按 `session/subscribed.lastSeq` 或 `session.history` 补拉
library;

import 'dart:async';
import 'dart:math';

import 'downlink_stream.dart';
import 'host_frame.dart';
import 'mux_frame.dart';
import 'rpc_client.dart';

/// 连接状态（命名为 DshConnectionState 避免与 Flutter 的 ConnectionState 冲突）。
enum DshConnectionState { disconnected, connecting, connected, reconnecting }

/// host.describe 的返回（握手快照）。
class HostDescribe {
  HostDescribe({required this.version, required this.cwd, this.provider, this.model, this.raw = const {}});

  factory HostDescribe.fromJson(Map<String, Object?> json) => HostDescribe(
        version: json['version'] as String,
        cwd: json['cwd'] as String,
        provider: json['provider'] as String?,
        model: json['model'] as String?,
        raw: json,
      );

  final String version;
  final String cwd;
  final String? provider;
  final String? model;
  final Map<String, Object?> raw;
}

/// 连接管理器。
///
/// 使用方式：
/// ```dart
/// final conn = DshConnection(baseUri);
/// conn.onMuxFrame = (frame) => ...;
/// conn.onHostFrame = (frame) => ...;
/// conn.start();
/// ...
/// conn.stop();
/// ```
class DshConnection {
  DshConnection(this.baseUri, {RpcClient? rpc}) : _rpc = rpc ?? RpcClient(baseUri);

  final Uri baseUri;
  final RpcClient _rpc;

  // --- 退避参数（官方默认值）---
  static const int backoffBaseMs = 500;
  static const int backoffFactor = 2;
  static const int backoffMaxMs = 10000;

  // --- 状态 ---
  DshConnectionState _state = DshConnectionState.disconnected;
  int _attempt = 0;
  int _generation = 0;
  DownlinkStream? _mux;
  DownlinkStream? _host;
  final _stateController = StreamController<DshConnectionState>.broadcast();
  final _muxController = StreamController<MuxFrame>.broadcast();
  final _hostController = StreamController<HostFrame>.broadcast();
  HostDescribe? _describe;
  bool _running = false;

  Stream<DshConnectionState> get stateChanges => _stateController.stream;
  DshConnectionState get state => _state;
  HostDescribe? get describe => _describe;
  RpcClient get rpc => _rpc;

  /// 全部 mux 帧的广播流（会话事件/审批/提问）。
  Stream<MuxFrame> get muxFrames => _muxController.stream;

  /// 全部 host 帧的广播流（会话列表/工作区变更）。
  Stream<HostFrame> get hostFrames => _hostController.stream;

  /// mux 帧回调（会话事件/审批/提问）。
  void Function(MuxFrame frame)? onMuxFrame;

  /// host 帧回调（会话列表/工作区变更）。
  void Function(HostFrame frame)? onHostFrame;

  /// 握手完成回调。
  void Function(HostDescribe describe)? onConnected;

  /// 每代重连回调（attempt 为第几次重试）。
  void Function(int attempt)? onReconnecting;

  void _setState(DshConnectionState s) {
    if (_state == s) return;
    _state = s;
    if (!_stateController.isClosed) _stateController.add(s);
  }

  /// 启动连接循环（幂等）。
  void start() {
    if (_running) return;
    _running = true;
    _loop();
  }

  /// 停止连接循环并关闭当前流的代。
  void stop() {
    _running = false;
    _generation++;
    _mux?.close();
    _host?.close();
    _mux = null;
    _host = null;
    _setState(DshConnectionState.disconnected);
  }

  Future<void> _loop() async {
    while (_running) {
      final gen = ++_generation;
      _setState(_attempt == 0 ? DshConnectionState.connecting : DshConnectionState.reconnecting);

      // 打开两条下行流（不等待，由握手统一判活）
      final mux = DownlinkStream(path: '/api/events.mux', baseUri: baseUri);
      final host = DownlinkStream(path: '/api/events.host', baseUri: baseUri);
      _mux = mux;
      _host = host;

      final muxEnd = mux.open();
      final hostEnd = host.open();
      mux.frames.listen((envelope) {
        if (gen != _generation) return;
        final frame = MuxFrame.fromEnvelope(envelope);
        // 单帧异常不得影响泵（与官方 sink 隔离一致）
        try {
          onMuxFrame?.call(frame);
          if (!_muxController.isClosed) _muxController.add(frame);
        } catch (e) {
          // ignore: avoid_print
          print('[dsh-mobile] mux frame handler threw: $e');
        }
      });
      host.frames.listen((envelope) {
        if (gen != _generation) return;
        try {
          final frame = HostFrame.fromEnvelope(envelope);
          onHostFrame?.call(frame);
          if (!_hostController.isClosed) _hostController.add(frame);
        } catch (e) {
          // ignore: avoid_print
          print('[dsh-mobile] host frame handler threw: $e');
        }
      });

      // 握手：host.describe 成功 + 双流已建 → connected
      final handshake = _rpc.callUnary('host.describe', const {}).then((result) {
        if (!result.isOk) {
          throw RpcTransportException('host.describe 失败: ${result.error}');
        }
        return HostDescribe.fromJson(result.value as Map<String, Object?>);
      });

      try {
        final describe = await handshake.timeout(const Duration(seconds: 10));
        if (!_running || gen != _generation) break;
        _attempt = 0;
        _describe = describe;
        _setState(DshConnectionState.connected);
        try {
          onConnected?.call(describe);
        } catch (e) {
          // ignore: avoid_print
          print('[dsh-mobile] onConnected threw: $e');
        }
      } catch (e) {
        // 握手失败：关闭本代流
        if (gen == _generation) {
          mux.close();
          host.close();
        }
      }

      // 等待本代流结束（握手成功则一直等到断线；失败则立即返回）
      final first = await _firstEnd([muxEnd, hostEnd]);
      if (first is DownlinkFailed) {
        // ignore: avoid_print
        print('[dsh-mobile] downlink failed: ${first.error}');
      }
      if (!_running || gen != _generation) return;

      // 一代结束：主动关闭仍开着的流，避免 WS 资源泄漏
      mux.close();
      host.close();

      _describe = null;
      _attempt += 1;
      _setState(DshConnectionState.reconnecting);
      try {
        onReconnecting?.call(_attempt);
      } catch (e) {
        // ignore: avoid_print
        print('[dsh-mobile] onReconnecting threw: $e');
      }

      // 退避后重连
      await Future<void>.delayed(_backoffDelay(_attempt));
    }
  }

  Future<DownlinkEnd> _firstEnd(List<Future<DownlinkEnd>> futures) async {
    final completer = Completer<DownlinkEnd>();
    for (final f in futures) {
      f.then((end) {
        if (!completer.isCompleted) completer.complete(end);
      });
    }
    return completer.future;
  }

  /// 官方同款退避：`cap/2 + random(0..cap/2)`，cap = min(max, base*factor^(attempt-1))。
  Duration _backoffDelay(int attempt) {
    final cap = min(backoffMaxMs, backoffBaseMs * pow(backoffFactor, max(0, attempt - 1)).toInt());
    final delay = cap ~/ 2 + Random().nextInt(cap ~/ 2 + 1);
    return Duration(milliseconds: delay);
  }

  void dispose() {
    stop();
    _stateController.close();
    _muxController.close();
    _hostController.close();
    _rpc.close();
  }
}
