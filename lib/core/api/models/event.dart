import 'dart:convert';

import 'package:code_app/core/api/models/message.dart';
import 'package:code_app/core/api/models/session.dart';

enum OpencodeEventType {
  sessionUpdated,
  messageUpdated,
  messagePartUpdated,
  messagePartDelta,
  messagePartRemoved,
  toolCalled,
  permissionAsked,
  sessionError,
  sessionStatus,
  unknown;

  static OpencodeEventType fromName(String name) {
    return switch (name) {
      'session.updated' => OpencodeEventType.sessionUpdated,
      'session.status' => OpencodeEventType.sessionStatus,
      'message.updated' => OpencodeEventType.messageUpdated,
      'message.part.updated' => OpencodeEventType.messagePartUpdated,
      'message.part.delta' => OpencodeEventType.messagePartDelta,
      'message.part.removed' => OpencodeEventType.messagePartRemoved,
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
    this.part,
    this.partDelta,
    this.removedPartId,
    this.tool,
    this.input,
    this.output,
    this.permissionId,
    this.sessionId,
    this.title,
    this.command,
    this.error,
    this.sessionStatusType,
  });

  final OpencodeEventType type;
  final String rawType;
  final Map<String, dynamic> payload;
  final OpencodeSession? session;
  final OpencodeMessage? message;
  final MessagePartEvent? part;
  final MessagePartDelta? partDelta;
  final String? removedPartId;
  final String? tool;
  final Map<String, dynamic>? input;
  final String? output;
  final String? permissionId;
  final String? sessionId;
  final String? title;
  final String? command;
  final String? error;
  final String? sessionStatusType;

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

    final inner = outer['payload'] is Map
        ? Map<String, dynamic>.from(outer['payload'] as Map)
        : outer;

    final rawType = inner['type']?.toString() ?? eventName;
    final properties = inner['properties'] is Map
        ? Map<String, dynamic>.from(inner['properties'] as Map)
        : <String, dynamic>{};

    final sessionIdStr = properties['sessionID']?.toString() ??
        properties['sessionId']?.toString() ??
        properties['session_id']?.toString();

    final infoJson = properties['info'];
    OpencodeSession? session;
    OpencodeMessage? message;
    if (rawType == 'session.updated' && infoJson is Map) {
      session = OpencodeSession.fromJson(Map<String, dynamic>.from(infoJson));
    } else if (rawType == 'message.updated' && infoJson is Map) {
      message = OpencodeMessage.fromJson(Map<String, dynamic>.from(infoJson));
    }

    MessagePartEvent? part;
    if (rawType == 'message.part.updated' && properties['part'] is Map) {
      part = MessagePartEvent.fromJson(
          Map<String, dynamic>.from(properties['part'] as Map));
    }

    MessagePartDelta? partDelta;
    if (rawType == 'message.part.delta') {
      partDelta = MessagePartDelta(
        sessionId: sessionIdStr ?? '',
        messageId: properties['messageID']?.toString() ?? '',
        partId: properties['partID']?.toString() ?? '',
        field: properties['field']?.toString() ?? 'text',
        delta: properties['delta']?.toString() ?? '',
      );
    }

    final removedPartId = rawType == 'message.part.removed'
        ? properties['partID']?.toString()
        : null;

    String? sessionStatusType;
    if (rawType == 'session.status' && properties['status'] is Map) {
      sessionStatusType = properties['status']['type']?.toString();
    }

    return OpencodeEvent(
      type: OpencodeEventType.fromName(rawType),
      rawType: rawType,
      payload: inner,
      session: session,
      message: message,
      part: part,
      partDelta: partDelta,
      removedPartId: removedPartId,
      tool: properties['tool']?.toString() ?? inner['tool']?.toString(),
      input: properties['input'] is Map
          ? Map<String, dynamic>.from(properties['input'] as Map)
          : null,
      output: properties['output']?.toString() ?? inner['output']?.toString(),
      permissionId: properties['id']?.toString() ?? inner['id']?.toString(),
      sessionId: sessionIdStr ??
          part?.sessionId ??
          partDelta?.sessionId ??
          message?.sessionId ??
          session?.id,
      title: properties['title']?.toString() ?? inner['title']?.toString(),
      command: properties['command']?.toString() ?? inner['command']?.toString(),
      error: properties['error']?.toString() ?? inner['error']?.toString(),
      sessionStatusType: sessionStatusType,
    );
  }
}

class MessagePartEvent {
  const MessagePartEvent({
    required this.id,
    required this.messageId,
    required this.sessionId,
    required this.type,
    this.text,
  });

  final String id;
  final String messageId;
  final String sessionId;
  final String type;
  final String? text;

  factory MessagePartEvent.fromJson(Map<String, dynamic> json) {
    return MessagePartEvent(
      id: json['id']?.toString() ?? '',
      messageId: json['messageID']?.toString() ??
          json['messageId']?.toString() ?? '',
      sessionId: json['sessionID']?.toString() ??
          json['sessionId']?.toString() ?? '',
      type: json['type']?.toString() ?? 'text',
      text: json['text']?.toString(),
    );
  }

  bool get isSkippable =>
      type == 'patch' || type == 'step-start' || type == 'step-finish';

  MessagePart toMessagePart() =>
      MessagePart(type: MessagePartType.text, text: text ?? '');
}

class MessagePartDelta {
  const MessagePartDelta({
    required this.sessionId,
    required this.messageId,
    required this.partId,
    required this.field,
    required this.delta,
  });

  final String sessionId;
  final String messageId;
  final String partId;
  final String field;
  final String delta;
}
