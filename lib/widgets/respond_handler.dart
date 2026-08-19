/// 全局审批/提问处理器：监听 mux 流，弹 UI，回发 /api/respond。
///
/// 协议确认（对照官方实现）：
/// - 审批应答：`client-response`，rpcId = approval/requested 帧的 rpcId，
///   result = `{ok:true, value:{approvalId, outcome:"allowed-once"|"rejected"}}`
/// - 提问应答：`client-response`，rpcId = question/requested 帧的 rpcId，
///   result = `{ok:true, value:{answers:[{id, selected:[], custom?}]}}`；
///   ok=false 表示取消（outcome: cancelled）
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../core/protocol/connection.dart';
import '../core/protocol/envelope.dart';
import '../core/protocol/mux_frame.dart';
import '../navigation.dart';
import '../state/app_state.dart';

/// 挂在 MaterialApp 之下；连接变化时自动订阅/退订。
class RespondHandler extends StatefulWidget {
  const RespondHandler({super.key, required this.child});
  final Widget child;

  @override
  State<RespondHandler> createState() => _RespondHandlerState();
}

class _RespondHandlerState extends State<RespondHandler> {
  StreamSubscription<MuxFrame>? _muxSub;
  DshConnection? _bound;

  @override
  Widget build(BuildContext context) => widget.child;

  @override
  void initState() {
    super.initState();
    final state = AppState.instance;
    state.addListener(_onAppStateChanged);
    _rebind();
  }

  void _onAppStateChanged() => _rebind();

  void _rebind() {
    final conn = AppState.instance.conn;
    if (identical(conn, _bound)) return;
    _muxSub?.cancel();
    _bound = conn;
    if (conn == null) return;
    _muxSub = conn.muxFrames.listen(_handle);
  }

  Future<void> _handle(MuxFrame frame) async {
    switch (frame) {
      case ApprovalRequestedFrame f:
        await _showApproval(f);
      case QuestionRequestedFrame f:
        await _showQuestions(f);
      default:
        break;
    }
  }

  Future<void> _showApproval(ApprovalRequestedFrame f) async {
    final nav = appNavigatorKey.currentState;
    if (nav == null) return;
    final outcome = await showModalBottomSheet<String>(
      context: nav.context,
      builder: (ctx) => _ApprovalSheet(frame: f),
    );
    if (outcome == null) return;
    final conn = AppState.instance.conn;
    if (conn == null) return;
    try {
      await conn.rpc.respond(ClientResponse(
        rpcId: f.rpcId,
        result: RpcResult.ok({
          'approvalId': f.approvalId,
          'outcome': outcome,
        }),
      ));
    } catch (e) {
      _toast('应答失败: $e');
    }
  }

  Future<void> _showQuestions(QuestionRequestedFrame f) async {
    if (f.questions.isEmpty) return;
    final nav = appNavigatorKey.currentState;
    if (nav == null) return;
    final answers = <Map<String, Object?>>[];
    for (final q in f.questions) {
      final result = await showDialog<Map<String, Object?>>(
        context: nav.context,
        builder: (ctx) => _QuestionDialog(item: q),
      );
      if (result == null) {
        // 用户取消整个批次
        final conn = AppState.instance.conn;
        if (conn != null) {
          await conn.rpc.respond(ClientResponse(
            rpcId: f.rpcId,
            result: RpcResult.error(const RpcError(code: 'cancelled', message: '用户取消')),
          ));
        }
        return;
      }
      answers.add(result);
    }
    final conn = AppState.instance.conn;
    if (conn == null) return;
    await conn.rpc.respond(ClientResponse(
      rpcId: f.rpcId,
      result: RpcResult.ok({'answers': answers}),
    ));
  }

  void _toast(String message) {
    final nav = appNavigatorKey.currentState;
    if (nav == null || !nav.mounted) return;
    ScaffoldMessenger.of(nav.context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    AppState.instance.removeListener(_onAppStateChanged);
    _muxSub?.cancel();
    super.dispose();
  }
}

/// 审批卡片：允许一次 / 拒绝。
class _ApprovalSheet extends StatelessWidget {
  const _ApprovalSheet({required this.frame});
  final ApprovalRequestedFrame frame;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.shield_outlined, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('工具执行请求', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 12),
            Text('Agent 请求执行工具：${frame.toolName}',
                style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
            if (frame.reason != null && frame.reason!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(frame.reason!, style: theme.textTheme.bodyMedium),
            ],
            if (frame.callId != null) ...[
              const SizedBox(height: 8),
              Text('callId: ${frame.callId}', style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, 'rejected'),
                    child: const Text('拒绝'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, 'allowed-once'),
                    child: const Text('允许一次'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 单个提问：选项选择 / 自定义输入。
class _QuestionDialog extends StatefulWidget {
  const _QuestionDialog({required this.item});
  final QuestionItem item;

  @override
  State<_QuestionDialog> createState() => _QuestionDialogState();
}

class _QuestionDialogState extends State<_QuestionDialog> {
  final _customController = TextEditingController();
  String? _selected;
  final List<String> _multiSelected = [];

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final options = item.options;
    final multiSelect = item.multiSelect;
    final labels = options
        .map((o) => o['label'] is String ? o['label'] as String : '${o['label']}')
        .toList();

    return AlertDialog(
      title: Text(item.header ?? '模型提问'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item.question),
            if (labels.isNotEmpty) ...[
              const SizedBox(height: 12),
              if (multiSelect)
                ...labels.map((label) => CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(label),
                      value: _multiSelected.contains(label),
                      onChanged: (v) => setState(() {
                        if (v == true) {
                          _multiSelected.add(label);
                        } else {
                          _multiSelected.remove(label);
                        }
                      }),
                    ))
              else
                RadioGroup<String>(
                  groupValue: _selected,
                  onChanged: (v) => setState(() => _selected = v),
                  child: Column(
                    children: labels
                        .map((label) => RadioListTile<String>(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: Text(label),
                              value: label,
                            ))
                        .toList(),
                  ),
                ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _customController,
              decoration: const InputDecoration(
                labelText: '自定义答案（可选）',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            final custom = _customController.text.trim();
            final selected = multiSelect ? _multiSelected : (_selected == null ? <String>[] : [_selected!]);
            Navigator.pop(context, {
              'id': item.id,
              'selected': selected,
              if (custom.isNotEmpty) 'custom': custom,
            });
          },
          child: const Text('提交'),
        ),
      ],
    );
  }
}
