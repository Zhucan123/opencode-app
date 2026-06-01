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
                receiveTimeout: const Duration(seconds: 30),
                sendTimeout: const Duration(seconds: 10),
                responseType: ResponseType.json,
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
        .toList()
      ..sort((left, right) {
        final rightTime = right.updatedAt ?? right.createdAt;
        final leftTime = left.updatedAt ?? left.createdAt;
        if (rightTime == null && leftTime == null) {
          return 0;
        }
        if (rightTime == null) {
          return -1;
        }
        if (leftTime == null) {
          return 1;
        }
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

  Future<List<OpencodeMessage>> getMessages(String sessionId) async {
    final response = await _dio.get<List<dynamic>>('/session/$sessionId/message');
    final payload = response.data ?? const <dynamic>[];
    return payload
        .whereType<Map>()
        .map((item) => OpencodeMessage.fromJson(Map<String, dynamic>.from(item)))
        .toList();
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
