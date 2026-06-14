import 'dart:async';
import 'package:code_app/core/api/models/event.dart';
import 'package:code_app/core/api/opencode_client.dart';
import 'package:code_app/core/api/sse_client.dart';
import 'package:code_app/core/ssh/ssh_client.dart';
import 'package:code_app/core/storage/server_config_store.dart';
import 'package:code_app/features/servers/server_provider.dart';
import 'package:code_app/shared/notification_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum ConnectionStatus {
  idle,
  connecting,
  connected,
  reconnecting,
  disconnected,
  error,
}

enum ConnectionStep {
  idle,
  sshHandshake,
  authentication,
  startingOpencode,
  establishingTunnel,
  ready,
}

class ConnectionViewState {
  const ConnectionViewState({
    required this.status,
    required this.step,
    this.localPort,
    this.errorMessage,
  });

  const ConnectionViewState.idle()
      : status = ConnectionStatus.idle,
        step = ConnectionStep.idle,
        localPort = null,
        errorMessage = null;

  final ConnectionStatus status;
  final ConnectionStep step;
  final int? localPort;
  final String? errorMessage;

  bool get isConnected => status == ConnectionStatus.connected;
  bool get isConnecting => status == ConnectionStatus.connecting;
  bool get isReconnecting => status == ConnectionStatus.reconnecting;

  ConnectionViewState copyWith({
    ConnectionStatus? status,
    ConnectionStep? step,
    int? localPort,
    String? errorMessage,
    bool clearError = false,
  }) {
    return ConnectionViewState(
      status: status ?? this.status,
      step: step ?? this.step,
      localPort: localPort ?? this.localPort,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

class ActiveConnection {
  ActiveConnection({
    required this.serverId,
    required this.localPort,
    required this.sshConnection,
    required this.apiClient,
    required this.sseClient,
  });

  final String serverId;
  final int localPort;
  final ManagedSshConnection sshConnection;
  final OpencodeClient apiClient;
  final SseClient sseClient;

  Stream<OpencodeEvent> get events => sseClient.events;

  Future<void> dispose() async {
    sseClient.dispose();
    apiClient.dispose();
    await sshConnection.close();
  }
}

class ConnectionRegistry extends StateNotifier<Map<String, ActiveConnection>> {
  ConnectionRegistry() : super(const <String, ActiveConnection>{});

  void upsert(ActiveConnection connection) {
    state = {...state, connection.serverId: connection};
  }

  Future<void> remove(String serverId) async {
    final connection = state[serverId];
    if (connection != null) {
      await connection.dispose();
    }
    final next = {...state}..remove(serverId);
    state = next;
  }
}

final connectionRegistryProvider =
    StateNotifierProvider<ConnectionRegistry, Map<String, ActiveConnection>>(
  (ref) => ConnectionRegistry(),
);

final activeConnectionProvider = Provider.family<ActiveConnection?, String>((ref, serverId) {
  return ref.watch(connectionRegistryProvider.select((connections) => connections[serverId]));
});

final connectionProvider =
    StateNotifierProvider.family<ConnectionController, ConnectionViewState, String>(
  (ref, serverId) => ConnectionController(ref, serverId),
);

class ConnectionController extends StateNotifier<ConnectionViewState> {
  ConnectionController(this.ref, this.serverId) : super(const ConnectionViewState.idle());

  final Ref ref;
  final String serverId;
  final OpencodeSshClient _sshClient = OpencodeSshClient();
  DateTime? _lastHealthCheck;
  Timer? _heartbeatTimer;
  Timer? _retryTimer;

  @override
  void dispose() {
    _heartbeatTimer?.cancel();
    _retryTimer?.cancel();
    super.dispose();
  }

  void _scheduleRetry() {
    _retryTimer?.cancel();
    _retryTimer = Timer(const Duration(seconds: 15), () {
      if (mounted && state.status == ConnectionStatus.error) {
        _lastHealthCheck = null; // 重置防抖，允许立即重试
        healthCheckAndReconnect();
      }
    });
  }

  void _startMonitoring(ManagedSshConnection sshConnection) {
    _heartbeatTimer?.cancel();
    
    // 被动监听底层连接断开
    sshConnection.client.done.then((_) {
      if (mounted && state.status != ConnectionStatus.disconnected) {
        healthCheckAndReconnect();
      }
    }).catchError((_) {});

    sshConnection.opencodeSession.done.then((_) {
      if (mounted && state.status != ConnectionStatus.disconnected) {
        healthCheckAndReconnect();
      }
    }).catchError((_) {});

    // 主动应用层心跳（每 10 秒）
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted && state.status != ConnectionStatus.disconnected) {
        healthCheckAndReconnect();
      }
    });
  }

  Future<void> connect() async {
    if (state.isConnecting) {
      return;
    }

    final existing = ref.read(activeConnectionProvider(serverId));
    if (existing != null) {
      state = ConnectionViewState(
        status: ConnectionStatus.connected,
        step: ConnectionStep.ready,
        localPort: existing.localPort,
      );
      return;
    }

    final store = ref.read(serverConfigStoreProvider);
    final server = await store.getServer(serverId);
    if (server == null) {
      state = const ConnectionViewState.idle().copyWith(
        status: ConnectionStatus.error,
        errorMessage: '未找到服务器配置。',
      );
      return;
    }

    final localPort = _allocateLocalPort(ref.read(connectionRegistryProvider));
    state = ConnectionViewState(
      status: ConnectionStatus.connecting,
      step: ConnectionStep.sshHandshake,
      localPort: localPort,
    );

    ManagedSshConnection? sshConnection;
    OpencodeClient? apiClient;
    try {
      sshConnection = await _sshClient.connect(
        server: server,
        localPort: localPort,
        onStageChanged: (stage) {
          state = state.copyWith(
            status: ConnectionStatus.connecting,
            step: _mapStage(stage),
            localPort: localPort,
            clearError: true,
          );
        },
      );

      apiClient = OpencodeClient(port: localPort);
      await apiClient.getSessions();
      final sseClient = SseClient(dio: apiClient.dio);

      final actualPort = sshConnection.localPort;
      final activeConnection = ActiveConnection(
        serverId: serverId,
        localPort: actualPort,
        sshConnection: sshConnection,
        apiClient: apiClient,
        sseClient: sseClient,
      );

      ref.read(connectionRegistryProvider.notifier).upsert(activeConnection);
      await store.updateLastConnected(serverId);
      await ref.read(serverListProvider.notifier).refresh();

      NotificationService.startForeground(server.name).ignore();

      state = ConnectionViewState(
        status: ConnectionStatus.connected,
        step: ConnectionStep.ready,
        localPort: actualPort,
      );
      
      _startMonitoring(sshConnection);
    } catch (error) {
      apiClient?.dispose();
      if (sshConnection != null) {
        await sshConnection.close();
      }
      state = ConnectionViewState(
        status: ConnectionStatus.error,
        step: state.step,
        localPort: localPort,
        errorMessage: _friendlyError(error),
      );
    }
  }

  Future<void> healthCheckAndReconnect() async {
    // 正在连接/重连中跳过；用户主动断开或从未连接也跳过
    if (state.isConnecting ||
        state.isReconnecting ||
        state.status == ConnectionStatus.idle ||
        state.status == ConnectionStatus.disconnected) return;

    final now = DateTime.now();
    if (_lastHealthCheck != null && now.difference(_lastHealthCheck!).inSeconds < 10) {
      return;
    }
    _lastHealthCheck = now;

    final existing = ref.read(activeConnectionProvider(serverId));
    if (existing != null) {
      // 有活跃连接 → 先做 health check
      try {
        await existing.apiClient.getSessions().timeout(const Duration(seconds: 8));
        return; // 连接健康，无需重连
      } catch (_) {
        // 不健康，继续走重连
      }
      await ref.read(connectionRegistryProvider.notifier).remove(serverId);
    }
    // existing == null（error 状态）或 health check 失败，直接重连

    state = state.copyWith(status: ConnectionStatus.reconnecting, clearError: true);

    final store = ref.read(serverConfigStoreProvider);
    final server = await store.getServer(serverId);
    if (server == null) {
      state = state.copyWith(
        status: ConnectionStatus.error,
        errorMessage: '未找到服务器配置。',
      );
      return;
    }

    final localPort = _allocateLocalPort(ref.read(connectionRegistryProvider));
    ManagedSshConnection? sshConnection;
    OpencodeClient? apiClient;
    try {
      sshConnection = await _sshClient.connect(
        server: server,
        localPort: localPort,
        onStageChanged: (_) {},
      );
      apiClient = OpencodeClient(port: localPort);
      await apiClient.getSessions();
      final sseClient = SseClient(dio: apiClient.dio);

      final actualPort = sshConnection.localPort;
      ref.read(connectionRegistryProvider.notifier).upsert(ActiveConnection(
            serverId: serverId,
            localPort: actualPort,
            sshConnection: sshConnection,
            apiClient: apiClient,
            sseClient: sseClient,
          ));

      NotificationService.startForeground(server.name).ignore();

      state = ConnectionViewState(
        status: ConnectionStatus.connected,
        step: ConnectionStep.ready,
        localPort: actualPort,
      );

      _startMonitoring(sshConnection);
    } catch (error) {
      apiClient?.dispose();
      if (sshConnection != null) await sshConnection.close();
      NotificationService.stopForeground().ignore();
      state = state.copyWith(
        status: ConnectionStatus.error,
        errorMessage: _friendlyError(error),
      );
      _scheduleRetry();
    }
  }

  Future<void> disconnect() async {
    await ref.read(connectionRegistryProvider.notifier).remove(serverId);
    NotificationService.stopForeground().ignore();
    state = const ConnectionViewState.idle().copyWith(
      status: ConnectionStatus.disconnected,
      step: ConnectionStep.idle,
      clearError: true,
    );
  }

  int _allocateLocalPort(Map<String, ActiveConnection> connections) {
    const basePort = 14096;
    final usedPorts = connections.values.map((connection) => connection.localPort).toSet();
    var nextPort = basePort;
    while (usedPorts.contains(nextPort)) {
      nextPort += 1;
    }
    return nextPort;
  }

  ConnectionStep _mapStage(SshConnectionStage stage) {
    return switch (stage) {
      SshConnectionStage.sshHandshake => ConnectionStep.sshHandshake,
      SshConnectionStage.authentication => ConnectionStep.authentication,
      SshConnectionStage.startingOpencode => ConnectionStep.startingOpencode,
      SshConnectionStage.establishingTunnel => ConnectionStep.establishingTunnel,
    };
  }

  String _friendlyError(Object error) {
    final text = error.toString();
    if (text.isEmpty) {
      return '连接失败，请稍后重试。';
    }
    return text;
  }
}
