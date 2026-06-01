import 'dart:convert';

import 'package:code_app/core/api/models/message.dart';
import 'package:code_app/core/api/models/session.dart';

enum OpencodeEventType {
  sessionUpdated,
  messageUpdated,   // 实际事件名：message.updated（不是 session.message）
  toolCalled,       // 实际事件名：session.next.tool.called（不是 tool.execution）
  permissionAsked,  // 实际事件名：permission.asked（不是 permission.requested）
  sessionError,
  unknown;

  static OpencodeEventType fromName(String name) {
    return switch (name) {
      'session.updated' => OpencodeEventType.sessionUpdated,
      'message.updated' => OpencodeEventType.messageUpdated,
      'session.next.tool.called' => OpencodeEventType.toolCalled,
      'permission.asked' => OpencodeEventType.permissionAsked,
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

    // 实际字段：sessionID（大写D），info（而不是 session/message）
    final sessionIdStr = properties['sessionID']?.toString() ??
        properties['sessionId']?.toString() ??
        properties['session_id']?.toString();

    // session.updated 和 message.updated 都把对象放在 properties['info']
    final infoJson = properties['info'];

    OpencodeSession? session;
    OpencodeMessage? message;

    if (rawType == 'session.updated' && infoJson is Map) {
      session = OpencodeSession.fromJson(Map<String, dynamic>.from(infoJson));
    } else if (rawType == 'message.updated' && infoJson is Map) {
      message = OpencodeMessage.fromJson(Map<String, dynamic>.from(infoJson));
    }

    // tool.called 事件：properties 直接含 tool、input
    final toolName = properties['tool']?.toString() ?? inner['tool']?.toString();
    final inputMap = properties['input'] is Map
        ? Map<String, dynamic>.from(properties['input'] as Map)
        : null;

    return OpencodeEvent(
      type: OpencodeEventType.fromName(rawType),
      rawType: rawType,
      payload: inner,
      session: session,
      message: message,
      tool: toolName,
      input: inputMap,
      output: properties['output']?.toString() ?? inner['output']?.toString(),
      // permission.asked 事件：properties['id'] 是权限 ID
      permissionId: properties['id']?.toString() ?? inner['id']?.toString(),
      sessionId: sessionIdStr ??
          (message?.sessionId) ??
          (session?.id),
      title: properties['title']?.toString() ?? inner['title']?.toString(),
      command: properties['command']?.toString() ?? inner['command']?.toString(),
      error: properties['error']?.toString() ?? inner['error']?.toString(),
    );
  }
}
