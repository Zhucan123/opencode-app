enum MessageRole {
  user,
  assistant,
  system,
  tool,
  unknown;

  static MessageRole fromJson(Object? value) {
    return switch (value?.toString()) {
      'user' => MessageRole.user,
      'assistant' => MessageRole.assistant,
      'system' => MessageRole.system,
      'tool' => MessageRole.tool,
      _ => MessageRole.unknown,
    };
  }
}

enum MessagePartType {
  text,
  markdown,
  code,
  unknown;

  static MessagePartType fromJson(Object? value) {
    return switch (value?.toString()) {
      'text' => MessagePartType.text,
      'markdown' => MessagePartType.markdown,
      'code' => MessagePartType.code,
      _ => MessagePartType.unknown,
    };
  }
}

class MessagePart {
  const MessagePart({
    required this.type,
    required this.text,
    this.language,
  });

  final MessagePartType type;
  final String text;
  final String? language;

  factory MessagePart.fromJson(Object? raw) {
    if (raw is String) {
      return MessagePart(type: MessagePartType.text, text: raw);
    }

    final json = raw is Map<String, dynamic> ? raw : <String, dynamic>{};
    return MessagePart(
      type: MessagePartType.fromJson(json['type']),
      text: json['text']?.toString() ?? json['content']?.toString() ?? '',
      language: json['language']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type.name,
      'text': text,
      'language': language,
    };
  }
}

class OpencodeMessage {
  const OpencodeMessage({
    required this.id,
    required this.role,
    required this.parts,
    this.sessionId,
    this.createdAt,
  });

  final String id;
  final String? sessionId;
  final MessageRole role;
  final List<MessagePart> parts;
  final DateTime? createdAt;

  String get plainText => parts.map((part) => part.text).join('\n').trim();

  factory OpencodeMessage.fromJson(Map<String, dynamic> json) {
    final rawParts = json['parts'];
    final partList = rawParts is List
        ? rawParts.map(MessagePart.fromJson).toList()
        : <MessagePart>[];

    return OpencodeMessage(
      id: json['id']?.toString() ?? '',
      sessionId: json['sessionId']?.toString() ?? json['session_id']?.toString(),
      role: MessageRole.fromJson(json['role']),
      parts: partList,
      createdAt: _parseDate(json['createdAt'] ?? json['created_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sessionId': sessionId,
      'role': role.name,
      'parts': parts.map((part) => part.toJson()).toList(),
      'createdAt': createdAt?.toIso8601String(),
    };
  }

  OpencodeMessage copyWith({
    String? id,
    String? sessionId,
    MessageRole? role,
    List<MessagePart>? parts,
    DateTime? createdAt,
  }) {
    return OpencodeMessage(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      role: role ?? this.role,
      parts: parts ?? this.parts,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  static DateTime? _parseDate(Object? raw) {
    if (raw == null) {
      return null;
    }

    return DateTime.tryParse(raw.toString())?.toLocal();
  }
}
