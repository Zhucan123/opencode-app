import 'package:code_app/features/chat/chat_provider.dart';
import 'package:code_app/features/chat/widgets/chat_input_bar.dart';
import 'package:code_app/features/chat/widgets/message_bubble.dart';
import 'package:code_app/features/chat/widgets/permission_sheet.dart';
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
    final title = _sessionTitle();
    final existingIds = state.messages.map((m) => m.id).toSet();
    final pendingText = state.streamingParts.entries
        .where((e) => !existingIds.contains(e.key))
        .map((e) => e.value.values.join(''))
        .where((t) => t.isNotEmpty)
        .join('\n\n');
    final lastMessage = state.messages.isNotEmpty ? state.messages.last : null;
    final showThinkingBubble = state.isStreaming &&
        pendingText.isEmpty &&
        (lastMessage == null || lastMessage.role == MessageRole.user);
    final showTailBubble = pendingText.isNotEmpty || showThinkingBubble;
    final isBusy = state.isSending || state.isStreaming;

    ref.listen<ChatState>(chatProvider(args), (prev, next) {
      if (next.error != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(next.error!)),
        );
      }
      if (prev?.pendingPermission == null && next.pendingPermission != null && mounted) {
        _showPermissionSheet(next.pendingPermission!);
      }
      if (mounted) {
        _scrollToBottom();
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (state.messages.isNotEmpty && !isBusy)
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
            child: RefreshIndicator(
              onRefresh: () => ref.read(chatProvider(args).notifier).refreshMessages(),
              child: state.isLoading && state.messages.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.separated(
                      controller: _scrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
                      itemCount: state.messages.length + (showTailBubble ? 1 : 0),
                      separatorBuilder: (_, __) => const SizedBox(height: 16),
                      itemBuilder: (context, index) {
                        if (showTailBubble && index == state.messages.length) {
                          if (pendingText.isNotEmpty) {
                            // 有流式内容但还没进 REST 列表，显示为临时气泡
                            return _StreamingBubble(text: pendingText);
                          }
                          return _ThinkingBubble(
                            text: state.processingLabel ?? 'OpenCode 正在思考...',
                          );
                        }
                        final msg = state.messages[index];
                        final streamingText = state.streamingTextFor(msg.id);
                        return MessageBubble(
                          message: msg,
                          streamingText: streamingText.isNotEmpty ? streamingText : null,
                        );
                      },
                    ),
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
            onSend: (text) => ref.read(chatProvider(args).notifier).sendMessage(text),
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

  void _showPermissionSheet(OpencodeEvent event) {
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
          styleSheet: MarkdownStyleSheet(
            p: Theme.of(context).textTheme.bodyLarge,
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
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 10),
            Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textMuted,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
