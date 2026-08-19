/// 信封编解码 + 帧解析单元测试（纯 Dart，不依赖网络）。
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:dsh_mobile/core/protocol/envelope.dart';
import 'package:dsh_mobile/core/protocol/host_frame.dart';
import 'package:dsh_mobile/core/protocol/mux_frame.dart';
import 'package:dsh_mobile/core/protocol/rpc_client.dart';

void main() {
  group('envelope', () {
    test('client-request 编解码往返', () {
      const request = ClientRequest(rpcId: 'r-1', method: 'session.list', payload: <String, Object?>{});
      final json = request.toJson();
      expect(json['type'], 'client-request');
      expect(json['method'], 'session.list');
      final decoded = Envelope.fromJson(json);
      expect(decoded, isA<ClientRequest>());
      final dr = decoded as ClientRequest;
      expect(dr.rpcId, 'r-1');
      expect(dr.payload, <String, Object?>{});
    });

    test('server-response ok 分支', () {
      const json = {
        'type': 'server-response',
        'rpcId': 'r-1',
        'result': {'ok': true, 'value': {'version': '0.1.0', 'cwd': '/tmp'}},
      };
      final envelope = Envelope.fromJson(json);
      final response = envelope as ServerResponse;
      expect(response.result.isOk, isTrue);
      final value = response.result.value as Map<String, Object?>;
      expect(value['version'], '0.1.0');
    });

    test('server-response error 分支', () {
      const json = {
        'type': 'server-response',
        'rpcId': 'r-2',
        'result': {
          'ok': false,
          'error': {'code': 'unknown-session', 'message': 'no such session', 'details': <String, Object?>{}},
        },
      };
      final envelope = Envelope.fromJson(json);
      final response = envelope as ServerResponse;
      expect(response.result.isOk, isFalse);
      expect(response.result.error!.code, 'unknown-session');
    });

    test('mintRpcId 生成合法 UUID v4', () {
      final id = mintRpcId();
      final pattern = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');
      expect(pattern.hasMatch(id), isTrue);
      expect(mintRpcId() == mintRpcId(), isFalse);
    });
  });

  group('mux frames', () {
    Map<String, Object?> envelopeWith(String type, Map<String, Object?> payload) =>
        {'type': 'server-request', 'rpcId': 'rpc-9', 'method': 'events.mux', 'payload': {'type': type, ...payload}};

    test('session/event 帧', () {
      final envelope = Envelope.fromJson(envelopeWith('session/event', {
        'sessionId': 's1',
        'event': {
          'type': 'assistant/message',
          'seq': 3,
          'time': 1234,
          'data': {'message': {'id': 'm1', 'content': <Object?>[], 'source': {'kind': 'model'}}},
        },
      }));
      final frame = MuxFrame.fromEnvelope(envelope as ServerRequest);
      expect(frame, isA<SessionEventFrame>());
      final f = frame as SessionEventFrame;
      expect(f.sessionId, 's1');
      expect(f.event.type, 'assistant/message');
      expect(f.event.seq, 3);
    });

    test('approval/requested 帧', () {
      final envelope = Envelope.fromJson(envelopeWith('approval/requested', {
        'sessionId': 's1',
        'approvalId': 'a1',
        'toolName': 'bash',
        'reason': 'run ls',
      }));
      final frame = MuxFrame.fromEnvelope(envelope as ServerRequest);
      expect(frame, isA<ApprovalRequestedFrame>());
      final f = frame as ApprovalRequestedFrame;
      expect(f.approvalId, 'a1');
      expect(f.toolName, 'bash');
      expect(f.rpcId, 'rpc-9'); // respond 时回填
    });

    test('question/requested 帧', () {
      final envelope = Envelope.fromJson(envelopeWith('question/requested', {
        'sessionId': 's1',
        'questions': [
          {'id': 'q1', 'question': '继续吗？', 'options': [{'label': '是'}], 'multiSelect': false},
        ],
      }));
      final frame = MuxFrame.fromEnvelope(envelope as ServerRequest);
      expect(frame, isA<QuestionRequestedFrame>());
      final f = frame as QuestionRequestedFrame;
      expect(f.questions.single.id, 'q1');
      expect(f.questions.single.multiSelect, isFalse);
    });

    test('未知帧类型保留原始 payload（前向兼容）', () {
      final envelope = Envelope.fromJson(envelopeWith('host/whatever-new', {'sessionId': 's1'}));
      final frame = MuxFrame.fromEnvelope(envelope as ServerRequest);
      expect(frame, isA<UnknownFrame>());
    });
  });

  group('host frames', () {
    test('session-added 帧', () {
      final envelope = Envelope.fromJson({
        'type': 'server-request',
        'rpcId': 'rpc-1',
        'method': 'events.host',
        'payload': {'type': 'host/session-added', 'sessionId': 's2', 'blank': true},
      });
      final frame = HostFrame.fromEnvelope(envelope as ServerRequest);
      expect(frame, isA<SessionAddedFrame>());
      final f = frame as SessionAddedFrame;
      expect(f.sessionId, 's2');
      expect(f.blank, isTrue);
    });

    test('session-status 帧', () {
      final envelope = Envelope.fromJson({
        'type': 'server-request',
        'rpcId': 'rpc-2',
        'method': 'events.host',
        'payload': {'type': 'host/session-status', 'sessionId': 's2', 'running': true},
      });
      final frame = HostFrame.fromEnvelope(envelope as ServerRequest);
      expect(frame, isA<SessionStatusFrame>());
      expect((frame as SessionStatusFrame).running, isTrue);
    });
  });

  group('rpc client', () {
    test('normalizeBase 补齐协议和默认端口', () {
      expect(RpcClient.normalizeBase('192.168.1.5:3080').toString(), 'http://192.168.1.5:3080');
      expect(RpcClient.normalizeBase('http://localhost:3080').toString(), 'http://localhost:3080');
      expect(RpcClient.normalizeBase('http://100.64.0.1').toString(), 'http://100.64.0.1:3080');
      expect(RpcClient.normalizeBase('https://harness.example.com:8443').toString(), 'https://harness.example.com:8443');
    });

    test('信封 JSON 与官方示例字节一致', () {
      const request = ClientRequest(rpcId: 'r-1', method: 'host.describe', payload: <String, Object?>{});
      final encoded = jsonEncode(request.toJson());
      final decoded = jsonDecode(encoded) as Map<String, Object?>;
      expect(decoded['type'], 'client-request');
      expect(decoded['method'], 'host.describe');
    });
  });
}
