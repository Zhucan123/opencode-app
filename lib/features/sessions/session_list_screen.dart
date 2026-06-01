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
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(session.title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text(
                      session.preview?.trim().isNotEmpty == true
                          ? session.preview!.trim()
                          : '点击进入对话',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.textMuted,
                          ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _formatTime(session.updatedAt ?? session.createdAt),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline_rounded),
                tooltip: '删除会话',
              ),
            ],
          ),
        ),
      ),
    );
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
        const Icon(Icons.chat_bubble_outline_rounded, size: 48, color: AppColors.textMuted),
        const SizedBox(height: 16),
        Text('还没有会话', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          '点击右下角按钮创建第一个 OpenCode 会话。',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.textMuted,
              ),
        ),
      ],
    );
  }
}
