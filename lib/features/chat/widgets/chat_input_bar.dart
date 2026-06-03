import 'package:code_app/core/api/opencode_client.dart';
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
    this.availableModels = const [],
    this.selectedModel,
    this.onModelSelected,
  });

  final Future<void> Function(String text) onSend;
  final bool isBusy;
  final List<String> availableModes;
  final String? selectedMode;
  final ValueChanged<String>? onModeSelected;
  final List<OpencodeModel> availableModels;
  final OpencodeModel? selectedModel;
  final ValueChanged<OpencodeModel>? onModelSelected;

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
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        decoration: const BoxDecoration(
          color: AppColors.background,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 模式 + 模型选择行
            if (widget.availableModes.isNotEmpty || widget.availableModels.isNotEmpty) ...[
              Row(
                children: [
                  if (widget.availableModes.isNotEmpty)
                    _ModeButton(
                      enabled: !widget.isBusy,
                      selected: widget.selectedMode,
                      modes: widget.availableModes,
                      onModeSelected: widget.onModeSelected,
                    ),
                  if (widget.availableModes.isNotEmpty && widget.availableModels.isNotEmpty)
                    const SizedBox(width: 8),
                  if (widget.availableModels.isNotEmpty)
                    _ModelButton(
                      enabled: !widget.isBusy,
                      selected: widget.selectedModel,
                      models: widget.availableModels,
                      onModelSelected: widget.onModelSelected,
                    ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            // 输入行：全宽输入框 + 发送按钮
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    enabled: !widget.isBusy,
                    minLines: 1,
                    maxLines: 6,
                    textInputAction: TextInputAction.newline,
                    decoration: const InputDecoration(
                      hintText: 'Message OpenCode...',
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
    required this.enabled,
    required this.selected,
    required this.modes,
    this.onModeSelected,
  });

  final bool enabled;
  final String? selected;
  final List<String> modes;
  final ValueChanged<String>? onModeSelected;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? () => _showModeSheet(context) : null,
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: enabled ? AppColors.surface : AppColors.card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              selected ?? 'build',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: enabled ? AppColors.accent : AppColors.textMuted,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
            ),
            const SizedBox(width: 3),
            Icon(Icons.expand_more_rounded,
                size: 13,
                color: enabled ? AppColors.textMuted : AppColors.border),
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
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.5,
            ),
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
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: modes.map((mode) {
                      final isSelected = mode == selected;
                      return ListTile(
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 20),
                        leading: Icon(
                          _modeIcon(mode),
                          color: isSelected
                              ? AppColors.accent
                              : AppColors.textMuted,
                          size: 20,
                        ),
                        title: Text(
                          mode,
                          style:
                              Theme.of(context).textTheme.bodyLarge?.copyWith(
                                    color: isSelected
                                        ? AppColors.accent
                                        : AppColors.textPrimary,
                                    fontWeight: isSelected
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                  ),
                        ),
                        trailing: isSelected
                            ? const Icon(Icons.check_rounded,
                                color: AppColors.accent, size: 18)
                            : null,
                        onTap: () {
                          onModeSelected?.call(mode);
                          Navigator.pop(context);
                        },
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
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

class _ModelButton extends StatelessWidget {
  const _ModelButton({
    required this.enabled,
    required this.selected,
    required this.models,
    this.onModelSelected,
  });

  final bool enabled;
  final OpencodeModel? selected;
  final List<OpencodeModel> models;
  final ValueChanged<OpencodeModel>? onModelSelected;

  @override
  Widget build(BuildContext context) {
    final label = selected?.displayName ?? '默认模型';
    // 截断太长的模型名
    final short = label.length > 20 ? '${label.substring(0, 18)}…' : label;
    return GestureDetector(
      onTap: enabled ? () => _showModelSheet(context) : null,
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: enabled ? AppColors.surface : AppColors.card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome_outlined,
                size: 12,
                color: enabled ? AppColors.textMuted : AppColors.border),
            const SizedBox(width: 4),
            Text(
              short,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: enabled ? AppColors.textMuted : AppColors.border,
                    fontSize: 12,
                  ),
            ),
            const SizedBox(width: 3),
            Icon(Icons.expand_more_rounded,
                size: 13,
                color: enabled ? AppColors.textMuted : AppColors.border),
          ],
        ),
      ),
    );
  }

  void _showModelSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          maxChildSize: 0.9,
          minChildSize: 0.3,
          builder: (context, scrollController) {
            // 按 provider 分组
            final grouped = <String, List<OpencodeModel>>{};
            for (final m in models) {
              grouped.putIfAbsent(m.providerId, () => []).add(m);
            }
            return Column(
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 36, height: 4,
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
                    child: Text('选择模型',
                        style: Theme.of(context).textTheme.titleMedium),
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    children: [
                      for (final entry in grouped.entries) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                          child: Text(
                            entry.key.toUpperCase(),
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                  color: AppColors.textMuted,
                                  letterSpacing: 1,
                                ),
                          ),
                        ),
                        ...entry.value.map((model) {
                          final isSelected = model.id == selected?.id;
                          return ListTile(
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 20),
                            title: Text(
                              model.displayName,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    color: isSelected
                                        ? AppColors.accent
                                        : AppColors.textPrimary,
                                    fontWeight: isSelected
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                  ),
                            ),
                            subtitle: Text(
                              model.id,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(fontSize: 11),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: isSelected
                                ? const Icon(Icons.check_rounded,
                                    color: AppColors.accent, size: 18)
                                : null,
                            onTap: () {
                              onModelSelected?.call(model);
                              Navigator.pop(context);
                            },
                          );
                        }),
                      ],
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
