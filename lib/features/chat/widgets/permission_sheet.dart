import 'package:code_app/core/api/models/event.dart';
import 'package:code_app/shared/theme.dart';
import 'package:flutter/material.dart';

class PermissionSheet extends StatefulWidget {
  const PermissionSheet({
    super.key,
    required this.event,
    required this.onDecision,
  });

  final OpencodeEvent event;
  final void Function(bool allow, bool permanent) onDecision;

  @override
  State<PermissionSheet> createState() => _PermissionSheetState();
}

class _PermissionSheetState extends State<PermissionSheet> {
  bool _permanent = false;

  @override
  Widget build(BuildContext context) {
    final title = widget.event.title ?? '需要权限';
    final command = widget.event.command ?? widget.event.tool ?? '未知操作';
    final textTheme = Theme.of(context).textTheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.security, color: AppColors.primary, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text('OpenCode 请求执行以下操作：', style: textTheme.bodyMedium),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              child: SelectableText(
                command,
                style: textTheme.bodyMedium?.copyWith(
                  fontFamily: 'monospace',
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Checkbox(
                  value: _permanent,
                  onChanged: (val) {
                    setState(() {
                      _permanent = val ?? false;
                    });
                  },
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _permanent = !_permanent;
                      });
                    },
                    child: Text('在此会话中永久允许此操作', style: textTheme.bodyMedium),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => widget.onDecision(false, _permanent),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      side: const BorderSide(color: AppColors.error),
                      foregroundColor: AppColors.error,
                    ),
                    child: const Text('拒绝 (Deny)'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => widget.onDecision(true, _permanent),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.text,
                    ),
                    child: const Text('允许 (Allow)'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
