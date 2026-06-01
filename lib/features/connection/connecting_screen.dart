import 'package:code_app/features/connection/connection_provider.dart';
import 'package:code_app/features/servers/server_provider.dart';
import 'package:code_app/shared/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class ConnectingScreen extends ConsumerStatefulWidget {
  const ConnectingScreen({super.key, required this.serverId});

  final String serverId;

  @override
  ConsumerState<ConnectingScreen> createState() => _ConnectingScreenState();
}

class _ConnectingScreenState extends ConsumerState<ConnectingScreen> {
  bool _started = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_started && mounted) {
        _started = true;
        ref.read(connectionProvider(widget.serverId).notifier).connect();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final server = ref.watch(serverByIdProvider(widget.serverId));
    final state = ref.watch(connectionProvider(widget.serverId));

    ref.listen<ConnectionViewState>(connectionProvider(widget.serverId), (_, next) {
      if (next.status == ConnectionStatus.connected && mounted) {
        context.go('/servers/${widget.serverId}/sessions');
      }
    });

    return Scaffold(
      appBar: AppBar(title: Text(server?.name ?? 'Connecting...')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            Text(
              server == null ? '正在准备连接' : '正在连接 ${server.name}',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              server == null ? '' : server.addressLabel,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textMuted,
                  ),
            ),
            const SizedBox(height: 32),
            Expanded(
              child: Column(
                children: [
                  _ConnectionStepTile(
                    title: 'SSH 握手',
                    subtitle: '与远端服务器协商协议',
                    state: _tileState(state.step, ConnectionStep.sshHandshake),
                  ),
                  _ConnectionStepTile(
                    title: '身份认证',
                    subtitle: '校验用户名与密码',
                    state: _tileState(state.step, ConnectionStep.authentication),
                  ),
                  _ConnectionStepTile(
                    title: '启动 OpenCode',
                    subtitle: '执行 opencode serve --port 4096',
                    state: _tileState(state.step, ConnectionStep.startingOpencode),
                  ),
                  _ConnectionStepTile(
                    title: '建立隧道',
                    subtitle: '映射到本地端口 ${state.localPort ?? 14096}',
                    state: _tileState(state.step, ConnectionStep.establishingTunnel),
                  ),
                ],
              ),
            ),
            if (state.status == ConnectionStatus.error) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.danger.withOpacity(0.3)),
                ),
                child: Text(state.errorMessage ?? '连接失败。'),
              ),
              const SizedBox(height: 16),
            ],
            FilledButton(
              onPressed: state.isConnecting
                  ? null
                  : () {
                      ref.read(connectionProvider(widget.serverId).notifier).connect();
                    },
              child: Text(state.status == ConnectionStatus.error ? '重试连接' : '重新连接'),
            ),
          ],
        ),
      ),
    );
  }

  _ConnectionTileVisualState _tileState(ConnectionStep current, ConnectionStep target) {
    const order = <ConnectionStep>[
      ConnectionStep.idle,
      ConnectionStep.sshHandshake,
      ConnectionStep.authentication,
      ConnectionStep.startingOpencode,
      ConnectionStep.establishingTunnel,
      ConnectionStep.ready,
    ];

    final currentIndex = order.indexOf(current);
    final targetIndex = order.indexOf(target);
    if (current == ConnectionStep.ready || targetIndex < currentIndex) {
      return _ConnectionTileVisualState.done;
    }
    if (current == target) {
      return _ConnectionTileVisualState.active;
    }
    return _ConnectionTileVisualState.idle;
  }
}

enum _ConnectionTileVisualState { idle, active, done }

class _ConnectionStepTile extends StatelessWidget {
  const _ConnectionStepTile({
    required this.title,
    required this.subtitle,
    required this.state,
  });

  final String title;
  final String subtitle;
  final _ConnectionTileVisualState state;

  @override
  Widget build(BuildContext context) {
    final isActive = state == _ConnectionTileVisualState.active;
    final isDone = state == _ConnectionTileVisualState.done;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 250),
      opacity: isActive || isDone ? 1 : 0.35,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isDone ? AppColors.success : Colors.transparent,
                border: Border.all(
                  color: isDone
                      ? AppColors.success
                      : isActive
                          ? AppColors.accent
                          : AppColors.border,
                  width: 2,
                ),
              ),
              alignment: Alignment.center,
              child: isActive
                  ? const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : isDone
                      ? const Icon(Icons.check, size: 14, color: Colors.black)
                      : null,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.textMuted,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
