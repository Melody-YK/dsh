/// 聊天页：历史 + 实时事件流 + 输入框 + 取消生成。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../core/api/sessions_api.dart';
import '../state/app_state.dart';
import '../state/chat_controller.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.sessionId});
  final String sessionId;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  static const _primary = Color(0xFF4D6BFE);

  ChatController? _controller;
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  bool _sending = false;
  ModelSelection? _currentModel;

  @override
  void initState() {
    super.initState();
    final conn = AppState.instance.conn;
    if (conn == null) return;
    final controller = ChatController(sessionId: widget.sessionId, connection: conn);
    _controller = controller;
    controller.onReady = () {
      if (mounted) _scrollToBottom(animated: false);
    };
    controller.addListener(_onChatChanged);
    _scrollController.addListener(() {
      final c = _controller;
      if (c == null || !c.hasMore || c.loading) return;
      if (!_scrollController.hasClients) return;
      final pos = _scrollController.position;
      if (pos.pixels >= pos.maxScrollExtent - 200) {
        c.loadMore();
      }
    });
    controller.start();
    _loadCurrentModel();
  }

  Future<void> _loadCurrentModel() async {
    final conn = AppState.instance.conn;
    if (conn == null) return;
    try {
      final catalog = await SessionsApi(conn.rpc).models(widget.sessionId);
      if (!mounted) return;
      setState(() => _currentModel = catalog.current);
    } catch (_) {}
  }

  void _onChatChanged() {
    if (!mounted) return;
    setState(() {});
    if (_scrollController.hasClients && _scrollController.position.pixels < 200) {
      _scrollToBottom();
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_onChatChanged);
    _controller?.dispose();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom({bool animated = true}) {
    if (!_scrollController.hasClients) return;
    if (animated) {
      _scrollController.animateTo(0, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    } else {
      _scrollController.jumpTo(0);
    }
  }

  Future<void> _send() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _sending) return;
    final conn = AppState.instance.conn;
    if (conn == null) return;
    _inputController.clear();
    setState(() => _sending = true);
    try {
      await SessionsApi(conn.rpc).prompt(widget.sessionId, [PromptTextPart(text)]);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('发送失败: $e')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _cancel() async {
    try {
      final conn = AppState.instance.conn;
      if (conn != null) await SessionsApi(conn.rpc).cancel(widget.sessionId);
    } catch (_) {}
  }

  Future<void> _showModelPicker() async {
    final conn = AppState.instance.conn;
    if (conn == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('未连接')));
      return;
    }
    ModelCatalog catalog;
    try {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('加载模型列表…'), duration: Duration(seconds: 1)),
        );
      }
      catalog = await SessionsApi(conn.rpc).models(widget.sessionId);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('获取模型失败: $e')));
      return;
    }
    if (!mounted) return;

    final picked = await showModalBottomSheet<(String, String, List<String>)>(
      context: context,
      builder: (ctx) => _ModelPickerSheet(catalog: catalog),
    );
    if (picked == null || !mounted) return;

    final (provider, model, efforts) = picked;
    String? effort;
    if (efforts.isNotEmpty) {
      effort = await _pickReasoningEffort(efforts, currentEffort: _currentModel?.reasoningEffort);
      if (effort == null && mounted) return;
      if (effort == '') effort = null;
    }
    try {
      await SessionsApi(conn.rpc).selectModel(widget.sessionId, provider: provider, model: model, reasoningEffort: effort);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已切换: $provider / $model${effort != null ? '（$effort）' : ''}')),
      );
      _loadCurrentModel();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('切换失败: $e')));
    }
  }

  Future<String?> _pickReasoningEffort(List<String> efforts, {String? currentEffort}) async {
    return showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('推理档位', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
            ListTile(
              leading: const Icon(Icons.auto_awesome_outlined),
              title: const Text('不指定（用模型默认）'),
              trailing: currentEffort == null ? const Icon(Icons.check, size: 18) : null,
              onTap: () => Navigator.pop(ctx, ''),
            ),
            for (final e in efforts)
              ListTile(
                leading: const Icon(Icons.psychology_outlined),
                title: Text(e),
                trailing: currentEffort == e ? const Icon(Icons.check, size: 18) : null,
                onTap: () => Navigator.pop(ctx, e),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = _controller;
    final running = AppState.instance.runningSessions.any((s) => s.sessionId == widget.sessionId);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 4,
        title: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: _showModelPicker,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.chat_bubble_outline, size: 16),
                    const SizedBox(width: 6),
                    Text(widget.sessionId.substring(0, 8), overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 6),
                    const Icon(Icons.expand_more, size: 16),
                  ],
                ),
                if (_currentModel != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 22),
                    child: Text(
                      '${_currentModel!.model}${_currentModel!.reasoningEffort != null ? ' · ${_currentModel!.reasoningEffort}' : ''}',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: _primary),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          if (running)
            IconButton(
              icon: const Icon(Icons.stop_circle_outlined, color: Colors.redAccent),
              tooltip: '取消生成',
              onPressed: _cancel,
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: controller == null
                  ? const Center(child: Text('未连接'))
                  : ListenableBuilder(
                      listenable: controller,
                      builder: (ctx, _) {
                        if (controller.loading && controller.messages.isEmpty) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        if (controller.error != null && controller.messages.isEmpty) {
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(controller.error!, style: TextStyle(color: theme.colorScheme.error)),
                            ),
                          );
                        }
                        final messages = controller.messages;
                        return ListView.builder(
                          controller: _scrollController,
                          reverse: true,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: messages.length,
                          itemBuilder: (ctx, i) => _MessageBubble(message: messages[messages.length - 1 - i]),
                        );
                      },
                    ),
            ),
            if (running) const LinearProgressIndicator(minHeight: 2, backgroundColor: Colors.transparent),
            _buildInputBar(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildInputBar(ThemeData theme) {
    return Container(
      padding: EdgeInsets.only(left: 12, right: 8, top: 10, bottom: 10 + MediaQuery.of(context).padding.bottom),
      decoration: const BoxDecoration(
        color: Color(0xFF151517),
        border: Border(top: BorderSide(color: Color(0xFF2C2C2E), width: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF232325),
                borderRadius: BorderRadius.circular(24),
              ),
              child: TextField(
                controller: _inputController,
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                style: const TextStyle(fontSize: 15),
                decoration: const InputDecoration(
                  hintText: '输入消息…',
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            decoration: const BoxDecoration(color: _primary, shape: BoxShape.circle),
            child: IconButton(
              onPressed: _sending ? null : _send,
              icon: _sending
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send_rounded, color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}

/// 单条消息气泡。
class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});
  final ChatMessage message;

  static const _primary = Color(0xFF4D6BFE);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    switch (message.role) {
      case 'user':
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Align(
            alignment: Alignment.centerRight,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 300),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: _primary.withAlpha(40),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(18), topRight: Radius.circular(18),
                  bottomLeft: Radius.circular(18), bottomRight: Radius.circular(4),
                ),
              ),
              child: Text(message.text ?? '', style: const TextStyle(fontSize: 15, height: 1.4)),
            ),
          ),
        );
      case 'assistant':
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 330),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF202124),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(18), topRight: Radius.circular(18),
                  bottomLeft: Radius.circular(4), bottomRight: Radius.circular(18),
                ),
                border: Border.all(color: const Color(0xFF2C2C2E), width: 0.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (message.model != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(message.model!, style: const TextStyle(fontSize: 11, color: _primary, fontWeight: FontWeight.w600)),
                    ),
                  if (message.reasoning != null && message.reasoning!.isNotEmpty)
                    _ReasoningBlock(reasoning: message.reasoning!),
                  if (message.text != null && message.text!.isNotEmpty)
                    MarkdownBody(
                      data: message.text!,
                      styleSheet: MarkdownStyleSheet(
                        p: const TextStyle(fontSize: 15, height: 1.5, color: Colors.white),
                        code: TextStyle(fontSize: 13, backgroundColor: const Color(0xFF2C2C2E), fontFamily: 'monospace'),
                        blockquoteDecoration: const BoxDecoration(
                          border: Border(left: BorderSide(color: _primary, width: 3)),
                        ),
                        codeblockDecoration: BoxDecoration(
                          color: const Color(0xFF151517),
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

/// 思考过程折叠块：默认只显示前几行，点击展开/收起。
class _ReasoningBlock extends StatefulWidget {
  const _ReasoningBlock({required this.reasoning});
  final String reasoning;

  @override
  State<_ReasoningBlock> createState() => _ReasoningBlockState();
}

class _ReasoningBlockState extends State<_ReasoningBlock> {
  bool _expanded = false;

  static const _primary = Color(0xFF4D6BFE);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final full = widget.reasoning;
    const previewLen = 160;
    final collapsed = full.length <= previewLen;
    final shown = _expanded || collapsed ? full : '${full.substring(0, previewLen)}…';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF151517),
        borderRadius: BorderRadius.circular(10),
        border: const Border(left: BorderSide(color: _primary, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.psychology_outlined, size: 14, color: _primary),
              const SizedBox(width: 6),
              const Text('思考过程', style: TextStyle(fontSize: 12, color: _primary, fontWeight: FontWeight.w600)),
              const Spacer(),
              if (!collapsed)
                InkWell(
                  onTap: () => setState(() => _expanded = !_expanded),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_expanded ? '收起' : '展开', style: const TextStyle(fontSize: 11, color: _primary)),
                      Icon(_expanded ? Icons.expand_less : Icons.expand_more, size: 16, color: _primary),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(shown, style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurfaceVariant, height: 1.4)),
        ],
      ),
    );
  }
}

/// 模型选择底部弹窗：按 provider 分组，当前模型打勾，点击返回选择。
class _ModelPickerSheet extends StatelessWidget {
  const _ModelPickerSheet({required this.catalog});
  final ModelCatalog catalog;

  static const _primary = Color(0xFF4D6BFE);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = catalog.current;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('切换模型（当前：${current.provider} / ${current.model}）', style: theme.textTheme.titleMedium),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final group in catalog.groups) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Text(group.name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _primary)),
                  ),
                  for (final model in group.models)
                    ListTile(
                      dense: true,
                      leading: Icon(
                        (group.id == current.provider && model.id == current.model) ? Icons.radio_button_checked : Icons.radio_button_off,
                        color: (group.id == current.provider && model.id == current.model) ? _primary : theme.colorScheme.outline,
                      ),
                      title: Text(model.name),
                      subtitle: Text(
                        '${group.id} / ${model.id}${model.reasoningEfforts.isNotEmpty ? ' · ${model.reasoningEfforts.length} 档推理' : ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => Navigator.pop(context, (group.id, model.id, model.reasoningEfforts)),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}