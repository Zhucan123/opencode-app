import 'dart:async';

import 'package:code_app/core/api/models/event.dart';
import 'package:code_app/core/api/models/message.dart';
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
    this.isLoading = false,
    this.isSending = false,
    this.isStreaming = false,
    this.error,
  });

  final List<OpencodeMessage> messages;
  // messageId → { partId → accumulatedText }
  final Map<String, Map<String, String>> streamingParts;
  final bool isLoading;
  final bool isSending;
  final bool isStreaming;
  final String? error;

  /// 获取某条消息的展示文本（优先用流式累积内容）
  String streamingTextFor(String messageId) {
    final parts = streamingParts[messageId];
    if (parts == null || parts.isEmpty) return '';
    return parts.values.join('');
  }

  ChatState copyWith({
    List<OpencodeMessage>? messages,
    Map<String, Map<String, String>>? streamingParts,
    bool? isLoading,
    bool? isSending,
    bool? isStreaming,
    String? error,
    bool clearError = false,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      streamingParts: streamingParts ?? this.streamingParts,
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

  Future<void> _initialize() async {
    final connection = ref.read(activeConnectionProvider(args.serverId));
    if (connection == null) {
      state = state.copyWith(isLoading: false, error: '当前服务器尚未建立连接。');
      return;
    }

    try {
      final messages = await connection.apiClient.getMessages(args.sessionId);
      state = state.copyWith(messages: messages, isLoading: false, clearError: true);

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

  Future<void> refreshMessages() async {
    final connection = ref.read(activeConnectionProvider(args.serverId));
    if (connection == null) return;
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final messages = await connection.apiClient.getMessages(args.sessionId);
      state = state.copyWith(messages: messages, isLoading: false);
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
      await connection.apiClient.sendPrompt(args.sessionId, trimmed);
      state = state.copyWith(isSending: false, isStreaming: true);
    } catch (error) {
      state = state.copyWith(isSending: false, isStreaming: false, error: error.toString());
    }
  }

  void _handleEvent(OpencodeEvent event) {
    if (!_matchesSession(event)) return;

    switch (event.type) {
      case OpencodeEventType.sessionUpdated:
        // session 元数据更新，标记流式状态
        state = state.copyWith(isStreaming: true, clearError: true);
        return;

      case OpencodeEventType.messageUpdated:
        // 消息元数据更新（无 parts），upsert 到消息列表
        final msg = event.message;
        if (msg == null) return;
        state = state.copyWith(
          messages: _upsertMessage(state.messages, msg),
          isStreaming: true,
          clearError: true,
        );
        return;

      case OpencodeEventType.messagePartUpdated:
        // 完整 part 对象到达（通常是 part 完成时）
        final part = event.part;
        if (part == null || part.isSkippable) return;
        if (part.type != 'text') return; // 暂只处理文本 part

        final text = part.text;
        if (text == null) return;

        final updated = Map<String, Map<String, String>>.from(state.streamingParts);
        final msgParts = Map<String, String>.from(updated[part.messageId] ?? {});
        msgParts[part.id] = text;
        updated[part.messageId] = msgParts;

        state = state.copyWith(streamingParts: updated, isStreaming: true);
        return;

      case OpencodeEventType.messagePartDelta:
        // 文本增量：追加到对应 part
        final delta = event.partDelta;
        if (delta == null || delta.field != 'text' || delta.delta.isEmpty) return;

        final updated = Map<String, Map<String, String>>.from(state.streamingParts);
        final msgParts = Map<String, String>.from(updated[delta.messageId] ?? {});
        msgParts[delta.partId] = (msgParts[delta.partId] ?? '') + delta.delta;
        updated[delta.messageId] = msgParts;

        state = state.copyWith(streamingParts: updated, isStreaming: true);
        return;

      case OpencodeEventType.messagePartRemoved:
        final partId = event.removedPartId;
        if (partId == null) return;
        // 从所有 messageId 的 parts 里删除这个 partId
        final updated = <String, Map<String, String>>{};
        for (final entry in state.streamingParts.entries) {
          final parts = Map<String, String>.from(entry.value)..remove(partId);
          updated[entry.key] = parts;
        }
        state = state.copyWith(streamingParts: updated);
        return;

      case OpencodeEventType.sessionError:
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

  bool _matchesSession(OpencodeEvent event) {
    final sid = event.sessionId;
    if (sid != null && sid.isNotEmpty) return sid == args.sessionId;
    // fallback：message.updated 事件里 message.sessionId
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
    _subscription?.cancel();
    super.dispose();
  }
}
