import 'dart:async';
import 'dart:convert';

import 'package:code_app/core/api/models/event.dart';
import 'package:dio/dio.dart';

class SseClient {
  SseClient({required Dio dio}) : _dio = dio;

  final Dio _dio;
  CancelToken _cancelToken = CancelToken();
  StreamController<OpencodeEvent>? _controller;

  Stream<OpencodeEvent> get events {
    if (_controller == null || _controller!.isClosed) {
      _controller = StreamController<OpencodeEvent>.broadcast();
      _listenLoop();
    }
    return _controller!.stream;
  }

  Future<void> _listenLoop() async {
    var retryDelay = const Duration(seconds: 2);

    while (true) {
      if (_cancelToken.isCancelled) return;
      if (_controller == null || _controller!.isClosed) return;

      try {
        await _connectAndStream();
        // 正常结束后立即重连，重置退避
        retryDelay = const Duration(seconds: 2);
      } on DioException catch (e) {
        if (_cancelToken.isCancelled) return;
        if (e.type == DioExceptionType.cancel) return;
        // 网络错误，等待后重试
        await Future<void>.delayed(retryDelay);
        retryDelay = Duration(seconds: (retryDelay.inSeconds * 2).clamp(2, 30));
      } catch (_) {
        if (_cancelToken.isCancelled) return;
        await Future<void>.delayed(retryDelay);
        retryDelay = Duration(seconds: (retryDelay.inSeconds * 2).clamp(2, 30));
      }
    }
  }

  Future<void> _connectAndStream() async {
    final response = await _dio.get<ResponseBody>(
      '/global/event',
      options: Options(
        responseType: ResponseType.stream,
        receiveTimeout: Duration.zero, // SSE 长连接，不设超时
        headers: const {'Accept': 'text/event-stream'},
      ),
      cancelToken: _cancelToken,
    );

    final body = response.data;
    if (body == null) return;

    String currentEvent = 'message';
    final dataLines = <String>[];

    void resetFrame() {
      currentEvent = 'message';
      dataLines.clear();
    }

    OpencodeEvent? parseFrame() {
      if (dataLines.isEmpty) return null;
      return OpencodeEvent.fromSse(
        eventName: currentEvent,
        data: dataLines.join('\n'),
      );
    }

    await for (final line in body.stream
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      if (_cancelToken.isCancelled) return;

      if (line.isEmpty) {
        final event = parseFrame();
        if (event != null && !(_controller?.isClosed ?? true)) {
          _controller!.add(event);
        }
        resetFrame();
        continue;
      }

      if (line.startsWith(':')) continue; // 心跳注释，忽略

      if (line.startsWith('event:')) {
        currentEvent = line.substring(6).trimLeft();
        continue;
      }

      if (line.startsWith('data:')) {
        dataLines.add(line.substring(5).trimLeft());
      }
    }

    final lastEvent = parseFrame();
    if (lastEvent != null && !(_controller?.isClosed ?? true)) {
      _controller!.add(lastEvent);
    }
  }

  void dispose() {
    if (!_cancelToken.isCancelled) {
      _cancelToken.cancel('SSE closed');
    }
    _controller?.close();
  }
}
