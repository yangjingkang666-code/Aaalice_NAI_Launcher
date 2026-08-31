import 'dart:convert';

/// A single semantic fact returned by the image reverse-prompt route.
///
/// These entries are evidence for a human review. They are intentionally kept
/// separate from the final prompt so that a model cannot silently turn an
/// uncertain guess into generation input.
class ReversePromptSemanticEntry {
  const ReversePromptSemanticEntry({
    required this.text,
    required this.category,
    this.translation = '',
    this.confidence,
  });

  final String text;
  final String category;
  final String translation;
  final double? confidence;

  ReversePromptSemanticEntry copyWith({
    String? text,
    String? category,
    String? translation,
    double? confidence,
  }) {
    return ReversePromptSemanticEntry(
      text: text ?? this.text,
      category: category ?? this.category,
      translation: translation ?? this.translation,
      confidence: confidence ?? this.confidence,
    );
  }

  Map<String, dynamic> toJson() => {
    'text': text,
    'category': category,
    if (translation.trim().isNotEmpty) 'translation': translation,
    if (confidence != null) 'confidence': confidence,
  };

  static ReversePromptSemanticEntry? tryParse(dynamic value) {
    if (value is String) {
      final text = value.trim();
      if (text.isEmpty) return null;
      return ReversePromptSemanticEntry(text: text, category: 'other');
    }
    if (value is! Map) return null;

    final text = _readStringValue(value, const ['text', 'term', 'tag']);
    if (text.isEmpty) return null;
    final category = _readStringValue(value, const ['category', 'kind']);
    final translation = _readStringValue(value, const [
      'translation',
      'chinese',
      'label',
    ]);
    final rawConfidence = value['confidence'];
    final confidence = rawConfidence is num
        ? rawConfidence.toDouble().clamp(0.0, 1.0)
        : null;
    return ReversePromptSemanticEntry(
      text: text,
      category: category.isEmpty ? 'other' : category,
      translation: translation,
      confidence: confidence,
    );
  }
}

/// Structured, reviewable output of an image reverse-prompt operation.
///
/// The parser accepts the schema used by the TypeScript launcher and a small
/// set of backwards-compatible aliases. If a provider ignores JSON mode and
/// returns plain text, the result is retained as a positive prompt with an
/// explicit warning instead of being discarded.
class ReversePromptDraft {
  const ReversePromptDraft({
    required this.positivePrompt,
    this.negativePrompt = '',
    this.semanticEntries = const [],
    this.chineseSummary = '',
    this.warnings = const [],
    this.rawResponse = '',
    this.routeFingerprint = '',
    this.routeLabel = '',
    this.usedFallback = false,
  });

  final String positivePrompt;
  final String negativePrompt;
  final List<ReversePromptSemanticEntry> semanticEntries;
  final String chineseSummary;
  final List<String> warnings;
  final String rawResponse;
  final String routeFingerprint;
  final String routeLabel;
  final bool usedFallback;

  bool get isEmpty => positivePrompt.trim().isEmpty;

  ReversePromptDraft copyWith({
    String? positivePrompt,
    String? negativePrompt,
    List<ReversePromptSemanticEntry>? semanticEntries,
    String? chineseSummary,
    List<String>? warnings,
    String? rawResponse,
    String? routeFingerprint,
    String? routeLabel,
    bool? usedFallback,
  }) {
    return ReversePromptDraft(
      positivePrompt: positivePrompt ?? this.positivePrompt,
      negativePrompt: negativePrompt ?? this.negativePrompt,
      semanticEntries: semanticEntries ?? this.semanticEntries,
      chineseSummary: chineseSummary ?? this.chineseSummary,
      warnings: warnings ?? this.warnings,
      rawResponse: rawResponse ?? this.rawResponse,
      routeFingerprint: routeFingerprint ?? this.routeFingerprint,
      routeLabel: routeLabel ?? this.routeLabel,
      usedFallback: usedFallback ?? this.usedFallback,
    );
  }

  Map<String, dynamic> toJson() => {
    'positivePrompt': positivePrompt,
    'negativePrompt': negativePrompt,
    'semanticEntries': semanticEntries.map((entry) => entry.toJson()).toList(),
    'chineseSummary': chineseSummary,
    'warnings': warnings,
    'rawResponse': rawResponse,
    'routeFingerprint': routeFingerprint,
    'routeLabel': routeLabel,
    'usedFallback': usedFallback,
  };

  static ReversePromptDraft parse(
    String raw, {
    String routeFingerprint = '',
    String routeLabel = '',
  }) {
    final response = raw.trim();
    if (response.isEmpty) {
      throw const FormatException('Reverse prompt response is empty.');
    }

    final decoded = _decodeObject(response);
    if (decoded is Map) {
      final positive = _readStringValue(decoded, const [
        'main_prompt',
        'positive_prompt',
        'prompt',
        'mainPrompt',
      ]);
      final negative = _readStringValue(decoded, const [
        'negative_prompt',
        'negativePrompt',
        'negative',
      ]);
      final summary = _readStringValue(decoded, const [
        'chinese_summary',
        'chineseSummary',
        'summary',
      ]);
      final warnings = _stringList(decoded['warnings']);
      final entries = _entryList(
        decoded['main_prompt_entries'] ??
            decoded['semantic_entries'] ??
            decoded['semanticEntries'] ??
            decoded['items'],
      );
      if (positive.isNotEmpty) {
        return ReversePromptDraft(
          positivePrompt: _normalizePrompt(positive),
          negativePrompt: _normalizePrompt(negative),
          semanticEntries: entries,
          chineseSummary: summary.trim(),
          warnings: warnings,
          rawResponse: response,
          routeFingerprint: routeFingerprint,
          routeLabel: routeLabel,
        );
      }
    }

    // Some OpenAI-compatible gateways ignore response_format. Keep the text
    // usable, but make the loss of structured fields explicit to the reviewer.
    final fallback = _normalizePrompt(_stripCodeFence(response));
    if (fallback.isEmpty) {
      throw const FormatException(
        'Reverse prompt response did not contain a usable prompt.',
      );
    }
    return ReversePromptDraft(
      positivePrompt: fallback,
      warnings: const [
        'The provider returned plain text; semantic, negative-prompt, and confidence fields were not available.',
      ],
      rawResponse: response,
      routeFingerprint: routeFingerprint,
      routeLabel: routeLabel,
      usedFallback: true,
    );
  }

  static dynamic _decodeObject(String raw) {
    final candidates = <String>[raw, _stripCodeFence(raw)];
    final firstBrace = raw.indexOf('{');
    final lastBrace = raw.lastIndexOf('}');
    if (firstBrace >= 0 && lastBrace > firstBrace) {
      candidates.add(raw.substring(firstBrace, lastBrace + 1));
    }
    for (final candidate in candidates) {
      try {
        final decoded = jsonDecode(candidate.trim());
        if (decoded is Map) return decoded;
      } catch (_) {
        // Try the next compatible representation before falling back to text.
      }
    }
    return null;
  }

  static String _stripCodeFence(String value) {
    final match = RegExp(
      r'^\s*```(?:json)?\s*([\s\S]*?)\s*```\s*$',
      caseSensitive: false,
    ).firstMatch(value);
    return match?.group(1)?.trim() ?? value.trim();
  }

  static List<ReversePromptSemanticEntry> _entryList(dynamic value) {
    if (value is! List) return const [];
    return value
        .map(ReversePromptSemanticEntry.tryParse)
        .whereType<ReversePromptSemanticEntry>()
        .where((entry) => entry.text.trim().isNotEmpty)
        .toList(growable: false);
  }

  static List<String> _stringList(dynamic value) {
    if (value is String) {
      final text = value.trim();
      return text.isEmpty ? const [] : [text];
    }
    if (value is! List) return const [];
    return value
        .whereType<String>()
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  static String _normalizePrompt(String value) {
    return value
        .replaceAll(RegExp(r'```(?:json)?', caseSensitive: false), '')
        .replaceAll(RegExp(r'[\r\n]+'), ' ')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .replaceAll(RegExp(r'\s+,'), ',')
        .trim();
  }
}

String _readStringValue(dynamic value, List<String> keys) {
  if (value is! Map) return '';
  for (final key in keys) {
    final candidate = value[key];
    if (candidate is String && candidate.trim().isNotEmpty) {
      return candidate.trim();
    }
  }
  return '';
}
