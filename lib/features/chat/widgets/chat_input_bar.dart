import 'package:code_app/shared/theme.dart';
import 'package:flutter/material.dart';

class ChatInputBar extends StatefulWidget {
  const ChatInputBar({
    super.key,
    required this.onSend,
    this.isBusy = false,
    this.availableModes = const [],
    this.selectedMode,
    this.onModeSelected,
  });

  final Future<void> Function(String text) onSend;
  final bool isBusy;
  final List<String> availableModes;
  final String? selectedMode;
  final ValueChanged<String>? onModeSelected;

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: const BoxDecoration(
          color: AppColors.background,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (widget.availableModes.isNotEmpty)
              _ModeButton(
                selected: widget.selectedMode,
                modes: widget.availableModes,
                onModeSelected: widget.onModeSelected,
              )
            else
              IconButton(
                onPressed: null,
                icon: const Icon(Icons.attach_file_rounded),
                color: AppColors.textMuted,
                disabledColor: AppColors.textMuted,
              ),
            Expanded(
              child: TextField(
                controller: _controller,
                enabled: !widget.isBusy,
                minLines: 1,
                maxLines: 6,
                textInputAction: TextInputAction.newline,
                decoration: const InputDecoration(
                  hintText: 'Message OpenCode...',
                  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 44,
              height: 44,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  padding: EdgeInsets.zero,
                  shape: const CircleBorder(),
                  backgroundColor: AppColors.textPrimary,
                  foregroundColor: AppColors.background,
                ),
                onPressed: widget.isBusy ? null : _handleSend,
                child: widget.isBusy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.arrow_upward_rounded, size: 18),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleSend() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    await widget.onSend(text);
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.selected,
    required this.modes,
    this.onModeSelected,
  });

  final String? selected;
  final List<String> modes;
  final ValueChanged<String>? onModeSelected;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showModeSheet(context),
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        margin: const EdgeInsets.only(bottom: 4, right: 4),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              selected ?? 'build',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: AppColors.accent,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.expand_more_rounded, size: 14, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }

  void _showModeSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '选择模式',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              ...modes.map((mode) {
                final isSelected = mode == selected;
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                  leading: Icon(
                    _modeIcon(mode),
                    color: isSelected ? AppColors.accent : AppColors.textMuted,
                    size: 20,
                  ),
                  title: Text(
                    mode,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: isSelected ? AppColors.accent : AppColors.textPrimary,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                        ),
                  ),
                  trailing: isSelected
                      ? const Icon(Icons.check_rounded, color: AppColors.accent, size: 18)
                      : null,
                  onTap: () {
                    onModeSelected?.call(mode);
                    Navigator.pop(context);
                  },
                );
              }),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  IconData _modeIcon(String mode) {
    return switch (mode.toLowerCase()) {
      'build' => Icons.construction_rounded,
      'plan' => Icons.map_outlined,
      _ => Icons.smart_toy_outlined,
    };
  }
}
