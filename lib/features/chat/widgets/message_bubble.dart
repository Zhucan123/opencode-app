import 'package:code_app/core/api/models/message.dart';
import 'package:code_app/features/chat/markdown/code_element_builder.dart';
import 'package:code_app/shared/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    this.streamingText,
  });

  final OpencodeMessage message;
  /// 流式传输时的累积文本，优先于 message.parts
  final String? streamingText;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == MessageRole.user;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.9,
        ),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: isUser ? 16 : 0,
            vertical: isUser ? 12 : 0,
          ),
          decoration: isUser
              ? BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.border),
                )
              : null,
          child: isUser
              ? _UserMessageText(message: message)
              : _AssistantMessageMarkdown(
                  message: message,
                  streamingText: streamingText,
                ),
        ),
      ),
    );
  }
}

class _UserMessageText extends StatelessWidget {
  const _UserMessageText({required this.message});

  final OpencodeMessage message;

  @override
  Widget build(BuildContext context) {
    return Text(
      message.parts.map((part) => part.text).join('\n').trim(),
      style: Theme.of(context).textTheme.bodyLarge,
    );
  }
}

class _AssistantMessageMarkdown extends StatelessWidget {
  const _AssistantMessageMarkdown({required this.message, this.streamingText});

  final OpencodeMessage message;
  final String? streamingText;

  @override
  Widget build(BuildContext context) {
    if (streamingText != null && streamingText!.isNotEmpty) {
      return _buildMarkdown(context, streamingText!);
    }

    final children = <Widget>[];
    final textBuffer = StringBuffer();

    void flushText() {
      if (textBuffer.isNotEmpty) {
        children.add(_buildMarkdown(context, textBuffer.toString().trim()));
        textBuffer.clear();
      }
    }

    for (final part in message.parts) {
      if (part.type == MessagePartType.text ||
          part.type == MessagePartType.markdown) {
        textBuffer.writeln(part.text);
        textBuffer.writeln();
      } else if (part.type == MessagePartType.code) {
        final lang = part.language ?? '';
        textBuffer.writeln('```$lang\n${part.text}\n```\n');
      } else if (part.type == MessagePartType.toolCall ||
                 part.type == MessagePartType.stepStart) {
        flushText();
        children.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: _ToolExecutionCard(part: part),
        ));
      } else if (part.type == MessagePartType.patch) {
        flushText();
        children.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: _DiffPreviewCard(part: part),
        ));
      } else {
        // Fallback for other unknown types, try to display text if present
        if (part.text.isNotEmpty) {
          textBuffer.writeln(part.text);
          textBuffer.writeln();
        }
      }
    }
    flushText();

    if (children.isEmpty) {
      return const SizedBox.shrink();
    }
    if (children.length == 1) {
      return children.first;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  Widget _buildMarkdown(BuildContext context, String data) {
    final textTheme = Theme.of(context).textTheme;
    return MarkdownBody(
      data: data,
      selectable: true,
      builders: {
        'code': CodeElementBuilder(context),
      },
      styleSheet: MarkdownStyleSheet(
        p: textTheme.bodyLarge,
        code: textTheme.bodyMedium?.copyWith(
          fontFamily: 'monospace',
          backgroundColor: AppColors.card,
        ),
        codeblockDecoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        blockquote: textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
      ),
    );
  }
}

class _ToolExecutionCard extends StatelessWidget {
  const _ToolExecutionCard({required this.part});

  final MessagePart part;

  @override
  Widget build(BuildContext context) {
    final title = part.rawJson?['title']?.toString() ?? '执行工具';
    final command = part.rawJson?['command']?.toString() ?? part.text;
    
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          collapsedIconColor: AppColors.textMuted,
          iconColor: AppColors.textPrimary,
          title: Row(
            children: [
              const Icon(Icons.build_circle_outlined, size: 18, color: AppColors.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(
                color: Color(0xFF1E1E1E),
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(12)),
              ),
              child: SelectableText(
                command,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: Colors.white70,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DiffPreviewCard extends StatelessWidget {
  const _DiffPreviewCard({required this.part});

  final MessagePart part;

  @override
  Widget build(BuildContext context) {
    final diffText = part.text;
    
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                const Icon(Icons.difference_outlined, size: 18, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(
                  '代码变更 (Diff)',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              color: Color(0xFF1E1E1E),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(12)),
            ),
            child: SelectableText(
              diffText,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
