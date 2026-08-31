import '../../core/autocomplete/completion_models.dart';
import '../../core/autocomplete/tag_catalog_repository.dart';
import '../../core/utils/nai_prompt_parser.dart';
import '../models/prompt/tag_category.dart';
import '../models/recipe/prompt_recipe.dart';

/// Result of turning the wire-format prompt into durable editor semantics.
class PromptSemanticBuildResult {
  const PromptSemanticBuildResult({
    required this.entries,
    required this.structured,
  });

  final List<PromptSemanticEntry> entries;
  final StructuredPrompt structured;
}

/// Builds semantic entries without changing the prompt sent to NovelAI.
///
/// The local catalog is authoritative when it recognizes a tag. A caller may
/// provide a resolver for the bundled SQLite catalog; the synchronous method
/// remains useful for editor startup and old recipes where opening SQLite
/// would be needlessly expensive.
class PromptSemanticEntryBuilder {
  const PromptSemanticEntryBuilder._();

  static const semanticCategories = <String>{
    'subject',
    'appearance',
    'expression',
    'clothing',
    'action',
    'pose',
    'adult',
    'object',
    'scene',
    'lighting',
    'camera',
    'composition',
    'style',
    'quality',
    'negative',
    'other',
  };

  static PromptSemanticBuildResult buildSync(
    String prompt, {
    String negativePrompt = '',
    List<PromptSemanticEntry> existingEntries = const [],
  }) {
    final entries = _buildEntries(
      prompt,
      existingEntries: existingEntries,
      localHits: const {},
    );
    return PromptSemanticBuildResult(
      entries: List.unmodifiable(entries),
      structured: _buildStructured(entries, negativePrompt),
    );
  }

  static Future<PromptSemanticBuildResult> build(
    String prompt, {
    String negativePrompt = '',
    List<PromptSemanticEntry> existingEntries = const [],
    Future<Map<String, TagCatalogRecord>> Function(Iterable<String>)?
    resolveExactTags,
  }) async {
    Map<String, TagCatalogRecord> localHits = const {};
    if (resolveExactTags != null) {
      final terms = NaiPromptParser.splitSegments(prompt)
          .map(NaiPromptParser.stripWeightSyntax)
          .where((term) => term.trim().isNotEmpty);
      try {
        localHits = await resolveExactTags(terms);
      } catch (_) {
        // Semantic persistence must never make a successful generation fail.
        localHits = const {};
      }
    }
    final entries = _buildEntries(
      prompt,
      existingEntries: existingEntries,
      localHits: localHits,
    );
    return PromptSemanticBuildResult(
      entries: List.unmodifiable(entries),
      structured: _buildStructured(entries, negativePrompt),
    );
  }

  static List<PromptSemanticEntry> _buildEntries(
    String prompt, {
    required List<PromptSemanticEntry> existingEntries,
    required Map<String, TagCatalogRecord> localHits,
  }) {
    final priorByText = <String, PromptSemanticEntry>{};
    for (final entry in existingEntries) {
      final key = _normalize(entry.text);
      if (key.isNotEmpty) priorByText.putIfAbsent(key, () => entry);
    }

    final occurrences = <String, int>{};
    final entries = <PromptSemanticEntry>[];
    for (final rawSegment in NaiPromptParser.splitSegments(prompt)) {
      final text = NaiPromptParser.stripWeightSyntax(rawSegment).trim();
      if (text.isEmpty) continue;
      final normalized = _normalize(text);
      final occurrence = occurrences.update(
        normalized,
        (value) => value + 1,
        ifAbsent: () => 0,
      );
      final previous = priorByText[normalized];
      final local = localHits[_lookupKey(text)];
      // Manual classifications are an explicit user decision. Preserve them
      // even when the catalog later becomes available; all other prior
      // classifications are retained only when the catalog has no answer.
      final preservePrevious =
          previous != null &&
          (previous.source == 'manual' ||
              (local == null &&
                  (previous.source == 'tag-db' ||
                      previous.source == 'imported' ||
                      previous.source == 'ai')));
      if (preservePrevious) {
        entries.add(previous.copyWith(text: text));
        continue;
      }

      final category = local == null
          ? _heuristicCategory(text)
          : _categoryForLocal(local);
      entries.add(
        PromptSemanticEntry(
          id: previous?.id ?? _stableId(normalized, occurrence),
          text: text,
          category: category,
          source: local == null ? 'imported' : 'tag-db',
          localTagHit: local != null,
          confidence: local == null ? 0.45 : 1,
          kind: local != null || _looksLikeTag(text) ? 'tag' : 'natural-phrase',
        ),
      );
    }
    return entries;
  }

  static StructuredPrompt _buildStructured(
    List<PromptSemanticEntry> entries,
    String negativePrompt,
  ) {
    final fields = <String, List<String>>{
      for (final field in StructuredPrompt.structuredPromptFields)
        field: <String>[],
    };
    for (final entry in entries) {
      final bucket = _structuredBucket(entry.category);
      if (bucket == null) continue;
      final values = fields[bucket]!;
      if (!values.any((value) => _normalize(value) == _normalize(entry.text))) {
        values.add(entry.text);
      }
    }
    if (negativePrompt.trim().isNotEmpty) {
      final negativeValues = fields['negative']!;
      for (final segment in NaiPromptParser.splitSegments(negativePrompt)) {
        final text = NaiPromptParser.stripWeightSyntax(segment).trim();
        if (text.isNotEmpty &&
            !negativeValues.any(
              (value) => _normalize(value) == _normalize(text),
            )) {
          negativeValues.add(text);
        }
      }
    }
    return StructuredPrompt(fields: fields);
  }

  static String? _structuredBucket(String category) => switch (category) {
    'negative' => 'negative',
    'quality' => 'quality',
    'subject' => 'subject',
    'appearance' || 'expression' => 'appearance',
    'clothing' => 'clothing',
    'action' || 'pose' => 'pose',
    'adult' => 'adult',
    'object' || 'scene' => 'scene',
    'lighting' => 'lighting',
    'camera' || 'composition' => 'camera',
    'style' => 'style',
    _ => null,
  };

  static String _categoryForLocal(TagCatalogRecord record) {
    switch (record.category) {
      case TagCategory.character:
      case TagCategory.copyright:
      case TagCategory.artist:
        return 'subject';
      case TagCategory.species:
        return 'subject';
      case TagCategory.meta:
        return 'quality';
      case TagCategory.contributor:
      case TagCategory.lore:
      case TagCategory.library:
        return 'subject';
      case TagCategory.general:
        return _categoryForSubCategory(
          TagSubCategoryHelper.classifyTag(record.canonicalTag),
        );
    }
  }

  static String _categoryForSubCategory(TagSubCategory category) =>
      switch (category) {
        TagSubCategory.clothing ||
        TagSubCategory.clothingFemale ||
        TagSubCategory.clothingMale ||
        TagSubCategory.clothingGeneral => 'clothing',
        TagSubCategory.pose => 'pose',
        TagSubCategory.scene || TagSubCategory.background => 'scene',
        TagSubCategory.camera ||
        TagSubCategory.framing ||
        TagSubCategory.focus => 'camera',
        TagSubCategory.style => 'style',
        TagSubCategory.characterCount ||
        TagSubCategory.species ||
        TagSubCategory.prop => 'subject',
        TagSubCategory.effect => 'lighting',
        _ => 'appearance',
      };

  static String _heuristicCategory(String value) {
    final text = _normalize(value).replaceAll('_', ' ');
    if (RegExp(
      r'\b(masterpiece|best quality|high quality|quality)\b',
    ).hasMatch(text)) {
      return 'quality';
    }
    if (RegExp(
      r'\b(nude|nsfw|sex|penis|vagina|breasts|cum|explicit)\b',
    ).hasMatch(text)) {
      return 'adult';
    }
    if (RegExp(
      r'\b(eye|eyes|hair|hairstyle|skin|face|freckles|makeup|color|colour)\b',
    ).hasMatch(text)) {
      return 'appearance';
    }
    if (RegExp(
      r'\b(wearing|dress|shirt|skirt|pants|uniform|swimsuit|coat|shoes)\b',
    ).hasMatch(text)) {
      return 'clothing';
    }
    if (RegExp(
      r'\b(standing|sitting|lying|kneeling|walking|running|looking|smile|blush|pose|holding)\b',
    ).hasMatch(text)) {
      return 'pose';
    }
    if (RegExp(
      r'\b(camera|close[- ]up|portrait|view|angle|composition|framing|foreground|background)\b',
    ).hasMatch(text)) {
      return 'camera';
    }
    if (RegExp(
      r'\b(light|lighting|shadow|sunlight|moonlight|glow|dark|bright)\b',
    ).hasMatch(text)) {
      return 'lighting';
    }
    if (RegExp(
      r'\b(indoor|outdoor|classroom|room|street|forest|beach|sky|city|landscape|scenery)\b',
    ).hasMatch(text)) {
      return 'scene';
    }
    if (RegExp(
      r'\b(style|anime|realistic|illustration|watercolor|sketch|3d|photorealistic)\b',
    ).hasMatch(text)) {
      return 'style';
    }
    if (RegExp(
      r'(?:^|\d|\s)(?:girl|boy|woman|man|person|character|solo|group|animal|dragon|cat|dog)\b',
    ).hasMatch(text)) {
      return 'subject';
    }
    return 'other';
  }

  static bool _looksLikeTag(String value) =>
      RegExp(r'^[a-z0-9_():.!+\-]+$').hasMatch(value.toLowerCase());

  static String _normalize(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'\s*,\s*'), ',');

  static String _lookupKey(String value) =>
      _normalize(value).replaceAll(' ', '_');

  static String _stableId(String normalized, int occurrence) {
    var hash = 2166136261;
    for (final codeUnit in normalized.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 16777619) & 0xffffffff;
    }
    return 'main-${hash.toRadixString(16).padLeft(8, '0')}-$occurrence';
  }
}
