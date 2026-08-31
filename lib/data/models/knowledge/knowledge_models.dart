import '../recipe/prompt_recipe.dart';

/// User-facing semantic retrieval request.
class KnowledgeQuery {
  const KnowledgeQuery({
    required this.text,
    this.limit = 120,
    this.includeRelated = true,
  });

  final String text;
  final int limit;
  final bool includeRelated;

  KnowledgeQuery normalized() => KnowledgeQuery(
    text: text.trim(),
    limit: limit.clamp(1, 300),
    includeRelated: includeRelated,
  );
}

/// A normalized candidate shared by local and remote Knowledge providers.
class KnowledgeCandidate {
  const KnowledgeCandidate({
    required this.tag,
    required this.category,
    this.zh,
    this.postCount = 0,
    this.score = 0,
    this.description,
    this.related = false,
  });

  final String tag;
  final String category;
  final String? zh;
  final int postCount;
  final double score;
  final String? description;
  final bool related;

  Map<String, dynamic> toJson() => {
    'tag': tag,
    'category': category,
    if (zh != null && zh!.isNotEmpty) 'zh': zh,
    'postCount': postCount,
    'score': score,
    if (description != null && description!.isNotEmpty)
      'description': description,
    if (related) 'related': true,
  };

  static KnowledgeCandidate? tryFromJson(Object? value) {
    if (value is! Map) return null;
    final tag = value['tag'] ?? value['name'];
    if (tag is! String || tag.trim().isEmpty) return null;
    final category = value['category'];
    final zh = value['zh'] ?? value['translation'] ?? value['chinese'];
    final postCount = value['postCount'] ?? value['post_count'];
    final score = value['score'];
    final description = value['description'];
    return KnowledgeCandidate(
      tag: tag.trim(),
      category: category is String && category.trim().isNotEmpty
          ? category.trim()
          : 'other',
      zh: zh is String && zh.trim().isNotEmpty ? zh.trim() : null,
      postCount: postCount is num && postCount.isFinite
          ? postCount.toInt().clamp(0, 0x7fffffff).toInt()
          : 0,
      score: score is num && score.isFinite
          ? score.toDouble().clamp(0.0, 1.0).toDouble()
          : 0,
      description: description is String && description.trim().isNotEmpty
          ? description.trim()
          : null,
      related: value['related'] == true,
    );
  }

  KnowledgeCandidate copyWith({
    String? category,
    String? zh,
    int? postCount,
    double? score,
    String? description,
    bool? related,
  }) => KnowledgeCandidate(
    tag: tag,
    category: category ?? this.category,
    zh: zh ?? this.zh,
    postCount: postCount ?? this.postCount,
    score: score ?? this.score,
    description: description ?? this.description,
    related: related ?? this.related,
  );
}

class KnowledgeResult {
  const KnowledgeResult({
    required this.candidates,
    required this.evidence,
    required this.provider,
    required this.degraded,
    this.warning,
  });

  final List<KnowledgeCandidate> candidates;
  final List<RetrievalEvidence> evidence;
  final String provider;
  final bool degraded;
  final String? warning;
}

class KnowledgeHealth {
  const KnowledgeHealth({
    required this.available,
    required this.provider,
    required this.message,
  });

  final bool available;
  final String provider;
  final String message;
}

abstract interface class KnowledgeProvider {
  Future<KnowledgeHealth> health();

  Future<KnowledgeResult> retrieve(KnowledgeQuery query);
}
