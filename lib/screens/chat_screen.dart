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
  ChatController? _controller;
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  bool _sending = false;

  /// 当前会话使用的模型（进入页面时加载，切换后刷新）。
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
    // 向上滑到更早消息处（reverse 列表的 maxScrollExtent）时加载更多历史
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

  /// 加载当前会话的模型，显示在 AppBar。
  Future<void> _loadCurrentModel() async {
    final conn = AppState.instance.conn;
    if (conn == null) return;
    try {
      final catalog = await SessionsApi(conn.rpc).models(widget.sessionId);
      if (!mounted) return;
      setState(() => _currentModel = catalog.current);
    } catch (_) {
      // 模型信息加载失败不影响聊天
    }
  }

  void _onChatChanged() {
    if (!mounted) return;
    setState(() {});
    // 只有用户在底部附近（reverse: offset 接近 0）时才自动跟随到底部；
    // 用户滚上去看历史时不打扰
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
    // reverse 列表：offset 0 = 底部（最新消息）
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
    setState(() => _sending = true);
    _inputController.clear();
    // 乐观回显：发消息立即在界面显示
    _controller?.addOptimistic(text);
    try {
      final api = SessionsApi(conn.rpc);
      // 不传 clientTimeZone：Dart 的 timeZoneName 是本地化名称（如"中国标准时间"），
      // 不是 IANA Area/Location 名，服务端会拒绝（invalid-time-zone）
      await api.prompt(widget.sessionId, [PromptTextPart(text)]);
    } catch (e) {
      _controller?.removeOptimistic(text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('发送失败: $e')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _cancel() async {
    final conn = AppState.instance.conn;
    if (conn == null) return;
    try {
      await SessionsApi(conn.rpc).cancel(widget.sessionId);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('取消失败: $e')));
    }
  }

  /// 弹出模型选择：列出当前会话可用模型分组，点击切换（含推理档位）。
  Future<void> _showModelPicker() async {
    final conn = AppState.instance.conn;
    if (conn == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('未连接，无法切换模型')));
      return;
    }
    ModelCatalog catalog;
    try {
      // 先给用户反馈，避免看起来"卡住"
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

    // 选模型：返回 (provider, model, 支持的推理档位)
    final picked = await showModalBottomSheet<(String, String, List<String>)>(
      context: context,
      builder: (ctx) => _ModelPickerSheet(catalog: catalog),
    );
    if (picked == null || !mounted) return;

    final (provider, model, efforts) = picked;

    // 模型支持推理档位 → 再选档位
    String? effort;
    if (efforts.isNotEmpty) {
      effort = await _pickReasoningEffort(efforts, currentEffort: _currentModel?.reasoningEffort);
      if (effort == null && mounted) return; // 用户下滑关闭 = 取消切换
      if (effort == '') effort = null; // "不指定" = 用模型默认
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

  /// 推理档位选择（含"不指定"选项）。
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
        // 标题：会话 id + 当前模型（可点击弹出模型选择）
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.sessionId, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16)),
            if (_currentModel != null)
              Text(
                '${_currentModel!.model}${_currentModel!.reasoningEffort != null ? ' · ${_currentModel!.reasoningEffort}' : ''}',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.primary),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: '切换模型',
            onPressed: _showModelPicker,
          ),
          if (running)
            IconButton(
              icon: const Icon(Icons.stop_circle_outlined),
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
                  : AnimatedBuilder(
                      animation: controller,
                      builder: (ctx, _) {
                        if (controller.loading && controller.messages.isEmpty) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        if (controller.error != null && controller.messages.isEmpty) {
                          return Center(
                            child: Text(controller.error!, style: TextStyle(color: theme.colorScheme.error)),
                          );
                        }
                        final messages = controller.messages;
                        // reverse: true 让最新消息默认显示在底部（offset 0 = 底部），
                        // itemBuilder 倒序访问：index 0 = 最新消息
                        return ListView.builder(
                          controller: _scrollController,
                          reverse: true,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          itemCount: messages.length,
                          itemBuilder: (ctx, i) => _MessageBubble(message: messages[messages.length - 1 - i]),
                        );
                      },
                    ),
            ),
            if (running) const LinearProgressIndicator(minHeight: 2),
            _buildInputBar(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildInputBar(ThemeData theme) {
    return Container(
      padding: EdgeInsets.only(
        left: 12,
        right: 8,
        top: 8,
        bottom: 8 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(top: BorderSide(color: theme.colorScheme.outlineVariant)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: _inputController,
              minLines: 1,
              maxLines: 5,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              decoration: const InputDecoration(
                hintText: '输入消息…',
                border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(20))),
                contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 4),
          IconButton.filled(
            onPressed: _sending ? null : _send,
            icon: const Icon(Icons.send),
            tooltip: '发送',
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    switch (message.role) {
      case 'user':
        return Align(
          alignment: Alignment.centerRight,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            constraints: const BoxConstraints(maxWidth: 300),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(message.text ?? '', style: theme.textTheme.bodyMedium),
          ),
        );
      case 'assistant':
        return Align(
          alignment: Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            constraints: const BoxConstraints(maxWidth: 320),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (message.model != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      message.model!,
                      style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.primary),
                    ),
                  ),
                // 思考过程：默认折叠，点按钮展开完整内容
                if (message.reasoning != null && message.reasoning!.isNotEmpty)
                  _ReasoningBlock(reasoning: message.reasoning!),
                // 正式回答是 Markdown，用渲染器展示
                if (message.text != null && message.text!.isNotEmpty)
                  MarkdownBody(
                    data: message.text!,
                    styleSheet: MarkdownStyleSheet(
                      p: theme.textTheme.bodyMedium,
                      code: theme.textTheme.bodySmall?.copyWith(
                        backgroundColor: theme.colorScheme.surfaceContainerHigh,
                        fontFamily: 'monospace',
                      ),
                      blockquoteDecoration: BoxDecoration(
                        border: Border(
                          left: BorderSide(color: theme.colorScheme.outlineVariant, width: 3),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      default:
        // tool 消息已被 messages 过滤，不再渲染
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final full = widget.reasoning;
    // 折叠时只取前 160 字符（约 2-3 行），避免思考过程铺满屏幕
    const previewLen = 160;
    final collapsed = full.length <= previewLen;
    final shown = _expanded || collapsed ? full : '${full.substring(0, previewLen)}…';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border(left: BorderSide(color: theme.colorScheme.outlineVariant, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.psychology_outlined, size: 14, color: theme.colorScheme.outline),
              const SizedBox(width: 4),
              Text('思考过程', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline)),
              const Spacer(),
              if (!collapsed)
                InkWell(
                  onTap: () => setState(() => _expanded = !_expanded),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _expanded ? '收起' : '展开',
                        style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.primary),
                      ),
                      Icon(
                        _expanded ? Icons.expand_less : Icons.expand_more,
                        size: 16,
                        color: theme.colorScheme.primary,
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            shown,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant, height: 1.4),
          ),
        ],
      ),
    );
  }
}

/// 模型选择底部弹窗：按 provider 分组，当前模型打勾，点击返回选择。
class _ModelPickerSheet extends StatelessWidget {
  const _ModelPickerSheet({required this.catalog});

  final ModelCatalog catalog;

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
            child: Text(
              '切换模型（当前：${current.provider} / ${current.model}）',
              style: theme.textTheme.titleMedium,
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final group in catalog.groups) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Text(
                      group.name,
                      style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.primary),
                    ),
                  ),
                  for (final model in group.models)
                    ListTile(
                      dense: true,
                      leading: Icon(
                        (group.id == current.provider && model.id == current.model)
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                        color: (group.id == current.provider && model.id == current.model)
                            ? theme.colorScheme.primary
                            : theme.colorScheme.outline,
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
