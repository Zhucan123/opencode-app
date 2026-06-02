import 'package:code_app/features/chat/chat_provider.dart';
import 'package:code_app/features/chat/widgets/chat_input_bar.dart';
import 'package:code_app/features/chat/widgets/message_bubble.dart';
import 'package:code_app/features/sessions/session_provider.dart';
import 'package:code_app/shared/theme.dart';
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

    ref.listen<ChatState>(chatProvider(args), (_, next) {
      if (next.error != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(next.error!)),
        );
      }
      if (mounted) {
        _scrollToBottom();
      }
    });

    return Scaffold(
      appBar: AppBar(title: Text(title)),
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
                      itemCount: state.messages.length + (state.isStreaming ? 1 : 0),
                      separatorBuilder: (_, __) => const SizedBox(height: 16),
                      itemBuilder: (context, index) {
                        if (state.isStreaming && index == state.messages.length) {
                          // 收集所有正在流式输出的文本（不在消息列表里的 messageId）
                          final existingIds = state.messages.map((m) => m.id).toSet();
                          final pendingText = state.streamingParts.entries
                              .where((e) => !existingIds.contains(e.key))
                              .map((e) => e.value.values.join(''))
                              .where((t) => t.isNotEmpty)
                              .join('\n\n');

                          if (pendingText.isNotEmpty) {
                            // 有流式内容但还没进 REST 列表，显示为临时气泡
                            return _StreamingBubble(text: pendingText);
                          }
                          return const _ThinkingBubble();
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
          if (state.availableModes.isNotEmpty)
            _ModeSelectorBar(
              modes: state.availableModes,
              selected: state.selectedMode,
              onSelect: (mode) => ref.read(chatProvider(args).notifier).setMode(mode),
            ),
          ChatInputBar(
            isBusy: state.isSending,
            onSend: (text) => ref.read(chatProvider(args).notifier).sendMessage(text),
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
  const _ThinkingBubble();

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
              'OpenCode 正在思考...',
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

class _ModeSelectorBar extends StatelessWidget {
  const _ModeSelectorBar({
    required this.modes,
    required this.selected,
    required this.onSelect,
  });

  final List<String> modes;
  final String? selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        itemCount: modes.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final mode = modes[index];
          final isSelected = mode == selected;
          return GestureDetector(
            onTap: () => onSelect(mode),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.accent : AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected ? AppColors.accent : AppColors.border,
                ),
              ),
              child: Text(
                mode,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: isSelected ? Colors.white : AppColors.textMuted,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    ),
              ),
            ),
          );
        },
      ),
    );
  }
}
