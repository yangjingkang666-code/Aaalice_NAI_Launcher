import 'dart:convert';

import '../models/recipe/prompt_recipe.dart';
import 'prompt_semantic_entry_builder.dart';

class PromptSemanticOrganizationResult {
  const PromptSemanticOrganizationResult({
    required this.entries,
    required this.translations,
    required this.warnings,
  });

  final List<PromptSemanticEntry> entries;
  final Map<String, String> translations;
  final List<String> warnings;
}

/// Validates and merges one AI organization response.
///
/// Invalid rows are discarded individually. Local catalog and manual rows are
/// never overwritten, even if the model returns a conflicting category.
class PromptSemanticOrganizationService {
  const PromptSemanticOrganizationService._();

  static const int maxResponseBytes = 64 * 1024;
  static const int maxItems = 64;
  static const int maxTextLength = 192;
  static const int maxTranslationLength = 128;

  static String buildUserContent(Iterable<PromptSemanticEntry> entries) {
    final payload = entries
        .where((entry) => entry.source != 'tag-db' && entry.source != 'manual')
        .take(maxItems)
        .map(
          (entry) => {
            'text': entry.text,
            'category': entry.category,
            'kind': entry.kind,
          },
        )
        .toList(growable: false);
    return jsonEncode(payload);
  }

  static PromptSemanticOrganizationResult parseAndMerge(
    String raw,
    List<PromptSemanticEntry> existing,
  ) {
    if (utf8.encode(raw).length > maxResponseBytes) {
      throw const FormatException('Prompt organization response is too large.');
    }
    final decoded = jsonDecode(raw.trim());
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException(
        'Prompt organization response must be an object.',
      );
    }
    final unknownFields = decoded.keys
        .where((key) => key != 'items')
        .toList(growable: false);
    if (unknownFields.isNotEmpty) {
      throw FormatException(
        'Prompt organization response contains unknown fields: '
        '${unknownFields.join(', ')}',
      );
    }
    final rows = decoded['items'];
    if (rows is! List) {
      throw const FormatException(
        'Prompt organization response must contain items.',
      );
    }

    final byText = <String, PromptSemanticEntry>{
      for (final entry in existing) _normalize(entry.text): entry,
    };
    final updated = <String, PromptSemanticEntry>{};
    final translations = <String, String>{};
    final warnings = <String>[];
    var accepted = 0;
    for (final value in rows.take(maxItems)) {
      if (value is! Map) {
        warnings.add('Skipped a malformed organization item.');
        continue;
      }
      final map = Map<String, dynamic>.from(value);
      final text = map['text'];
      final category = map['category'];
      final kind = map['kind'];
      final confidence = map['confidence'];
      final translation = map['translation'] ?? map['zh'];
      if (text is! String ||
          category is! String ||
          !PromptSemanticEntryBuilder.semanticCategories.contains(category) ||
          text.trim().isEmpty ||
          text.length > maxTextLength ||
          kind != null && kind is! String ||
          kind is String && kind != 'tag' && kind != 'natural-phrase' ||
          confidence != null && confidence is! num ||
          translation != null && translation is! String) {
        warnings.add('Skipped an invalid organization item.');
        continue;
      }
      final cleanText = text.trim();
      final key = _normalize(cleanText);
      final original = byText[key];
      if (original == null) {
        // The assistant may classify existing phrases but must not invent
        // semantic entries that are absent from the actual prompt. Otherwise
        // the durable structured view could silently diverge from the string
        // sent to NovelAI.
        warnings.add(
          'Skipped an organization item that was not in the prompt.',
        );
        continue;
      }
      if (original.source == 'tag-db' || original.source == 'manual') {
        // Known/local and manually moved entries are authoritative.
        if (translation is String && _validTranslation(translation)) {
          translations[original.text] = translation.trim();
        }
        continue;
      }
      final confidenceValue = confidence is num
          ? confidence.toDouble().clamp(0, 1).toDouble()
          : 0.5;
      final next = original;
      updated[key] = next.copyWith(
        text: original.text,
        category: category,
        source: 'ai',
        localTagHit: false,
        confidence: confidenceValue,
        kind: kind as String? ?? next.kind,
      );
      if (translation is String && _validTranslation(translation)) {
        translations[original.text] = translation.trim();
      }
      accepted++;
    }

    final merged = <PromptSemanticEntry>[];
    for (final entry in existing) {
      final replacement = updated[_normalize(entry.text)];
      merged.add(replacement ?? entry);
    }
    for (final entry in updated.values) {
      if (!existing.any(
        (candidate) => _normalize(candidate.text) == _normalize(entry.text),
      )) {
        merged.add(entry);
      }
    }
    if (accepted == 0 && existing.any((entry) => entry.source == 'imported')) {
      warnings.add('No unknown prompt item could be classified.');
    }
    return PromptSemanticOrganizationResult(
      entries: List.unmodifiable(merged),
      translations: Map.unmodifiable(translations),
      warnings: List.unmodifiable(warnings),
    );
  }

  static bool _validTranslation(String value) =>
      value.trim().isNotEmpty &&
      value.length <= maxTranslationLength &&
      !value.contains(RegExp(r'[\r\n]'));

  static String _normalize(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'\s*,\s*'), ',');
}
