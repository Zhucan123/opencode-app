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
  Future<List<OpencodeMessage>> getMessages(String sessionId, {int limit = 50}) async {
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
    // 取最新的 limit 条，避免超长会话卡顿
    if (all.length > limit) {
      return all.sublist(all.length - limit);
    }
    return all;
  }

  Future<void> sendPrompt(String sessionId, String text) async {
    await _dio.post<void>(
      '/session/$sessionId/prompt_async',
      data: {
        'parts': [
          {
            'type': 'text',
            'text': text,
          },
        ],
      },
    );
  }

  Future<void> abort(String sessionId) async {
    await _dio.post<void>('/session/$sessionId/abort');
  }

  void dispose() {
    _dio.close(force: true);
  }
}
