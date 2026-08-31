import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/data/models/style_lab/style_lab_models.dart';
import 'package:nai_launcher/presentation/screens/style_lab/style_lab_copy.dart';
import 'package:nai_launcher/presentation/screens/style_lab/style_lab_widgets.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('controls remain usable on narrow and desktop widths', (
    tester,
  ) async {
    final baseController = TextEditingController(text: 'portrait');
    final auxiliaryController = TextEditingController();
    final artistController = TextEditingController(text: 'artist:alpha');
    final styleController = TextEditingController(text: 'random|color|blue');
    final fixedSeedController = TextEditingController(text: '123456');
    addTearDown(() {
      baseController.dispose();
      auxiliaryController.dispose();
      artistController.dispose();
      styleController.dispose();
      fixedSeedController.dispose();
    });

    for (final size in const [
      Size(320, 900),
      Size(390, 844),
      Size(600, 900),
      Size(1200, 900),
    ]) {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(
        _controlsApp(
          baseController: baseController,
          auxiliaryController: auxiliaryController,
          artistController: artistController,
          styleController: styleController,
          fixedSeedController: fixedSeedController,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Base prompt'), findsOneWidget, reason: 'width=$size');
      expect(find.text('Artist pool'), findsOneWidget, reason: 'width=$size');
      expect(
        find.text('Generate all A/B'),
        findsOneWidget,
        reason: 'width=$size',
      );
      expect(find.byType(SegmentedButton<StyleLabSeedMode>), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'width=$size');
    }

    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('results stack variants and keep actions reachable on mobile', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final now = DateTime(2026);
    final plain = StyleLabVariant(
      id: 'plain',
      kind: StyleLabVariantKind.plain,
      prompt: 'portrait, artist:alpha',
      artistPrompt: 'artist:alpha',
      mutationPrompt: '',
      seed: 42,
      createdAt: now,
    );
    final mutated = StyleLabVariant(
      id: 'mutated',
      kind: StyleLabVariantKind.mutated,
      prompt: 'portrait, artist:alpha, blue lighting',
      artistPrompt: 'artist:alpha',
      mutationPrompt: 'blue lighting',
      seed: 42,
      status: StyleLabResultStatus.failed,
      error: 'temporary failure',
      createdAt: now,
    );
    final pair = StyleLabPair(
      id: 'pair-1',
      artists: const [StyleLabArtist(name: 'alpha')],
      mutations: const [
        StyleLabToken(
          value: 'blue lighting',
          category: StyleLabMutationCategory.lighting,
          weight: 1,
        ),
      ],
      seed: 42,
      variants: [plain, mutated],
      createdAt: now,
    );

    await tester.pumpWidget(
      _resultsApp(
        pairs: [pair],
        favorites: [StyleLabFavorite.fromVariant(mutated, model: 'nai-test')],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Pair 1'), findsOneWidget);
    expect(find.text('A · Plain chain'), findsOneWidget);
    expect(find.text('B · Mutated style'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.byTooltip('Copy prompt'), findsNWidgets(3));
    expect(tester.takeException(), isNull);
  });
}

Widget _controlsApp({
  required TextEditingController baseController,
  required TextEditingController auxiliaryController,
  required TextEditingController artistController,
  required TextEditingController styleController,
  required TextEditingController fixedSeedController,
}) {
  return MaterialApp(
    locale: const Locale('en'),
    home: Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Builder(
          builder: (context) {
            final copy = StyleLabCopy.of(context);
            return StyleLabControls(
              copy: copy,
              baseController: baseController,
              auxiliaryController: auxiliaryController,
              artistController: artistController,
              styleController: styleController,
              fixedSeedController: fixedSeedController,
              pairCount: 4,
              artistRange: const RangeValues(2, 4),
              artistWeightRange: const RangeValues(0.65, 1.15),
              styleRange: const RangeValues(2, 4),
              mutateStyles: true,
              seedMode: StyleLabSeedMode.randomPerPair,
              isBusy: false,
              onPairCountChanged: (_) {},
              onArtistRangeChanged: (_) {},
              onArtistWeightChanged: (_) {},
              onStyleRangeChanged: (_) {},
              onMutateChanged: (_) {},
              onSeedModeChanged: (_) {},
              onDraw: () {},
              onGenerateAll: () {},
              onStop: () {},
              onSyncParams: () {},
              onUseDefaults: () {},
              onLoadLocalArtists: () {},
            );
          },
        ),
      ),
    ),
  );
}

Widget _resultsApp({
  required List<StyleLabPair> pairs,
  required List<StyleLabFavorite> favorites,
}) {
  return MaterialApp(
    locale: const Locale('en'),
    home: Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Builder(
          builder: (context) {
            return StyleLabResultsView(
              copy: StyleLabCopy.of(context),
              pairs: pairs,
              favorites: favorites,
              images: const {},
              favoriteIds: favorites.map((item) => item.variantId).toSet(),
              onGenerate: (_) {},
              onToggleFavorite: (_) {},
              onApply: (_) {},
              onApplyFavorite: (_) {},
              onCopy: (_) {},
              onPreview: (_) {},
              onRemoveFavorite: (_) {},
            );
          },
        ),
      ),
    ),
  );
}
