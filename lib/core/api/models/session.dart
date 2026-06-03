class OpencodeSession {
  const OpencodeSession({
    required this.id,
    required this.title,
    this.parentId,
    this.createdAt,
    this.updatedAt,
    this.preview,
    this.state,
    this.agent,
    this.modelId,
    this.cost,
    this.totalTokens,
  });

  final String id;
  final String title;
  final String? parentId; // 子 agent 会话有此字段，主会话为 null
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? preview;
  final String? state;
  final String? agent;
  final String? modelId;
  final double? cost;
  final int? totalTokens;

  bool get isSubAgent => parentId != null && parentId!.isNotEmpty;

  factory OpencodeSession.fromJson(Map<String, dynamic> json) {
    String? modelId;
    if (json['model'] is Map) {
      modelId = json['model']['id']?.toString();
    } else if (json['model'] is String) {
      modelId = json['model'].toString();
    }

    final timeJson = json['time'] is Map ? json['time'] : null;
    final rawCreated = timeJson?['created'] ?? json['createdAt'] ?? json['created_at'];
    final rawUpdated = timeJson?['updated'] ?? json['updatedAt'] ?? json['updated_at'];

    int? totalTokens;
    if (json['tokens'] is Map) {
      final t = json['tokens'] as Map;
      final input = (t['input'] as num?)?.toInt() ?? 0;
      final output = (t['output'] as num?)?.toInt() ?? 0;
      final reasoning = (t['reasoning'] as num?)?.toInt() ?? 0;
      totalTokens = input + output + reasoning;
    }

    return OpencodeSession(
      id: json['id']?.toString() ?? '',
      title: (json['title']?.toString().trim().isNotEmpty ?? false)
          ? json['title'].toString().trim()
          : 'Untitled Session',
      parentId: json['parentID']?.toString() ?? json['parentId']?.toString(),
      createdAt: _parseDate(rawCreated),
      updatedAt: _parseDate(rawUpdated),
      preview: json['preview']?.toString() ??
          json['lastMessagePreview']?.toString() ??
          json['last_message_preview']?.toString(),
      state: json['state']?.toString(),
      agent: json['agent']?.toString(),
      modelId: modelId,
      cost: (json['cost'] as num?)?.toDouble(),
      totalTokens: totalTokens,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'createdAt': createdAt?.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
      'preview': preview,
      'state': state,
      'cost': cost,
      'totalTokens': totalTokens,
    };
  }

  static DateTime? _parseDate(Object? raw) {
    if (raw == null) {
      return null;
    }
    
    if (raw is num) {
      return DateTime.fromMillisecondsSinceEpoch(raw.toInt()).toLocal();
    }

    return DateTime.tryParse(raw.toString())?.toLocal();
  }
}
