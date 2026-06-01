import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

const _serverListKey = 'server_configs';

enum SshAuthType { password, pemKey }

class ServerConfig {
  const ServerConfig({
    required this.id,
    required this.name,
    required this.host,
    required this.sshPort,
    required this.username,
    required this.opencodePort,
    this.authType = SshAuthType.password,
    this.password = '',
    this.pemKey = '',
    this.lastConnected,
  });

  final String id;
  final String name;
  final String host;
  final int sshPort;
  final String username;
  final int opencodePort;
  final SshAuthType authType;
  final String password;
  final String pemKey;
  final DateTime? lastConnected;

  String get addressLabel => '$username@$host';

  factory ServerConfig.fromStoredJson(
    Map<String, dynamic> json, {
    required String password,
    required String pemKey,
  }) {
    final authTypeRaw = json['authType']?.toString() ?? 'password';
    return ServerConfig(
      id: json['id']?.toString() ?? const Uuid().v4(),
      name: json['name']?.toString() ?? '',
      host: json['host']?.toString() ?? '',
      sshPort: int.tryParse(json['sshPort']?.toString() ?? '') ?? 22,
      username: json['username']?.toString() ?? '',
      opencodePort: int.tryParse(json['opencodePort']?.toString() ?? '') ?? 4096,
      authType: authTypeRaw == 'pemKey' ? SshAuthType.pemKey : SshAuthType.password,
      password: password,
      pemKey: pemKey,
      lastConnected: _parseDate(json['lastConnected']),
    );
  }

  Map<String, dynamic> toStoredJson() {
    return {
      'id': id,
      'name': name,
      'host': host,
      'sshPort': sshPort,
      'username': username,
      'opencodePort': opencodePort,
      'authType': authType == SshAuthType.pemKey ? 'pemKey' : 'password',
      'lastConnected': lastConnected?.toIso8601String(),
    };
  }

  ServerConfig copyWith({
    String? id,
    String? name,
    String? host,
    int? sshPort,
    String? username,
    int? opencodePort,
    SshAuthType? authType,
    String? password,
    String? pemKey,
    DateTime? lastConnected,
  }) {
    return ServerConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      host: host ?? this.host,
      sshPort: sshPort ?? this.sshPort,
      username: username ?? this.username,
      opencodePort: opencodePort ?? this.opencodePort,
      authType: authType ?? this.authType,
      password: password ?? this.password,
      pemKey: pemKey ?? this.pemKey,
      lastConnected: lastConnected ?? this.lastConnected,
    );
  }

  static DateTime? _parseDate(Object? raw) {
    if (raw == null) return null;
    return DateTime.tryParse(raw.toString())?.toLocal();
  }
}

class ServerConfigStore {
  ServerConfigStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  final Uuid _uuid = const Uuid();

  Future<List<ServerConfig>> loadServers() async {
    final raw = await _storage.read(key: _serverListKey);
    if (raw == null || raw.isEmpty) return const <ServerConfig>[];

    final decoded = jsonDecode(raw);
    if (decoded is! List) return const <ServerConfig>[];

    final servers = <ServerConfig>[];
    for (final entry in decoded) {
      if (entry is! Map) continue;
      final map = Map<String, dynamic>.from(entry);
      final id = map['id']?.toString();
      if (id == null || id.isEmpty) continue;
      final password = await _storage.read(key: _passwordKey(id)) ?? '';
      final pemKey = await _storage.read(key: _pemKey(id)) ?? '';
      servers.add(ServerConfig.fromStoredJson(map, password: password, pemKey: pemKey));
    }

    servers.sort((left, right) {
      final leftTime = left.lastConnected;
      final rightTime = right.lastConnected;
      if (leftTime == null && rightTime == null) return left.name.compareTo(right.name);
      if (leftTime == null) return 1;
      if (rightTime == null) return -1;
      return rightTime.compareTo(leftTime);
    });

    return servers;
  }

  Future<ServerConfig?> getServer(String id) async {
    final servers = await loadServers();
    for (final server in servers) {
      if (server.id == id) return server;
    }
    return null;
  }

  Future<ServerConfig> saveServer(ServerConfig config) async {
    final servers = await loadServers();
    final resolved = config.id.isEmpty ? config.copyWith(id: _uuid.v4()) : config;
    final updated = <ServerConfig>[];
    var replaced = false;

    for (final server in servers) {
      if (server.id == resolved.id) {
        updated.add(resolved);
        replaced = true;
      } else {
        updated.add(server);
      }
    }
    if (!replaced) updated.add(resolved);

    await _storage.write(
      key: _serverListKey,
      value: jsonEncode(updated.map((s) => s.toStoredJson()).toList()),
    );
    await _storage.write(key: _passwordKey(resolved.id), value: resolved.password);
    await _storage.write(key: _pemKey(resolved.id), value: resolved.pemKey);

    return resolved;
  }

  Future<void> deleteServer(String id) async {
    final servers = await loadServers();
    final updated = servers.where((s) => s.id != id).toList();
    await _storage.write(
      key: _serverListKey,
      value: jsonEncode(updated.map((s) => s.toStoredJson()).toList()),
    );
    await _storage.delete(key: _passwordKey(id));
    await _storage.delete(key: _pemKey(id));
  }

  Future<void> updateLastConnected(String id) async {
    final server = await getServer(id);
    if (server == null) return;
    await saveServer(server.copyWith(lastConnected: DateTime.now()));
  }

  String _passwordKey(String serverId) => 'password_$serverId';
  String _pemKey(String serverId) => 'pem_$serverId';
}

final serverConfigStoreProvider = Provider<ServerConfigStore>((ref) {
  return ServerConfigStore();
});
