import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/autocomplete/completion_models.dart';
import 'package:nai_launcher/core/autocomplete/tag_catalog_repository.dart';
import 'package:nai_launcher/data/models/recipe/prompt_recipe.dart';
import 'package:nai_launcher/data/services/prompt_semantic_entry_builder.dart';

void main() {
  test('splits prompt terms and keeps a stable structured fallback', () {
    final first = PromptSemanticEntryBuilder.buildSync(
      '1girl, red-purple eyes, moonlit classroom with a desk',
      negativePrompt: 'bad anatomy',
    );
    final second = PromptSemanticEntryBuilder.buildSync(
      '1girl, red-purple eyes, moonlit classroom with a desk',
      negativePrompt: 'bad anatomy',
    );

    expect(
      first.entries.map((entry) => entry.id),
      second.entries.map((entry) => entry.id),
    );
    expect(first.entries.map((entry) => entry.text), [
      '1girl',
      'red-purple eyes',
      'moonlit classroom with a desk',
    ]);
    expect(first.entries.first.category, 'subject');
    expect(first.structured['negative'], ['bad anatomy']);
    expect(first.structured['scene'], ['moonlit classroom with a desk']);
  });

  test(
    'local catalog classification wins over heuristic classification',
    () async {
      final result = await PromptSemanticEntryBuilder.build(
        'blue_eyes, custom phrase',
        resolveExactTags: (terms) async => {
          'blue_eyes': const TagCatalogRecord(
            canonicalTag: 'blue_eyes',
            category: TagCategory.general,
            postCount: 10,
          ),
        },
      );

      expect(result.entries.first.source, 'tag-db');
      expect(result.entries.first.localTagHit, isTrue);
      expect(result.entries.first.category, 'appearance');
      expect(result.entries[1].source, 'imported');
    },
  );

  test('manual and AI classifications survive a rebuild', () {
    const manual = PromptSemanticEntry(
      id: 'manual-id',
      text: 'red-purple eyes',
      category: 'appearance',
      source: 'manual',
      localTagHit: false,
      confidence: 1,
      kind: 'natural-phrase',
    );
    final result = PromptSemanticEntryBuilder.buildSync(
      'red-purple eyes, standing',
      existingEntries: [manual],
    );

    expect(result.entries.first.id, 'manual-id');
    expect(result.entries.first.category, 'appearance');
    expect(result.entries.first.source, 'manual');
  });

  test('a later local catalog match upgrades an imported entry', () async {
    final imported = PromptSemanticEntryBuilder.buildSync('blue_eyes').entries;
    final result = await PromptSemanticEntryBuilder.build(
      'blue_eyes',
      existingEntries: imported,
      resolveExactTags: (terms) async => {
        'blue_eyes': const TagCatalogRecord(
          canonicalTag: 'blue_eyes',
          category: TagCategory.general,
          postCount: 42,
        ),
      },
    );

    expect(result.entries.single.source, 'tag-db');
    expect(result.entries.single.localTagHit, isTrue);
  });
}
