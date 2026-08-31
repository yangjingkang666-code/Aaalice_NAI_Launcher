import 'dart:convert';

import '../models/recipe/prompt_recipe.dart';
import 'prompt_patch_service.dart';

/// A parsed, but not yet accepted, assistant proposal.
class PromptPatchProposal {
  const PromptPatchProposal({
    required this.operations,
    required this.validation,
  });

  final List<PromptPatchOperation> operations;
  final PromptPatchValidation validation;

  bool get isValid => validation.isValid;
}

/// Strict boundary for assistant-generated Prompt Patch JSON.
///
/// The parser accepts no executable instructions and never marks an operation
/// as explicit: only a human can grant the explicit-lock override in the UI.
class PromptPatchProposalService {
  const PromptPatchProposalService._();

  static const int maxResponseBytes = 64 * 1024;
  static const int maxOperations = 32;
  static const int maxOperationIdLength = 128;
  static const int maxReasonLength = 2000;
  static const int maxValueLength = 8192;
  static const int maxEvidenceIds = 32;

  static PromptPatchProposal parseAndValidate(
    String raw,
    PromptRecipe recipe, {
    PromptPatchLockPolicy policy = PromptPatchLockPolicy.strict,
  }) {
    final operations = parse(raw);
    return PromptPatchProposal(
      operations: operations,
      validation: PromptPatchService.validate(
        recipe,
        operations,
        policy: policy,
      ),
    );
  }

  /// Parses `{ "operations": [...] }` and rejects all other top-level data.
  static List<PromptPatchOperation> parse(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty || utf8.encode(trimmed).length > maxResponseBytes) {
      throw const FormatException(
        'Prompt Patch proposal is empty or too large.',
      );
    }
    final jsonText = _stripOptionalCodeFence(trimmed);
    final decoded = jsonDecode(jsonText);
    if (decoded is! Map) {
      throw const FormatException(
        'Prompt Patch proposal must be a JSON object.',
      );
    }
    if (decoded.keys.any((key) => key is! String)) {
      throw const FormatException(
        'Prompt Patch proposal object keys must be strings.',
      );
    }
    final map = Map<String, dynamic>.from(decoded);
    final unknown = map.keys.where((key) => key != 'operations').toList();
    if (unknown.isNotEmpty) {
      throw FormatException(
        'Prompt Patch proposal contains unknown fields: ${unknown.join(', ')}',
      );
    }
    final rawOperations = map['operations'];
    if (rawOperations is! List) {
      throw const FormatException(
        'Prompt Patch proposal operations must be a list.',
      );
    }
    if (rawOperations.length > maxOperations) {
      // The limit is interpolated into the diagnostic, so this constructor
      // cannot be const.
      // ignore: prefer_const_constructors
      throw FormatException(
        'Prompt Patch proposal contains more than $maxOperations operations.',
      );
    }

    final operations = <PromptPatchOperation>[];
    for (var index = 0; index < rawOperations.length; index++) {
      final value = rawOperations[index];
      if (value is! Map) {
        throw FormatException(
          'Prompt Patch operation $index must be an object.',
        );
      }
      if (value.keys.any((key) => key is! String)) {
        throw FormatException(
          'Prompt Patch operation $index keys must be strings.',
        );
      }
      operations.add(_parseOperation(Map<String, dynamic>.from(value), index));
    }
    return List.unmodifiable(operations);
  }

  /// Builds a byte-free assistant input payload from a recipe.
  static String buildUserContent(
    PromptRecipe recipe, {
    String userInstruction = '',
  }) {
    final request = recipe.request;
    final payload = <String, dynamic>{
      'recipeId': recipe.id,
      'prompt': request.params.prompt,
      'negativePrompt': request.params.negativePrompt,
      'model': request.params.model,
      'characters': [
        for (final character in recipe.characters)
          {
            'id': character.id,
            'name': character.name,
            'prompt': character.prompt,
            'negativePrompt': character.negativePrompt,
            'corePrompt': character.corePrompt,
            'lockedTraits': character.lockedTraits,
            'enabled': character.enabled,
          },
      ],
      'semanticEntries': [
        for (final entry in recipe.mainPromptEntries)
          {
            'id': entry.id,
            'text': entry.text,
            'category': entry.category,
            'kind': entry.kind,
          },
      ],
      'structuredMain': recipe.structuredMain.toJson(),
      'retrievalEvidence': [
        for (final evidence in recipe.retrievalEvidence)
          {
            'id': evidence.id,
            'tag': evidence.tag,
            'category': evidence.category,
            'zh': evidence.zh,
            'score': evidence.score,
          },
      ],
    };
    final instruction = userInstruction.trim();
    return [
      'Current recipe (metadata only):',
      jsonEncode(payload),
      if (instruction.isNotEmpty) ...['', 'User request:', instruction],
    ].join('\n');
  }

  static PromptPatchOperation _parseOperation(
    Map<String, dynamic> raw,
    int index,
  ) {
    const allowed = {
      'id',
      'op',
      'target',
      'category',
      'before',
      'after',
      'reason',
      'evidenceIds',
      'confidence',
      'explicit',
      'tokenId',
    };
    final unknown = raw.keys.where((key) => !allowed.contains(key)).toList();
    if (unknown.isNotEmpty) {
      throw FormatException(
        'Prompt Patch operation $index contains unknown fields: ${unknown.join(', ')}',
      );
    }

    final id = raw['id'];
    final reason = raw['reason'];
    final evidenceIds = raw['evidenceIds'];
    final explicit = raw['explicit'];
    if (id is! String ||
        id.trim().isEmpty ||
        id.length > maxOperationIdLength) {
      throw FormatException('Prompt Patch operation $index has an invalid id.');
    }
    if (reason is! String ||
        reason.trim().isEmpty ||
        reason.length > maxReasonLength) {
      throw FormatException(
        'Prompt Patch operation $index must include a bounded reason.',
      );
    }
    if (explicit == true) {
      throw const FormatException(
        'Assistant proposals cannot mark operations as explicit.',
      );
    }
    if (evidenceIds != null &&
        (evidenceIds is! List || evidenceIds.any((item) => item is! String))) {
      throw FormatException(
        'Prompt Patch operation $index has invalid evidence ids.',
      );
    }
    if (evidenceIds is List && evidenceIds.length > maxEvidenceIds) {
      throw FormatException(
        'Prompt Patch operation $index has too many evidence ids.',
      );
    }

    for (final key in const ['before', 'after']) {
      final value = raw[key];
      if (value is String && value.length > maxValueLength) {
        throw FormatException(
          'Prompt Patch operation $index has an oversized $key value.',
        );
      }
    }

    final normalized = <String, dynamic>{
      ...raw,
      'evidenceIds': evidenceIds ?? const <String>[],
      'confidence': raw['confidence'] ?? 0.5,
      // Explicit lock overrides are granted only by a later human action.
      'explicit': false,
    };
    return PromptPatchOperation.fromJson(normalized);
  }

  static String _stripOptionalCodeFence(String value) {
    final match = RegExp(
      r'^```(?:json)?\s*([\s\S]*?)\s*```$',
      caseSensitive: false,
    ).firstMatch(value);
    return match?.group(1)?.trim() ?? value;
  }
}
