import 'dart:convert';

import 'package:code_app/core/api/models/message.dart';
import 'package:code_app/features/chat/markdown/code_element_builder.dart';
import 'package:code_app/features/connection/connection_provider.dart';
import 'package:code_app/shared/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.serverId,
    required this.sessionId,
    this.streamingText,
    this.isCurrentlyStreaming = false,
    this.sessionDiffs,
  });

  final OpencodeMessage message;
  final String serverId;
  final String sessionId;
  final String? streamingText;
  final bool isCurrentlyStreaming;
  final List<FileDiff>? sessionDiffs;

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
                  color: const Color(0xFF252525),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.borderLight),
                )
              : null,
          child: isUser
              ? _UserMessageText(message: message)
              : _AssistantMessageMarkdown(
                  message: message,
                  serverId: serverId,
                  sessionId: sessionId,
                  streamingText: streamingText,
                  isCurrentlyStreaming: isCurrentlyStreaming,
                  sessionDiffs: sessionDiffs,
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
  const _AssistantMessageMarkdown({
    required this.message,
    required this.serverId,
    required this.sessionId,
    this.streamingText,
    this.isCurrentlyStreaming = false,
    this.sessionDiffs,
  });

  final OpencodeMessage message;
  final String serverId;
  final String sessionId;
  final String? streamingText;
  final bool isCurrentlyStreaming;
  final List<FileDiff>? sessionDiffs;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    final textBuffer = StringBuffer();

    void flushText() {
      if (textBuffer.isNotEmpty) {
        children.add(_buildMarkdown(context, textBuffer.toString().trim()));
        textBuffer.clear();
      }
    }

    final lastPatchIndex = message.parts.lastIndexWhere((p) => p.type == MessagePartType.patch);
    final allModifiedFiles = <String>{};
    if (lastPatchIndex != -1) {
      for (final part in message.parts) {
        if (part.type == MessagePartType.patch) {
          final files = part.rawJson?['files'] as List?;
          if (files != null) {
            allModifiedFiles.addAll(files.map((f) => f.toString()));
          }
        }
      }
    }

    for (var i = 0; i < message.parts.length; i++) {
      final part = message.parts[i];
      if (part.type == MessagePartType.text ||
          part.type == MessagePartType.markdown) {
        // Only render text/markdown parts if NOT currently streaming
        if (!isCurrentlyStreaming || (streamingText?.isEmpty ?? true)) {
          textBuffer.writeln(part.text);
          textBuffer.writeln();
        }
      } else if (part.type == MessagePartType.reasoning) {
        flushText();
        children.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0),
          child: _ReasoningCard(
            text: part.text,
            isStreaming: isCurrentlyStreaming,
          ),
        ));
      } else if (part.type == MessagePartType.code) {
        final lang = part.language ?? '';
        textBuffer.writeln('```$lang\n${part.text}\n```\n');
      } else if (part.type == MessagePartType.toolCall) {
        flushText();
        final raw = part.rawJson ?? {};
        final toolName = raw['tool_name']?.toString() ??
            raw['toolName']?.toString() ??
            raw['tool']?.toString() ??
            raw['name']?.toString() ??
            '';
        final stateObj = raw['state'] is Map ? raw['state'] as Map : null;
        final inputObj = stateObj != null ? stateObj['input'] : raw['input'] ?? raw['args'];
        final isTodo = toolName.toLowerCase() == 'todowrite';
        children.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0),
          child: isTodo
              ? _TodoCard(input: inputObj)
              : _ToolExecutionCard(part: part),
        ));
      } else if (part.type == MessagePartType.stepStart || part.type == MessagePartType.stepFinish) {
        // 忽略底层的 step 事件，避免界面杂乱
      } else if (part.type == MessagePartType.toolResult) {
        flushText();
        children.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0),
          child: _ToolResultCard(part: part),
        ));
      } else if (part.type == MessagePartType.patch) {
        if (i == lastPatchIndex) {
          flushText();
          children.add(Padding(
            padding: const EdgeInsets.symmetric(vertical: 4.0),
            child: _DiffPreviewCard(
              files: allModifiedFiles.toList(),
              preloadedDiffs: sessionDiffs,
            ),
          ));
        }
      } else if (part.type == MessagePartType.image) {
        flushText();
        final imgUrl = part.imageUrl;
        if (imgUrl != null) {
          children.add(Padding(
            padding: const EdgeInsets.symmetric(vertical: 4.0),
            child: _ImageCard(imageUrl: imgUrl),
          ));
        }
      } else {
        // Fallback for other unknown types, try to display text if present
        if (part.text.isNotEmpty && !isCurrentlyStreaming) {
          textBuffer.writeln(part.text);
          textBuffer.writeln();
        }
      }
    }
    flushText();

    // Append streaming text after all parts are rendered (if currently streaming)
    if (isCurrentlyStreaming && streamingText != null && streamingText!.isNotEmpty) {
      children.add(_buildMarkdown(context, streamingText!));
    }

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

    final stateObj = raw['state'] is Map ? raw['state'] as Map : null;
    final inputObj = stateObj != null ? stateObj['input'] : null;
    final inputRaw = inputObj ?? raw['input'] ?? raw['args'] ?? raw['command'];

    String? subTitle;
    if (inputRaw is Map) {
      if (rawToolName.toLowerCase() == 'bash') {
        subTitle = inputRaw['description']?.toString() ?? inputRaw['command']?.toString();
      } else if (rawToolName.toLowerCase() == 'edit' || 
                 rawToolName.toLowerCase() == 'write' || 
                 rawToolName.toLowerCase() == 'read' ||
                 rawToolName.toLowerCase() == 'read_file' ||
                 rawToolName.toLowerCase() == 'write_file' ||
                 rawToolName.toLowerCase() == 'edit_file') {
        subTitle = inputRaw['filePath']?.toString() ?? inputRaw['file_path']?.toString();
        if (subTitle != null && subTitle.contains('/')) {
          subTitle = subTitle.split('/').last;
        }
      }
    } else if (inputRaw is String) {
      subTitle = inputRaw;
    }

    if (subTitle != null) {
      subTitle = subTitle.replaceAll('\n', ' ').trim();
      if (subTitle.length > 30) {
        subTitle = '${subTitle.substring(0, 27)}...';
      }
    }

    String displayToolName;
    IconData toolIcon;

    switch (rawToolName.toLowerCase()) {
      case 'bash':
        displayToolName = subTitle ?? '执行终端命令';
        toolIcon = Icons.terminal_rounded;
        break;
      case 'read':
      case 'read_file':
        displayToolName = subTitle != null ? '读取 $subTitle' : '读取文件';
        toolIcon = Icons.description_outlined;
        break;
      case 'write':
      case 'write_file':
        displayToolName = subTitle != null ? '写入 $subTitle' : '写入文件';
        toolIcon = Icons.edit_document;
        break;
      case 'edit':
      case 'edit_file':
        displayToolName = subTitle != null ? '修改 $subTitle' : '修改文件';
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
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
          minTileHeight: 38,
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
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
          minTileHeight: 38,
          title: Row(
            children: [
              const Icon(Icons.output_rounded, size: 18, color: Colors.green),
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

class _DiffPreviewCard extends StatefulWidget {
  const _DiffPreviewCard({
    required this.files,
    this.preloadedDiffs,
  });

  final List<String> files;
  final List<FileDiff>? preloadedDiffs;

  @override
  State<_DiffPreviewCard> createState() => _DiffPreviewCardState();
}

class _DiffPreviewCardState extends State<_DiffPreviewCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final diffs = widget.preloadedDiffs;
    final fileCount = diffs?.length ?? widget.files.length;
    final additions = diffs?.fold(0, (s, d) => s + d.additions) ?? 0;
    final deletions = diffs?.fold(0, (s, d) => s + d.deletions) ?? 0;
    final hasDiffs = diffs != null && diffs.isNotEmpty;

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
          // Header
          InkWell(
            onTap: diffs != null && diffs.isNotEmpty
                ? () => setState(() => _expanded = !_expanded)
                : null,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.difference_outlined, size: 18, color: AppColors.accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$fileCount 个文件变更',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (diffs == null)
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else if (diffs.isNotEmpty) ...[
                    Text(
                      '+$additions',
                      style: const TextStyle(
                        color: Color(0xFF4CAF50),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '-$deletions',
                      style: const TextStyle(
                        color: Color(0xFFF44336),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      size: 18,
                      color: AppColors.textMuted,
                    ),
                  ],
                ],
              ),
            ),
          ),
          // Expanded diff view
          if (_expanded && diffs != null)
            const Divider(height: 1, color: AppColors.border),
          if (_expanded && diffs != null)
            ClipRRect(
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
              child: _buildDiffContent(context, diffs),
            ),
        ],
      ),
    );
  }

  Widget _buildDiffContent(BuildContext context, List<FileDiff> diffs) {
    const maxLinesPerFile = 40;
    const bgColor = Color(0xFF1E1E1E);

    final fileWidgets = <Widget>[];

    for (final diff in diffs) {
      if (diff.patch.isEmpty) continue;

      final spans = _parsePatchToSpans(diff.patch, maxLinesPerFile);
      if (spans.isEmpty) continue;

      fileWidgets.add(Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: const Color(0xFF2A2A2A),
            child: Row(
              children: [
                const Icon(Icons.insert_drive_file_outlined,
                    size: 13, color: Color(0xFF888888)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    diff.file,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: Color(0xFFCCCCCC),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '+${diff.additions}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF4CAF50),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  '-${diff.deletions}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFFF44336),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            color: bgColor,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SelectableText.rich(TextSpan(children: spans)),
            ),
          ),
        ],
      ));
    }

    if (fileWidgets.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        color: bgColor,
        child: const Text(
          '(无变更内容)',
          style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: Colors.white54),
        ),
      );
    }

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
      child: Column(
        children: fileWidgets
            .expand((w) => [w, const Divider(height: 1, color: Color(0xFF333333))])
            .toList()
          ..removeLast(),
      ),
    );
  }

  List<TextSpan> _parsePatchToSpans(String patch, int maxLines) {
    final spans = <TextSpan>[];
    var shownLines = 0;
    bool wasContext = false; // 用于追踪上一行是否是未修改的上下文

    for (final line in patch.split('\n')) {
      if (shownLines >= maxLines) {
        spans.add(TextSpan(
          text: '... (变更过多，已截断)\n',
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 11,
            color: AppColors.textMuted.withOpacity(0.6),
          ),
        ));
        break;
      }

      if (line.startsWith('---') || line.startsWith('+++')) {
        continue; // 忽略文件头
      } else if (line.startsWith('@@')) {
        spans.add(TextSpan(
          text: '$line\n',
          style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: AppColors.textMuted.withOpacity(0.6)),
        ));
        wasContext = false;
      } else if (line.startsWith('-')) {
        spans.add(TextSpan(
          text: '$line\n',
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Color(0xFFEF9A9A), backgroundColor: Color(0x44F44336)),
        ));
        shownLines++;
        wasContext = false;
      } else if (line.startsWith('+')) {
        spans.add(TextSpan(
          text: '$line\n',
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Color(0xFFA5D6A7), backgroundColor: Color(0x444CAF50)),
        ));
        shownLines++;
        wasContext = false;
      } else {
        // 未修改的上下文代码，进行折叠处理
        if (!wasContext) {
          spans.add(TextSpan(
            text: '  ... \n',
            style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: AppColors.textMuted.withOpacity(0.4)),
          ));
          wasContext = true;
          shownLines++;
        }
      }
    }
    return spans;
  }
}

class _TodoCard extends StatefulWidget {
  const _TodoCard({required this.input});

  final dynamic input;

  @override
  State<_TodoCard> createState() => _TodoCardState();
}

class _TodoCardState extends State<_TodoCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final todos = _parseTodos(widget.input);
    final total = todos.length;
    final completed = todos.where((t) => t['status'] == 'completed').length;
    final inProgress = todos.where((t) => t['status'] == 'in_progress').length;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: todos.isNotEmpty ? () => setState(() => _expanded = !_expanded) : null,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.checklist_rtl_rounded, size: 18, color: AppColors.accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '任务计划',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (total > 0) ...[
                    if (inProgress > 0)
                      Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.accent.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$inProgress 进行中',
                          style: TextStyle(fontSize: 11, color: AppColors.accent),
                        ),
                      ),
                    Text(
                      '$completed/$total',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      size: 18,
                      color: AppColors.textMuted,
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (_expanded && todos.isNotEmpty) ...[
            const Divider(height: 1, color: AppColors.border),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                children: todos.map((todo) => _TodoItem(todo: todo)).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _parseTodos(dynamic input) {
    if (input is Map) {
      final todosRaw = input['todos'];
      if (todosRaw is List) {
        return todosRaw.whereType<Map>().map((t) => Map<String, dynamic>.from(t)).toList();
      }
    }
    return const [];
  }
}

class _TodoItem extends StatelessWidget {
  const _TodoItem({required this.todo});

  final Map<String, dynamic> todo;

  @override
  Widget build(BuildContext context) {
    final content = todo['content']?.toString() ?? '';
    final status = todo['status']?.toString() ?? 'pending';
    final priority = todo['priority']?.toString() ?? 'medium';

    final isCompleted = status == 'completed';
    final isCancelled = status == 'cancelled';
    final isInProgress = status == 'in_progress';
    final isHighPriority = priority == 'high';

    Widget statusIcon;
    Color textColor;
    if (isCompleted) {
      statusIcon = const Icon(Icons.check_circle_rounded, size: 16, color: Color(0xFF4CAF50));
      textColor = AppColors.textMuted;
    } else if (isCancelled) {
      statusIcon = Icon(Icons.cancel_outlined, size: 16, color: AppColors.textMuted.withOpacity(0.5));
      textColor = AppColors.textMuted.withOpacity(0.5);
    } else if (isInProgress) {
      statusIcon = SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: AppColors.accent,
        ),
      );
      textColor = AppColors.textPrimary;
    } else {
      statusIcon = Icon(Icons.radio_button_unchecked, size: 16, color: AppColors.textMuted);
      textColor = AppColors.textPrimary;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isHighPriority && !isCompleted && !isCancelled)
            Container(
              width: 3,
              height: 16,
              margin: const EdgeInsets.only(right: 8, top: 1),
              decoration: BoxDecoration(
                color: AppColors.warning,
                borderRadius: BorderRadius.circular(2),
              ),
            )
          else
            const SizedBox(width: 11),
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: statusIcon,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              content,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: textColor,
                decoration: (isCompleted || isCancelled)
                    ? TextDecoration.lineThrough
                    : null,
                decorationColor: textColor,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReasoningCard extends StatefulWidget {
  const _ReasoningCard({required this.text, this.isStreaming = false});

  final String text;
  final bool isStreaming;

  @override
  State<_ReasoningCard> createState() => _ReasoningCardState();
}

class _ReasoningCardState extends State<_ReasoningCard> {
  final ExpansionTileController _controller = ExpansionTileController();
  late bool _wasStreaming;

  @override
  void initState() {
    super.initState();
    _wasStreaming = widget.isStreaming;
  }

  @override
  void didUpdateWidget(covariant _ReasoningCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isStreaming && !widget.isStreaming) {
      // 停止生成，折叠卡片
      if (_controller.isExpanded) {
        _controller.collapse();
      }
    }
    _wasStreaming = widget.isStreaming;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.text.isEmpty) return const SizedBox.shrink();
    
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          controller: _controller,
          initiallyExpanded: _wasStreaming,
          collapsedIconColor: AppColors.textMuted,
          iconColor: AppColors.textMuted,
          title: Text(
            '深度思考 (Reasoning)',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w500,
                ),
          ),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                widget.text,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textMuted,
                      height: 1.5,
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
