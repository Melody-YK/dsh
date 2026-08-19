/// DSH /api 一元 RPC 的 HTTP 载体。
///
/// 协议要点（与官方 `dsh-client-connection` 一致）：
/// - `POST {base}/api/<method>`，body 为 client-request 信封，content-type: application/json
/// - 响应体为 server-response 信封，rpcId 必须回显请求的 rpcId
/// - 非 2xx → 传输层错误；2xx 但信封不合法 → 解析错误
/// - result.ok == false → 返回失败分支的 [RpcResult]（业务错误，不是异常）
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'envelope.dart';

/// 传输层错误（网络不可达、非 2xx、响应无法解析）。
class RpcTransportException implements Exception {
  RpcTransportException(this.message, {this.cause});
  final String message;
  final Object? cause;

  @override
  String toString() => 'RpcTransportException: $message';
}

/// 一元 RPC 客户端：只负责 HTTP 信封往返，不关心方法语义。
class RpcClient {
  RpcClient(this.baseUri, {http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  final Uri baseUri;
  final http.Client _http;

  /// 归一化 base：`http://host:port`（尾部斜杠会被 trim）。
  static Uri normalizeBase(String raw) {
    var s = raw.trim();
    if (!s.contains('://')) s = 'http://$s';
    final uri = Uri.parse(s);
    final scheme = uri.scheme == 'https' ? 'https' : 'http';
    final host = uri.host;
    final port = uri.hasPort ? uri.port : (scheme == 'https' ? 443 : 3080);
    return Uri(scheme: scheme, host: host, port: port);
  }

  /// 调用一个一元方法。payload 与响应 value 都是 JSON 值。
  ///
  /// 抛 [RpcTransportException] 表示传输/信封层失败；
  /// 返回 [RpcResult.error] 表示服务器端业务错误。
  Future<RpcResult> callUnary(String method, Object? payload, {Duration? timeout}) async {
    final rpcId = mintRpcId();
    final request = ClientRequest(rpcId: rpcId, method: method, payload: payload);
    final uri = baseUri.replace(path: '/api/$method');

    final http.Response response;
    try {
      response = await _http
          .post(
            uri,
            headers: const {'content-type': 'application/json'},
            body: jsonEncode(request.toJson()),
          )
          .timeout(timeout ?? const Duration(seconds: 90));
    } on SocketException catch (e) {
      throw RpcTransportException('无法连接 ${baseUri.host}:${baseUri.port}: ${e.message}', cause: e);
    } on http.ClientException catch (e) {
      throw RpcTransportException('请求失败: ${e.message}', cause: e);
    } on TimeoutException {
      throw RpcTransportException('请求超时: $method');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw RpcTransportException('$method 返回 HTTP ${response.statusCode}');
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException catch (e) {
      throw RpcTransportException('$method 响应不是合法 JSON', cause: e);
    }

    final Envelope envelope;
    try {
      envelope = Envelope.fromJson(decoded as Map<String, Object?>);
    } catch (e) {
      throw RpcTransportException('$method 响应信封不合法: $e', cause: e);
    }
    if (envelope is! ServerResponse) {
      throw RpcTransportException('$method 响应类型异常: ${envelope.type.wire}');
    }
    if (envelope.rpcId != rpcId) {
      throw RpcTransportException('$method rpcId 不匹配: 发送 $rpcId，收到 ${envelope.rpcId}');
    }
    return envelope.result;
  }

  /// POST /api/respond（审批/提问应答）。返回收据：`{accepted: true}` 或
  /// `{accepted: false, reason}`。
  Future<Map<String, Object?>> respond(ClientResponse response) async {
    final uri = baseUri.replace(path: '/api/respond');
    final http.Response res;
    try {
      res = await _http
          .post(
            uri,
            headers: const {'content-type': 'application/json'},
            body: jsonEncode(response.toJson()),
          )
          .timeout(const Duration(seconds: 15));
    } on SocketException catch (e) {
      throw RpcTransportException('respond 无法连接: ${e.message}', cause: e);
    } on http.ClientException catch (e) {
      throw RpcTransportException('respond 请求失败: ${e.message}', cause: e);
    } on TimeoutException {
      throw RpcTransportException('respond 请求超时');
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw RpcTransportException('respond 返回 HTTP ${res.statusCode}');
    }
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    if (decoded is! Map<String, Object?>) {
      throw RpcTransportException('respond 响应不是 JSON 对象');
    }
    return decoded;
  }

  void close() => _http.close();
}
