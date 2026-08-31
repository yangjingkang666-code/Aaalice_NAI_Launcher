import 'dart:convert';

import '../models/image/image_params.dart' as image;
import '../models/queue/replication_task.dart';
import '../models/queue/replication_task_generation_snapshot.dart';
import '../models/recipe/modification_seed_strategy.dart';
import '../models/recipe/prompt_recipe.dart';
import 'prompt_patch_service.dart';

/// A single, human-reviewable change in an AI batch plan.
class AiBatchPlanItem {
  const AiBatchPlanItem({
    required this.id,
    required this.summary,
    required this.operations,
    this.conflictWarnings = const [],
    this.enabled = true,
    this.order = 0,
  });

  final String id;
  final String summary;
  final List<PromptPatchOperation> operations;
  final List<String> conflictWarnings;
  final bool enabled;
  final int order;

  AiBatchPlanItem copyWith({
    String? id,
    String? summary,
    List<PromptPatchOperation>? operations,
    List<String>? conflictWarnings,
    bool? enabled,
    int? order,
  }) {
    return AiBatchPlanItem(
      id: id ?? this.id,
      summary: summary ?? this.summary,
      operations: operations ?? this.operations,
      conflictWarnings: conflictWarnings ?? this.conflictWarnings,
      enabled: enabled ?? this.enabled,
      order: order ?? this.order,
    );
  }
}

/// A proposed set of serial tasks. It contains no images, tokens, commands,
/// or scheduler side effects; callers must explicitly materialize selected
/// items after the user has reviewed them.
class AiBatchPlan {
  const AiBatchPlan({required this.items, this.warnings = const []});

  final List<AiBatchPlanItem> items;
  final List<String> warnings;

  bool get isEmpty => items.isEmpty;
}

/// Strict, binary-free parser and materializer for Sprint 8.4 batch plans.
///
/// The parser deliberately accepts only text Prompt Patch operations that can
/// vary a requested pose/scene/camera while identity, quality, parameters and
/// references remain protected. Invalid rows are disabled individually so one
/// malformed model response never discards the rest of a reviewable plan.
abstract final class AiBatchPlanService {
  static const int maxResponseBytes = 128 * 1024;
  static const int maxItems = 16;
  static const int maxOperationsPerItem = 8;
  static const int maxSummaryLength = 512;
  static const int maxWarningLength = 512;

  static const Set<String> _allowedCategories = {
    'pose',
    'action',
    'expression',
    'clothing',
    'scene',
    'lighting',
    'camera',
    'composition',
  };

  static const PromptPatchLockPolicy batchLockPolicy = PromptPatchLockPolicy(
    characterIdentity: true,
    characterCore: true,
    lockedTraits: true,
    // These are the only intentionally variable dimensions in a plan.
    pose: false,
    composition: false,
    style: true,
    generationParameters: true,
    references: true,
  );

  /// Builds the text-only request sent to the planning model.
  static String buildUserContent(
    PromptRecipe recipe, {
    required String instruction,
    required int requestedCount,
  }) {
    final payload = <String, dynamic>{
      'recipeId': recipe.id,
      'prompt': recipe.request.params.prompt,
      'negativePrompt': recipe.request.params.negativePrompt,
      'model': recipe.request.params.model,
      'requestedCount': requestedCount,
      'instruction': instruction.trim(),
      'characters': [
        for (final character in recipe.characters)
          {
            'id': character.id,
            'name': character.name,
            'prompt': character.prompt,
            'negativePrompt': character.negativePrompt,
            'corePrompt': character.corePrompt,
            'lockedTraits': character.lockedTraits,
            'negativeTraits': character.negativeTraits,
            'enabled': character.enabled,
          },
      ],
      'locked': [
        'character identity, core prompt, locked traits',
        'model, width, height, steps, sampler, scale, quality and seed',
        'image-to-image, Vibe and Precise references',
      ],
      'semanticEntries': [
        for (final entry in recipe.mainPromptEntries)
          {'text': entry.text, 'category': entry.category, 'kind': entry.kind},
      ],
    };
    return jsonEncode(payload);
  }

  /// Parses the model response into a bounded, review-only plan.
  static AiBatchPlan parseAndValidate(String raw, PromptRecipe recipe) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty || utf8.encode(trimmed).length > maxResponseBytes) {
      throw const FormatException('AI batch plan is empty or too large.');
    }
    final decoded = jsonDecode(_stripCodeFence(trimmed));
    if (decoded is! Map) {
      throw const FormatException('AI batch plan must be a JSON object.');
    }
    final map = Map<String, dynamic>.from(decoded);
    final unknown = map.keys
        .where((key) => key != 'items' && key != 'warnings')
        .toList();
    if (unknown.isNotEmpty) {
      throw FormatException(
        'AI batch plan contains unknown fields: ${unknown.join(', ')}',
      );
    }
    final rawItems = map['items'];
    if (rawItems is! List) {
      throw const FormatException('AI batch plan items must be a list.');
    }
    if (rawItems.length > maxItems) {
      throw const FormatException(
        'AI batch plan contains more than $maxItems items.',
      );
    }

    final warnings = <String>[
      ..._boundedWarnings(map['warnings'], 'plan warning'),
    ];
    final seenIds = <String>{};
    final items = <AiBatchPlanItem>[];
    for (var index = 0; index < rawItems.length; index++) {
      final value = rawItems[index];
      if (value is! Map) {
        warnings.add('Item $index was ignored because it is not an object.');
        continue;
      }
      final parsed = _parseItem(
        Map<String, dynamic>.from(value),
        index: index,
        recipe: recipe,
        seenIds: seenIds,
      );
      if (parsed == null) continue;
      items.add(parsed);
    }
    if (items.isEmpty && warnings.isEmpty) {
      warnings.add('The assistant returned no reviewable batch items.');
    }
    items.sort((a, b) => a.order.compareTo(b.order));
    return AiBatchPlan(
      items: List.unmodifiable(items),
      warnings: List.unmodifiable(warnings),
    );
  }

  /// Converts one approved plan item to an immutable serial queue task.
  ///
  /// This method is the only place where a plan crosses into the scheduler;
  /// it still does not start generation. Queue admission later materializes an
  /// implicit random seed exactly once.
  static ReplicationTask materializeTask(
    PromptRecipe recipe,
    AiBatchPlanItem item, {
    ModificationSeedStrategy seedStrategy = ModificationSeedStrategy.base,
    int? specifiedSeed,
  }) {
    if (!item.enabled) {
      throw StateError('Cannot materialize a disabled batch item.');
    }
    final applied = PromptPatchService.apply(
      recipe,
      item.operations,
      policy: batchLockPolicy,
      seedStrategy: seedStrategy,
      specifiedSeed: specifiedSeed,
    );
    final recipeCharacters = applied.recipe.characters;
    final params = _paramsWithCharacters(
      applied.recipe.request.params,
      recipeCharacters,
    ).copyWith(nSamples: 1);
    final characterSnapshots = [
      for (final character in recipeCharacters)
        ReplicationCharacterPromptSnapshot(
          prompt: character.prompt,
          negativePrompt: character.negativePrompt,
          enabled: character.enabled,
          positionX: character.center.x,
          positionY: character.center.y,
        ),
    ];
    return ReplicationTask.create(
      prompt: params.prompt,
      negativePrompt: params.negativePrompt,
      applyNegativePrompt: true,
      characterPrompts: characterSnapshots,
      generationSnapshot: ReplicationTaskGenerationSnapshot.encode(params),
      source: ReplicationTaskSource.local,
      seed: params.seed,
      sampler: params.sampler,
      steps: params.steps,
      cfgScale: params.scale,
      model: params.model,
      width: params.width,
      height: params.height,
    );
  }

  static AiBatchPlanItem? _parseItem(
    Map<String, dynamic> raw, {
    required int index,
    required PromptRecipe recipe,
    required Set<String> seenIds,
  }) {
    const allowed = {
      'id',
      'summary',
      'operations',
      'warnings',
      'enabled',
      'order',
    };
    final unknown = raw.keys.where((key) => !allowed.contains(key)).toList();
    if (unknown.isNotEmpty) {
      return AiBatchPlanItem(
        id: 'invalid-$index',
        summary: 'Invalid item',
        operations: const [],
        conflictWarnings: [
          'Item $index contains unknown fields: ${unknown.join(', ')}',
        ],
        enabled: false,
        order: index,
      );
    }
    final id = raw['id'];
    final summary = raw['summary'];
    final rawOperations = raw['operations'];
    if (id is! String ||
        id.trim().isEmpty ||
        id.length > 128 ||
        summary is! String ||
        summary.trim().isEmpty ||
        summary.length > maxSummaryLength ||
        rawOperations is! List) {
      return AiBatchPlanItem(
        id: 'invalid-$index',
        summary: 'Invalid item',
        operations: const [],
        conflictWarnings: [
          'Item $index has invalid id, summary, or operations.',
        ],
        enabled: false,
        order: index,
      );
    }
    final normalizedId = id.trim();
    if (!seenIds.add(normalizedId)) {
      return AiBatchPlanItem(
        id: normalizedId,
        summary: summary.trim(),
        operations: const [],
        conflictWarnings: ['Duplicate item id: $normalizedId'],
        enabled: false,
        order: index,
      );
    }
    final warnings = <String>[
      ..._boundedWarnings(raw['warnings'], 'item warning'),
    ];
    if (rawOperations.length > maxOperationsPerItem) {
      warnings.add(
        'Item $normalizedId exceeds the $maxOperationsPerItem operation limit.',
      );
    }
    final operations = <PromptPatchOperation>[];
    final operationIds = <String>{};
    for (
      var operationIndex = 0;
      operationIndex < rawOperations.length &&
          operationIndex < maxOperationsPerItem;
      operationIndex++
    ) {
      final value = rawOperations[operationIndex];
      final operation = _parseOperation(
        value,
        itemId: normalizedId,
        operationIndex: operationIndex,
      );
      if (operation == null) {
        warnings.add(
          'Operation $operationIndex in $normalizedId was ignored as unsafe.',
        );
        continue;
      }
      if (!operationIds.add(operation.id)) {
        warnings.add('Duplicate operation id ${operation.id} was ignored.');
        continue;
      }
      operations.add(operation);
    }

    final validation = PromptPatchService.validate(
      recipe,
      operations,
      policy: batchLockPolicy,
    );
    if (!validation.isValid) {
      warnings.addAll(validation.issues.map((issue) => issue.message));
    }
    final validIds = validation.valid.map((operation) => operation.id).toSet();
    final reviewOperations = operations
        .where((operation) => validIds.contains(operation.id))
        .toList(growable: false);
    if (reviewOperations.isEmpty) {
      warnings.add('No operation in $normalizedId can be applied safely.');
    }
    return AiBatchPlanItem(
      id: normalizedId,
      summary: summary.trim(),
      operations: List.unmodifiable(reviewOperations),
      conflictWarnings: List.unmodifiable(warnings),
      enabled: raw['enabled'] != false && reviewOperations.isNotEmpty,
      order: raw['order'] is int && (raw['order'] as int) >= 0
          ? raw['order'] as int
          : index,
    );
  }

  static PromptPatchOperation? _parseOperation(
    Object? value, {
    required String itemId,
    required int operationIndex,
  }) {
    if (value is! Map) return null;
    final raw = Map<String, dynamic>.from(value);
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
    if (raw.keys.any((key) => !allowed.contains(key))) return null;
    final target = raw['target'];
    final op = raw['op'];
    final category = raw['category'];
    if (target is! String ||
        (target.trim() != 'main' && !target.trim().startsWith('character:')) ||
        target.trim().contains(' ') ||
        op is! String ||
        !const {'add', 'remove', 'replace', 'move', 'keep'}.contains(op) ||
        category is! String ||
        !_allowedCategories.contains(category.trim().toLowerCase())) {
      return null;
    }
    if (raw['explicit'] == true) return null;
    final id = raw['id'];
    final reason = raw['reason'];
    if (id is! String ||
        id.trim().isEmpty ||
        reason is! String ||
        reason.trim().isEmpty) {
      return null;
    }
    final normalized = <String, dynamic>{
      ...raw,
      'id': id.trim(),
      'target': target.trim(),
      'category': category.trim().toLowerCase(),
      'reason': reason.trim(),
      'evidenceIds': raw['evidenceIds'] ?? const <String>[],
      'confidence': raw['confidence'] ?? 0.5,
      'explicit': false,
    };
    try {
      final operation = PromptPatchOperation.fromJson(normalized);
      if (operation.before is Map || operation.after is Map) return null;
      return operation;
    } catch (_) {
      return null;
    }
  }

  static List<String> _boundedWarnings(Object? raw, String label) {
    if (raw is! List) return const [];
    return [
      for (final item in raw)
        if (item is String &&
            item.trim().isNotEmpty &&
            item.length <= maxWarningLength)
          item.trim(),
    ];
  }

  static image.ImageParams _paramsWithCharacters(
    image.ImageParams params,
    List<RecipeCharacter> characters,
  ) {
    final converted = [
      for (final character in characters)
        if (character.enabled)
          image.CharacterPrompt(
            prompt: character.prompt,
            negativePrompt: character.negativePrompt,
            positionX: character.center.x,
            positionY: character.center.y,
            position: null,
          ),
    ];
    return params.copyWith(
      characters: converted,
      useCoords: converted.isNotEmpty,
    );
  }

  static String _stripCodeFence(String value) {
    final match = RegExp(
      r'^```(?:json)?\s*([\s\S]*?)\s*```$',
      caseSensitive: false,
    ).firstMatch(value);
    return match?.group(1)?.trim() ?? value;
  }
}
