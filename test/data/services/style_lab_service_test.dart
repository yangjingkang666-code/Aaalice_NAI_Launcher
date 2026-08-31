import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/data/models/image/image_params.dart';
import 'package:nai_launcher/data/models/style_lab/style_lab_models.dart';
import 'package:nai_launcher/data/services/style_lab_service.dart';

void main() {
  test('draw is reproducible for the same seed', () {
    final session = StyleLabSession.initial(const ImageParams()).copyWith(
      basePrompt: 'portrait, moonlit city',
      auxiliaryPrompt: 'high detail',
      artistPool: 'artist:alice|100, bob|10, carol|5',
      stylePool: 'always|lighting|rim lighting\nrandom|color|limited palette',
      pairCount: 3,
      minArtists: 2,
      maxArtists: 2,
      seedMode: StyleLabSeedMode.fixed,
      fixedSeed: 42,
      drawSeed: 99,
    );

    final first = StyleLabService().generatePairs(session);
    final second = StyleLabService().generatePairs(session);

    expect(first.length, 3);
    expect(
      first.map(
        (pair) => pair.variants.map((variant) => variant.prompt).toList(),
      ),
      second.map(
        (pair) => pair.variants.map((variant) => variant.prompt).toList(),
      ),
    );
    expect(first.map((pair) => pair.seed), everyElement(42));
    for (final pair in first) {
      expect(pair.variants[0].seed, pair.variants[1].seed);
      expect(pair.variants[0].artistPrompt, pair.variants[1].artistPrompt);
      expect(pair.variants[1].prompt, contains('rim lighting'));
    }
  });

  test('artist and style pool parsers accept prefixes and weights', () {
    final artists = StyleLabService.parseArtistPool(
      'artist:foo bar|12\nfoo bar\nartist:baz',
    );
    expect(artists.map((artist) => artist.name), ['foo_bar', 'baz']);
    expect(artists.first.postCount, 12);

    final styles = StyleLabService.parseStylePool(
      'always|medium|watercolor\ncolor|pastel palette\nrandom:rim lighting',
    );
    expect(styles[0].mode, StyleLabPoolMode.always);
    expect(styles[0].category, StyleLabMutationCategory.medium);
    expect(styles[1].category, StyleLabMutationCategory.color);
    expect(styles[2].mode, StyleLabPoolMode.random);
  });

  test('empty pools use the offline curated defaults', () {
    expect(StyleLabService.parseArtistPool(''), isNotEmpty);
    expect(StyleLabService.parseStylePool(''), isNotEmpty);
    final session = StyleLabSession.initial(
      const ImageParams(),
    ).copyWith(basePrompt: 'a test subject', pairCount: 1);
    final pair = StyleLabService().generatePairs(session).single;
    expect(pair.variants.first.prompt, contains('artist:'));
  });

  test('session JSON keeps prompts, generation settings and favorites', () {
    final session =
        StyleLabSession.initial(
          const ImageParams(model: 'nai-diffusion-4-5-full', seed: 7),
        ).copyWith(
          basePrompt: 'a lighthouse',
          auxiliaryPrompt: 'misty sea',
          pairCount: 2,
          fixedSeed: 314,
        );
    final restored = StyleLabSession.fromJson(session.toJson());
    expect(restored.basePrompt, 'a lighthouse');
    expect(restored.auxiliaryPrompt, 'misty sea');
    expect(restored.pairCount, 2);
    expect(restored.fixedSeed, 314);
    expect(restored.generationParams.model, 'nai-diffusion-4-5-full');
    expect(restored.generationParams.seed, 7);
  });
}
