import 'dart:convert';

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
      } else if (part.type == MessagePartType.reasoning) {
        flushText();
        children.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0),
          child: _ReasoningCard(text: part.text),
        ));
      } else if (part.type == MessagePartType.code) {
        final lang = part.language ?? '';
        textBuffer.writeln('```$lang\n${part.text}\n```\n');
      } else if (part.type == MessagePartType.toolCall) {
        flushText();
        children.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: _ToolExecutionCard(part: part),
        ));
      } else if (part.type == MessagePartType.stepStart || part.type == MessagePartType.stepFinish) {
        // 忽略底层的 step 事件，避免界面杂乱
      } else if (part.type == MessagePartType.toolResult) {
        flushText();
        children.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: _ToolResultCard(part: part),
        ));
      } else if (part.type == MessagePartType.patch) {
        flushText();
        children.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: _DiffPreviewCard(part: part),
        ));
      } else if (part.type == MessagePartType.image) {
        flushText();
        final imgUrl = part.imageUrl;
        if (imgUrl != null) {
          children.add(Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: _ImageCard(imageUrl: imgUrl),
          ));
        }
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
    final raw = part.rawJson ?? {};

    // 尝试多种字段名，兼容不同版本的 opencode API
    final rawToolName = raw['tool_name']?.toString() ??
        raw['toolName']?.toString() ??
        raw['tool']?.toString() ??
        raw['name']?.toString() ??
        (raw['tool_call'] is Map ? raw['tool_call']['name']?.toString() : null) ??
        '执行工具';

    String displayToolName;
    IconData toolIcon;

    switch (rawToolName.toLowerCase()) {
      case 'bash':
        displayToolName = '执行终端命令';
        toolIcon = Icons.terminal_rounded;
        break;
      case 'read':
      case 'read_file':
        displayToolName = '读取文件';
        toolIcon = Icons.description_outlined;
        break;
      case 'write':
      case 'write_file':
        displayToolName = '写入文件';
        toolIcon = Icons.edit_document;
        break;
      case 'edit':
      case 'edit_file':
        displayToolName = '修改文件';
        toolIcon = Icons.edit_note_rounded;
        break;
      case 'glob':
        displayToolName = '检索文件';
        toolIcon = Icons.manage_search_rounded;
        break;
      case 'grep':
        displayToolName = '搜索代码';
        toolIcon = Icons.find_in_page_outlined;
        break;
      case 'google_search':
      case 'websearch_web_search_exa':
        displayToolName = '网络搜索';
        toolIcon = Icons.travel_explore_rounded;
        break;
      case 'webfetch':
        displayToolName = '读取网页';
        toolIcon = Icons.language_rounded;
        break;
      case 'todowrite':
        displayToolName = '更新任务清单';
        toolIcon = Icons.checklist_rtl_rounded;
        break;
      default:
        displayToolName = rawToolName == '执行工具' ? rawToolName : '调用工具 ($rawToolName)';
        toolIcon = Icons.build_circle_outlined;
    }

    final stateObj = raw['state'] is Map ? raw['state'] as Map : null;

    // 工具的详细入参：input / args / command / text，展示 JSON 或字符串
    final inputObj = stateObj != null ? stateObj['input'] : null;
    final inputRaw = inputObj ?? raw['input'] ?? raw['args'] ?? raw['command'];
    String detail;
    if (inputRaw is Map || inputRaw is List) {
      const encoder = JsonEncoder.withIndent('  ');
      detail = encoder.convert(inputRaw);
    } else if (inputRaw != null) {
      detail = inputRaw.toString();
    } else if (part.text.isNotEmpty) {
      detail = part.text;
    } else {
      detail = raw.isNotEmpty ? const JsonEncoder.withIndent('  ').convert(raw) : '(无详情)';
    }
    
    // 尝试提取结果文本
    final resultRaw = (stateObj != null ? stateObj['output'] : null) ?? raw['result'] ?? raw['output'] ?? raw['stdout'];
    String? resultDetail;
    if (resultRaw != null) {
      if (resultRaw is Map || resultRaw is List) {
        resultDetail = const JsonEncoder.withIndent('  ').convert(resultRaw);
      } else {
        resultDetail = resultRaw.toString();
      }
    }
    
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
              Icon(toolIcon, size: 18, color: AppColors.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  displayToolName,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (resultDetail != null)
                const Icon(Icons.check_circle, size: 14, color: Colors.green),
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('输入 (Input):', style: TextStyle(fontSize: 12, color: Colors.grey[400])),
                  const SizedBox(height: 4),
                  SelectableText(
                    detail,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: Colors.white70,
                    ),
                  ),
                  if (resultDetail != null) ...[
                    const Divider(color: Colors.white24, height: 24),
                    Text('输出 (Output):', style: TextStyle(fontSize: 12, color: Colors.green[300])),
                    const SizedBox(height: 4),
                    SelectableText(
                      resultDetail,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolResultCard extends StatelessWidget {
  const _ToolResultCard({required this.part});

  final MessagePart part;

  @override
  Widget build(BuildContext context) {
    final raw = part.rawJson ?? {};
    
    // 尝试提取结果文本
    String detail;
    final resultRaw = raw['result'] ?? raw['output'] ?? raw['stdout'];
    if (resultRaw is Map || resultRaw is List) {
      const encoder = JsonEncoder.withIndent('  ');
      detail = encoder.convert(resultRaw);
    } else if (resultRaw != null) {
      detail = resultRaw.toString();
    } else if (part.text.isNotEmpty) {
      detail = part.text;
    } else {
      detail = raw.isNotEmpty ? const JsonEncoder.withIndent('  ').convert(raw) : '(执行成功)';
    }

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
              const Icon(Icons.check_circle_outline, size: 18, color: Colors.green),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '执行结果',
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
                detail,
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
    final lines = diffText.split('\n');
    
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
                const Icon(Icons.difference_outlined, size: 18, color: AppColors.accent),
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
            child: SelectableText.rich(
              TextSpan(
                children: lines.map((line) {
                  Color? bgColor;
                  Color textColor = Colors.white;
                  
                  if (line.startsWith('+')) {
                    bgColor = const Color(0x334CAF50); // 浅绿色背景
                    textColor = Colors.green[300]!;
                  } else if (line.startsWith('-')) {
                    bgColor = const Color(0x33F44336); // 浅红色背景
                    textColor = Colors.red[300]!;
                  } else if (line.startsWith('@@')) {
                    textColor = Colors.grey[500]!;
                  }

                  return TextSpan(
                    text: '$line\n',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: textColor,
                      backgroundColor: bgColor,
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReasoningCard extends StatelessWidget {
  const _ReasoningCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();
    
    return Container(
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
          tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
          minTileHeight: 40,
          title: Row(
            children: [
              const Icon(Icons.psychology_outlined, size: 16, color: AppColors.textMuted),
              const SizedBox(width: 8),
              Text(
                '深度思考',
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
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: SelectableText(
                text,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textMuted.withOpacity(0.8),
                  height: 1.5,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImageCard extends StatelessWidget {
  const _ImageCard({required this.imageUrl});

  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    Widget imageWidget;
    if (imageUrl.startsWith('data:image')) {
      final b64 = imageUrl.split(',').last;
      imageWidget = Image.memory(base64Decode(b64), fit: BoxFit.cover);
    } else if (imageUrl.startsWith('http')) {
      imageWidget = Image.network(imageUrl, fit: BoxFit.cover);
    } else {
      return const SizedBox.shrink();
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 300),
        child: imageWidget,
      ),
    );
  }
}
