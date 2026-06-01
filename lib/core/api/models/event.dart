import 'dart:convert';

import 'package:code_app/core/api/models/message.dart';
import 'package:code_app/core/api/models/session.dart';

enum OpencodeEventType {
  sessionUpdated,
  sessionMessage,
  toolExecution,
  permissionRequested,
  sessionError,
  unknown;

  static OpencodeEventType fromName(String name) {
    return switch (name) {
      'session.updated' => OpencodeEventType.sessionUpdated,
      'session.message' => OpencodeEventType.sessionMessage,
      'tool.execution' => OpencodeEventType.toolExecution,
      'permission.requested' => OpencodeEventType.permissionRequested,
      'session.error' => OpencodeEventType.sessionError,
      _ => OpencodeEventType.unknown,
    };
  }
}

class OpencodeEvent {
  const OpencodeEvent({
    required this.type,
    required this.rawType,
    required this.payload,
    this.session,
    this.message,
    this.tool,
    this.input,
    this.output,
    this.permissionId,
    this.sessionId,
    this.title,
    this.command,
    this.error,
  });

  final OpencodeEventType type;
  final String rawType;
  final Map<String, dynamic> payload;
  final OpencodeSession? session;
  final OpencodeMessage? message;
  final String? tool;
  final Map<String, dynamic>? input;
  final String? output;
  final String? permissionId;
  final String? sessionId;
  final String? title;
  final String? command;
  final String? error;

  factory OpencodeEvent.fromSse({required String eventName, required String data}) {
    Map<String, dynamic> payload;
    try {
      final decoded = jsonDecode(data);
      payload = decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : <String, dynamic>{'value': decoded};
    } catch (_) {
      payload = <String, dynamic>{'raw': data};
    }

    final rawType = payload['type']?.toString() ?? eventName;
    final sessionJson = payload['session'];
    final messageJson = payload['message'];

    return OpencodeEvent(
      type: OpencodeEventType.fromName(rawType),
      rawType: rawType,
      payload: payload,
      session: sessionJson is Map
          ? OpencodeSession.fromJson(Map<String, dynamic>.from(sessionJson))
          : null,
      message: messageJson is Map
          ? OpencodeMessage.fromJson(Map<String, dynamic>.from(messageJson))
          : null,
      tool: payload['tool']?.toString(),
      input: payload['input'] is Map
          ? Map<String, dynamic>.from(payload['input'] as Map)
          : null,
      output: payload['output']?.toString(),
      permissionId: payload['id']?.toString(),
      sessionId: payload['sessionId']?.toString() ??
          payload['session_id']?.toString() ??
          (messageJson is Map
              ? messageJson['sessionId']?.toString() ??
                  messageJson['session_id']?.toString()
              : null) ??
          (sessionJson is Map
              ? sessionJson['id']?.toString()
              : null),
      title: payload['title']?.toString(),
      command: payload['command']?.toString(),
      error: payload['error']?.toString(),
    );
  }
}
