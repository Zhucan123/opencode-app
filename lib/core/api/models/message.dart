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
  patch,
  toolCall,
  toolResult,
  stepStart,
  stepFinish,
  reasoning,
  image,
  unknown;

  static MessagePartType fromJson(Object? value) {
    return switch (value?.toString()) {
      'text' => MessagePartType.text,
      'markdown' => MessagePartType.markdown,
      'code' => MessagePartType.code,
      'patch' => MessagePartType.patch,
      'tool' || 'tool_call' || 'toolCall' => MessagePartType.toolCall,
      'tool_result' || 'toolResult' => MessagePartType.toolResult,
      'step-start' => MessagePartType.stepStart,
      'step-finish' => MessagePartType.stepFinish,
      'reasoning' || 'thought' => MessagePartType.reasoning,
      'image' || 'image_url' => MessagePartType.image,
      _ => MessagePartType.unknown,
    };
  }
}

class MessagePart {
  const MessagePart({
    required this.type,
    required this.text,
    this.language,
    this.rawJson,
  });

  final MessagePartType type;
  final String text;
  final String? language;
  final Map<String, dynamic>? rawJson;

  String? get imageUrl {
    if (type != MessagePartType.image || rawJson == null) return null;
    
    // {"type": "file", "url": "data:image/jpeg;base64,..."}
    if (rawJson!['type'] == 'file' && rawJson!['url'] != null) {
      return rawJson!['url'].toString();
    }
    
    // {"type": "image_url", "image_url": {"url": "..."}}
    if (rawJson!['image_url'] is Map && rawJson!['image_url']['url'] != null) {
      return rawJson!['image_url']['url'].toString();
    }
    
    // {"type": "image", "source": {"type": "base64", "media_type": "...", "data": "..."}}
    if (rawJson!['source'] is Map && rawJson!['source']['data'] != null) {
      final mediaType = rawJson!['source']['media_type'] ?? 'image/jpeg';
      final base64Data = rawJson!['source']['data'];
      return 'data:$mediaType;base64,$base64Data';
    }
    
    return null;
  }

  factory MessagePart.fromJson(Object? raw) {
    if (raw is String) {
      return MessagePart(type: MessagePartType.text, text: raw);
    }

    final json = raw is Map<String, dynamic> ? raw : <String, dynamic>{};
    var parsedType = MessagePartType.fromJson(json['type']);
    if (json['type'] == 'file' && json['mime']?.toString().startsWith('image/') == true) {
      parsedType = MessagePartType.image;
    }

    return MessagePart(
      type: parsedType,
      text: json['text']?.toString() ?? json['content']?.toString() ?? '',
      language: json['language']?.toString(),
      rawJson: json,
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

class FileDiff {
  const FileDiff({
    required this.file,
    required this.before,
    required this.after,
    required this.additions,
    required this.deletions,
  });

  final String file;
  final String before;
  final String after;
  final int additions;
  final int deletions;

  factory FileDiff.fromJson(Map<String, dynamic> json) {
    return FileDiff(
      file: json['file']?.toString() ?? '',
      before: json['before']?.toString() ?? '',
      after: json['after']?.toString() ?? '',
      additions: json['additions'] as int? ?? 0,
      deletions: json['deletions'] as int? ?? 0,
    );
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
