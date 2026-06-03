import 'package:code_app/core/api/models/message.dart';
import 'package:code_app/core/api/models/session.dart';
import 'package:dio/dio.dart';

class OpencodeClient {
  OpencodeClient({
    Dio? dio,
    this.host = '127.0.0.1',
    this.port = 14096,
  }) : _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: 'http://$host:$port',
                connectTimeout: const Duration(seconds: 10),
                receiveTimeout: const Duration(seconds: 120),
                sendTimeout: const Duration(seconds: 10),
                responseType: ResponseType.json,
                // SSH 隧道每次 forwardLocal 是独立 channel，不支持 keep-alive 复用
                // 强制 Connection: close 确保每次请求用新 TCP 连接
                headers: const {'Connection': 'close'},
              ),
            );

  final Dio _dio;
  final String host;
  final int port;

  Dio get dio => _dio;

  Future<List<OpencodeSession>> getSessions() async {
    final response = await _dio.get<List<dynamic>>('/session');
    final payload = response.data ?? const <dynamic>[];
    return payload
        .whereType<Map>()
        .map((item) => OpencodeSession.fromJson(Map<String, dynamic>.from(item)))
        .where((s) => !s.isSubAgent) // 过滤掉子 agent 会话（有 parentID 的）
        .toList()
      ..sort((left, right) {
        final rightTime = right.updatedAt ?? right.createdAt;
        final leftTime = left.updatedAt ?? left.createdAt;
        if (rightTime == null && leftTime == null) return 0;
        if (rightTime == null) return -1;
        if (leftTime == null) return 1;
        return rightTime.compareTo(leftTime);
      });
  }

  Future<OpencodeSession> createSession({String? title}) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/session',
      data: title == null || title.trim().isEmpty ? const {} : {'title': title.trim()},
    );
    return OpencodeSession.fromJson(response.data ?? const <String, dynamic>{});
  }

  Future<void> deleteSession(String sessionId) async {
    await _dio.delete<void>('/session/$sessionId');
  }

  /// 加载历史消息，最多返回 [limit] 条（取最新的）
  Future<List<OpencodeMessage>> getMessages(String sessionId, {int limit = 20}) async {
    final response = await _dio.get<List<dynamic>>('/session/$sessionId/message');
    final payload = response.data ?? const <dynamic>[];
    final all = payload
        .whereType<Map>()
        .map((item) {
          final map = Map<String, dynamic>.from(item);
          // 新格式：{ info: {...}, parts: [...] }
          if (map.containsKey('info') && map['info'] is Map) {
            final info = Map<String, dynamic>.from(map['info'] as Map);
            info['parts'] = map['parts'];
            return OpencodeMessage.fromJson(info);
          }
          // 旧格式：直接是 Message 对象
          return OpencodeMessage.fromJson(map);
        })
        .toList();
    // 只保留 user / assistant 消息，过滤 system / tool 等弹窗通知类消息
    final visible = all
        .where((m) => m.role == MessageRole.user || m.role == MessageRole.assistant)
        .toList();
    if (visible.length > limit) {
      return visible.sublist(visible.length - limit);
    }
    return visible;
  }

  Future<void> sendPrompt(String sessionId, String text,
      {String? mode, String? modelId, String? providerId, List<Map<String, dynamic>>? extraParts}) async {
    final parts = <Map<String, dynamic>>[];
    if (text.isNotEmpty) {
      parts.add({'type': 'text', 'text': text});
    }
    if (extraParts != null) {
      parts.addAll(extraParts);
    }
    
    final data = <String, dynamic>{
      'parts': parts,
    };
    if (mode != null && mode.isNotEmpty) data['agent'] = mode;
    // model 必须嵌套在 model 对象里，不能放顶层
    if (modelId != null && modelId.isNotEmpty &&
        providerId != null && providerId.isNotEmpty) {
      data['model'] = {'modelID': modelId, 'providerID': providerId};
    }
    await _dio.post<void>('/session/$sessionId/prompt_async', data: data);
  }

  /// 获取可用主模式列表（过滤掉 subagent 和 hidden agent）
  Future<List<String>> getModes() async {
    try {
      final response = await _dio.get<List<dynamic>>('/agent');
      final payload = response.data ?? const <dynamic>[];
      return payload
          .whereType<Map>()
          .where((m) {
            final mode = m['mode']?.toString() ?? '';
            final hidden = m['hidden'] as bool? ?? false;
            // 只展示 primary/all 且非隐藏的 agent
            return (mode == 'primary' || mode == 'all') && !hidden;
          })
          .map((m) => m['name']?.toString() ?? '')
          .where((name) => name.isNotEmpty)
          .toList();
    } catch (_) {
      return const ['build', 'plan'];
    }
  }

  /// 获取可用模型列表（尝试新旧两个路径）
  Future<List<OpencodeModel>> getModels() async {
    for (final path in ['/api/model', '/model']) {
      try {
        final response = await _dio.get<List<dynamic>>(path);
        final payload = response.data ?? const <dynamic>[];
        if (payload.isEmpty) continue;
        final models = payload
            .whereType<Map>()
            .map((m) => OpencodeModel.fromJson(Map<String, dynamic>.from(m)))
            .where((m) => m.enabled && m.id.isNotEmpty)
            .toList();
        if (models.isNotEmpty) return models;
      } catch (_) {
        continue;
      }
    }
    return const [];
  }

  Future<void> respondToPermission(String sessionId, String permissionId, bool allow, {bool permanent = false}) async {
    final decision = allow ? 'allow' : 'deny';
    await _dio.post<void>(
      '/session/$sessionId/permissions/$permissionId',
      data: {'decision': decision, 'permanent': permanent},
    );
  }

  Future<void> abort(String sessionId) async {
    await _dio.post<void>('/session/$sessionId/abort');
  }

  Future<void> revert(String sessionId) async {
    await _dio.post<void>('/session/$sessionId/revert');
  }

  Future<List<FileDiff>> getSessionDiff(String sessionId, {String? messageId}) async {
    final queryParams = messageId != null ? {'messageID': messageId} : null;
    final response = await _dio.get<List<dynamic>>(
      '/session/$sessionId/diff',
      queryParameters: queryParams,
    );
    final payload = response.data ?? const <dynamic>[];
    return payload
        .whereType<Map>()
        .map((item) => FileDiff.fromJson(Map<String, dynamic>.from(item)))
        .where((d) => d.file.isNotEmpty)
        .toList();
  }

  void dispose() {
    _dio.close(force: true);
  }
}

class OpencodeModel {
  const OpencodeModel({
    required this.id,
    required this.name,
    required this.providerId,
    required this.enabled,
  });

  final String id;
  final String name;
  final String providerId;
  final bool enabled;

  String get displayName => name.isNotEmpty ? name : id;

  factory OpencodeModel.fromJson(Map<String, dynamic> json) {
    return OpencodeModel(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      providerId: json['providerID']?.toString() ?? '',
      enabled: json['enabled'] as bool? ?? true,
    );
  }
}
