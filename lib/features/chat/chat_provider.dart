import 'dart:async';

import 'package:code_app/core/api/models/event.dart';
import 'package:code_app/core/api/models/message.dart';
import 'package:code_app/core/api/opencode_client.dart';
import 'package:code_app/core/storage/server_config_store.dart';
import 'package:code_app/features/connection/connection_provider.dart';
import 'package:code_app/features/sessions/session_provider.dart';
import 'package:code_app/shared/notification_service.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter/widgets.dart';
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
    this.hasMore = false,
    this.streamingParts = const <String, Map<String, String>>{},
    this.streamingReasoningText = '',
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
    this.pendingQuestion,
  });

  final List<OpencodeMessage> messages;
  final bool hasMore;
  final Map<String, Map<String, String>> streamingParts;
  final String streamingReasoningText;
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
  final OpencodeEvent? pendingQuestion;

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
    bool? hasMore,
    Map<String, Map<String, String>>? streamingParts,
    String? streamingReasoningText,
    bool clearStreamingReasoning = false,
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
    OpencodeEvent? pendingQuestion,
    bool clearPendingQuestion = false,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      hasMore: hasMore ?? this.hasMore,
      streamingParts: streamingParts ?? this.streamingParts,
      streamingReasoningText: clearStreamingReasoning ? '' : (streamingReasoningText ?? this.streamingReasoningText),
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
        pendingQuestion: clearPendingQuestion
            ? null
            : (pendingQuestion ?? this.pendingQuestion),
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
    
    // 监听底层连接的热替换，实现无缝重连
    ref.listen<ActiveConnection?>(activeConnectionProvider(args.serverId), (previous, next) {
      if (previous != next && next != null) {
        _swapConnection(next);
      }
    });
  }

  final Ref ref;
  final ChatProviderArgs args;
  StreamSubscription<OpencodeEvent>? _subscription;
  Timer? _refreshTimer;
  Timer? _streamStopTimer;
  final Set<String> _userMessageIds = {};
  static const int _pageSize = 20;
  int _currentLimit = 20;
  bool _isLoadingMore = false;
  final Map<String, String> _partTypes = {};

  void _swapConnection(ActiveConnection newConnection) {
    _subscription?.cancel();
    _subscription = newConnection.events.listen(
      _handleEvent,
      onError: (Object error, StackTrace _) {
        state = state.copyWith(isStreaming: false, error: error.toString());
      },
    );
    // 顺便刷新一下消息
    refreshMessages(stopStreaming: false);
  }

  Future<void> _initialize() async {
    try {
      final connection = ref.read(activeConnectionProvider(args.serverId));
      if (connection == null) {
        state = state.copyWith(isLoading: false, error: '未连接到服务器');
        return;
      }

      final messages = await connection.apiClient.getMessages(args.sessionId, limit: _currentLimit);
      final modes = await connection.apiClient.getModes();
      final models = await connection.apiClient.getModels();

      // 读取会话和本地存储记录
      final sessions = ref.read(sessionListProvider(args.serverId)).valueOrNull;
      final currentSession = sessions?.where((s) => s.id == args.sessionId).firstOrNull;
      
      final store = ref.read(serverConfigStoreProvider);
      final lastMode = await store.getLastMode(args.serverId);
      final lastModelId = await store.getLastModel(args.serverId);

      // 优先级: 1. 服务端当前会话保存的模式/模型  2. 本地存储的当前服务器偏好  3. 列表第一个兜底
      String? initialMode = currentSession?.agent ?? lastMode;
      if (!modes.contains(initialMode)) {
        initialMode = modes.isNotEmpty ? modes.first : null;
      }

      final sessionModelId = currentSession?.modelId ?? lastModelId;
      final sessionProviderId = currentSession?.providerId;
      OpencodeModel? initialModel;
      if (sessionModelId != null) {
        // 优先用 modelId + providerId 双字段精确匹配
        if (sessionProviderId != null) {
          initialModel = models
              .where((m) => m.id == sessionModelId && m.providerId == sessionProviderId)
              .firstOrNull;
        }
        // 降级：只用 modelId 匹配
        initialModel ??= models.where((m) => m.id == sessionModelId).firstOrNull;
      }
      initialModel ??= models.isNotEmpty ? models.first : null;

      state = state.copyWith(
        messages: messages,
        hasMore: messages.length >= _currentLimit,
        availableModes: modes,
        selectedMode: initialMode,
        availableModels: models,
        selectedModel: initialModel,
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
    ref.read(serverConfigStoreProvider).saveLastMode(args.serverId, mode);
  }

  void setModel(OpencodeModel model) {
    state = state.copyWith(selectedModel: model);
    ref.read(serverConfigStoreProvider).saveLastModel(args.serverId, model.id);
  }

  Future<void> refreshMessages({bool stopStreaming = false}) async {
    final connection = ref.read(activeConnectionProvider(args.serverId));
    if (connection == null) return;
    try {
      final messages = await connection.apiClient.getMessages(args.sessionId, limit: _currentLimit);
      state = state.copyWith(
        messages: messages,
        hasMore: messages.length >= _currentLimit,
        streamingParts: stopStreaming ? const {} : state.streamingParts,
        clearStreamingReasoning: stopStreaming,
        isLoading: false,
        isStreaming: stopStreaming ? false : state.isStreaming,
        clearProcessingLabel: stopStreaming,
      );
      if (stopStreaming) _userMessageIds.clear();
    } catch (error) {
      state = state.copyWith(isLoading: false, error: error.toString());
    }
  }

  Future<void> loadMore() async {
    if (!state.hasMore || _isLoadingMore) return;
    _isLoadingMore = true;
    _currentLimit += _pageSize;
    await refreshMessages();
    _isLoadingMore = false;
  }

  Future<void> sendMessage(String text, {List<Map<String, dynamic>>? extraParts}) async {
    final connection = ref.read(activeConnectionProvider(args.serverId));
    if (connection == null) {
      state = state.copyWith(error: '连接已断开，无法发送消息。');
      return;
    }

    final trimmed = text.trim();
    if (trimmed.isEmpty && (extraParts == null || extraParts.isEmpty)) return;
    if (state.isSending) return;

    // 乐观插入用户消息
    final userParts = <MessagePart>[];
    if (trimmed.isNotEmpty) {
      userParts.add(MessagePart(type: MessagePartType.text, text: trimmed));
    }
    if (extraParts != null) {
      for (final part in extraParts) {
        if (part['type'] == 'file' && part['mime']?.toString().startsWith('image/') == true) {
          userParts.add(MessagePart(
            type: MessagePartType.image,
            text: '[图片]',
            rawJson: part,
          ));
        }
      }
    }

    final optimistic = OpencodeMessage(
      id: 'local-${DateTime.now().microsecondsSinceEpoch}',
      sessionId: args.sessionId,
      role: MessageRole.user,
      parts: userParts,
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
        extraParts: extraParts,
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

  Future<void> respondToQuestion(List<List<String>> answers) async {
    final questionId = state.pendingQuestion?.permissionId; // It uses the 'id' field, same as permissionId
    if (questionId == null) return;

    final connection = ref.read(activeConnectionProvider(args.serverId));
    if (connection == null) return;

    state = state.copyWith(
      clearPendingQuestion: true,
      processingLabel: '正在提交选择...',
    );

    try {
      await connection.apiClient.respondToQuestion(questionId, answers);
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
        // 兼容旧版，如果传来了会话状态，且为 ready / error，则代表流式彻底结束
        final sessionState = event.session?.state?.toLowerCase();
        if (sessionState == 'ready' || sessionState == 'error' || sessionState == 'stopped') {
          _refreshTimer?.cancel();
          _streamStopTimer?.cancel();
          refreshMessages(stopStreaming: true);
          _notifyIfBackground();
          return;
        }
        // 否则继续认为是 streaming 状态
        state = state.copyWith(
          isStreaming: true,
          processingLabel: state.processingLabel ?? 'OpenCode 正在思考...',
          clearError: true,
        );
        return;

      case OpencodeEventType.sessionStatus:
        final statusType = event.sessionStatusType?.toLowerCase();
        if (statusType == 'idle') {
          _refreshTimer?.cancel();
          _streamStopTimer?.cancel();
          refreshMessages(stopStreaming: true);
          _notifyIfBackground();
          return;
        }
        state = state.copyWith(
          isStreaming: true,
          processingLabel: state.processingLabel ?? 'OpenCode 正在思考...',
          clearError: true,
        );
        return;

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
          processingLabel: state.processingLabel ?? 'OpenCode 正在思考...',
          clearError: true,
        );
        return;

      case OpencodeEventType.messagePartUpdated:
        final part = event.part;
        if (part == null || part.isSkippable || (part.type != 'text' && part.type != 'reasoning')) return;
        // 记录 part 类型，供 delta 使用
        _partTypes[part.id] = part.type;
        // 跳过用户消息的 part，避免渲染到 assistant 流式气泡
        if (_userMessageIds.contains(part.messageId)) return;
        final text = part.text;
        if (text == null || text.isEmpty) return;

        if (part.type == 'reasoning') {
          state = state.copyWith(
            streamingReasoningText: text,
            isStreaming: true,
            processingLabel: 'OpenCode 正在思考...',
          );
        } else {
          final updated = _updateStreamingPart(part.messageId, part.id, text);
          state = state.copyWith(
            streamingParts: updated,
            streamingReasoningText: '', // 开始输出正文时，清空之前遗留的 reasoning 状态
            isStreaming: true,
            processingLabel: 'OpenCode 正在回复...',
          );
        }
        return;

      case OpencodeEventType.messagePartDelta:
        final delta = event.partDelta;
        if (delta == null || delta.field != 'text' || delta.delta.isEmpty) return;
        // 跳过用户消息的 part
        if (_userMessageIds.contains(delta.messageId)) return;

        final isReasoning = _partTypes[delta.partId] == 'reasoning';
        
        if (isReasoning) {
          final currentReasoning = state.streamingReasoningText;
          state = state.copyWith(
            streamingReasoningText: currentReasoning + delta.delta,
            isStreaming: true,
            processingLabel: 'OpenCode 正在思考...',
          );
        } else {
          final currentText = state.streamingParts[delta.messageId]?[delta.partId] ?? '';
          final updated = _updateStreamingPart(
              delta.messageId, delta.partId, currentText + delta.delta);
          state = state.copyWith(
            streamingParts: updated,
            streamingReasoningText: '', // 输出正文 delta 时，同样清空 reasoning 状态
            isStreaming: true,
            processingLabel: 'OpenCode 正在回复...',
          );
        }
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

      case OpencodeEventType.questionAsked:
        state = state.copyWith(
          isStreaming: true,
          processingLabel: '等待您的选择...',
          pendingQuestion: event,
        );
        return;

      case OpencodeEventType.unknown:
        return;
    }
  }

  void _notifyIfBackground() {
    final state = WidgetsBinding.instance.lifecycleState;
    final isBackground = state == AppLifecycleState.paused || state == AppLifecycleState.hidden || state == AppLifecycleState.inactive;
    
    if (isBackground) {
      final sessions = ref.read(sessionListProvider(args.serverId)).valueOrNull;
      final title = sessions
              ?.where((s) => s.id == args.sessionId)
              .firstOrNull
              ?.title ??
          'OpenCode Chat';
      NotificationService.notifyAiComplete(title).ignore();
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
