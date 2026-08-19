/// DSH /api 四象限 RPC 信封模型。
///
/// 协议来源：`@deepseek-ai/dsh-client-connection` 与 `@deepseek-ai/dsh-host-apiproxy`
/// 的 api/rpc 消息模型。四个成员是判别联合（type 字段）：
///
/// - [ClientRequest]  客户端→服务器 一元调用（HTTP POST /api/<method>）
/// - [ServerResponse] 服务器→客户端 一元调用结果（HTTP 响应体）
/// - [ServerRequest]  服务器→客户端 下行推送（WebSocket /api/events.* 帧）
/// - [ClientResponse] 客户端→服务器 应答（HTTP POST /api/respond）
///
/// 物理载体（HTTP/WS/SSE）与逻辑消息解耦：本文件只负责 JSON 编解码。
library;

import 'dart:math';

/// RPC 消息类型判别字段。
enum RpcType {
  clientRequest('client-request'),
  serverResponse('server-response'),
  serverRequest('server-request'),
  clientResponse('client-response');

  const RpcType(this.wire);
  final String wire;

  static RpcType fromWire(String value) =>
      values.firstWhere((t) => t.wire == value, orElse: () => throw FormatException('unknown rpc type: $value'));
}

/// 一元调用成功分支的 value。
class RpcOk {
  RpcOk(this.value);
  final Object? value;

  factory RpcOk.fromJson(Map<String, Object?> json) => RpcOk(json['value']);
}

/// 一元调用失败分支的 error。
class RpcError {
  const RpcError({required this.code, required this.message, this.details = const {}});

  factory RpcError.fromJson(Map<String, Object?> json) => RpcError(
        code: json['code'] as String,
        message: json['message'] as String,
        details: (json['details'] as Map<String, Object?>?) ?? const {},
      );

  final String code;
  final String message;
  final Map<String, Object?> details;

  @override
  String toString() => 'RpcError($code: $message)';
}

/// `result` 槽：`{ok: true, value}` 或 `{ok: false, error}`。
class RpcResult {
  RpcResult.ok(this.value) : error = null;
  RpcResult.error(this.error) : value = null;

  factory RpcResult.fromJson(Map<String, Object?> json) {
    final ok = json['ok'] as bool;
    if (ok) return RpcResult.ok(json['value']);
    return RpcResult.error(RpcError.fromJson(json['error'] as Map<String, Object?>));
  }

  final Object? value;
  final RpcError? error;
  bool get isOk => error == null;

  Map<String, Object?> toJson() => isOk
      ? {'ok': true, 'value': value}
      : {'ok': false, 'error': {'code': error!.code, 'message': error!.message, 'details': error!.details}};
}

/// 消息信封基类。
sealed class Envelope {
  const Envelope({required this.rpcId});
  final String rpcId;

  RpcType get type;

  Map<String, Object?> toJson();

  static Envelope fromJson(Map<String, Object?> json) {
    final type = RpcType.fromWire(json['type'] as String);
    final rpcId = json['rpcId'] as String;
    return switch (type) {
      RpcType.clientRequest => ClientRequest(
          rpcId: rpcId,
          method: json['method'] as String,
          payload: json['payload'],
        ),
      RpcType.serverResponse => ServerResponse(rpcId: rpcId, result: RpcResult.fromJson(json['result'] as Map<String, Object?>)),
      RpcType.serverRequest => ServerRequest(
          rpcId: rpcId,
          method: json['method'] as String,
          payload: json['payload'],
        ),
      RpcType.clientResponse => ClientResponse(rpcId: rpcId, result: RpcResult.fromJson(json['result'] as Map<String, Object?>)),
    };
  }
}

/// 客户端→服务器 一元调用（POST /api/<method>）。
class ClientRequest extends Envelope {
  const ClientRequest({required super.rpcId, required this.method, required this.payload});

  final String method;
  final Object? payload;

  @override
  RpcType get type => RpcType.clientRequest;

  @override
  Map<String, Object?> toJson() => {'type': type.wire, 'rpcId': rpcId, 'method': method, 'payload': payload};
}

/// 服务器→客户端 一元调用结果。
class ServerResponse extends Envelope {
  const ServerResponse({required super.rpcId, required this.result});

  final RpcResult result;

  @override
  RpcType get type => RpcType.serverResponse;

  @override
  Map<String, Object?> toJson() => {'type': type.wire, 'rpcId': rpcId, 'result': result.toJson()};
}

/// 服务器→客户端 下行推送（WS 帧 / SSE data 行）。
class ServerRequest extends Envelope {
  const ServerRequest({required super.rpcId, required this.method, required this.payload});

  final String method;
  final Object? payload;

  @override
  RpcType get type => RpcType.serverRequest;

  @override
  Map<String, Object?> toJson() => {'type': type.wire, 'rpcId': rpcId, 'method': method, 'payload': payload};
}

/// 客户端→服务器 应答（POST /api/respond）。
class ClientResponse extends Envelope {
  const ClientResponse({required super.rpcId, required this.result});

  final RpcResult result;

  @override
  RpcType get type => RpcType.clientResponse;

  @override
  Map<String, Object?> toJson() => {'type': type.wire, 'rpcId': rpcId, 'result': result.toJson()};
}

/// RFC 4122 v4 UUID（协议要求 rpcId 由发起方生成）。
/// Flutter 全平台可用：VM 上 `Random.secure()` 读系统熵源，Web 上映射到
/// `crypto.getRandomValues`。
String mintRpcId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 10
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
