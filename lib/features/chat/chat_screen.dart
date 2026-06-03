import 'package:code_app/features/chat/chat_provider.dart';
import 'package:code_app/features/chat/widgets/chat_input_bar.dart';
import 'package:code_app/features/chat/widgets/message_bubble.dart';
import 'package:code_app/features/chat/widgets/permission_sheet.dart';
import 'package:code_app/features/chat/markdown/code_element_builder.dart';
import 'package:code_app/features/connection/connection_provider.dart';
import 'package:code_app/features/sessions/session_provider.dart';
import 'package:code_app/shared/theme.dart';
import 'package:code_app/core/api/models/event.dart';
import 'package:code_app/core/api/models/message.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({
    super.key,
    required this.serverId,
    required this.sessionId,
  });

  final String serverId;
  final String sessionId;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollController.position.pixels <= 80) {
      final args = ChatProviderArgs(serverId: widget.serverId, sessionId: widget.sessionId);
      ref.read(chatProvider(args).notifier).loadMore();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final args = ChatProviderArgs(
      serverId: widget.serverId,
      sessionId: widget.sessionId,
    );
    final state = ref.watch(chatProvider(args));
    final connState = ref.watch(connectionProvider(widget.serverId));
    final isReconnecting = connState.isReconnecting;
    final isConnError = connState.status == ConnectionStatus.error;
    final title = isReconnecting 
        ? '恢复连接中...' 
        : (isConnError ? '连接已断开' : _sessionTitle());
    final existingIds = state.messages.map((m) => m.id).toSet();
    final pendingText = state.streamingParts.entries
        .where((e) => !existingIds.contains(e.key))
        .map((e) => e.value.values.join(''))
        .where((t) => t.isNotEmpty)
        .join('\n\n');
    final pendingReasoning = state.streamingReasoningText;
    final lastMessage = state.messages.isNotEmpty ? state.messages.last : null;
    final showThinkingBubble = state.isStreaming && pendingText.isEmpty && pendingReasoning.isEmpty;
    final showTailBubble = state.isStreaming && (pendingText.isNotEmpty || pendingReasoning.isNotEmpty || showThinkingBubble);
    final isBusy = state.isSending || state.isStreaming || isReconnecting || isConnError;

    ref.listen<ConnectionViewState>(connectionProvider(widget.serverId), (prev, next) {
      if (prev?.status != ConnectionStatus.error && next.status == ConnectionStatus.error && mounted) {
        final err = next.errorMessage ?? '连接失败，请手动重试。';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(err), backgroundColor: AppColors.danger),
        );
      }
    });

    ref.listen<ChatState>(chatProvider(args), (prev, next) {
      if (next.error != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(next.error!)),
        );
      }
      if (prev?.pendingPermission == null && next.pendingPermission != null && mounted) {
        _showPermissionSheet(next.pendingPermission!, args);
      }
      if (mounted) {
        bool shouldScroll = true;
        if (_scrollController.hasClients) {
          final pos = _scrollController.position;
          // 如果当前位置距离底部不超过 200 像素，认为用户在关注最新消息
          shouldScroll = (pos.maxScrollExtent - pos.pixels) <= 200;
        }

        // 如果用户刚刚发送了新消息，强制滚动到底部
        final justSent = next.isSending && !(prev?.isSending ?? false);

        if (shouldScroll || justSent) {
          _scrollToBottom();
        }
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isReconnecting) ...[
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 8),
            ] else if (isConnError) ...[
              const Icon(Icons.error_outline, size: 18, color: AppColors.danger),
              const SizedBox(width: 8),
            ],
            Text(title),
          ],
        ),
        actions: [
          if (isConnError)
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: '重新连接',
              onPressed: () => ref.read(connectionProvider(widget.serverId).notifier).connect(),
            )
          else if (state.messages.isNotEmpty && !isBusy)
            IconButton(
              icon: const Icon(Icons.undo_rounded),
              tooltip: 'Undo last message',
              onPressed: () => ref.read(chatProvider(args).notifier).revert(),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: state.isLoading && state.messages.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : ListView.separated(
                    controller: _scrollController,
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                    itemCount: state.messages.length + (showTailBubble ? 1 : 0) + (state.hasMore ? 1 : 0),
                    separatorBuilder: (_, __) => const SizedBox(height: 16),
                    itemBuilder: (context, index) {
                      // 顶部"加载更多"指示
                      if (state.hasMore && index == 0) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Center(
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 1.5),
                            ),
                          ),
                        );
                      }
                      final msgIndex = state.hasMore ? index - 1 : index;
                      if (showTailBubble && msgIndex == state.messages.length) {
                        if (pendingReasoning.isNotEmpty) {
                          return _StreamingReasoningCard(text: pendingReasoning);
                        }
                        if (pendingText.isNotEmpty) {
                          return _StreamingBubble(text: pendingText);
                        }
                        return _ThinkingBubble(
                          text: state.processingLabel ?? 'OpenCode 正在思考...',
                        );
                      }
                      final msg = state.messages[msgIndex];
                      final streamingText = state.streamingTextFor(msg.id);
                      return MessageBubble(
                        message: msg,
                        serverId: widget.serverId,
                        sessionId: widget.sessionId,
                        streamingText: streamingText.isNotEmpty ? streamingText : null,
                      );
                    },
                  ),
          ),
          ChatInputBar(
            isBusy: isBusy,
            availableModes: state.availableModes,
            selectedMode: state.selectedMode,
            onModeSelected: (mode) => ref.read(chatProvider(args).notifier).setMode(mode),
            availableModels: state.availableModels,
            selectedModel: state.selectedModel,
            onModelSelected: (model) => ref.read(chatProvider(args).notifier).setModel(model),
            onSend: (text, {extraParts}) => ref.read(chatProvider(args).notifier).sendMessage(text, extraParts: extraParts),
            onAbort: () => ref.read(chatProvider(args).notifier).abort(),
          ),
        ],
      ),
    );
  }

  String _sessionTitle() {
    final sessions = ref.watch(sessionListProvider(widget.serverId)).valueOrNull;
    if (sessions != null) {
      for (final session in sessions) {
        if (session.id == widget.sessionId) {
          return session.title;
        }
      }
    }
    return 'OpenCode Chat';
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  void _showPermissionSheet(OpencodeEvent event, ChatProviderArgs args) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: PermissionSheet(
            event: event,
            onDecision: (allow, permanent) {
              Navigator.of(context).pop();
              ref.read(chatProvider(args).notifier).respondToPermission(
                    allow,
                    permanent: permanent,
                  );
            },
          ),
        );
      },
    );
  }
}

class _StreamingBubble extends StatelessWidget {
  const _StreamingBubble({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.9,
        ),
        child: MarkdownBody(
          data: text,
          selectable: false,
          builders: {
            'code': CodeElementBuilder(context),
          },
          styleSheet: MarkdownStyleSheet(
            p: Theme.of(context).textTheme.bodyLarge,
            code: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontFamily: 'monospace',
              backgroundColor: AppColors.card,
            ),
            codeblockDecoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
          ),
        ),
      ),
    );
  }
}

class _ThinkingBubble extends StatelessWidget {
  const _ThinkingBubble({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textMuted,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StreamingReasoningCard extends StatelessWidget {
  const _StreamingReasoningCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            initiallyExpanded: false,
            collapsedIconColor: AppColors.textMuted,
            iconColor: AppColors.textMuted,
            tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
            minTileHeight: 38,
            title: Row(
              children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 1.5),
                ),
                const SizedBox(width: 8),
                Text(
                  '深度思考中...',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                child: Text(
                  text,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textMuted,
                    height: 1.5,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
