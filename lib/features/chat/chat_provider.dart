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
    this.error,
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
  final String? error;

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
    String? error,
    bool clearError = false,
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
      error: clearError ? null : (error ?? this.error),
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
  // 流式结束检测：最后一次事件后 3s 无新事件则自动刷新消息列表
  Timer? _streamEndTimer;

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

  Future<void> refreshMessages() async {
    final connection = ref.read(activeConnectionProvider(args.serverId));
    if (connection == null) return;
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final messages = await connection.apiClient.getMessages(args.sessionId);
      // 刷新完成后清空流式内容，因为 REST 已包含完整数据
      state = state.copyWith(
        messages: messages,
        streamingParts: const {},
        isLoading: false,
        isStreaming: false,
      );
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
      state = state.copyWith(isSending: false, isStreaming: true);
    } catch (error) {
      state = state.copyWith(isSending: false, isStreaming: false, error: error.toString());
    }
  }

  void _handleEvent(OpencodeEvent event) {
    if (!_matchesSession(event)) return;
    _resetStreamEndTimer();

    switch (event.type) {
      case OpencodeEventType.sessionUpdated:
      case OpencodeEventType.messageUpdated:
        // 只标记流式状态，不修改 messages 列表
        // messages 列表由 REST API 维护，SSE 只做流式内容展示
        state = state.copyWith(isStreaming: true, clearError: true);
        return;

      case OpencodeEventType.messagePartUpdated:
        final part = event.part;
        if (part == null || part.isSkippable || part.type != 'text') return;
        final text = part.text;
        if (text == null || text.isEmpty) return;

        final updated = _updateStreamingPart(part.messageId, part.id, text);
        state = state.copyWith(streamingParts: updated, isStreaming: true);
        return;

      case OpencodeEventType.messagePartDelta:
        final delta = event.partDelta;
        if (delta == null || delta.field != 'text' || delta.delta.isEmpty) return;

        final currentText = state.streamingParts[delta.messageId]?[delta.partId] ?? '';
        final updated = _updateStreamingPart(
            delta.messageId, delta.partId, currentText + delta.delta);
        state = state.copyWith(streamingParts: updated, isStreaming: true);
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
        _streamEndTimer?.cancel();
        state = state.copyWith(
          isStreaming: false,
          isSending: false,
          error: event.error ?? 'OpenCode 返回错误事件。',
        );
        return;

      case OpencodeEventType.toolCalled:
      case OpencodeEventType.permissionAsked:
      case OpencodeEventType.unknown:
        return;
    }
  }

  /// 重置流式结束计时器：最后一个事件后 3s 自动刷新消息列表
  void _resetStreamEndTimer() {
    _streamEndTimer?.cancel();
    _streamEndTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        refreshMessages();
      }
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
    _streamEndTimer?.cancel();
    _subscription?.cancel();
    super.dispose();
  }
}
