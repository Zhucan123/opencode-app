import 'dart:async';
import 'package:code_app/core/api/models/event.dart';
import 'package:code_app/core/api/opencode_client.dart';
import 'package:code_app/core/api/sse_client.dart';
import 'package:code_app/core/ssh/ssh_client.dart';
import 'package:code_app/core/storage/server_config_store.dart';
import 'package:code_app/features/servers/server_provider.dart';
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
  
  Timer? _heartbeatTimer;

  @override
  void dispose() {
    _heartbeatTimer?.cancel();
    super.dispose();
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

    // 主动应用层心跳（每 15 秒）
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 15), (_) {
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

      final activeConnection = ActiveConnection(
        serverId: serverId,
        localPort: localPort,
        sshConnection: sshConnection,
        apiClient: apiClient,
        sseClient: sseClient,
      );

      ref.read(connectionRegistryProvider.notifier).upsert(activeConnection);
      await store.updateLastConnected(serverId);
      await ref.read(serverListProvider.notifier).refresh();

      state = ConnectionViewState(
        status: ConnectionStatus.connected,
        step: ConnectionStep.ready,
        localPort: localPort,
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
    if (state.isConnecting || state.isReconnecting) return;

    final existing = ref.read(activeConnectionProvider(serverId));
    if (existing != null) {
      try {
        await existing.apiClient.getSessions().timeout(const Duration(seconds: 3));
        return; // still healthy
      } catch (_) {
        // unhealthy — tear down and reconnect silently
      }
    }

    state = state.copyWith(status: ConnectionStatus.reconnecting, clearError: true);
    await ref.read(connectionRegistryProvider.notifier).remove(serverId);

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

      ref.read(connectionRegistryProvider.notifier).upsert(ActiveConnection(
            serverId: serverId,
            localPort: localPort,
            sshConnection: sshConnection,
            apiClient: apiClient,
            sseClient: sseClient,
          ));

      state = ConnectionViewState(
        status: ConnectionStatus.connected,
        step: ConnectionStep.ready,
        localPort: localPort,
      );
      
      _startMonitoring(sshConnection);
    } catch (error) {
      apiClient?.dispose();
      if (sshConnection != null) await sshConnection.close();
      state = state.copyWith(
        status: ConnectionStatus.error,
        errorMessage: _friendlyError(error),
      );
    }
  }

  Future<void> disconnect() async {
    _heartbeatTimer?.cancel();
    await ref.read(connectionRegistryProvider.notifier).remove(serverId);
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
