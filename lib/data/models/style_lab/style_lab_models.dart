import '../image/image_params.dart';

/// The four style dimensions used by the manual style laboratory.
enum StyleLabMutationCategory { artStyle, medium, color, lighting }

/// Whether a style-pool item is included in every mutated variant or sampled
/// from the pool for each draw.
enum StyleLabPoolMode { always, random }

enum StyleLabSeedMode { randomPerPair, fixed }

enum StyleLabVariantKind { plain, mutated }

enum StyleLabResultStatus { pending, generating, completed, failed }

class StyleLabArtist {
  const StyleLabArtist({required this.name, this.postCount = 1});

  final String name;
  final int postCount;

  Map<String, dynamic> toJson() => {'name': name, 'postCount': postCount};

  factory StyleLabArtist.fromJson(Map<String, dynamic> json) {
    return StyleLabArtist(
      name: (json['name'] as String? ?? '').trim(),
      postCount: (json['postCount'] as num?)?.toInt() ?? 1,
    );
  }
}

class StyleLabPoolItem {
  const StyleLabPoolItem({
    required this.value,
    this.category = StyleLabMutationCategory.artStyle,
    this.mode = StyleLabPoolMode.random,
  });

  final String value;
  final StyleLabMutationCategory category;
  final StyleLabPoolMode mode;

  Map<String, dynamic> toJson() => {
    'value': value,
    'category': category.name,
    'mode': mode.name,
  };

  factory StyleLabPoolItem.fromJson(Map<String, dynamic> json) {
    return StyleLabPoolItem(
      value: (json['value'] as String? ?? '').trim(),
      category: _enumFromName(
        StyleLabMutationCategory.values,
        json['category'] as String?,
        StyleLabMutationCategory.artStyle,
      ),
      mode: _enumFromName(
        StyleLabPoolMode.values,
        json['mode'] as String?,
        StyleLabPoolMode.random,
      ),
    );
  }
}

class StyleLabToken {
  const StyleLabToken({
    required this.value,
    required this.category,
    required this.weight,
  });

  final String value;
  final StyleLabMutationCategory category;
  final double weight;

  Map<String, dynamic> toJson() => {
    'value': value,
    'category': category.name,
    'weight': weight,
  };

  factory StyleLabToken.fromJson(Map<String, dynamic> json) {
    return StyleLabToken(
      value: (json['value'] as String? ?? '').trim(),
      category: _enumFromName(
        StyleLabMutationCategory.values,
        json['category'] as String?,
        StyleLabMutationCategory.artStyle,
      ),
      weight: (json['weight'] as num?)?.toDouble() ?? 1,
    );
  }
}

class StyleLabVariant {
  const StyleLabVariant({
    required this.id,
    required this.kind,
    required this.prompt,
    required this.artistPrompt,
    required this.mutationPrompt,
    required this.seed,
    this.status = StyleLabResultStatus.pending,
    this.error,
    this.imageId,
    this.imagePath,
    this.recipeId,
    required this.createdAt,
  });

  final String id;
  final StyleLabVariantKind kind;
  final String prompt;
  final String artistPrompt;
  final String mutationPrompt;
  final int seed;
  final StyleLabResultStatus status;
  final String? error;
  final String? imageId;
  final String? imagePath;
  final String? recipeId;
  final DateTime createdAt;

  bool get isMutated => kind == StyleLabVariantKind.mutated;

  StyleLabVariant copyWith({
    String? prompt,
    String? artistPrompt,
    String? mutationPrompt,
    int? seed,
    StyleLabResultStatus? status,
    String? error,
    bool clearError = false,
    String? imageId,
    bool clearImageId = false,
    String? imagePath,
    bool clearImagePath = false,
    String? recipeId,
    bool clearRecipeId = false,
  }) {
    return StyleLabVariant(
      id: id,
      kind: kind,
      prompt: prompt ?? this.prompt,
      artistPrompt: artistPrompt ?? this.artistPrompt,
      mutationPrompt: mutationPrompt ?? this.mutationPrompt,
      seed: seed ?? this.seed,
      status: status ?? this.status,
      error: clearError ? null : (error ?? this.error),
      imageId: clearImageId ? null : (imageId ?? this.imageId),
      imagePath: clearImagePath ? null : (imagePath ?? this.imagePath),
      recipeId: clearRecipeId ? null : (recipeId ?? this.recipeId),
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.name,
    'prompt': prompt,
    'artistPrompt': artistPrompt,
    'mutationPrompt': mutationPrompt,
    'seed': seed,
    'status': status.name,
    if (error != null) 'error': error,
    if (imageId != null) 'imageId': imageId,
    if (imagePath != null) 'imagePath': imagePath,
    if (recipeId != null) 'recipeId': recipeId,
    'createdAt': createdAt.toIso8601String(),
  };

  factory StyleLabVariant.fromJson(Map<String, dynamic> json) {
    return StyleLabVariant(
      id: (json['id'] as String? ?? '').trim(),
      kind: _enumFromName(
        StyleLabVariantKind.values,
        json['kind'] as String?,
        StyleLabVariantKind.plain,
      ),
      prompt: json['prompt'] as String? ?? '',
      artistPrompt: json['artistPrompt'] as String? ?? '',
      mutationPrompt: json['mutationPrompt'] as String? ?? '',
      seed: (json['seed'] as num?)?.toInt() ?? -1,
      status: _enumFromName(
        StyleLabResultStatus.values,
        json['status'] as String?,
        StyleLabResultStatus.pending,
      ),
      error: json['error'] as String?,
      imageId: json['imageId'] as String?,
      imagePath: json['imagePath'] as String?,
      recipeId: json['recipeId'] as String?,
      createdAt: _dateFromJson(json['createdAt']),
    );
  }
}

class StyleLabPair {
  const StyleLabPair({
    required this.id,
    required this.artists,
    required this.mutations,
    required this.seed,
    required this.variants,
    required this.createdAt,
  });

  final String id;
  final List<StyleLabArtist> artists;
  final List<StyleLabToken> mutations;
  final int seed;
  final List<StyleLabVariant> variants;
  final DateTime createdAt;

  StyleLabPair copyWith({List<StyleLabVariant>? variants}) {
    return StyleLabPair(
      id: id,
      artists: artists,
      mutations: mutations,
      seed: seed,
      variants: variants ?? this.variants,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'artists': artists.map((artist) => artist.toJson()).toList(),
    'mutations': mutations.map((token) => token.toJson()).toList(),
    'seed': seed,
    'variants': variants.map((variant) => variant.toJson()).toList(),
    'createdAt': createdAt.toIso8601String(),
  };

  factory StyleLabPair.fromJson(Map<String, dynamic> json) {
    return StyleLabPair(
      id: (json['id'] as String? ?? '').trim(),
      artists: _mapList(json['artists'])
          .map(StyleLabArtist.fromJson)
          .where((artist) => artist.name.isNotEmpty)
          .toList(growable: false),
      mutations: _mapList(json['mutations'])
          .map(StyleLabToken.fromJson)
          .where((token) => token.value.isNotEmpty)
          .toList(growable: false),
      seed: (json['seed'] as num?)?.toInt() ?? -1,
      variants: _mapList(json['variants'])
          .map(StyleLabVariant.fromJson)
          .where((variant) => variant.id.isNotEmpty)
          .toList(growable: false),
      createdAt: _dateFromJson(json['createdAt']),
    );
  }
}

class StyleLabFavorite {
  const StyleLabFavorite({
    required this.id,
    required this.variantId,
    required this.kind,
    required this.prompt,
    required this.artistPrompt,
    required this.mutationPrompt,
    required this.seed,
    required this.model,
    required this.createdAt,
    this.imageId,
    this.imagePath,
    this.recipeId,
  });

  final String id;
  final String variantId;
  final StyleLabVariantKind kind;
  final String prompt;
  final String artistPrompt;
  final String mutationPrompt;
  final int seed;
  final String model;
  final DateTime createdAt;
  final String? imageId;
  final String? imagePath;
  final String? recipeId;

  factory StyleLabFavorite.fromVariant(
    StyleLabVariant variant, {
    required String model,
    String? imageId,
    String? imagePath,
    String? recipeId,
  }) {
    return StyleLabFavorite(
      id: '${variant.id}:favorite',
      variantId: variant.id,
      kind: variant.kind,
      prompt: variant.prompt,
      artistPrompt: variant.artistPrompt,
      mutationPrompt: variant.mutationPrompt,
      seed: variant.seed,
      model: model,
      createdAt: DateTime.now().toUtc(),
      imageId: imageId ?? variant.imageId,
      imagePath: imagePath ?? variant.imagePath,
      recipeId: recipeId ?? variant.recipeId,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'variantId': variantId,
    'kind': kind.name,
    'prompt': prompt,
    'artistPrompt': artistPrompt,
    'mutationPrompt': mutationPrompt,
    'seed': seed,
    'model': model,
    'createdAt': createdAt.toIso8601String(),
    if (imageId != null) 'imageId': imageId,
    if (imagePath != null) 'imagePath': imagePath,
    if (recipeId != null) 'recipeId': recipeId,
  };

  factory StyleLabFavorite.fromJson(Map<String, dynamic> json) {
    return StyleLabFavorite(
      id: (json['id'] as String? ?? '').trim(),
      variantId: (json['variantId'] as String? ?? '').trim(),
      kind: _enumFromName(
        StyleLabVariantKind.values,
        json['kind'] as String?,
        StyleLabVariantKind.plain,
      ),
      prompt: json['prompt'] as String? ?? '',
      artistPrompt: json['artistPrompt'] as String? ?? '',
      mutationPrompt: json['mutationPrompt'] as String? ?? '',
      seed: (json['seed'] as num?)?.toInt() ?? -1,
      model: json['model'] as String? ?? '',
      createdAt: _dateFromJson(json['createdAt']),
      imageId: json['imageId'] as String?,
      imagePath: json['imagePath'] as String?,
      recipeId: json['recipeId'] as String?,
    );
  }
}

class StyleLabSession {
  const StyleLabSession({
    required this.basePrompt,
    required this.auxiliaryPrompt,
    required this.artistPool,
    required this.stylePool,
    required this.pairCount,
    required this.minArtists,
    required this.maxArtists,
    required this.artistWeightMin,
    required this.artistWeightMax,
    required this.mutateStyles,
    required this.minStyleTokens,
    required this.maxStyleTokens,
    required this.seedMode,
    required this.fixedSeed,
    required this.drawSeed,
    required this.generationParams,
    required this.pairs,
    required this.favorites,
    required this.updatedAt,
  });

  final String basePrompt;
  final String auxiliaryPrompt;
  final String artistPool;
  final String stylePool;
  final int pairCount;
  final int minArtists;
  final int maxArtists;
  final double artistWeightMin;
  final double artistWeightMax;
  final bool mutateStyles;
  final int minStyleTokens;
  final int maxStyleTokens;
  final StyleLabSeedMode seedMode;
  final int fixedSeed;
  final int drawSeed;
  final ImageParams generationParams;
  final List<StyleLabPair> pairs;
  final List<StyleLabFavorite> favorites;
  final DateTime updatedAt;

  factory StyleLabSession.initial(ImageParams params) {
    return StyleLabSession(
      basePrompt: params.prompt,
      auxiliaryPrompt: '',
      artistPool: '',
      stylePool: '',
      pairCount: 4,
      minArtists: 2,
      maxArtists: 4,
      artistWeightMin: 0.65,
      artistWeightMax: 1.15,
      mutateStyles: true,
      minStyleTokens: 2,
      maxStyleTokens: 4,
      seedMode: StyleLabSeedMode.randomPerPair,
      fixedSeed: 123456,
      drawSeed: DateTime.now().millisecondsSinceEpoch,
      generationParams: params,
      pairs: const [],
      favorites: const [],
      updatedAt: DateTime.now().toUtc(),
    );
  }

  StyleLabSession copyWith({
    String? basePrompt,
    String? auxiliaryPrompt,
    String? artistPool,
    String? stylePool,
    int? pairCount,
    int? minArtists,
    int? maxArtists,
    double? artistWeightMin,
    double? artistWeightMax,
    bool? mutateStyles,
    int? minStyleTokens,
    int? maxStyleTokens,
    StyleLabSeedMode? seedMode,
    int? fixedSeed,
    int? drawSeed,
    ImageParams? generationParams,
    List<StyleLabPair>? pairs,
    List<StyleLabFavorite>? favorites,
  }) {
    return StyleLabSession(
      basePrompt: basePrompt ?? this.basePrompt,
      auxiliaryPrompt: auxiliaryPrompt ?? this.auxiliaryPrompt,
      artistPool: artistPool ?? this.artistPool,
      stylePool: stylePool ?? this.stylePool,
      pairCount: pairCount ?? this.pairCount,
      minArtists: minArtists ?? this.minArtists,
      maxArtists: maxArtists ?? this.maxArtists,
      artistWeightMin: artistWeightMin ?? this.artistWeightMin,
      artistWeightMax: artistWeightMax ?? this.artistWeightMax,
      mutateStyles: mutateStyles ?? this.mutateStyles,
      minStyleTokens: minStyleTokens ?? this.minStyleTokens,
      maxStyleTokens: maxStyleTokens ?? this.maxStyleTokens,
      seedMode: seedMode ?? this.seedMode,
      fixedSeed: fixedSeed ?? this.fixedSeed,
      drawSeed: drawSeed ?? this.drawSeed,
      generationParams: generationParams ?? this.generationParams,
      pairs: pairs ?? this.pairs,
      favorites: favorites ?? this.favorites,
      updatedAt: DateTime.now().toUtc(),
    );
  }

  Map<String, dynamic> toJson() => {
    'version': 1,
    'basePrompt': basePrompt,
    'auxiliaryPrompt': auxiliaryPrompt,
    'artistPool': artistPool,
    'stylePool': stylePool,
    'pairCount': pairCount,
    'minArtists': minArtists,
    'maxArtists': maxArtists,
    'artistWeightMin': artistWeightMin,
    'artistWeightMax': artistWeightMax,
    'mutateStyles': mutateStyles,
    'minStyleTokens': minStyleTokens,
    'maxStyleTokens': maxStyleTokens,
    'seedMode': seedMode.name,
    'fixedSeed': fixedSeed,
    'drawSeed': drawSeed,
    'generationParams': generationParams.toJson(),
    'pairs': pairs.map((pair) => pair.toJson()).toList(),
    'favorites': favorites.map((favorite) => favorite.toJson()).toList(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory StyleLabSession.fromJson(Map<String, dynamic> json) {
    final paramsJson = json['generationParams'];
    final generationParams = paramsJson is Map
        ? ImageParams.fromJson(Map<String, dynamic>.from(paramsJson))
        : const ImageParams();
    return StyleLabSession(
      basePrompt: json['basePrompt'] as String? ?? generationParams.prompt,
      auxiliaryPrompt: json['auxiliaryPrompt'] as String? ?? '',
      artistPool: json['artistPool'] as String? ?? '',
      stylePool: json['stylePool'] as String? ?? '',
      pairCount: _boundedInt(json['pairCount'], 4, 1, 12),
      minArtists: _boundedInt(json['minArtists'], 2, 1, 8),
      maxArtists: _boundedInt(json['maxArtists'], 4, 1, 8),
      artistWeightMin: _boundedDouble(json['artistWeightMin'], 0.65, 0.1, 2),
      artistWeightMax: _boundedDouble(json['artistWeightMax'], 1.15, 0.1, 2),
      mutateStyles: json['mutateStyles'] as bool? ?? true,
      minStyleTokens: _boundedInt(json['minStyleTokens'], 2, 0, 8),
      maxStyleTokens: _boundedInt(json['maxStyleTokens'], 4, 0, 8),
      seedMode: _enumFromName(
        StyleLabSeedMode.values,
        json['seedMode'] as String?,
        StyleLabSeedMode.randomPerPair,
      ),
      fixedSeed: (json['fixedSeed'] as num?)?.toInt() ?? 123456,
      drawSeed:
          (json['drawSeed'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch,
      generationParams: generationParams,
      pairs: _mapList(json['pairs'])
          .map(StyleLabPair.fromJson)
          .where((pair) => pair.id.isNotEmpty)
          .take(24)
          .toList(growable: false),
      favorites: _mapList(json['favorites'])
          .map(StyleLabFavorite.fromJson)
          .where((favorite) => favorite.id.isNotEmpty)
          .take(100)
          .toList(growable: false),
      updatedAt: _dateFromJson(json['updatedAt']),
    );
  }
}

T _enumFromName<T extends Enum>(List<T> values, String? name, T fallback) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  return fallback;
}

List<Map<String, dynamic>> _mapList(dynamic value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList(growable: false);
}

DateTime _dateFromJson(dynamic value) {
  return DateTime.tryParse(value as String? ?? '')?.toUtc() ??
      DateTime.now().toUtc();
}

int _boundedInt(dynamic value, int fallback, int min, int max) {
  final number = value is num ? value.toInt() : fallback;
  return number.clamp(min, max);
}

double _boundedDouble(dynamic value, double fallback, double min, double max) {
  final number = value is num ? value.toDouble() : fallback;
  return number.clamp(min, max).toDouble();
}
