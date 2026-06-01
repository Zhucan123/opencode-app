import 'package:code_app/core/storage/server_config_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final serverListProvider =
    AsyncNotifierProvider<ServerListController, List<ServerConfig>>(
  ServerListController.new,
);

final serverByIdProvider = Provider.family<ServerConfig?, String>((ref, serverId) {
  final servers = ref.watch(serverListProvider).valueOrNull ?? const <ServerConfig>[];
  for (final server in servers) {
    if (server.id == serverId) {
      return server;
    }
  }
  return null;
});

class ServerListController extends AsyncNotifier<List<ServerConfig>> {
  ServerConfigStore get _store => ref.read(serverConfigStoreProvider);

  @override
  Future<List<ServerConfig>> build() {
    return _store.loadServers();
  }

  Future<ServerConfig> saveServer(ServerConfig config) async {
    final saved = await _store.saveServer(config);
    state = AsyncData(await _store.loadServers());
    return saved;
  }

  Future<void> deleteServer(String serverId) async {
    await _store.deleteServer(serverId);
    state = AsyncData(await _store.loadServers());
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = AsyncData(await _store.loadServers());
  }
}
