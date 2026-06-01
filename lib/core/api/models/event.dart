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
    Map<String, dynamic> outer;
    try {
      final decoded = jsonDecode(data);
      outer = decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : <String, dynamic>{'value': decoded};
    } catch (_) {
      outer = <String, dynamic>{'raw': data};
    }

    // 实际格式：{ "payload": { "id": "...", "type": "...", "properties": {...} } }
    final inner = outer['payload'] is Map
        ? Map<String, dynamic>.from(outer['payload'] as Map)
        : outer;

    final rawType = inner['type']?.toString() ?? eventName;
    final properties = inner['properties'] is Map
        ? Map<String, dynamic>.from(inner['properties'] as Map)
        : <String, dynamic>{};

    final sessionJson = properties['session'] ?? inner['session'];
    final messageJson = properties['message'] ?? inner['message'];

    return OpencodeEvent(
      type: OpencodeEventType.fromName(rawType),
      rawType: rawType,
      payload: inner,
      session: sessionJson is Map
          ? OpencodeSession.fromJson(Map<String, dynamic>.from(sessionJson))
          : null,
      message: messageJson is Map
          ? OpencodeMessage.fromJson(Map<String, dynamic>.from(messageJson))
          : null,
      tool: properties['tool']?.toString() ?? inner['tool']?.toString(),
      input: properties['input'] is Map
          ? Map<String, dynamic>.from(properties['input'] as Map)
          : null,
      output: properties['output']?.toString() ?? inner['output']?.toString(),
      permissionId: properties['id']?.toString() ?? inner['id']?.toString(),
      sessionId: properties['sessionId']?.toString() ??
          properties['session_id']?.toString() ??
          (messageJson is Map
              ? messageJson['sessionId']?.toString() ??
                  messageJson['session_id']?.toString()
              : null) ??
          (sessionJson is Map ? sessionJson['id']?.toString() : null),
      title: properties['title']?.toString() ?? inner['title']?.toString(),
      command: properties['command']?.toString() ?? inner['command']?.toString(),
      error: properties['error']?.toString() ?? inner['error']?.toString(),
    );
  }
}
