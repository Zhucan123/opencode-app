import 'dart:async';

import 'package:code_app/core/api/models/event.dart';
import 'package:code_app/core/api/models/message.dart';
import 'package:code_app/core/api/opencode_client.dart';
import 'package:code_app/features/connection/connection_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ChatProviderArgs {
  const ChatProviderArgs({required this.serverId, required this.sessionId});

  final String serverId;
  final String sessionId;

  @override
  bool operator ==(Object other) =>
      other is ChatProviderArgs &&
      other.serverId == serverId &&
      other.sessionId == sessionId;

  @override
  int get hashCode => Object.hash(serverId, sessionId);
}

class ChatState {
  const ChatState({
    this.messages = const <OpencodeMessage>[],
    this.streamingParts = const <String, Map<String, String>>{},
    this.availableModes = const <String>[],
    this.selectedMode,
    this.availableModels = const <OpencodeModel>[],
    this.selectedModel,
    this.isLoading = false,
    this.isSending = false,
    this.isStreaming = false,
    this.processingLabel,
    this.error,
    this.pendingPermission,
  });

  final List<OpencodeMessage> messages;
  final Map<String, Map<String, String>> streamingParts;
  final List<String> availableModes;
  final String? selectedMode;
  final List<OpencodeModel> availableModels;
  final OpencodeModel? selectedModel;
  final bool isLoading;
  final bool isSending;
  final bool isStreaming;
  final String? processingLabel;
  final String? error;
  final OpencodeEvent? pendingPermission;

  /// 获取某条消息的流式累积文本
  String streamingTextFor(String messageId) {
    final parts = streamingParts[messageId];
    if (parts == null || parts.isEmpty) return '';
    return parts.values.join('');
  }

  /// 是否有任何流式内容
  bool get hasStreamingContent => streamingParts.isNotEmpty;

  ChatState copyWith({
    List<OpencodeMessage>? messages,
    Map<String, Map<String, String>>? streamingParts,
    List<String>? availableModes,
    String? selectedMode,
    bool clearSelectedMode = false,
    List<OpencodeModel>? availableModels,
    OpencodeModel? selectedModel,
    bool clearSelectedModel = false,
    bool? isLoading,
    bool? isSending,
    bool? isStreaming,
    String? processingLabel,
    bool clearProcessingLabel = false,
    String? error,
    bool clearError = false,
    OpencodeEvent? pendingPermission,
    bool clearPendingPermission = false,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      streamingParts: streamingParts ?? this.streamingParts,
      availableModes: availableModes ?? this.availableModes,
      selectedMode: clearSelectedMode ? null : (selectedMode ?? this.selectedMode),
      availableModels: availableModels ?? this.availableModels,
      selectedModel: clearSelectedModel ? null : (selectedModel ?? this.selectedModel),
        isLoading: isLoading ?? this.isLoading,
        isSending: isSending ?? this.isSending,
        isStreaming: isStreaming ?? this.isStreaming,
        processingLabel: clearProcessingLabel
            ? null
            : (processingLabel ?? this.processingLabel),
        error: clearError ? null : (error ?? this.error),
        pendingPermission: clearPendingPermission
            ? null
            : (pendingPermission ?? this.pendingPermission),
      );
  }
}

final chatProvider = StateNotifierProvider.autoDispose
    .family<ChatController, ChatState, ChatProviderArgs>(
  (ref, args) => ChatController(ref, args),
);

class ChatController extends StateNotifier<ChatState> {
  ChatController(this.ref, this.args) : super(const ChatState(isLoading: true)) {
    _initialize();
  }

  final Ref ref;
  final ChatProviderArgs args;
  StreamSubscription<OpencodeEvent>? _subscription;
  // 定期刷新 REST 消息（保持流式气泡内容最新）
  Timer? _refreshTimer;
  // 超时停止流式：最后一次事件后 20s 无新事件才结束
  Timer? _streamStopTimer;
  // 用户消息的真实 ID（服务端分配），用于过滤掉用户侧 part 事件
  final Set<String> _userMessageIds = {};

  Future<void> _initialize() async {
    final connection = ref.read(activeConnectionProvider(args.serverId));
    if (connection == null) {
      state = state.copyWith(isLoading: false, error: '当前服务器尚未建立连接。');
      return;
    }

    try {
      // 分开调用，避免 Future.wait 混合类型在运行时转换失败导致消息加载丢失
      final messages = await connection.apiClient.getMessages(args.sessionId);
      final modes = await connection.apiClient.getModes();
      final models = await connection.apiClient.getModels();
      state = state.copyWith(
        messages: messages,
        availableModes: modes,
        selectedMode: modes.isNotEmpty ? modes.first : null,
        availableModels: models,
        isLoading: false,
        clearError: true,
      );

      _subscription = connection.events.listen(
        _handleEvent,
        onError: (Object error, StackTrace _) {
          state = state.copyWith(isStreaming: false, error: error.toString());
        },
      );
    } catch (error) {
      state = state.copyWith(isLoading: false, error: error.toString());
    }
  }

  void setMode(String mode) {
    state = state.copyWith(selectedMode: mode);
  }

  void setModel(OpencodeModel model) {
    state = state.copyWith(selectedModel: model);
  }

  Future<void> refreshMessages({bool stopStreaming = false}) async {
    final connection = ref.read(activeConnectionProvider(args.serverId));
    if (connection == null) return;
    try {
      final messages = await connection.apiClient.getMessages(args.sessionId);
      state = state.copyWith(
        messages: messages,
        streamingParts: stopStreaming ? const {} : state.streamingParts,
        isLoading: false,
        isStreaming: stopStreaming ? false : state.isStreaming,
        clearProcessingLabel: stopStreaming,
      );
      if (stopStreaming) _userMessageIds.clear();
    } catch (error) {
      state = state.copyWith(isLoading: false, error: error.toString());
    }
  }

  Future<void> sendMessage(String text) async {
    final connection = ref.read(activeConnectionProvider(args.serverId));
    if (connection == null) {
      state = state.copyWith(error: '连接已断开，无法发送消息。');
      return;
    }

    final trimmed = text.trim();
    if (trimmed.isEmpty || state.isSending) return;

    // 乐观插入用户消息
    final optimistic = OpencodeMessage(
      id: 'local-${DateTime.now().microsecondsSinceEpoch}',
      sessionId: args.sessionId,
      role: MessageRole.user,
      parts: [MessagePart(type: MessagePartType.text, text: trimmed)],
      createdAt: DateTime.now(),
    );

    state = state.copyWith(
      messages: [...state.messages, optimistic],
      isSending: true,
      processingLabel: 'OpenCode 正在思考...',
      clearError: true,
    );

    try {
      await connection.apiClient.sendPrompt(
        args.sessionId,
        trimmed,
        mode: state.selectedMode,
        modelId: state.selectedModel?.id,
        providerId: state.selectedModel?.providerId,
      );
      state = state.copyWith(
        isSending: false,
        isStreaming: true,
        processingLabel: 'OpenCode 正在思考...',
      );
    } catch (error) {
      state = state.copyWith(
        isSending: false,
        isStreaming: false,
        clearProcessingLabel: true,
        error: error.toString(),
      );
    }
  }

  Future<void> respondToPermission(bool allow, {bool permanent = false}) async {
    final permissionId = state.pendingPermission?.permissionId;
    if (permissionId == null) return;

    final connection = ref.read(activeConnectionProvider(args.serverId));
    if (connection == null) return;

    state = state.copyWith(
      clearPendingPermission: true,
      processingLabel: '正在确认权限...',
    );

    try {
      await connection.apiClient.respondToPermission(
        args.sessionId,
        permissionId,
        allow,
        permanent: permanent,
      );
    } catch (error) {
      state = state.copyWith(error: error.toString());
    }
  }

  Future<void> abort() async {
    final connection = ref.read(activeConnectionProvider(args.serverId));
    if (connection == null) return;
    try {
      await connection.apiClient.abort(args.sessionId);
    } catch (error) {
      state = state.copyWith(error: error.toString());
    }
  }

  Future<void> revert() async {
    final connection = ref.read(activeConnectionProvider(args.serverId));
    if (connection == null) return;
    state = state.copyWith(isLoading: true);
    try {
      await connection.apiClient.revert(args.sessionId);
      await refreshMessages(stopStreaming: true);
    } catch (error) {
      state = state.copyWith(error: error.toString(), isLoading: false);
    }
  }

  void _handleEvent(OpencodeEvent event) {
    if (!_matchesSession(event)) return;
    _resetStreamEndTimer();

    switch (event.type) {
      case OpencodeEventType.sessionUpdated:
      case OpencodeEventType.messageUpdated:
        // 记录用户消息的真实服务端 ID，后续 part 事件用来过滤
        if (event.message?.role == MessageRole.user) {
          final realId = event.message!.id;
          if (realId.isNotEmpty) _userMessageIds.add(realId);
        }
        // 只标记流式状态，不修改 messages 列表
        // messages 列表由 REST API 维护，SSE 只做流式内容展示
        state = state.copyWith(
          isStreaming: true,
          processingLabel: 'OpenCode 正在思考...',
          clearError: true,
        );
        return;

      case OpencodeEventType.messagePartUpdated:
        final part = event.part;
        if (part == null || part.isSkippable || part.type != 'text') return;
        // 跳过用户消息的 part，避免渲染到 assistant 流式气泡
        if (_userMessageIds.contains(part.messageId)) return;
        final text = part.text;
        if (text == null || text.isEmpty) return;

        final updated = _updateStreamingPart(part.messageId, part.id, text);
        state = state.copyWith(
          streamingParts: updated,
          isStreaming: true,
          processingLabel: 'OpenCode 正在回复...',
        );
        return;

      case OpencodeEventType.messagePartDelta:
        final delta = event.partDelta;
        if (delta == null || delta.field != 'text' || delta.delta.isEmpty) return;
        // 跳过用户消息的 part
        if (_userMessageIds.contains(delta.messageId)) return;

        final currentText = state.streamingParts[delta.messageId]?[delta.partId] ?? '';
        final updated = _updateStreamingPart(
            delta.messageId, delta.partId, currentText + delta.delta);
        state = state.copyWith(
          streamingParts: updated,
          isStreaming: true,
          processingLabel: 'OpenCode 正在回复...',
        );
        return;

      case OpencodeEventType.messagePartRemoved:
        final partId = event.removedPartId;
        if (partId == null) return;
        final updated = <String, Map<String, String>>{};
        for (final entry in state.streamingParts.entries) {
          final parts = Map<String, String>.from(entry.value)..remove(partId);
          updated[entry.key] = parts;
        }
        state = state.copyWith(streamingParts: updated);
        return;

      case OpencodeEventType.sessionError:
        _refreshTimer?.cancel();
        _streamStopTimer?.cancel();
        state = state.copyWith(
          isStreaming: false,
          isSending: false,
          clearProcessingLabel: true,
          error: event.error ?? 'OpenCode 返回错误事件。',
        );
        return;

      case OpencodeEventType.toolCalled:
        state = state.copyWith(
          isStreaming: true,
          processingLabel: 'OpenCode 正在执行工具...',
        );
        return;

      case OpencodeEventType.permissionAsked:
        state = state.copyWith(
          isStreaming: true,
          processingLabel: '等待权限确认...',
          pendingPermission: event,
        );
        return;

      case OpencodeEventType.unknown:
        return;
    }
  }

  /// 重置流式定时器：
  /// - 5s 后刷新 REST 消息（保持内容最新，但保持 isStreaming=true）
  /// - 20s 后强制结束流式（长时间无事件认为已完成）
  void _resetStreamEndTimer() {
    _refreshTimer?.cancel();
    _streamStopTimer?.cancel();
    _refreshTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) refreshMessages();
    });
    _streamStopTimer = Timer(const Duration(seconds: 20), () {
      if (mounted) refreshMessages(stopStreaming: true);
    });
  }

  Map<String, Map<String, String>> _updateStreamingPart(
      String messageId, String partId, String text) {
    final updated = Map<String, Map<String, String>>.from(state.streamingParts);
    final msgParts = Map<String, String>.from(updated[messageId] ?? {});
    msgParts[partId] = text;
    updated[messageId] = msgParts;
    return updated;
  }

  bool _matchesSession(OpencodeEvent event) {
    final sid = event.sessionId;
    if (sid != null && sid.isNotEmpty) return sid == args.sessionId;
    return event.message?.sessionId == args.sessionId;
  }

  List<OpencodeMessage> _upsertMessage(
    List<OpencodeMessage> current,
    OpencodeMessage incoming,
  ) {
    final next = [...current];
    final index = next.indexWhere((m) => m.id == incoming.id);
    if (index == -1) {
      next.add(incoming);
    } else {
      next[index] = incoming;
    }
    next.sort((a, b) {
      final at = a.createdAt;
      final bt = b.createdAt;
      if (at == null && bt == null) return 0;
      if (at == null) return -1;
      if (bt == null) return 1;
      return at.compareTo(bt);
    });
    return next;
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _streamStopTimer?.cancel();
    _subscription?.cancel();
    super.dispose();
  }
}
