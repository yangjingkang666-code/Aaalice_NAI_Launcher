import 'dart:math';

import 'package:uuid/uuid.dart';

import '../models/style_lab/style_lab_models.dart';

/// Offline-first prompt composer for the manual artist-chain laboratory.
///
/// The service deliberately does not call Danbooru or an image model. It
/// creates reproducible A/B prompt pairs so a user can inspect the exact
/// artist chain and decide which variants are worth generating.
class StyleLabService {
  StyleLabService({Random? random, DateTime Function()? now})
    : _random = random,
      _now = now ?? DateTime.now;

  final Random? _random;
  final DateTime Function() _now;

  static const List<StyleLabArtist> defaultArtists = [
    StyleLabArtist(name: 'wlop', postCount: 100000),
    StyleLabArtist(name: 'ask_(askzy)', postCount: 65000),
    StyleLabArtist(name: 'torino_(artist)', postCount: 54000),
    StyleLabArtist(name: 'redjuice', postCount: 43000),
    StyleLabArtist(name: 'mika pikazo', postCount: 39000),
    StyleLabArtist(name: 'lack', postCount: 36000),
    StyleLabArtist(name: 'hiten_(hitenkei)', postCount: 33000),
    StyleLabArtist(name: 'loundraw', postCount: 30000),
    StyleLabArtist(name: 'saitom', postCount: 28000),
    StyleLabArtist(name: 'yoneyama mai', postCount: 26000),
    StyleLabArtist(name: 'krenz', postCount: 24000),
    StyleLabArtist(name: 'tiv', postCount: 22000),
    StyleLabArtist(name: 'ask_(artist)', postCount: 19000),
    StyleLabArtist(name: 'fuzichoco', postCount: 18000),
    StyleLabArtist(name: 'mignon', postCount: 17000),
    StyleLabArtist(name: 'redum', postCount: 15000),
    StyleLabArtist(name: 'moyoru', postCount: 13000),
    StyleLabArtist(name: 'patata_(pixiv)', postCount: 12000),
    StyleLabArtist(name: 'shigure ui', postCount: 11000),
    StyleLabArtist(name: 'huke', postCount: 10000),
  ];

  static const List<StyleLabPoolItem> defaultStylePool = [
    StyleLabPoolItem(
      value: 'anime key visual',
      category: StyleLabMutationCategory.artStyle,
    ),
    StyleLabPoolItem(
      value: 'cel shading',
      category: StyleLabMutationCategory.artStyle,
    ),
    StyleLabPoolItem(
      value: 'painterly brushwork',
      category: StyleLabMutationCategory.artStyle,
    ),
    StyleLabPoolItem(
      value: 'clean lineart',
      category: StyleLabMutationCategory.artStyle,
    ),
    StyleLabPoolItem(
      value: 'watercolor medium',
      category: StyleLabMutationCategory.medium,
    ),
    StyleLabPoolItem(
      value: 'gouache medium',
      category: StyleLabMutationCategory.medium,
    ),
    StyleLabPoolItem(
      value: 'ink wash',
      category: StyleLabMutationCategory.medium,
    ),
    StyleLabPoolItem(
      value: 'soft pastel palette',
      category: StyleLabMutationCategory.color,
    ),
    StyleLabPoolItem(
      value: 'high contrast colors',
      category: StyleLabMutationCategory.color,
    ),
    StyleLabPoolItem(
      value: 'limited color palette',
      category: StyleLabMutationCategory.color,
    ),
    StyleLabPoolItem(
      value: 'rim lighting',
      category: StyleLabMutationCategory.lighting,
    ),
    StyleLabPoolItem(
      value: 'soft diffused light',
      category: StyleLabMutationCategory.lighting,
    ),
    StyleLabPoolItem(
      value: 'cinematic lighting',
      category: StyleLabMutationCategory.lighting,
    ),
  ];

  /// Creates [StyleLabPair] records using the session's draw seed.
  List<StyleLabPair> generatePairs(StyleLabSession session) {
    final random = _random ?? Random(session.drawSeed);
    final artists = parseArtistPool(session.artistPool);
    final styleItems = parseStylePool(session.stylePool);
    final basePrompt = _joinPromptParts([
      session.basePrompt,
      session.auxiliaryPrompt,
    ]);
    final pairCount = session.pairCount.clamp(1, 12);
    final minArtists = session.minArtists.clamp(1, 8);
    final maxArtists = max(minArtists, session.maxArtists.clamp(1, 8));
    final minStyles = session.minStyleTokens.clamp(0, 8);
    final maxStyles = max(minStyles, session.maxStyleTokens.clamp(0, 8));
    final createdAt = _now().toUtc();
    final pairs = <StyleLabPair>[];

    for (var index = 0; index < pairCount; index++) {
      final pairSeed = session.seedMode == StyleLabSeedMode.fixed
          ? max(0, session.fixedSeed)
          : _nextSeed(random);
      final chosenArtists = _pickArtists(
        artists,
        count: _between(random, minArtists, maxArtists),
        random: random,
      );
      final artistPrompt = formatArtistPrompt(
        chosenArtists,
        minWeight: session.artistWeightMin,
        maxWeight: session.artistWeightMax,
        random: random,
      );
      final mutations = session.mutateStyles
          ? _pickMutations(
              styleItems,
              minCount: minStyles,
              maxCount: maxStyles,
              random: random,
            )
          : const <StyleLabToken>[];
      final mutationPrompt = formatMutationPrompt(mutations);
      final plainPrompt = composePrompt(
        basePrompt: basePrompt,
        artistPrompt: artistPrompt,
      );
      final mutatedPrompt = composePrompt(
        basePrompt: basePrompt,
        artistPrompt: artistPrompt,
        mutationPrompt: mutationPrompt,
      );
      final id = const Uuid().v4();
      final variants = [
        StyleLabVariant(
          id: '$id-plain',
          kind: StyleLabVariantKind.plain,
          prompt: plainPrompt,
          artistPrompt: artistPrompt,
          mutationPrompt: '',
          seed: pairSeed,
          createdAt: createdAt,
        ),
        StyleLabVariant(
          id: '$id-mutated',
          kind: StyleLabVariantKind.mutated,
          prompt: mutatedPrompt,
          artistPrompt: artistPrompt,
          mutationPrompt: mutationPrompt,
          seed: pairSeed,
          createdAt: createdAt,
        ),
      ];
      pairs.add(
        StyleLabPair(
          id: id,
          artists: chosenArtists,
          mutations: mutations,
          seed: pairSeed,
          variants: variants,
          createdAt: createdAt,
        ),
      );
    }
    return pairs;
  }

  /// Parses one artist tag per line or comma. A `|count` suffix is accepted
  /// for users who want to provide a rough popularity weight themselves.
  static List<StyleLabArtist> parseArtistPool(String source) {
    final values = source
        .split(RegExp(r'[\n\r,]+'))
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .map((value) {
          var name = value;
          var postCount = 1;
          final separator = value.lastIndexOf('|');
          if (separator > 0) {
            final parsed = int.tryParse(value.substring(separator + 1).trim());
            if (parsed != null) {
              name = value.substring(0, separator).trim();
              postCount = parsed;
            }
          }
          name = normalizeArtistTag(name);
          return StyleLabArtist(name: name, postCount: max(1, postCount));
        })
        .where((artist) => artist.name.isNotEmpty)
        .toList(growable: false);
    return values.isEmpty ? defaultArtists : _deduplicateArtists(values);
  }

  static String normalizeArtistTag(String value) {
    var normalized = value.trim();
    normalized = normalized.replaceFirst(RegExp(r'^artist\s*:\s*'), '');
    normalized = normalized.replaceFirst(RegExp(r'^artist\s+'), '');
    normalized = normalized.replaceAll(
      RegExp(r"^[\[\]{}()']+|[\[\]{}()']+$"),
      '',
    );
    normalized = normalized.replaceAll(RegExp(r'\s+'), '_');
    return normalized.trim();
  }

  /// Parses `always|category|tag`, `random|category|tag`, or just `tag`.
  static List<StyleLabPoolItem> parseStylePool(String source) {
    final raw = source
        .split(RegExp(r'[\n\r]+'))
        .expand((line) => line.split(','))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .map(_parseStyleLine)
        .where((item) => item.value.isNotEmpty)
        .toList(growable: false);
    return raw.isEmpty ? defaultStylePool : raw;
  }

  static StyleLabPoolItem _parseStyleLine(String line) {
    final pieces = line.split('|').map((piece) => piece.trim()).toList();
    var mode = StyleLabPoolMode.random;
    var category = StyleLabMutationCategory.artStyle;
    var value = line;
    if (pieces.length >= 2 && _modeFor(pieces.first) != null) {
      mode = _modeFor(pieces.first)!;
      if (pieces.length >= 3 && _categoryFor(pieces[1]) != null) {
        category = _categoryFor(pieces[1])!;
        value = pieces.sublist(2).join('|').trim();
      } else {
        value = pieces.sublist(1).join('|').trim();
        category = inferCategory(value);
      }
    } else if (pieces.length >= 2 && _categoryFor(pieces.first) != null) {
      category = _categoryFor(pieces.first)!;
      value = pieces.sublist(1).join('|').trim();
    } else if (line.toLowerCase().startsWith('always:')) {
      mode = StyleLabPoolMode.always;
      value = line.substring('always:'.length).trim();
      category = inferCategory(value);
    } else if (line.toLowerCase().startsWith('random:')) {
      value = line.substring('random:'.length).trim();
      category = inferCategory(value);
    } else {
      category = inferCategory(value);
    }
    return StyleLabPoolItem(value: value, category: category, mode: mode);
  }

  static StyleLabMutationCategory inferCategory(String value) {
    final lower = value.toLowerCase();
    if (RegExp(r'light|shadow|glow|rim|cinematic|backlit').hasMatch(lower)) {
      return StyleLabMutationCategory.lighting;
    }
    if (RegExp(
      r'color|colour|palette|pastel|monochrome|vibrant|contrast',
    ).hasMatch(lower)) {
      return StyleLabMutationCategory.color;
    }
    if (RegExp(
      r'watercolor|gouache|oil|ink|pencil|pastel|charcoal|medium',
    ).hasMatch(lower)) {
      return StyleLabMutationCategory.medium;
    }
    return StyleLabMutationCategory.artStyle;
  }

  static String formatArtistPrompt(
    List<StyleLabArtist> artists, {
    required double minWeight,
    required double maxWeight,
    Random? random,
  }) {
    if (artists.isEmpty) return '';
    final source = random ?? Random(0);
    final low = min(minWeight, maxWeight).clamp(0.1, 2.0).toDouble();
    final high = max(minWeight, maxWeight).clamp(0.1, 2.0).toDouble();
    return artists
        .map((artist) {
          final weight = low + source.nextDouble() * (high - low);
          final tag = 'artist:${normalizeArtistTag(artist.name)}';
          if ((weight - 1).abs() < 0.04) return tag;
          return '${weight.toStringAsFixed(2)}::$tag::';
        })
        .join(', ');
  }

  static String formatMutationPrompt(List<StyleLabToken> tokens) {
    return tokens
        .map((token) {
          if ((token.weight - 1).abs() < 0.04) return token.value;
          return '${token.weight.toStringAsFixed(2)}::${token.value}::';
        })
        .join(', ');
  }

  static String composePrompt({
    required String basePrompt,
    required String artistPrompt,
    String mutationPrompt = '',
  }) {
    return _joinPromptParts([basePrompt, artistPrompt, mutationPrompt]);
  }

  List<StyleLabArtist> _pickArtists(
    List<StyleLabArtist> source, {
    required int count,
    required Random random,
  }) {
    final remaining = [...source];
    final picked = <StyleLabArtist>[];
    final target = min(count, remaining.length);
    for (var index = 0; index < target; index++) {
      final total = remaining.fold<double>(
        0,
        (sum, artist) => sum + sqrt(max(1, artist.postCount)),
      );
      var cursor = random.nextDouble() * total;
      var selectedIndex = remaining.length - 1;
      for (var candidate = 0; candidate < remaining.length; candidate++) {
        cursor -= sqrt(max(1, remaining[candidate].postCount));
        if (cursor <= 0) {
          selectedIndex = candidate;
          break;
        }
      }
      picked.add(remaining.removeAt(selectedIndex));
    }
    return picked;
  }

  List<StyleLabToken> _pickMutations(
    List<StyleLabPoolItem> source, {
    required int minCount,
    required int maxCount,
    required Random random,
  }) {
    final always = source.where((item) => item.mode == StyleLabPoolMode.always);
    final randomItems = source
        .where((item) => item.mode == StyleLabPoolMode.random)
        .toList();
    final selected = <StyleLabToken>[
      for (final item in always) _tokenFor(item, random),
    ];
    final requested = _between(random, minCount, maxCount);
    final randomCount = max(0, requested - selected.length);
    final remaining = [...randomItems];
    for (var index = 0; index < randomCount && remaining.isNotEmpty; index++) {
      final item = remaining.removeAt(random.nextInt(remaining.length));
      selected.add(_tokenFor(item, random));
    }
    return selected;
  }

  StyleLabToken _tokenFor(StyleLabPoolItem item, Random random) {
    final weight = 0.3 + random.nextDouble() * 1.2;
    return StyleLabToken(
      value: item.value,
      category: item.category,
      weight: weight,
    );
  }

  static List<StyleLabArtist> _deduplicateArtists(
    Iterable<StyleLabArtist> artists,
  ) {
    final seen = <String>{};
    return [
      for (final artist in artists)
        if (seen.add(artist.name.toLowerCase())) artist,
    ];
  }

  static int _between(Random random, int minValue, int maxValue) {
    final low = min(minValue, maxValue);
    final high = max(minValue, maxValue);
    return low + random.nextInt(high - low + 1);
  }

  static int _nextSeed(Random random) => random.nextInt(0x7fffffff);

  static String _joinPromptParts(Iterable<String> values) {
    return values
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .join(', ');
  }

  static StyleLabPoolMode? _modeFor(String value) {
    return switch (value.toLowerCase()) {
      'always' => StyleLabPoolMode.always,
      'random' => StyleLabPoolMode.random,
      _ => null,
    };
  }

  static StyleLabMutationCategory? _categoryFor(String value) {
    return switch (value.toLowerCase()) {
      'art' || 'artstyle' || 'style' => StyleLabMutationCategory.artStyle,
      'medium' || 'material' => StyleLabMutationCategory.medium,
      'color' || 'colour' => StyleLabMutationCategory.color,
      'lighting' || 'light' => StyleLabMutationCategory.lighting,
      _ => null,
    };
  }
}
