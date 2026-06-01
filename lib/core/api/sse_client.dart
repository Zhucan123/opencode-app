import 'dart:async';
import 'dart:convert';

import 'package:code_app/core/api/models/event.dart';
import 'package:dio/dio.dart';

class SseClient {
  SseClient({required Dio dio}) : _dio = dio;

  final Dio _dio;
  final CancelToken _cancelToken = CancelToken();
  Stream<OpencodeEvent>? _events;

  Stream<OpencodeEvent> get events {
    _events ??= _buildEventStream().asBroadcastStream();
    return _events!;
  }

  Stream<OpencodeEvent> _buildEventStream() async* {
    final response = await _dio.get<ResponseBody>(
      '/event',
      options: Options(
        responseType: ResponseType.stream,
        headers: const {'Accept': 'text/event-stream'},
      ),
      cancelToken: _cancelToken,
    );

    final body = response.data;
    if (body == null) {
      return;
    }

    String currentEvent = 'message';
    final dataLines = <String>[];

    void resetFrame() {
      currentEvent = 'message';
      dataLines.clear();
    }

    OpencodeEvent? parseFrame() {
      if (dataLines.isEmpty) {
        return null;
      }

      final payload = dataLines.join('\n');
      return OpencodeEvent.fromSse(eventName: currentEvent, data: payload);
    }

    await for (final line in body.stream
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      if (line.isEmpty) {
        final event = parseFrame();
        if (event != null) {
          yield event;
        }
        resetFrame();
        continue;
      }

      if (line.startsWith(':')) {
        continue;
      }

      if (line.startsWith('event:')) {
        currentEvent = line.substring(6).trimLeft();
        continue;
      }

      if (line.startsWith('data:')) {
        dataLines.add(line.substring(5).trimLeft());
      }
    }

    final lastEvent = parseFrame();
    if (lastEvent != null) {
      yield lastEvent;
    }
  }

  void dispose() {
    if (!_cancelToken.isCancelled) {
      _cancelToken.cancel('SSE closed');
    }
  }
}
