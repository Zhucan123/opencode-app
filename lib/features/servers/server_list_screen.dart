import 'package:code_app/core/storage/server_config_store.dart';
import 'package:code_app/features/connection/connection_provider.dart';
import 'package:code_app/features/servers/server_provider.dart';
import 'package:code_app/shared/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class ServerListScreen extends ConsumerWidget {
  const ServerListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final servers = ref.watch(serverListProvider);

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text('opencode Mobile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline_rounded),
            onPressed: () => context.push('/help'),
            tooltip: '使用说明',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/servers/new'),
        child: const Icon(Icons.add),
      ),
      body: servers.when(
        data: (items) {
          if (items.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.dns_outlined, size: 48, color: AppColors.textMuted),
                    const SizedBox(height: 16),
                    Text('还没有服务器', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    Text(
                      '先添加一台支持 SSH 的服务器，然后就能在手机上使用 OpenCode。',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.textMuted,
                          ),
                    ),
                  ],
                ),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () => ref.read(serverListProvider.notifier).refresh(),
            child: ListView.separated(
              padding: const EdgeInsets.all(20),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                return _ServerCard(server: items[index]);
              },
            ),
          );
        },
        error: (error, _) => Center(child: Text(error.toString())),
        loading: () => const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

class _ServerCard extends ConsumerWidget {
  const _ServerCard({required this.server});

  final ServerConfig server;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connection = ref.watch(connectionProvider(server.id));
    final color = switch (connection.status) {
      ConnectionStatus.connected => AppColors.success,
      ConnectionStatus.connecting => AppColors.warning,
      _ => AppColors.textMuted,
    };
    final subtitle = switch (connection.status) {
      ConnectionStatus.connected => '已连接 · 本地端口 ${connection.localPort}',
      ConnectionStatus.connecting => '连接中...',
      ConnectionStatus.error => connection.errorMessage ?? '连接失败',
      _ => server.addressLabel,
    };

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push('/servers/${server.id}/connecting'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(server.name, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.textMuted,
                            fontFamily: connection.status == ConnectionStatus.error ? null : 'monospace',
                          ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (value) async {
                  switch (value) {
                    case 'edit':
                      context.push('/servers/new', extra: server);
                      return;
                    case 'delete':
                      final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (dialogContext) {
                              return AlertDialog(
                                backgroundColor: AppColors.card,
                                title: const Text('删除服务器'),
                                content: Text('确定删除“${server.name}”吗？'),
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
                      await ref.read(connectionProvider(server.id).notifier).disconnect();
                      await ref.read(serverListProvider.notifier).deleteServer(server.id);
                      return;
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'edit', child: Text('编辑')),
                  PopupMenuItem(value: 'delete', child: Text('删除')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
