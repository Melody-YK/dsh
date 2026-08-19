/// DSH 公开 API 的类型安全封装（会话/工作区/宿主）。
///
/// payload 与官方 schema 对齐（来源：`@deepseek-ai/dsh-host-apiproxy` 的
/// sessions.schema / workspace.schema / host 描述）。
library;

import '../protocol/envelope.dart';
import '../protocol/mux_frame.dart';
import '../protocol/rpc_client.dart';

/// session.list 的一行摘要。
class SessionSummary {
  SessionSummary({
    required this.sessionId,
    required this.updatedAt,
    required this.running,
    required this.blank,
    this.parentSessionId,
    this.origin,
    this.cwd,
    this.agentPreset,
    this.title,
  });

  factory SessionSummary.fromJson(Map<String, Object?> json) {
    // 标题来自 projections.values.title（会话投影缓存）
    final projections = json['projections'] as Map<String, Object?>?;
    final values = projections?['values'] as Map<String, Object?>?;
    final title = values?['title'] as String?;
    return SessionSummary(
      sessionId: json['sessionId'] as String,
      updatedAt: (json['updatedAt'] as num).toInt(),
      running: json['running'] as bool,
      blank: json['blank'] as bool,
      parentSessionId: json['parentSessionId'] as String?,
      origin: json['origin'] as String?,
      cwd: json['cwd'] as String?,
      agentPreset: json['agentPreset'] as String?,
      title: title,
    );
  }

  final String sessionId;
  final int updatedAt;
  final bool running;
  final bool blank;
  final String? parentSessionId;
  final String? origin;
  final String? cwd;
  final String? agentPreset;

  /// 会话标题（由服务端投影缓存提供，如首条消息摘要）。
  final String? title;
}

/// session.history 的一条记录（event + 可选 view）。
class HistoryEntry {
  HistoryEntry({required this.event, this.view});

  factory HistoryEntry.fromJson(Map<String, Object?> json) => HistoryEntry(
        event: SessionEvent.fromJson(json['event'] as Map<String, Object?>),
        view: json['view'] as Map<String, Object?>?,
      );

  final SessionEvent event;
  final Map<String, Object?>? view;
}

/// session.prompt 的文本内容块。
class PromptTextPart {
  const PromptTextPart(this.text);
  final String text;
  Map<String, Object?> toJson() => {'type': 'text', 'text': text};
}

/// session.prompt 的图片内容块（data 为 base64）。
class PromptImagePart {
  const PromptImagePart({required this.mediaType, required this.data, this.name});
  final String mediaType;
  final String data;
  final String? name;
  Map<String, Object?> toJson() => {'type': 'image', 'mediaType': mediaType, 'data': data, if (name != null) 'name': name};
}

/// 会话领域 API。
class SessionsApi {
  SessionsApi(this._rpc);
  final RpcClient _rpc;

  /// 会话列表。
  Future<List<SessionSummary>> list() async {
    final result = await _rpc.callUnary('session.list', const {});
    final value = _requireOk(result, 'session.list') as Map<String, Object?>;
    return (value['items'] as List<Object?>)
        .map((item) => SessionSummary.fromJson(item as Map<String, Object?>))
        .toList();
  }

  /// 创建会话。
  Future<String> create({String? workspaceId, String? cwd, String? sessionId, String? agentPreset}) async {
    final result = await _rpc.callUnary('session.create', {
      if (workspaceId != null) 'workspaceId': workspaceId,
      if (cwd != null) 'cwd': cwd,
      if (sessionId != null) 'sessionId': sessionId,
      if (agentPreset != null) 'agentPreset': agentPreset,
    });
    final value = _requireOk(result, 'session.create') as Map<String, Object?>;
    return value['sessionId'] as String;
  }

  /// 拉取会话历史。beforeSeq 为空时从最新往回翻；maxMessages 默认官方上限。
  Future<(List<HistoryEntry>, bool hasMore)> history(String sessionId, {int? beforeSeq, int? maxMessages}) async {
    final result = await _rpc.callUnary('session.history', {
      'sessionId': sessionId,
      if (beforeSeq != null) 'beforeSeq': beforeSeq,
      if (maxMessages != null) 'maxMessages': maxMessages,
    });
    final value = _requireOk(result, 'session.history') as Map<String, Object?>;
    final events = (value['events'] as List<Object?>)
        .map((e) => HistoryEntry.fromJson(e as Map<String, Object?>))
        .toList();
    return (events, value['hasMore'] as bool);
  }

  /// 发送消息。mode: queue（默认入队）/ steer（打断当前）。
  Future<void> prompt(
    String sessionId,
    List<Object> content, {
    String mode = 'queue',
    String? clientTimeZone,
  }) async {
    final result = await _rpc.callUnary('session.prompt', {
      'sessionId': sessionId,
      'mode': mode,
      'content': content.map((part) {
        return switch (part) {
          PromptTextPart p => p.toJson(),
          PromptImagePart p => p.toJson(),
          _ => throw ArgumentError('unsupported prompt part: $part'),
        };
      }).toList(),
      if (clientTimeZone != null) 'clientTimeZone': clientTimeZone,
    });
    _requireOk(result, 'session.prompt');
  }

  /// 取消当前生成。
  Future<void> cancel(String sessionId) async {
    final result = await _rpc.callUnary('session.cancel', {'sessionId': sessionId});
    _requireOk(result, 'session.cancel');
  }

  /// 重命名会话。
  Future<void> renameSession(String sessionId, String title) async {
    final result = await _rpc.callUnary('session.rename', {'sessionId': sessionId, 'title': title});
    _requireOk(result, 'session.rename');
  }

  // ---------- 工作区（文件夹）管理 ----------

  /// 工作区列表 + 归档会话 id 集合。
  Future<({List<WorkspaceView> items, List<String> archivedSessionIds})> workspaceList() async {
    final result = await _rpc.callUnary('workspace.list', const {});
    final value = _requireOk(result, 'workspace.list') as Map<String, Object?>;
    return (
      items: (value['items'] as List<Object?>)
          .map((w) => WorkspaceView.fromJson(w as Map<String, Object?>))
          .toList(),
      archivedSessionIds: (value['archivedSessionIds'] as List<Object?>).cast<String>(),
    );
  }

  /// 新建工作区（path 为目录路径；同 path 已存在则返回已有工作区，created=false）。
  Future<WorkspaceView> workspaceCreate(String path) async {
    final result = await _rpc.callUnary('workspace.create', {'path': path});
    final value = _requireOk(result, 'workspace.create') as Map<String, Object?>;
    return WorkspaceView.fromJson(value['workspace'] as Map<String, Object?>);
  }

  /// 重命名工作区。
  Future<void> workspaceRename(String workspaceId, String title) async {
    final result = await _rpc.callUnary('workspace.rename', {'workspaceId': workspaceId, 'title': title});
    _requireOk(result, 'workspace.rename');
  }

  /// 删除工作区（会话保留，归入未分组）。
  Future<void> workspaceDelete(String workspaceId) async {
    final result = await _rpc.callUnary('workspace.delete', {'workspaceId': workspaceId});
    _requireOk(result, 'workspace.delete');
  }

  /// 归档会话，返回完整归档集合。
  Future<List<String>> workspaceArchiveSession(String sessionId) async {
    final result = await _rpc.callUnary('workspace.archiveSession', {'sessionId': sessionId});
    final value = _requireOk(result, 'workspace.archiveSession') as Map<String, Object?>;
    return (value['archivedSessionIds'] as List<Object?>).cast<String>();
  }

  /// 把会话放进工作区（beforeSessionId 控制工作区内位置）。
  Future<void> workspaceInsertSessionBefore(String workspaceId, String sessionId, {String? beforeSessionId}) async {
    final result = await _rpc.callUnary('workspace.insertSessionBefore', {
      'workspaceId': workspaceId,
      'sessionId': sessionId,
      if (beforeSessionId != null) 'beforeSessionId': beforeSessionId,
    });
    _requireOk(result, 'workspace.insertSessionBefore');
  }

  // ---------- 模型选择 ----------

  /// 当前会话可用模型：current + 分组列表。
  Future<ModelCatalog> models(String sessionId) async {
    final result = await _rpc.callUnary('session.models', {'sessionId': sessionId});
    final value = _requireOk(result, 'session.models') as Map<String, Object?>;
    return ModelCatalog.fromJson(value);
  }

  /// 切换会话模型。
  Future<void> selectModel(String sessionId, {required String provider, required String model, String? reasoningEffort}) async {
    final result = await _rpc.callUnary('session.selectModel', {
      'sessionId': sessionId,
      'provider': provider,
      'model': model,
      if (reasoningEffort != null) 'reasoningEffort': reasoningEffort,
    });
    _requireOk(result, 'session.selectModel');
  }

  // ---------- 宿主目录浏览 ----------

  /// 列出目录：entries 为子目录/文件，crumbs 为路径面包屑。
  Future<DirectoryListing> listDirectory({String? path}) async {
    final result = await _rpc.callUnary('host.listDirectory', {
      if (path != null) 'path': path,
    });
    final value = _requireOk(result, 'host.listDirectory') as Map<String, Object?>;
    return DirectoryListing.fromJson(value);
  }

  /// 在电脑上弹出系统文件夹选择框；null 表示用户取消。
  Future<String?> pickDirectory() async {
    final result = await _rpc.callUnary('host.pickDirectory', const {});
    if (!result.isOk) throw RpcErrorException('host.pickDirectory', result.error!);
    final value = result.value as Map<String, Object?>;
    return value['path'] as String?;
  }

  Object? _requireOk(RpcResult result, String method) {
    if (!result.isOk) {
      throw RpcErrorException(method, result.error!);
    }
    return result.value;
  }
}

/// host.listDirectory 的返回。
class DirectoryListing {
  DirectoryListing({
    required this.path,
    required this.home,
    required this.crumbs,
    required this.entries,
    required this.truncated,
  });

  factory DirectoryListing.fromJson(Map<String, Object?> json) => DirectoryListing(
        path: json['path'] as String,
        home: json['home'] as String,
        crumbs: (json['crumbs'] as List<Object?>)
            .map((c) => DirectoryEntry.fromJson(c as Map<String, Object?>))
            .toList(),
        entries: (json['entries'] as List<Object?>)
            .map((e) => DirectoryEntry.fromJson(e as Map<String, Object?>))
            .toList(),
        truncated: json['truncated'] as bool,
      );

  final String path;
  final String home;
  final List<DirectoryEntry> crumbs;
  final List<DirectoryEntry> entries;
  final bool truncated;
}

/// 目录条目（name/path/hidden）。
class DirectoryEntry {
  DirectoryEntry({required this.name, required this.path, required this.hidden});

  factory DirectoryEntry.fromJson(Map<String, Object?> json) => DirectoryEntry(
        name: json['name'] as String,
        path: json['path'] as String,
        hidden: json['hidden'] as bool,
      );

  final String name;
  final String path;
  final bool hidden;
}

/// 模型目录：current + 分组列表。
class ModelCatalog {
  ModelCatalog({required this.current, required this.routable, required this.groups});

  factory ModelCatalog.fromJson(Map<String, Object?> json) => ModelCatalog(
        current: ModelSelection.fromJson(json['current'] as Map<String, Object?>),
        routable: json['routable'] as bool,
        groups: (json['groups'] as List<Object?>)
            .map((g) => ModelGroup.fromJson(g as Map<String, Object?>))
            .toList(),
      );

  final ModelSelection current;
  final bool routable;
  final List<ModelGroup> groups;
}

/// 一个 provider 分组。
class ModelGroup {
  ModelGroup({required this.id, required this.name, required this.models});

  factory ModelGroup.fromJson(Map<String, Object?> json) => ModelGroup(
        id: json['id'] as String,
        name: json['name'] as String,
        models: (json['models'] as List<Object?>)
            .map((m) => ModelEntry.fromJson(m as Map<String, Object?>))
            .toList(),
      );

  final String id;
  final String name;
  final List<ModelEntry> models;
}

/// 一个模型条目。
class ModelEntry {
  ModelEntry({required this.id, required this.name, this.reasoningEfforts = const []});

  factory ModelEntry.fromJson(Map<String, Object?> json) {
    // reasoning.efforts 是档位 id 数组（如 ["min","low","medium","high","max"]）
    final reasoning = json['reasoning'] as Map<String, Object?>?;
    final efforts = ((reasoning?['efforts'] as List<Object?>?) ?? const []).cast<String>();
    return ModelEntry(
      id: json['id'] as String,
      name: json['name'] as String,
      reasoningEfforts: efforts,
    );
  }

  final String id;
  final String name;

  /// 该模型支持的推理档位（空 = 不支持/未知）。
  final List<String> reasoningEfforts;
}

/// 当前模型选择。
class ModelSelection {
  ModelSelection({required this.provider, required this.model, this.reasoningEffort});

  factory ModelSelection.fromJson(Map<String, Object?> json) => ModelSelection(
        provider: json['provider'] as String,
        model: json['model'] as String,
        reasoningEffort: json['reasoningEffort'] as String?,
      );

  final String provider;
  final String model;
  final String? reasoningEffort;
}

/// 工作区（文件夹）视图。
class WorkspaceView {
  WorkspaceView({
    required this.workspaceId,
    required this.path,
    required this.title,
    required this.sessionIds,
    required this.createdAt,
    required this.updatedAt,
  });

  factory WorkspaceView.fromJson(Map<String, Object?> json) => WorkspaceView(
        workspaceId: json['workspaceId'] as String,
        path: json['path'] as String,
        title: json['title'] as String,
        sessionIds: (json['sessionIds'] as List<Object?>).cast<String>(),
        createdAt: json['createdAt'] as String,
        updatedAt: json['updatedAt'] as String,
      );

  final String workspaceId;
  final String path;
  final String title;
  final List<String> sessionIds;
  final String createdAt;
  final String updatedAt;
}

/// 业务错误：result.ok == false。
class RpcErrorException implements Exception {
  RpcErrorException(this.method, this.error);
  final String method;
  final RpcError error;

  @override
  String toString() => '$method: $error';
}
