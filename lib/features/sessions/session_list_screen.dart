import 'package:code_app/core/api/models/session.dart';
import 'package:code_app/features/connection/connection_provider.dart';
import 'package:code_app/features/servers/server_provider.dart';
import 'package:code_app/features/sessions/session_provider.dart';
import 'package:code_app/shared/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class SessionListScreen extends ConsumerWidget {
  const SessionListScreen({super.key, required this.serverId});

  final String serverId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final server = ref.watch(serverByIdProvider(serverId));
    final sessions = ref.watch(sessionListProvider(serverId));

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                color: AppColors.success,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Flexible(child: Text(server?.name ?? 'Sessions')),
          ],
        ),
        actions: [
          IconButton(
            onPressed: () async {
              await ref.read(connectionProvider(serverId).notifier).disconnect();
              if (context.mounted) {
                context.go('/');
              }
            },
            icon: const Icon(Icons.power_settings_new_rounded),
            tooltip: '断开连接',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _createSession(context, ref),
        child: const Icon(Icons.add),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(sessionListProvider(serverId).notifier).refreshSessions(),
        child: sessions.when(
          data: (items) {
            if (items.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(24),
                children: const [
                  SizedBox(height: 80),
                  _EmptySessionState(),
                ],
              );
            }

            return ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(20),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final session = items[index];
                return _SessionCard(
                  session: session,
                  onTap: () {
                    context.push(
                      '/servers/$serverId/sessions/${session.id}/chat',
                    );
                  },
                  onDelete: () => _deleteSession(context, ref, session),
                );
              },
            );
          },
          error: (error, _) => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(24),
            children: [
              const SizedBox(height: 120),
              Center(child: Text(error.toString())),
            ],
          ),
          loading: () => const Center(child: CircularProgressIndicator()),
        ),
      ),
    );
  }

  Future<void> _createSession(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final title = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: AppColors.card,
          title: const Text('新建会话'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: '标题（可选）',
              hintText: '例如：修复认证模块',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(controller.text.trim()),
              child: const Text('创建'),
            ),
          ],
        );
      },
    );

    if (!context.mounted || title == null) {
      return;
    }

    final session = await ref.read(sessionListProvider(serverId).notifier).createSession(
          title: title,
        );
    if (context.mounted) {
      context.push('/servers/$serverId/sessions/${session.id}/chat');
    }
  }

  Future<void> _deleteSession(
    BuildContext context,
    WidgetRef ref,
    OpencodeSession session,
  ) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            return AlertDialog(
              backgroundColor: AppColors.card,
              title: const Text('删除会话'),
              content: Text('确定删除“${session.title}”吗？'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('删除'),
                ),
              ],
            );
          },
        ) ??
        false;

    if (!confirmed) {
      return;
    }

    await ref.read(sessionListProvider(serverId).notifier).deleteSession(session.id);
  }
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({
    required this.session,
    required this.onTap,
    required this.onDelete,
  });

  final OpencodeSession session;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey(session.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDelete(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        decoration: BoxDecoration(
          color: AppColors.danger.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
      ),
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.border),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 标题
                Text(
                  session.title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),

                // 标签行
                if (session.agent != null || session.modelId != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (session.agent != null)
                          _buildTag(
                            context,
                            icon: Icons.smart_toy_outlined,
                            text: session.agent!,
                            color: AppColors.accent,
                          ),
                        if (session.modelId != null)
                          _buildTag(
                            context,
                            icon: Icons.auto_awesome_outlined,
                            text: session.modelId!,
                            color: Colors.purpleAccent,
                          ),
                      ],
                    ),
                  ),

                // 预览文本
                Text(
                  session.preview?.trim().isNotEmpty == true
                      ? session.preview!.trim()
                      : '点击进入对话...',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textMuted,
                        height: 1.4,
                      ),
                ),
                const SizedBox(height: 12),

                // 底部信息栏（时间 + 消耗）
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _formatTime(session.updatedAt ?? session.createdAt),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (session.cost != null || session.totalTokens != null)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (session.totalTokens != null && session.totalTokens! > 0)
                            Text(
                              _formatTokens(session.totalTokens!),
                              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: AppColors.textMuted.withOpacity(0.5),
                                    fontSize: 11,
                                  ),
                            ),
                          if (session.totalTokens != null && session.totalTokens! > 0 && session.cost != null && session.cost! > 0)
                            Text(
                              ' • ',
                              style: TextStyle(color: AppColors.textMuted.withOpacity(0.5), fontSize: 11),
                            ),
                          if (session.cost != null && session.cost! > 0)
                            Text(
                              '\$${session.cost!.toStringAsFixed(3)}',
                              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: AppColors.textMuted.withOpacity(0.8),
                                    fontWeight: FontWeight.w500,
                                    fontSize: 11,
                                  ),
                            ),
                        ],
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTag(BuildContext context, {required IconData icon, required String text, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
          ),
        ],
      ),
    );
  }

  static String _formatTokens(int tokens) {
    if (tokens < 1000) return '$tokens tkns';
    if (tokens < 1000000) return '${(tokens / 1000).toStringAsFixed(1)}k tkns';
    return '${(tokens / 1000000).toStringAsFixed(2)}M tkns';
  }

  static String _formatTime(DateTime? value) {
    if (value == null) {
      return '刚刚更新';
    }
    final now = DateTime.now();
    final difference = now.difference(value);
    if (difference.inMinutes < 1) {
      return '刚刚更新';
    }
    if (difference.inHours < 1) {
      return '${difference.inMinutes} 分钟前';
    }
    if (difference.inDays < 1) {
      return '${difference.inHours} 小时前';
    }
    return '${difference.inDays} 天前';
  }
}

class _EmptySessionState extends StatelessWidget {
  const _EmptySessionState();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppColors.surface,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.border),
          ),
          child: const Icon(Icons.rocket_launch_rounded, size: 48, color: AppColors.accent),
        ),
        const SizedBox(height: 24),
        Text('一切准备就绪', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        Text(
          '点击右下角按钮\n开启你的第一个 OpenCode 编程会话',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.textMuted,
                height: 1.5,
              ),
        ),
      ],
    );
  }
}
