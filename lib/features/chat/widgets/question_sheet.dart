import 'package:code_app/core/api/models/event.dart';
import 'package:code_app/shared/theme.dart';
import 'package:flutter/material.dart';

class QuestionSheet extends StatefulWidget {
  const QuestionSheet({
    super.key,
    required this.event,
    required this.onReply,
  });

  final OpencodeEvent event;
  final void Function(List<List<String>> answers) onReply;

  @override
  State<QuestionSheet> createState() => _QuestionSheetState();
}

class _QuestionSheetState extends State<QuestionSheet> {
  final List<Set<String>> _selections = [];

  @override
  void initState() {
    super.initState();
    final questions = widget.event.questions ?? [];
    for (var i = 0; i < questions.length; i++) {
      _selections.add(<String>{});
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final questions = widget.event.questions ?? [];

    if (questions.isEmpty) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('收到无效的提问请求'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => widget.onReply([]),
                child: const Text('关闭'),
              ),
            ],
          ),
        ),
      );
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.help_outline, color: AppColors.accent, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'OpenCode 需要你的选择',
                    style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.5,
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: questions.length,
                separatorBuilder: (context, index) => const Divider(color: AppColors.border, height: 32),
                itemBuilder: (context, qIndex) {
                  final q = questions[qIndex];
                  final title = q['header']?.toString() ?? '请选择';
                  final desc = q['question']?.toString() ?? '';
                  final isMultiple = q['multiple'] == true;
                  final options = q['options'] is List ? q['options'] as List : [];

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                      if (desc.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(desc, style: textTheme.bodyMedium?.copyWith(color: AppColors.textMuted)),
                      ],
                      const SizedBox(height: 12),
                      ...options.map((opt) {
                        final label = opt['label']?.toString() ?? '';
                        final optDesc = opt['description']?.toString() ?? '';
                        final isSelected = _selections[qIndex].contains(label);

                        return InkWell(
                          onTap: () {
                            setState(() {
                              if (isMultiple) {
                                if (isSelected) {
                                  _selections[qIndex].remove(label);
                                } else {
                                  _selections[qIndex].add(label);
                                }
                              } else {
                                _selections[qIndex].clear();
                                _selections[qIndex].add(label);
                              }
                            });
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            decoration: BoxDecoration(
                              color: isSelected ? AppColors.accent.withOpacity(0.1) : AppColors.surface,
                              border: Border.all(
                                color: isSelected ? AppColors.accent : AppColors.border,
                                width: 1,
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  isMultiple
                                      ? (isSelected ? Icons.check_box : Icons.check_box_outline_blank)
                                      : (isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked),
                                  color: isSelected ? AppColors.accent : AppColors.textMuted,
                                  size: 20,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(label, style: textTheme.bodyMedium),
                                      if (optDesc.isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Text(optDesc, style: textTheme.bodySmall?.copyWith(color: AppColors.textMuted)),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () {
                  // 把 Set 转为 List
                  final answers = _selections.map((s) => s.toList()).toList();
                  widget.onReply(answers);
                },
                child: const Text('确认选择', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
