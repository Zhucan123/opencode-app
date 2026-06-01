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
  bool operator ==(Object other) {
    return other is ChatProviderArgs &&
        other.serverId == serverId &&
        other.sessionId == sessionId;
  }

  @override
  int get hashCode => Object.hash(serverId, sessionId);
}

class ChatState {
  const ChatState({
    this.messages = const <OpencodeMessage>[],
    this.isLoading = false,
    this.isSending = false,
    this.isStreaming = false,
    this.error,
  });

  final List<OpencodeMessage> messages;
  final bool isLoading;
  final bool isSending;
  final bool isStreaming;
  final String? error;

  ChatState copyWith({
    List<OpencodeMessage>? messages,
    bool? isLoading,
    bool? isSending,
    bool? isStreaming,
    String? error,
    bool clearError = false,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
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
      state = state.copyWith(
        isLoading: false,
        error: '当前服务器尚未建立连接。',
      );
      return;
    }

    try {
      final messages = await connection.apiClient.getMessages(args.sessionId);
      state = state.copyWith(
        messages: messages,
        isLoading: false,
        clearError: true,
      );

      _subscription = connection.events.listen(
        _handleEvent,
        onError: (Object error, StackTrace stackTrace) {
          state = state.copyWith(
            isStreaming: false,
            error: error.toString(),
          );
        },
      );
    } catch (error) {
      state = state.copyWith(
        isLoading: false,
        error: error.toString(),
      );
    }
  }

  Future<void> refreshMessages() async {
    final connection = ref.read(activeConnectionProvider(args.serverId));
    if (connection == null) {
      return;
    }
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
    if (trimmed.isEmpty || state.isSending) {
      return;
    }

    final optimistic = OpencodeMessage(
      id: 'local-${DateTime.now().microsecondsSinceEpoch}',
      sessionId: args.sessionId,
      role: MessageRole.user,
      parts: [
        MessagePart(type: MessagePartType.text, text: trimmed),
      ],
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
      state = state.copyWith(
        isSending: false,
        isStreaming: false,
        error: error.toString(),
      );
    }
  }

  void _handleEvent(OpencodeEvent event) {
    if (!_matchesSession(event)) {
      return;
    }

    switch (event.type) {
      case OpencodeEventType.sessionUpdated:
        // session.updated 表示 session 元数据更新（标题等），标记为流式状态
        state = state.copyWith(isStreaming: true, clearError: true);
        return;
      case OpencodeEventType.messageUpdated:
        // message.updated 是实际的消息更新事件（流式 + 完成都走这里）
        final message = event.message;
        if (message == null) {
          return;
        }
        // 如果消息已完成（assistant 角色且有 time.completed），关闭流式状态
        final isComplete = message.role == MessageRole.assistant &&
            event.payload['properties']?['info']?['time']?['completed'] != null;
        state = state.copyWith(
          messages: _upsertMessage(state.messages, message),
          isStreaming: !isComplete,
          isSending: false,
          clearError: true,
        );
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
    final messageSessionId = event.message?.sessionId;
    final eventSessionId = event.sessionId;
    return messageSessionId == args.sessionId || eventSessionId == args.sessionId;
  }

  List<OpencodeMessage> _upsertMessage(
    List<OpencodeMessage> current,
    OpencodeMessage incoming,
  ) {
    final next = [...current];
    final index = next.indexWhere((message) => message.id == incoming.id);
    if (index == -1) {
      next.add(incoming);
    } else {
      next[index] = incoming;
    }
    next.sort((left, right) {
      final leftTime = left.createdAt;
      final rightTime = right.createdAt;
      if (leftTime == null && rightTime == null) {
        return 0;
      }
      if (leftTime == null) {
        return -1;
      }
      if (rightTime == null) {
        return 1;
      }
      return leftTime.compareTo(rightTime);
    });
    return next;
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
