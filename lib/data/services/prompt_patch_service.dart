import '../models/image/image_params.dart';
import '../models/recipe/prompt_recipe.dart';

/// Lock policy used when validating assistant- or user-authored Prompt Patch
/// operations. The strict policy mirrors the safety defaults of the web
/// workbench: identity, style, pose, generation parameters and references are
/// protected unless the user explicitly asks to change them.
class PromptPatchLockPolicy {
  const PromptPatchLockPolicy({
    this.characterIdentity = true,
    this.characterCore = true,
    this.lockedTraits = true,
    this.pose = true,
    this.composition = true,
    this.style = true,
    this.generationParameters = true,
    this.references = true,
  });

  static const strict = PromptPatchLockPolicy();

  final bool characterIdentity;
  final bool characterCore;
  final bool lockedTraits;
  final bool pose;
  final bool composition;
  final bool style;
  final bool generationParameters;
  final bool references;
}

enum PromptPatchIssueCode { invalid, locked, notFound, conflict }

class PromptPatchValidationIssue {
  const PromptPatchValidationIssue({
    required this.operationId,
    required this.code,
    required this.message,
  });

  final String operationId;
  final PromptPatchIssueCode code;
  final String message;
}

class PromptPatchValidation {
  PromptPatchValidation({
    required Iterable<PromptPatchOperation> valid,
    required Iterable<PromptPatchValidationIssue> issues,
  }) : valid = List.unmodifiable(valid),
       issues = List.unmodifiable(issues);

  final List<PromptPatchOperation> valid;
  final List<PromptPatchValidationIssue> issues;

  bool get isValid => issues.isEmpty;
}

class PromptPatchException implements Exception {
  PromptPatchException(this.validation);

  final PromptPatchValidation validation;

  @override
  String toString() {
    final details = validation.issues.map((issue) => issue.message).join('；');
    return details.isEmpty ? 'Prompt Patch 无法应用' : details;
  }
}

/// Result of applying a validated patch to a recipe.
///
/// [recipe] is a new child version; the input recipe is never mutated. The
/// inverse operations are ordered so they can be submitted to [apply] again
/// to return to the previous version.
class AppliedPromptPatch {
  AppliedPromptPatch({
    required this.recipe,
    required Iterable<PromptPatchOperation> applied,
    required Iterable<PromptPatchOperation> inverse,
  }) : applied = List.unmodifiable(applied),
       inverse = List.unmodifiable(inverse);

  final PromptRecipe recipe;
  final List<PromptPatchOperation> applied;
  final List<PromptPatchOperation> inverse;
}

/// Pure Prompt Patch validation and application service.
///
/// Keeping this layer independent from Riverpod and widgets makes it safe to
/// reuse from a future workbench, batch queue, or agent approval surface.
class PromptPatchService {
  const PromptPatchService._();

  static const Set<String> _supportedParameterFields = {
    'model',
    'width',
    'height',
    'steps',
    'seed',
    'sampler',
    'scale',
    'cfg',
    'cfgRescale',
    'qualityToggle',
    'qualityTier',
    'ucPreset',
    'transparentBackground',
  };

  static const Set<String> _referenceFields = {
    'imageToImage',
    'sourceImage',
    'maskImage',
    'vibeTransfers',
    'preciseReferences',
  };

  static const Set<String> _operations = {
    'add',
    'remove',
    'replace',
    'move',
    'keep',
    'parameter',
  };

  /// Validates operations without mutating [recipe]. Invalid operations are
  /// excluded from [PromptPatchValidation.valid] so callers can display a
  /// review list and apply only after all issues have been resolved.
  static PromptPatchValidation validate(
    PromptRecipe recipe,
    Iterable<PromptPatchOperation> operations, {
    PromptPatchLockPolicy policy = PromptPatchLockPolicy.strict,
  }) {
    final valid = <PromptPatchOperation>[];
    final issues = <PromptPatchValidationIssue>[];
    final claimedTokens = <String>{};
    final operationIds = <String>{};
    var simulatedParams = recipe.request.params;
    var simulatedCharacters = List<RecipeCharacter>.from(recipe.characters);

    void accept(PromptPatchOperation operation) {
      valid.add(operation);
      if (operation.op == 'keep') return;
      if (operation.op == 'parameter') {
        simulatedParams = _applyParameter(
          simulatedParams,
          operation.target.substring('request:'.length),
          operation.after,
        );
        return;
      }
      final current = _textForTarget(
        simulatedParams,
        simulatedCharacters,
        operation.target,
      );
      if (current == null) return;
      final mutation = _mutateText(current, operation);
      final updated = _setText(
        simulatedParams,
        simulatedCharacters,
        operation.target,
        mutation.value,
      );
      simulatedParams = updated.params;
      simulatedCharacters = updated.characters;
    }

    void fail(
      PromptPatchOperation operation,
      PromptPatchIssueCode code,
      String message,
    ) {
      issues.add(
        PromptPatchValidationIssue(
          operationId: operation.id,
          code: code,
          message: message,
        ),
      );
    }

    for (final operation in operations) {
      if (!operationIds.add(operation.id)) {
        fail(
          operation,
          PromptPatchIssueCode.conflict,
          '提案中不能重复使用同一个操作 ID：${operation.id}',
        );
        continue;
      }
      if (operation.id.trim().isEmpty ||
          operation.reason.trim().isEmpty ||
          !_isConfidenceValid(operation.confidence) ||
          !_operations.contains(operation.op)) {
        fail(
          operation,
          PromptPatchIssueCode.invalid,
          '操作缺少 ID、原因、有效置信度或使用了不支持的类型',
        );
        continue;
      }

      final target = operation.target.trim();
      if (target.isEmpty) {
        fail(operation, PromptPatchIssueCode.invalid, '操作目标不能为空');
        continue;
      }

      if (target.startsWith('request:')) {
        final field = target.substring('request:'.length);
        if (operation.op != 'parameter') {
          fail(
            operation,
            PromptPatchIssueCode.invalid,
            'request 目标只能使用 parameter 操作',
          );
          continue;
        }
        if (_referenceFields.contains(field)) {
          final code = policy.references && !operation.explicit
              ? PromptPatchIssueCode.locked
              : PromptPatchIssueCode.invalid;
          fail(
            operation,
            code,
            code == PromptPatchIssueCode.locked
                ? '参考图默认锁定，只有用户明确点名时才能修改'
                : '二进制参考输入不能通过 Prompt Patch 修改，请在编辑器中重新挂载',
          );
          continue;
        }
        if (!_supportedParameterFields.contains(field)) {
          fail(operation, PromptPatchIssueCode.invalid, '不支持的生成参数字段：$field');
          continue;
        }
        final parameterIssue = _validateParameterValue(field, operation.after);
        if (parameterIssue != null) {
          fail(operation, PromptPatchIssueCode.invalid, parameterIssue);
          continue;
        }
        if (policy.generationParameters && !operation.explicit) {
          fail(
            operation,
            PromptPatchIssueCode.locked,
            '生成参数默认锁定，只有用户明确点名时才能修改',
          );
          continue;
        }
        accept(operation);
        continue;
      }

      if (operation.op == 'parameter') {
        fail(
          operation,
          PromptPatchIssueCode.invalid,
          'parameter 操作必须指向 request:<字段>',
        );
        continue;
      }

      RecipeCharacter? character;
      if (target == 'main' || target == 'negative') {
        character = null;
      } else if (target.startsWith('character:')) {
        final characterId = target.substring('character:'.length);
        character = _findCharacter(simulatedCharacters, characterId);
        if (character == null) {
          fail(
            operation,
            PromptPatchIssueCode.notFound,
            '找不到目标角色：$characterId',
          );
          continue;
        }
      } else {
        fail(operation, PromptPatchIssueCode.invalid, '不支持的 Prompt 目标：$target');
        continue;
      }

      final category = operation.category?.trim().toLowerCase();
      if (operation.op != 'keep' && !operation.explicit) {
        if (category == 'pose' && policy.pose) {
          fail(operation, PromptPatchIssueCode.locked, '姿势当前已锁定');
          continue;
        }
        if (category == 'composition' && policy.composition) {
          fail(operation, PromptPatchIssueCode.locked, '构图当前已锁定');
          continue;
        }
        if (category == 'style' && policy.style) {
          fail(operation, PromptPatchIssueCode.locked, '风格当前已锁定');
          continue;
        }
      }

      if (character != null && operation.op != 'keep' && !operation.explicit) {
        final before = _stringValue(operation.before);
        final afterTokens = _splitPrompt(_stringValue(operation.after));
        final inspectedTokens = <String>[
          if (before != null) before,
          ...afterTokens,
        ];
        if (policy.characterIdentity &&
            inspectedTokens.any(
              (token) => _isIdentityToken(character!, token),
            )) {
          fail(operation, PromptPatchIssueCode.locked, '角色身份当前已锁定');
          continue;
        }
        if (policy.characterCore &&
            character.corePrompt != null &&
            inspectedTokens.any(
              (token) => _containsToken(character!.corePrompt!, token),
            )) {
          fail(operation, PromptPatchIssueCode.locked, 'Character Core 当前已锁定');
          continue;
        }
        if (policy.lockedTraits &&
            character.lockedTraits != null &&
            inspectedTokens.any(
              (token) => character!.lockedTraits!.any(
                (trait) => _sameToken(trait, token),
              ),
            )) {
          fail(operation, PromptPatchIssueCode.locked, 'Locked Trait 当前已锁定');
          continue;
        }
      }

      if (operation.op == 'add') {
        if (_splitPrompt(_stringValue(operation.after)).isEmpty) {
          fail(operation, PromptPatchIssueCode.invalid, 'add 操作必须提供 after');
          continue;
        }
        accept(operation);
        continue;
      }

      if (operation.op == 'keep') {
        accept(operation);
        continue;
      }

      final before = _stringValue(operation.before);
      if (before == null || before.trim().isEmpty) {
        fail(operation, PromptPatchIssueCode.invalid, '操作必须提供 before');
        continue;
      }
      final claim = '$target:${_normalizeToken(before)}';
      if (claimedTokens.contains(claim)) {
        fail(
          operation,
          PromptPatchIssueCode.conflict,
          '同一词条不能在一份提案中被重复修改：$before',
        );
        continue;
      }
      final current = _textForTarget(
        simulatedParams,
        simulatedCharacters,
        target,
      );
      if (current == null || !_containsToken(current, before)) {
        fail(
          operation,
          PromptPatchIssueCode.notFound,
          '当前 Prompt 中找不到独立词条：$before',
        );
        continue;
      }
      claimedTokens.add(claim);

      if (operation.op == 'replace' &&
          _splitPrompt(_stringValue(operation.after)).isEmpty) {
        fail(operation, PromptPatchIssueCode.invalid, 'replace 操作必须提供 after');
        continue;
      }
      if (operation.op == 'move' && !_isInteger(operation.after)) {
        fail(operation, PromptPatchIssueCode.invalid, 'move 操作的 after 必须是整数索引');
        continue;
      }
      accept(operation);
    }

    return PromptPatchValidation(valid: valid, issues: issues);
  }

  /// Applies a validated patch and returns a new child recipe plus inverse
  /// operations. The original recipe and all of its lists remain untouched.
  static AppliedPromptPatch apply(
    PromptRecipe recipe,
    Iterable<PromptPatchOperation> operations, {
    PromptPatchLockPolicy policy = PromptPatchLockPolicy.strict,
    String? id,
    DateTime? createdAt,
  }) {
    final validation = validate(recipe, operations, policy: policy);
    if (!validation.isValid) throw PromptPatchException(validation);

    var params = recipe.request.params;
    var characters = List<RecipeCharacter>.from(recipe.characters);
    final applied = <PromptPatchOperation>[];
    final inverse = <PromptPatchOperation>[];
    var promptChanged = false;

    for (final operation in validation.valid) {
      applied.add(operation);
      if (operation.op == 'keep') continue;

      if (operation.op == 'parameter') {
        final field = operation.target.substring('request:'.length);
        final previous = _parameterValue(params, field);
        params = _applyParameter(params, field, operation.after);
        inverse.insert(
          0,
          _inverseOperation(
            operation,
            op: 'parameter',
            before: operation.after,
            after: previous,
          ),
        );
        continue;
      }

      final target = operation.target;
      final current = _textForTarget(params, characters, target)!;
      final mutation = _mutateText(current, operation);
      final updated = _setText(params, characters, target, mutation.value);
      params = updated.params;
      characters = updated.characters;
      promptChanged = promptChanged || target == 'main' || target == 'negative';
      inverse.insertAll(
        0,
        mutation.inverse
            .map(
              (item) => _inverseOperation(
                operation,
                op: item.op,
                before: item.before,
                after: item.after,
              ),
            )
            .toList(),
      );
    }

    final child = PromptRecipe.create(
      id: id,
      parentRecipeId: recipe.id,
      sourceGalleryItemId: recipe.sourceGalleryItemId,
      params: params,
      characters: characters,
      mainPromptEntries: promptChanged ? const [] : recipe.mainPromptEntries,
      structuredMain: promptChanged
          ? StructuredPrompt.empty()
          : recipe.structuredMain,
      userInstruction: recipe.userInstruction,
      retrievalEvidence: recipe.retrievalEvidence,
      proposedPatch: const [],
      acceptedPatch: [...recipe.acceptedPatch, ...applied],
      provider: recipe.provider,
      providerModel: recipe.providerModel,
      imageToImage: recipe.request.imageToImage,
      preciseReferences: recipe.request.preciseReferences,
      vibeTransfers: recipe.request.vibeTransfers,
      createdAt: createdAt,
    );
    return AppliedPromptPatch(
      recipe: child,
      applied: applied,
      inverse: inverse,
    );
  }

  static RecipeCharacter? _findCharacter(
    List<RecipeCharacter> characters,
    String id,
  ) {
    for (final character in characters) {
      if (character.id == id) return character;
    }
    return null;
  }

  static String? _textForTarget(
    ImageParams params,
    List<RecipeCharacter> characters,
    String target,
  ) {
    if (target == 'main') return params.prompt;
    if (target == 'negative') return params.negativePrompt;
    if (target.startsWith('character:')) {
      return _findCharacter(
        characters,
        target.substring('character:'.length),
      )?.prompt;
    }
    return null;
  }

  static ({ImageParams params, List<RecipeCharacter> characters}) _setText(
    ImageParams params,
    List<RecipeCharacter> characters,
    String target,
    String value,
  ) {
    if (target == 'main') {
      return (params: params.copyWith(prompt: value), characters: characters);
    }
    if (target == 'negative') {
      return (
        params: params.copyWith(negativePrompt: value),
        characters: characters,
      );
    }
    final characterId = target.substring('character:'.length);
    final updated = characters
        .map((character) {
          if (character.id != characterId) return character;
          return _copyCharacter(character, prompt: value);
        })
        .toList(growable: false);
    return (params: params, characters: updated);
  }

  static RecipeCharacter _copyCharacter(
    RecipeCharacter character, {
    String? prompt,
  }) {
    return RecipeCharacter(
      id: character.id,
      profileId: character.profileId,
      name: character.name,
      gender: character.gender,
      hairColor: character.hairColor,
      hairstyle: character.hairstyle,
      eyeColor: character.eyeColor,
      body: character.body,
      fixedFeatures: character.fixedFeatures,
      defaultClothing: character.defaultClothing,
      corePrompt: character.corePrompt,
      prompt: prompt ?? character.prompt,
      lockedTraits: character.lockedTraits,
      negativePrompt: character.negativePrompt,
      negativeTraits: character.negativeTraits,
      seed: character.seed,
      referenceAssetIds: character.referenceAssetIds,
      sourceGalleryItemIds: character.sourceGalleryItemIds,
      enabled: character.enabled,
      center: character.center,
    );
  }

  static Object? _parameterValue(ImageParams params, String field) {
    return switch (field) {
      'model' => params.model,
      'width' => params.width,
      'height' => params.height,
      'steps' => params.steps,
      'seed' => params.seed,
      'sampler' => params.sampler,
      'scale' || 'cfg' => params.scale,
      'cfgRescale' => params.cfgRescale,
      'qualityToggle' => params.qualityToggle,
      'qualityTier' => params.qualityTier,
      'ucPreset' => params.ucPreset,
      'transparentBackground' => params.transparentBackground,
      _ => null,
    };
  }

  static ImageParams _applyParameter(
    ImageParams params,
    String field,
    Object? value,
  ) {
    return switch (field) {
      'model' => params.copyWith(model: value! as String),
      'width' => params.copyWith(width: (value! as num).toInt()),
      'height' => params.copyWith(height: (value! as num).toInt()),
      'steps' => params.copyWith(steps: (value! as num).toInt()),
      'seed' => params.copyWith(seed: (value! as num).toInt()),
      'sampler' => params.copyWith(sampler: value! as String),
      'scale' || 'cfg' => params.copyWith(scale: (value! as num).toDouble()),
      'cfgRescale' => params.copyWith(cfgRescale: (value! as num).toDouble()),
      'qualityToggle' => params.copyWith(qualityToggle: value! as bool),
      'qualityTier' => params.copyWith(qualityTier: value! as String),
      'ucPreset' => params.copyWith(ucPreset: (value! as num).toInt()),
      'transparentBackground' => params.copyWith(
        transparentBackground: value! as bool,
      ),
      _ => params,
    };
  }

  static String? _validateParameterValue(String field, Object? value) {
    switch (field) {
      case 'model' || 'sampler' || 'qualityTier':
        if (value is! String || value.trim().isEmpty) {
          return '$field 必须是非空字符串';
        }
      case 'width' || 'height' || 'steps':
        if (!_isInteger(value) || (value! as num).toInt() <= 0) {
          return '$field 必须是正整数';
        }
      case 'seed':
        if (!_isInteger(value) || (value! as num).toInt() < -1) {
          return 'seed 必须是不小于 -1 的整数';
        }
      case 'scale' || 'cfg' || 'cfgRescale':
        if (!_isFiniteNumber(value) || (value! as num).toDouble() < 0) {
          return '$field 必须是不小于 0 的数字';
        }
      case 'ucPreset':
        if (!_isInteger(value) || (value! as num).toInt() < 0) {
          return 'ucPreset 必须是不小于 0 的整数';
        }
      case 'qualityToggle' || 'transparentBackground':
        if (value is! bool) return '$field 必须是布尔值';
    }
    return null;
  }

  static _TextMutation _mutateText(
    String current,
    PromptPatchOperation operation,
  ) {
    final tokens = List<String>.from(_splitPrompt(current));
    final before = _stringValue(operation.before);
    final afterTokens = _splitPrompt(_stringValue(operation.after));
    final index = before == null
        ? -1
        : tokens.indexWhere((token) => _sameToken(token, before));

    switch (operation.op) {
      case 'add':
        final existing = tokens.map(_normalizeToken).toSet();
        final additions = afterTokens
            .where((token) => existing.add(_normalizeToken(token)))
            .toList(growable: false);
        tokens.addAll(additions);
        return _TextMutation(
          value: _joinPrompt(tokens),
          inverse: [
            for (final token in additions.reversed)
              _TextInverseOperation(op: 'remove', before: token),
          ],
        );
      case 'remove':
        final removed = tokens.removeAt(index);
        return _TextMutation(
          value: _joinPrompt(tokens),
          inverse: [
            _TextInverseOperation(op: 'add', after: removed),
            _TextInverseOperation(op: 'move', before: removed, after: index),
          ],
        );
      case 'replace':
        final old = tokens[index];
        tokens.removeAt(index);
        tokens.insertAll(index, afterTokens);
        final inverse = <_TextInverseOperation>[];
        if (afterTokens.length == 1) {
          inverse.add(
            _TextInverseOperation(
              op: 'replace',
              before: afterTokens.single,
              after: old,
            ),
          );
        } else {
          for (final token in afterTokens.reversed) {
            inverse.add(_TextInverseOperation(op: 'remove', before: token));
          }
          inverse.add(_TextInverseOperation(op: 'add', after: old));
          inverse.add(
            _TextInverseOperation(op: 'move', before: old, after: index),
          );
        }
        return _TextMutation(value: _joinPrompt(tokens), inverse: inverse);
      case 'move':
        final moved = tokens.removeAt(index);
        final requested = (operation.after! as num).toInt();
        final destination = requested.clamp(0, tokens.length).toInt();
        tokens.insert(destination, moved);
        return _TextMutation(
          value: _joinPrompt(tokens),
          inverse: [
            _TextInverseOperation(op: 'move', before: moved, after: index),
          ],
        );
      case 'keep':
        return _TextMutation(value: current, inverse: const []);
      case 'parameter':
        throw StateError('parameter is not a text operation');
    }
    throw StateError('Unsupported Prompt Patch operation: ${operation.op}');
  }

  static PromptPatchOperation _inverseOperation(
    PromptPatchOperation source, {
    required String op,
    Object? before,
    Object? after,
  }) {
    return PromptPatchOperation(
      id: '${source.id}:inverse:${op}_${before ?? after ?? ''}',
      op: op,
      target: source.target,
      category: source.category,
      before: before,
      after: after,
      reason: '撤销 ${source.id}',
      evidenceIds: const [],
      confidence: 1,
      explicit: true,
    );
  }

  static bool _isConfidenceValid(double value) =>
      value.isFinite && value >= 0 && value <= 1;

  static bool _isFiniteNumber(Object? value) =>
      value is num && value.toDouble().isFinite;

  static bool _isInteger(Object? value) =>
      _isFiniteNumber(value) &&
      (value! as num).toDouble().truncateToDouble() ==
          (value as num).toDouble();

  static String? _stringValue(Object? value) => value is String ? value : null;

  static bool _containsToken(String prompt, String token) =>
      _splitPrompt(prompt).any((item) => _sameToken(item, token));

  static bool _isIdentityToken(RecipeCharacter character, String token) {
    final normalized = _normalizeToken(token);
    final genderToken = switch (character.gender?.toLowerCase()) {
      'female' => '1girl',
      'male' => '1boy',
      _ => null,
    };
    return genderToken != null && normalized == genderToken;
  }

  static List<String> _splitPrompt(String? value) {
    if (value == null) return const [];
    return value
        .split(RegExp(r'[,，\n]+'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  static String _joinPrompt(Iterable<String> values) {
    final seen = <String>{};
    return values
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty && seen.add(_normalizeToken(value)))
        .join(', ');
  }

  static String _normalizeToken(String value) => value
      .trim()
      .replaceFirst(RegExp(r'^\{+'), '')
      .replaceFirst(RegExp(r'\}+$'), '')
      .replaceAll('_', ' ')
      .toLowerCase();

  static bool _sameToken(String left, String right) =>
      _normalizeToken(left) == _normalizeToken(right);
}

class _TextMutation {
  const _TextMutation({required this.value, required this.inverse});

  final String value;
  final List<_TextInverseOperation> inverse;
}

class _TextInverseOperation {
  const _TextInverseOperation({required this.op, this.before, this.after});

  final String op;
  final Object? before;
  final Object? after;
}
