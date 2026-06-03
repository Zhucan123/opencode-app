import 'package:code_app/core/api/models/session.dart';
import 'package:code_app/features/connection/connection_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final sessionListProvider = AsyncNotifierProvider.family<SessionListController,
    List<OpencodeSession>, String>(SessionListController.new);

class SessionListController
    extends FamilyAsyncNotifier<List<OpencodeSession>, String> {
  late String _serverId;

  @override
  Future<List<OpencodeSession>> build(String arg) async {
    _serverId = arg;
    final connection = ref.watch(activeConnectionProvider(_serverId));
    if (connection == null) {
      throw StateError('当前服务器尚未建立连接。');
    }
    return connection.apiClient.getSessions();
  }

  Future<OpencodeSession> createSession({String? title}) async {
    final connection = ref.read(activeConnectionProvider(_serverId));
    if (connection == null) {
      throw StateError('当前服务器尚未建立连接。');
    }
    final session = await connection.apiClient.createSession(title: title);
    state = AsyncData(await connection.apiClient.getSessions());
    return session;
  }

  Future<void> deleteSession(String sessionId) async {
    final connection = ref.read(activeConnectionProvider(_serverId));
    if (connection == null) {
      throw StateError('当前服务器尚未建立连接。');
    }
    await connection.apiClient.deleteSession(sessionId);
    state = AsyncData(await connection.apiClient.getSessions());
  }

  Future<void> renameSession(String sessionId, String title) async {
    final connection = ref.read(activeConnectionProvider(_serverId));
    if (connection == null) {
      throw StateError('当前服务器尚未建立连接。');
    }
    await connection.apiClient.renameSession(sessionId, title);
    state = AsyncData(await connection.apiClient.getSessions());
  }

  Future<void> refreshSessions() async {
    final connection = ref.read(activeConnectionProvider(_serverId));
    if (connection == null) {
      throw StateError('当前服务器尚未建立连接。');
    }
    state = const AsyncLoading();
    state = AsyncData(await connection.apiClient.getSessions());
  }
}
