class OpencodeSession {
  const OpencodeSession({
    required this.id,
    required this.title,
    this.parentId,
    this.createdAt,
    this.updatedAt,
    this.preview,
  });

  final String id;
  final String title;
  final String? parentId; // 子 agent 会话有此字段，主会话为 null
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? preview;

  bool get isSubAgent => parentId != null && parentId!.isNotEmpty;

  factory OpencodeSession.fromJson(Map<String, dynamic> json) {
    return OpencodeSession(
      id: json['id']?.toString() ?? '',
      title: (json['title']?.toString().trim().isNotEmpty ?? false)
          ? json['title'].toString().trim()
          : 'Untitled Session',
      parentId: json['parentID']?.toString() ?? json['parentId']?.toString(),
      createdAt: _parseDate(json['createdAt'] ?? json['created_at']),
      updatedAt: _parseDate(json['updatedAt'] ?? json['updated_at']),
      preview: json['preview']?.toString() ??
          json['lastMessagePreview']?.toString() ??
          json['last_message_preview']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'createdAt': createdAt?.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
      'preview': preview,
    };
  }

  static DateTime? _parseDate(Object? raw) {
    if (raw == null) {
      return null;
    }

    return DateTime.tryParse(raw.toString())?.toLocal();
  }
}
