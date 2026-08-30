import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../image/image_params.dart';
import '../vibe/vibe_reference.dart';

/// Client-side semantic information for one prompt token.
///
/// This is deliberately kept separate from [ImageParams]: NovelAI receives a
/// flat prompt string, while the editor needs stable ids and categories that
/// survive formatting and recipe reuse.
class PromptSemanticEntry {
  const PromptSemanticEntry({
    required this.id,
    required this.text,
    required this.category,
    required this.source,
    required this.localTagHit,
    required this.confidence,
    required this.kind,
  });

  final String id;
  final String text;
  final String category;
  final String source;
  final bool localTagHit;
  final double confidence;
  final String kind;

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'category': category,
    'source': source,
    'localTagHit': localTagHit,
    'confidence': confidence,
    'kind': kind,
  };

  factory PromptSemanticEntry.fromJson(Object? value) {
    final map = _asMap(value, 'prompt semantic entry');
    _rejectUnknownFields(map, const {
      'id',
      'text',
      'category',
      'source',
      'localTagHit',
      'confidence',
      'kind',
    }, 'prompt semantic entry');
    final id = _requiredString(map, 'id', 'prompt semantic entry');
    final text = _requiredString(map, 'text', 'prompt semantic entry');
    final category = _requiredString(map, 'category', 'prompt semantic entry');
    final source = _requiredString(map, 'source', 'prompt semantic entry');
    final localTagHit = map['localTagHit'];
    final confidence = map['confidence'];
    final kind = _requiredString(map, 'kind', 'prompt semantic entry');
    if (localTagHit is! bool || confidence is! num) {
      throw const FormatException('Invalid prompt semantic entry types.');
    }
    final confidenceValue = confidence.toDouble();
    if (confidenceValue.isNaN ||
        confidenceValue.isInfinite ||
        confidenceValue < 0 ||
        confidenceValue > 1) {
      throw const FormatException('Prompt semantic confidence must be 0..1.');
    }
    return PromptSemanticEntry(
      id: id,
      text: text,
      category: category,
      source: source,
      localTagHit: localTagHit,
      confidence: confidenceValue,
      kind: kind,
    );
  }
}

/// Structured prompt buckets used by the prompt workbench.
class StructuredPrompt {
  StructuredPrompt({Map<String, List<String>> fields = const {}})
    : fields = _normalizeStructuredFields(fields);

  factory StructuredPrompt.empty() => StructuredPrompt(
    fields: {for (final field in structuredPromptFields) field: const []},
  );

  factory StructuredPrompt.fromJson(Object? value) {
    final map = _asMap(value, 'structured prompt');
    _rejectUnknownFields(
      map,
      structuredPromptFields.toSet(),
      'structured prompt',
    );
    final fields = <String, List<String>>{};
    for (final field in structuredPromptFields) {
      final raw = map[field];
      if (raw == null) {
        fields[field] = const [];
        continue;
      }
      if (raw is! List || raw.any((item) => item is! String)) {
        throw FormatException(
          'Structured prompt field "$field" must be a list of strings.',
        );
      }
      fields[field] = List<String>.unmodifiable(raw.cast<String>());
    }
    return StructuredPrompt(fields: fields);
  }

  static const List<String> structuredPromptFields = [
    'quality',
    'subject',
    'appearance',
    'clothing',
    'pose',
    'adult',
    'scene',
    'lighting',
    'camera',
    'style',
    'negative',
  ];

  final Map<String, List<String>> fields;

  List<String> operator [](String field) => fields[field] ?? const [];

  Map<String, dynamic> toJson() => {
    for (final field in structuredPromptFields)
      field: List<String>.from(this[field]),
  };

  StructuredPrompt copyWith({Map<String, List<String>>? fields}) =>
      StructuredPrompt(fields: fields ?? this.fields);
}

/// Evidence used by an assistant or local catalog to explain a prompt edit.
class RetrievalEvidence {
  const RetrievalEvidence({
    required this.id,
    required this.source,
    required this.query,
    this.tag,
    this.zh,
    this.category,
    this.score,
    this.postCount,
    this.description,
  });

  final String id;
  final String source;
  final String query;
  final String? tag;
  final String? zh;
  final String? category;
  final double? score;
  final int? postCount;
  final String? description;

  Map<String, dynamic> toJson() => {
    'id': id,
    'source': source,
    'query': query,
    if (tag != null) 'tag': tag,
    if (zh != null) 'zh': zh,
    if (category != null) 'category': category,
    if (score != null) 'score': score,
    if (postCount != null) 'postCount': postCount,
    if (description != null) 'description': description,
  };

  factory RetrievalEvidence.fromJson(Object? value) {
    final map = _asMap(value, 'retrieval evidence');
    _rejectUnknownFields(map, const {
      'id',
      'source',
      'query',
      'tag',
      'zh',
      'category',
      'score',
      'postCount',
      'description',
    }, 'retrieval evidence');
    final score = map['score'];
    final postCount = map['postCount'];
    if (score != null && score is! num ||
        postCount != null && postCount is! int) {
      throw const FormatException('Invalid retrieval evidence numeric fields.');
    }
    return RetrievalEvidence(
      id: _requiredString(map, 'id', 'retrieval evidence'),
      source: _requiredString(map, 'source', 'retrieval evidence'),
      query: _requiredString(map, 'query', 'retrieval evidence'),
      tag: _optionalString(map, 'tag', 'retrieval evidence'),
      zh: _optionalString(map, 'zh', 'retrieval evidence'),
      category: _optionalString(map, 'category', 'retrieval evidence'),
      score: (score as num?)?.toDouble(),
      postCount: postCount as int?,
      description: _optionalString(map, 'description', 'retrieval evidence'),
    );
  }
}

/// Character data carried by a recipe.
///
/// The generation API currently only needs prompt/negativePrompt/position,
/// but keeping the reusable identity fields here lets the future profile UI
/// restore a recipe without silently losing identity constraints.
class RecipeCharacter {
  const RecipeCharacter({
    required this.id,
    required this.name,
    required this.prompt,
    required this.negativePrompt,
    required this.enabled,
    required this.center,
    this.profileId,
    this.gender,
    this.hairColor,
    this.hairstyle,
    this.eyeColor,
    this.body,
    this.fixedFeatures,
    this.defaultClothing,
    this.corePrompt,
    this.lockedTraits,
    this.negativeTraits,
    this.seed,
    this.referenceAssetIds,
    this.sourceGalleryItemIds,
  });

  final String id;
  final String? profileId;
  final String name;
  final String? gender;
  final List<String>? hairColor;
  final List<String>? hairstyle;
  final List<String>? eyeColor;
  final List<String>? body;
  final List<String>? fixedFeatures;
  final List<String>? defaultClothing;
  final String? corePrompt;
  final String prompt;
  final List<String>? lockedTraits;
  final String negativePrompt;
  final List<String>? negativeTraits;
  final int? seed;
  final List<String>? referenceAssetIds;
  final List<String>? sourceGalleryItemIds;
  final bool enabled;
  final RecipeCharacterCenter center;

  Map<String, dynamic> toJson() => {
    'id': id,
    if (profileId != null) 'profileId': profileId,
    'name': name,
    if (gender != null) 'gender': gender,
    if (hairColor != null) 'hairColor': hairColor,
    if (hairstyle != null) 'hairstyle': hairstyle,
    if (eyeColor != null) 'eyeColor': eyeColor,
    if (body != null) 'body': body,
    if (fixedFeatures != null) 'fixedFeatures': fixedFeatures,
    if (defaultClothing != null) 'defaultClothing': defaultClothing,
    if (corePrompt != null) 'corePrompt': corePrompt,
    'prompt': prompt,
    if (lockedTraits != null) 'lockedTraits': lockedTraits,
    'negativePrompt': negativePrompt,
    if (negativeTraits != null) 'negativeTraits': negativeTraits,
    if (seed != null) 'seed': seed,
    if (referenceAssetIds != null) 'referenceAssetIds': referenceAssetIds,
    if (sourceGalleryItemIds != null)
      'sourceGalleryItemIds': sourceGalleryItemIds,
    'enabled': enabled,
    'center': center.toJson(),
  };

  factory RecipeCharacter.fromJson(Object? value) {
    final map = _asMap(value, 'recipe character');
    _rejectUnknownFields(map, const {
      'id',
      'profileId',
      'name',
      'gender',
      'hairColor',
      'hairstyle',
      'eyeColor',
      'body',
      'fixedFeatures',
      'defaultClothing',
      'corePrompt',
      'prompt',
      'lockedTraits',
      'negativePrompt',
      'negativeTraits',
      'seed',
      'referenceAssetIds',
      'sourceGalleryItemIds',
      'enabled',
      'center',
    }, 'recipe character');
    final enabled = map['enabled'];
    final seed = map['seed'];
    if (enabled is! bool || seed != null && seed is! int) {
      throw const FormatException('Invalid recipe character flags.');
    }
    return RecipeCharacter(
      id: _requiredString(map, 'id', 'recipe character'),
      profileId: _optionalString(map, 'profileId', 'recipe character'),
      name: _requiredString(map, 'name', 'recipe character'),
      gender: _optionalString(map, 'gender', 'recipe character'),
      hairColor: _optionalStringList(map, 'hairColor', 'recipe character'),
      hairstyle: _optionalStringList(map, 'hairstyle', 'recipe character'),
      eyeColor: _optionalStringList(map, 'eyeColor', 'recipe character'),
      body: _optionalStringList(map, 'body', 'recipe character'),
      fixedFeatures: _optionalStringList(
        map,
        'fixedFeatures',
        'recipe character',
      ),
      defaultClothing: _optionalStringList(
        map,
        'defaultClothing',
        'recipe character',
      ),
      corePrompt: _optionalString(map, 'corePrompt', 'recipe character'),
      prompt: _requiredString(
        map,
        'prompt',
        'recipe character',
        allowEmpty: true,
      ),
      lockedTraits: _optionalStringList(
        map,
        'lockedTraits',
        'recipe character',
      ),
      negativePrompt: _requiredString(
        map,
        'negativePrompt',
        'recipe character',
        allowEmpty: true,
      ),
      negativeTraits: _optionalStringList(
        map,
        'negativeTraits',
        'recipe character',
      ),
      seed: seed as int?,
      referenceAssetIds: _optionalStringList(
        map,
        'referenceAssetIds',
        'recipe character',
      ),
      sourceGalleryItemIds: _optionalStringList(
        map,
        'sourceGalleryItemIds',
        'recipe character',
      ),
      enabled: enabled,
      center: RecipeCharacterCenter.fromJson(map['center']),
    );
  }
}

class RecipeCharacterCenter {
  const RecipeCharacterCenter({required this.x, required this.y});

  final double x;
  final double y;

  Map<String, dynamic> toJson() => {'x': x, 'y': y};

  factory RecipeCharacterCenter.fromJson(Object? value) {
    final map = _asMap(value, 'recipe character center');
    _rejectUnknownFields(map, const {'x', 'y'}, 'recipe character center');
    final x = map['x'];
    final y = map['y'];
    if (x is! num || y is! num) {
      throw const FormatException('Recipe character center must contain x/y.');
    }
    final center = RecipeCharacterCenter(x: x.toDouble(), y: y.toDouble());
    if (!center.x.isFinite || !center.y.isFinite) {
      throw const FormatException('Recipe character center must be finite.');
    }
    return center;
  }
}

/// Metadata-only image-to-image input.
///
/// The source bytes are intentionally never part of this model. A missing
/// [sourceGalleryItemId] is represented explicitly by [unavailable].
class RecipeImageInputSnapshot {
  const RecipeImageInputSnapshot({
    required this.mimeType,
    required this.filename,
    required this.strength,
    required this.noise,
    this.sourceGalleryItemId,
    this.unavailable = false,
  });

  final String? sourceGalleryItemId;
  final String mimeType;
  final String filename;
  final double strength;
  final double noise;
  final bool unavailable;

  Map<String, dynamic> toJson() => {
    if (sourceGalleryItemId != null) 'sourceGalleryItemId': sourceGalleryItemId,
    'mimeType': mimeType,
    'filename': filename,
    'strength': strength,
    'noise': noise,
    'unavailable': unavailable,
  };

  factory RecipeImageInputSnapshot.fromJson(Object? value) {
    final map = _asMap(value, 'recipe image input');
    _rejectUnknownFields(map, const {
      'sourceGalleryItemId',
      'mimeType',
      'filename',
      'strength',
      'noise',
      'unavailable',
    }, 'recipe image input');
    final strength = map['strength'];
    final noise = map['noise'];
    final unavailable = map['unavailable'];
    if (strength is! num || noise is! num || unavailable is! bool) {
      throw const FormatException('Invalid recipe image input fields.');
    }
    return RecipeImageInputSnapshot(
      sourceGalleryItemId: _optionalString(
        map,
        'sourceGalleryItemId',
        'recipe image input',
      ),
      mimeType: _requiredString(map, 'mimeType', 'recipe image input'),
      filename: _requiredString(map, 'filename', 'recipe image input'),
      strength: strength.toDouble(),
      noise: noise.toDouble(),
      unavailable: unavailable,
    );
  }
}

/// Metadata-only Precise Reference input.
class RecipePreciseReferenceSnapshot {
  const RecipePreciseReferenceSnapshot({
    required this.mimeType,
    required this.filename,
    required this.type,
    required this.strength,
    required this.fidelity,
    this.id,
    this.sourceAssetId,
    this.unavailable = false,
  });

  final String? id;
  final String? sourceAssetId;
  final String mimeType;
  final String filename;
  final String type;
  final double strength;
  final double fidelity;
  final bool unavailable;

  Map<String, dynamic> toJson() => {
    if (id != null) 'id': id,
    if (sourceAssetId != null) 'sourceAssetId': sourceAssetId,
    'mimeType': mimeType,
    'filename': filename,
    'type': type,
    'strength': strength,
    'fidelity': fidelity,
    'unavailable': unavailable,
  };

  factory RecipePreciseReferenceSnapshot.fromJson(Object? value) {
    final map = _asMap(value, 'recipe precise reference');
    _rejectUnknownFields(map, const {
      'id',
      'sourceAssetId',
      'mimeType',
      'filename',
      'type',
      'strength',
      'fidelity',
      'unavailable',
    }, 'recipe precise reference');
    final strength = map['strength'];
    final fidelity = map['fidelity'];
    final unavailable = map['unavailable'];
    if (strength is! num || fidelity is! num || unavailable is! bool) {
      throw const FormatException('Invalid recipe precise reference fields.');
    }
    return RecipePreciseReferenceSnapshot(
      id: _optionalString(map, 'id', 'recipe precise reference'),
      sourceAssetId: _optionalString(
        map,
        'sourceAssetId',
        'recipe precise reference',
      ),
      mimeType: _requiredString(map, 'mimeType', 'recipe precise reference'),
      filename: _requiredString(map, 'filename', 'recipe precise reference'),
      type: _requiredString(map, 'type', 'recipe precise reference'),
      strength: strength.toDouble(),
      fidelity: fidelity.toDouble(),
      unavailable: unavailable,
    );
  }
}

/// Metadata-only Vibe Transfer input.
class RecipeVibeTransferSnapshot {
  const RecipeVibeTransferSnapshot({
    required this.id,
    required this.mimeType,
    required this.filename,
    required this.strength,
    required this.informationExtracted,
    this.sourceAssetId,
    this.unavailable = false,
  });

  final String id;
  final String? sourceAssetId;
  final String mimeType;
  final String filename;
  final double strength;
  final double informationExtracted;
  final bool unavailable;

  Map<String, dynamic> toJson() => {
    'id': id,
    if (sourceAssetId != null) 'sourceAssetId': sourceAssetId,
    'mimeType': mimeType,
    'filename': filename,
    'strength': strength,
    'informationExtracted': informationExtracted,
    'unavailable': unavailable,
  };

  factory RecipeVibeTransferSnapshot.fromJson(Object? value) {
    final map = _asMap(value, 'recipe Vibe transfer');
    _rejectUnknownFields(map, const {
      'id',
      'sourceAssetId',
      'mimeType',
      'filename',
      'strength',
      'informationExtracted',
      'unavailable',
    }, 'recipe Vibe transfer');
    final strength = map['strength'];
    final informationExtracted = map['informationExtracted'];
    final unavailable = map['unavailable'];
    if (strength is! num ||
        informationExtracted is! num ||
        unavailable is! bool) {
      throw const FormatException('Invalid recipe Vibe transfer fields.');
    }
    return RecipeVibeTransferSnapshot(
      id: _requiredString(map, 'id', 'recipe Vibe transfer'),
      sourceAssetId: _optionalString(
        map,
        'sourceAssetId',
        'recipe Vibe transfer',
      ),
      mimeType: _requiredString(map, 'mimeType', 'recipe Vibe transfer'),
      filename: _requiredString(map, 'filename', 'recipe Vibe transfer'),
      strength: strength.toDouble(),
      informationExtracted: informationExtracted.toDouble(),
      unavailable: unavailable,
    );
  }
}

/// A durable, binary-free snapshot of the generation settings.
class RecipeGenerationSnapshot {
  const RecipeGenerationSnapshot({
    required this.params,
    this.imageToImage,
    this.preciseReferences = const [],
    this.vibeTransfers = const [],
  });

  static const int schemaVersion = 1;

  final ImageParams params;
  final RecipeImageInputSnapshot? imageToImage;
  final List<RecipePreciseReferenceSnapshot> preciseReferences;
  final List<RecipeVibeTransferSnapshot> vibeTransfers;

  /// Copies only metadata from a live request. Source bytes, masks, encoded
  /// Vibes, and character objects are deliberately stripped from [params].
  factory RecipeGenerationSnapshot.fromImageParams(
    ImageParams params, {
    RecipeImageInputSnapshot? imageToImage,
    List<RecipePreciseReferenceSnapshot>? preciseReferences,
    List<RecipeVibeTransferSnapshot>? vibeTransfers,
    String? sourceGalleryItemId,
  }) {
    final sanitizedParams = params.copyWith(
      sourceImage: null,
      maskImage: null,
      vibeReferencesV4: const [],
      preciseReferences: const [],
      characters: const [],
    );
    final resolvedImage =
        imageToImage ??
        (params.sourceImage == null
            ? null
            : RecipeImageInputSnapshot(
                sourceGalleryItemId: sourceGalleryItemId,
                mimeType: 'image/png',
                filename: 'source.png',
                strength: params.strength,
                noise: params.noise,
                unavailable: sourceGalleryItemId == null,
              ));
    final resolvedPrecise =
        preciseReferences ??
        [
          for (var index = 0; index < params.preciseReferences.length; index++)
            _preciseFromParams(params.preciseReferences[index], index),
        ];
    final resolvedVibes =
        vibeTransfers ??
        [
          for (var index = 0; index < params.vibeReferencesV4.length; index++)
            _vibeFromParams(params.vibeReferencesV4[index], index),
        ];
    return RecipeGenerationSnapshot(
      params: sanitizedParams,
      imageToImage: resolvedImage,
      preciseReferences: List.unmodifiable(resolvedPrecise),
      vibeTransfers: List.unmodifiable(resolvedVibes),
    );
  }

  Map<String, dynamic> toJson() => {
    'schemaVersion': schemaVersion,
    'params': params.toJson(),
    'transient': {
      'omitQualityTagHint': params.omitQualityTagHint,
      'omitUcPresetTagHint': params.omitUcPresetTagHint,
      'upscaledEnhance': params.upscaledEnhance,
      'isEnhanceRequest': params.isEnhanceRequest,
      'inpaintMaskClosingIterations': params.inpaintMaskClosingIterations,
      'inpaintMaskExpansionIterations': params.inpaintMaskExpansionIterations,
      'isOutpaint': params.isOutpaint,
    },
    if (imageToImage != null) 'imageToImage': imageToImage!.toJson(),
    'preciseReferences': [
      for (final reference in preciseReferences) reference.toJson(),
    ],
    'vibeTransfers': [for (final transfer in vibeTransfers) transfer.toJson()],
  };

  factory RecipeGenerationSnapshot.fromJson(Object? value) {
    final map = _asMap(value, 'recipe generation snapshot');
    _rejectUnknownFields(map, const {
      'schemaVersion',
      'params',
      'transient',
      'imageToImage',
      'preciseReferences',
      'vibeTransfers',
    }, 'recipe generation snapshot');
    if (map['schemaVersion'] != schemaVersion || map['params'] is! Map) {
      throw const FormatException('Unsupported recipe generation snapshot.');
    }
    final transient = map['transient'];
    if (transient != null && transient is! Map) {
      throw const FormatException(
        'Recipe snapshot transient must be an object.',
      );
    }
    final transientMap = transient == null
        ? const <String, dynamic>{}
        : Map<String, dynamic>.from(transient as Map);
    _rejectUnknownFields(transientMap, const {
      'omitQualityTagHint',
      'omitUcPresetTagHint',
      'upscaledEnhance',
      'isEnhanceRequest',
      'inpaintMaskClosingIterations',
      'inpaintMaskExpansionIterations',
      'isOutpaint',
    }, 'recipe snapshot transient');
    final params =
        ImageParams.fromJson(
          Map<String, dynamic>.from(map['params'] as Map),
        ).copyWith(
          omitQualityTagHint: transientMap['omitQualityTagHint'] == true,
          omitUcPresetTagHint: transientMap['omitUcPresetTagHint'] == true,
          upscaledEnhance: transientMap['upscaledEnhance'] == true,
          isEnhanceRequest: transientMap['isEnhanceRequest'] == true,
          inpaintMaskClosingIterations:
              _optionalInt(transientMap, 'inpaintMaskClosingIterations') ?? 0,
          inpaintMaskExpansionIterations:
              _optionalInt(transientMap, 'inpaintMaskExpansionIterations') ?? 0,
          isOutpaint: transientMap['isOutpaint'] == true,
          sourceImage: null,
          maskImage: null,
          vibeReferencesV4: const [],
          preciseReferences: const [],
          characters: const [],
        );
    final precise = _requiredList(
      map,
      'preciseReferences',
      'recipe snapshot',
    ).map(RecipePreciseReferenceSnapshot.fromJson).toList(growable: false);
    final vibes = _requiredList(
      map,
      'vibeTransfers',
      'recipe snapshot',
    ).map(RecipeVibeTransferSnapshot.fromJson).toList(growable: false);
    return RecipeGenerationSnapshot(
      params: params,
      imageToImage: map['imageToImage'] == null
          ? null
          : RecipeImageInputSnapshot.fromJson(map['imageToImage']),
      preciseReferences: precise,
      vibeTransfers: vibes,
    );
  }

  RecipeGenerationSnapshot copyWith({
    ImageParams? params,
    RecipeImageInputSnapshot? imageToImage,
    bool clearImageToImage = false,
    List<RecipePreciseReferenceSnapshot>? preciseReferences,
    List<RecipeVibeTransferSnapshot>? vibeTransfers,
  }) => RecipeGenerationSnapshot(
    params: params ?? this.params,
    imageToImage: clearImageToImage
        ? null
        : (imageToImage ?? this.imageToImage),
    preciseReferences: preciseReferences ?? this.preciseReferences,
    vibeTransfers: vibeTransfers ?? this.vibeTransfers,
  );
}

/// A text operation proposed by an assistant or accepted by the user.
class PromptPatchOperation {
  const PromptPatchOperation({
    required this.id,
    required this.op,
    required this.target,
    required this.reason,
    required this.evidenceIds,
    required this.confidence,
    this.category,
    this.before,
    this.after,
    this.explicit = false,
    this.tokenId,
  });

  final String id;
  final String op;
  final String target;
  final String? category;
  final Object? before;
  final Object? after;
  final String reason;
  final List<String> evidenceIds;
  final double confidence;
  final bool explicit;
  final String? tokenId;

  Map<String, dynamic> toJson() => {
    'id': id,
    'op': op,
    'target': target,
    if (category != null) 'category': category,
    if (before != null) 'before': before,
    if (after != null) 'after': after,
    'reason': reason,
    'evidenceIds': evidenceIds,
    'confidence': confidence,
    'explicit': explicit,
    if (tokenId != null) 'tokenId': tokenId,
  };

  factory PromptPatchOperation.fromJson(Object? value) {
    final map = _asMap(value, 'prompt patch operation');
    _rejectUnknownFields(map, const {
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
    }, 'prompt patch operation');
    final evidenceIds = map['evidenceIds'];
    final confidence = map['confidence'];
    final explicit = map['explicit'];
    if (evidenceIds is! List ||
        evidenceIds.any((item) => item is! String) ||
        confidence is! num ||
        explicit is! bool) {
      throw const FormatException('Invalid prompt patch operation fields.');
    }
    final confidenceValue = confidence.toDouble();
    if (!confidenceValue.isFinite ||
        confidenceValue < 0 ||
        confidenceValue > 1) {
      throw const FormatException('Prompt patch confidence must be 0..1.');
    }
    _ensurePrimitive(map['before'], 'prompt patch before');
    _ensurePrimitive(map['after'], 'prompt patch after');
    return PromptPatchOperation(
      id: _requiredString(map, 'id', 'prompt patch operation'),
      op: _requiredString(map, 'op', 'prompt patch operation'),
      target: _requiredString(map, 'target', 'prompt patch operation'),
      category: _optionalString(map, 'category', 'prompt patch operation'),
      before: map['before'],
      after: map['after'],
      reason: _requiredString(map, 'reason', 'prompt patch operation'),
      evidenceIds: List<String>.unmodifiable(evidenceIds.cast<String>()),
      confidence: confidenceValue,
      explicit: explicit,
      tokenId: _optionalString(map, 'tokenId', 'prompt patch operation'),
    );
  }
}

/// A binary-free versioned generation recipe.
class PromptRecipe {
  PromptRecipe({
    required this.id,
    required this.request,
    required this.characters,
    required this.mainPromptEntries,
    required this.structuredMain,
    required this.userInstruction,
    required this.retrievalEvidence,
    required this.proposedPatch,
    required this.acceptedPatch,
    required this.createdAt,
    this.parentRecipeId,
    this.sourceGalleryItemId,
    this.provider,
    this.providerModel,
  });

  static const int schemaVersion = 1;
  static const int maxEncodedBytes = 2 * 1024 * 1024;

  final String id;
  final String? parentRecipeId;
  final String? sourceGalleryItemId;
  final RecipeGenerationSnapshot request;
  final List<PromptSemanticEntry> mainPromptEntries;
  final StructuredPrompt structuredMain;
  final List<RecipeCharacter> characters;
  final String userInstruction;
  final List<RetrievalEvidence> retrievalEvidence;
  final List<PromptPatchOperation> proposedPatch;
  final List<PromptPatchOperation> acceptedPatch;
  final String? provider;
  final String? providerModel;
  final DateTime createdAt;

  factory PromptRecipe.create({
    required ImageParams params,
    String? id,
    String? parentRecipeId,
    String? sourceGalleryItemId,
    List<RecipeCharacter> characters = const [],
    List<PromptSemanticEntry> mainPromptEntries = const [],
    StructuredPrompt? structuredMain,
    String userInstruction = '',
    List<RetrievalEvidence> retrievalEvidence = const [],
    List<PromptPatchOperation> proposedPatch = const [],
    List<PromptPatchOperation> acceptedPatch = const [],
    String? provider,
    String? providerModel,
    DateTime? createdAt,
    RecipeImageInputSnapshot? imageToImage,
    List<RecipePreciseReferenceSnapshot>? preciseReferences,
    List<RecipeVibeTransferSnapshot>? vibeTransfers,
  }) {
    return PromptRecipe(
      id: id ?? const Uuid().v4(),
      parentRecipeId: parentRecipeId,
      sourceGalleryItemId: sourceGalleryItemId,
      request: RecipeGenerationSnapshot.fromImageParams(
        params,
        imageToImage: imageToImage,
        preciseReferences: preciseReferences,
        vibeTransfers: vibeTransfers,
        sourceGalleryItemId: sourceGalleryItemId,
      ),
      characters: List.unmodifiable(characters),
      mainPromptEntries: List.unmodifiable(mainPromptEntries),
      structuredMain: structuredMain ?? StructuredPrompt.empty(),
      userInstruction: userInstruction,
      retrievalEvidence: List.unmodifiable(retrievalEvidence),
      proposedPatch: List.unmodifiable(proposedPatch),
      acceptedPatch: List.unmodifiable(acceptedPatch),
      provider: provider,
      providerModel: providerModel,
      createdAt: createdAt ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'schemaVersion': schemaVersion,
    'id': id,
    if (parentRecipeId != null) 'parentRecipeId': parentRecipeId,
    if (sourceGalleryItemId != null) 'sourceGalleryItemId': sourceGalleryItemId,
    'request': request.toJson(),
    'mainPromptEntries': [
      for (final entry in mainPromptEntries) entry.toJson(),
    ],
    'structuredMain': structuredMain.toJson(),
    'characters': [for (final character in characters) character.toJson()],
    'userInstruction': userInstruction,
    'retrievalEvidence': [
      for (final evidence in retrievalEvidence) evidence.toJson(),
    ],
    'proposedPatch': [
      for (final operation in proposedPatch) operation.toJson(),
    ],
    'acceptedPatch': [
      for (final operation in acceptedPatch) operation.toJson(),
    ],
    if (provider != null) 'provider': provider,
    if (providerModel != null) 'providerModel': providerModel,
    'createdAt': createdAt.toUtc().millisecondsSinceEpoch,
  };

  String encode() {
    final encoded = jsonEncode(toJson());
    if (utf8.encode(encoded).length > maxEncodedBytes) {
      throw const FormatException('Prompt recipe is too large.');
    }
    return encoded;
  }

  factory PromptRecipe.decode(String raw) {
    if (utf8.encode(raw).length > maxEncodedBytes) {
      throw const FormatException('Prompt recipe is too large.');
    }
    final decoded = jsonDecode(raw);
    return PromptRecipe.fromJson(decoded);
  }

  factory PromptRecipe.fromJson(Object? value) {
    final map = _asMap(value, 'prompt recipe');
    _rejectUnknownFields(map, const {
      'schemaVersion',
      'id',
      'parentRecipeId',
      'sourceGalleryItemId',
      'request',
      'mainPromptEntries',
      'structuredMain',
      'characters',
      'userInstruction',
      'retrievalEvidence',
      'proposedPatch',
      'acceptedPatch',
      'provider',
      'providerModel',
      'createdAt',
    }, 'prompt recipe');
    if (map['schemaVersion'] != schemaVersion) {
      throw const FormatException('Unsupported prompt recipe schema.');
    }
    final createdAt = map['createdAt'];
    if (createdAt is! int || createdAt < 0) {
      throw const FormatException(
        'Prompt recipe createdAt must be epoch milliseconds.',
      );
    }
    return PromptRecipe(
      id: _requiredString(map, 'id', 'prompt recipe'),
      parentRecipeId: _optionalString(map, 'parentRecipeId', 'prompt recipe'),
      sourceGalleryItemId: _optionalString(
        map,
        'sourceGalleryItemId',
        'prompt recipe',
      ),
      request: RecipeGenerationSnapshot.fromJson(map['request']),
      mainPromptEntries: _requiredList(
        map,
        'mainPromptEntries',
        'prompt recipe',
      ).map(PromptSemanticEntry.fromJson).toList(growable: false),
      structuredMain: StructuredPrompt.fromJson(map['structuredMain']),
      characters: _requiredList(
        map,
        'characters',
        'prompt recipe',
      ).map(RecipeCharacter.fromJson).toList(growable: false),
      userInstruction: _requiredString(
        map,
        'userInstruction',
        'prompt recipe',
        allowEmpty: true,
      ),
      retrievalEvidence: _requiredList(
        map,
        'retrievalEvidence',
        'prompt recipe',
      ).map(RetrievalEvidence.fromJson).toList(growable: false),
      proposedPatch: _requiredList(
        map,
        'proposedPatch',
        'prompt recipe',
      ).map(PromptPatchOperation.fromJson).toList(growable: false),
      acceptedPatch: _requiredList(
        map,
        'acceptedPatch',
        'prompt recipe',
      ).map(PromptPatchOperation.fromJson).toList(growable: false),
      provider: _optionalString(map, 'provider', 'prompt recipe'),
      providerModel: _optionalString(map, 'providerModel', 'prompt recipe'),
      createdAt: DateTime.fromMillisecondsSinceEpoch(createdAt, isUtc: true),
    );
  }
}

/// Persistence boundary for versioned prompt recipes.
abstract interface class PromptRecipeRepository {
  Future<PromptRecipe?> get(String id);

  Future<PromptRecipe?> getByGalleryItemId(String galleryItemId);

  Future<List<PromptRecipe>> list();

  Future<List<PromptRecipe>> listChildren(String parentRecipeId);

  Future<PromptRecipe> save(PromptRecipe recipe);

  Future<void> remove(String id);
}

RecipePreciseReferenceSnapshot _preciseFromParams(
  PreciseReference reference,
  int index,
) => RecipePreciseReferenceSnapshot(
  id: 'precise-$index',
  mimeType: 'image/png',
  filename: 'precise-$index.png',
  type: reference.type.name,
  strength: reference.strength,
  fidelity: reference.fidelity,
  unavailable: true,
);

RecipeVibeTransferSnapshot _vibeFromParams(
  VibeReference reference,
  int index,
) => RecipeVibeTransferSnapshot(
  id: 'vibe-$index',
  mimeType: 'image/png',
  filename: reference.displayName,
  strength: reference.strength,
  informationExtracted: reference.infoExtracted,
  unavailable: true,
);

Map<String, dynamic> _asMap(Object? value, String label) {
  if (value is! Map) throw FormatException('$label must be an object.');
  return Map<String, dynamic>.from(value);
}

String _requiredString(
  Map<String, dynamic> map,
  String key,
  String label, {
  bool allowEmpty = false,
}) {
  final value = map[key];
  if (value is! String || !allowEmpty && value.isEmpty) {
    throw FormatException('$label $key must be a non-empty string.');
  }
  return value;
}

String? _optionalString(Map<String, dynamic> map, String key, String label) {
  final value = map[key];
  if (value == null) return null;
  if (value is! String) throw FormatException('$label $key must be a string.');
  return value;
}

List<String>? _optionalStringList(
  Map<String, dynamic> map,
  String key,
  String label,
) {
  final value = map[key];
  if (value == null) return null;
  if (value is! List || value.any((item) => item is! String)) {
    throw FormatException('$label $key must be a list of strings.');
  }
  return List<String>.unmodifiable(value.cast<String>());
}

List<Object?> _requiredList(
  Map<String, dynamic> map,
  String key,
  String label,
) {
  final value = map[key];
  if (value is! List) throw FormatException('$label $key must be a list.');
  return value.cast<Object?>();
}

int? _optionalInt(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value == null) return null;
  if (value is! int) throw FormatException('$key must be an integer.');
  return value;
}

Map<String, List<String>> _normalizeStructuredFields(
  Map<String, List<String>> fields,
) {
  final normalized = <String, List<String>>{};
  for (final field in StructuredPrompt.structuredPromptFields) {
    final values = fields[field] ?? const <String>[];
    normalized[field] = List<String>.unmodifiable(values);
  }
  return Map<String, List<String>>.unmodifiable(normalized);
}

void _rejectUnknownFields(
  Map<String, dynamic> map,
  Set<String> allowed,
  String label,
) {
  final unknown = map.keys.where((key) => !allowed.contains(key)).toList();
  if (unknown.isNotEmpty) {
    throw FormatException(
      '$label contains unknown fields: ${unknown.join(', ')}',
    );
  }
}

void _ensurePrimitive(Object? value, String label) {
  if (value == null || value is String || value is num || value is bool) return;
  throw FormatException('$label must be a string, number, boolean, or null.');
}
