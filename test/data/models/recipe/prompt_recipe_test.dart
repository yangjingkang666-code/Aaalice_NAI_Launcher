import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:nai_launcher/core/enums/precise_ref_type.dart';
import 'package:nai_launcher/data/models/image/image_params.dart';
import 'package:nai_launcher/data/models/recipe/prompt_recipe.dart';
import 'package:nai_launcher/data/models/vibe/vibe_reference.dart';
import 'package:nai_launcher/data/repositories/prompt_recipe_repository.dart';

void main() {
  late Directory hiveDirectory;

  setUp(() async {
    hiveDirectory = await Directory.systemTemp.createTemp('prompt-recipes-');
    Hive.init(hiveDirectory.path);
  });

  tearDown(() async {
    await Hive.close();
    if (hiveDirectory.existsSync()) await hiveDirectory.delete(recursive: true);
  });

  test(
    'creates a binary-free snapshot and preserves unavailable references',
    () {
      final sourceBytes = Uint8List.fromList([1, 2, 3, 4]);
      final params = ImageParams(
        prompt: '1girl, blue hair',
        negativePrompt: 'lowres',
        model: 'nai-diffusion-4-5-full',
        sourceImage: sourceBytes,
        maskImage: Uint8List.fromList([5, 6]),
        preciseReferences: [
          PreciseReference(
            image: Uint8List.fromList([7, 8]),
            type: PreciseRefType.style,
            strength: 0.8,
            fidelity: 0.9,
          ),
        ],
        vibeReferencesV4: [
          VibeReference(
            displayName: 'style.png',
            vibeEncoding: 'encoded-data',
            rawImageData: Uint8List.fromList([9, 10]),
            strength: 0.5,
            infoExtracted: 0.7,
          ),
        ],
      );

      final recipe = PromptRecipe.create(
        id: 'recipe-root',
        params: params,
        sourceGalleryItemId: null,
      );

      expect(recipe.request.params.sourceImage, isNull);
      expect(recipe.request.params.maskImage, isNull);
      expect(recipe.request.params.preciseReferences, isEmpty);
      expect(recipe.request.params.vibeReferencesV4, isEmpty);
      expect(recipe.request.imageToImage?.unavailable, isTrue);
      expect(recipe.request.preciseReferences.single.unavailable, isTrue);
      expect(recipe.request.vibeTransfers.single.unavailable, isTrue);

      final encoded = recipe.encode();
      expect(encoded, isNot(contains('encoded-data')));
      expect(encoded, isNot(contains('sourceImage')));
    },
  );

  test('round-trips semantic, character, evidence, and patch metadata', () {
    final recipe = PromptRecipe.create(
      id: 'recipe-child',
      parentRecipeId: 'recipe-root',
      sourceGalleryItemId: 'gallery-1',
      params: const ImageParams(prompt: '1girl, red hair'),
      characters: const [
        RecipeCharacter(
          id: 'character-1',
          name: 'Alice',
          prompt: '1girl, red hair',
          negativePrompt: 'bad hands',
          enabled: true,
          center: RecipeCharacterCenter(x: 0.25, y: 0.5),
          corePrompt: 'short red hair',
          lockedTraits: ['red hair'],
        ),
      ],
      mainPromptEntries: const [
        PromptSemanticEntry(
          id: 'token-1',
          text: 'red hair',
          category: 'appearance',
          source: 'manual',
          localTagHit: true,
          confidence: 1,
          kind: 'tag',
        ),
      ],
      structuredMain: StructuredPrompt(
        fields: {
          'appearance': ['red hair'],
          'style': ['illustration'],
        },
      ),
      userInstruction: 'Keep the character identity stable.',
      retrievalEvidence: const [
        RetrievalEvidence(
          id: 'evidence-1',
          source: 'local-tag-db',
          query: 'red hair',
          tag: 'red_hair',
          score: 0.98,
          postCount: 1234,
        ),
      ],
      proposedPatch: const [
        PromptPatchOperation(
          id: 'patch-1',
          op: 'add',
          target: 'main',
          after: 'soft lighting',
          reason: 'Improve readability.',
          evidenceIds: ['evidence-1'],
          confidence: 0.8,
        ),
      ],
      acceptedPatch: const [],
      provider: 'openai',
      providerModel: 'gpt-test',
      createdAt: DateTime.utc(2026, 8, 31, 1, 2, 3),
    );

    final restored = PromptRecipe.decode(recipe.encode());

    expect(restored.id, recipe.id);
    expect(restored.parentRecipeId, 'recipe-root');
    expect(restored.sourceGalleryItemId, 'gallery-1');
    expect(restored.request.params.prompt, '1girl, red hair');
    expect(restored.characters.single.corePrompt, 'short red hair');
    expect(restored.mainPromptEntries.single.text, 'red hair');
    expect(restored.structuredMain['appearance'], ['red hair']);
    expect(restored.retrievalEvidence.single.postCount, 1234);
    expect(restored.proposedPatch.single.after, 'soft lighting');
    expect(restored.providerModel, 'gpt-test');
    expect(restored.createdAt, recipe.createdAt);
  });

  test('rejects unknown fields and invalid confidence', () {
    final recipe = PromptRecipe.create(
      id: 'recipe-1',
      params: const ImageParams(prompt: 'prompt'),
    );
    final json = jsonDecode(recipe.encode()) as Map<String, dynamic>;
    json['unexpected'] = true;
    expect(() => PromptRecipe.fromJson(json), throwsA(isA<FormatException>()));

    final invalidEntry = {
      'id': 'token',
      'text': 'tag',
      'category': 'subject',
      'source': 'manual',
      'localTagHit': true,
      'confidence': 2,
      'kind': 'tag',
    };
    expect(
      () => PromptSemanticEntry.fromJson(invalidEntry),
      throwsA(isA<FormatException>()),
    );
  });

  test(
    'Hive repository saves, sorts, finds children, and ignores bad records',
    () async {
      final box = await Hive.openBox<String>('recipe-test-box');
      final repository = HivePromptRecipeRepository(box: box);
      final older = PromptRecipe.create(
        id: 'older',
        params: const ImageParams(prompt: 'older'),
        createdAt: DateTime.utc(2026, 1, 1),
      );
      final newer = PromptRecipe.create(
        id: 'newer',
        parentRecipeId: 'older',
        sourceGalleryItemId: 'gallery-2',
        params: const ImageParams(prompt: 'newer'),
        createdAt: DateTime.utc(2026, 1, 2),
      );
      await repository.save(older);
      await repository.save(newer);
      await box.put('broken', '{not-json');

      expect((await repository.get('older'))?.request.params.prompt, 'older');
      expect((await repository.getByGalleryItemId('gallery-2'))?.id, 'newer');
      expect((await repository.list()).map((item) => item.id), [
        'newer',
        'older',
      ]);
      expect((await repository.listChildren('older')).map((item) => item.id), [
        'newer',
      ]);

      await repository.remove('older');
      expect(await repository.get('older'), isNull);
    },
  );
}
