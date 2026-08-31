import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/data/models/image/image_params.dart';
import 'package:nai_launcher/data/models/recipe/modification_seed_strategy.dart';
import 'package:nai_launcher/data/models/recipe/prompt_recipe.dart';
import 'package:nai_launcher/data/services/prompt_patch_service.dart';

void main() {
  test('applies text operations without mutating the source recipe', () {
    final recipe = _recipe();
    final result = PromptPatchService.apply(
      recipe,
      const [
        PromptPatchOperation(
          id: 'add-light',
          op: 'add',
          target: 'main',
          after: 'soft lighting',
          reason: 'Add a gentle light cue.',
          evidenceIds: [],
          confidence: 0.9,
        ),
        PromptPatchOperation(
          id: 'replace-hair',
          op: 'replace',
          target: 'main',
          before: 'blue hair',
          after: 'red hair',
          category: 'appearance',
          reason: 'Use the requested hair color.',
          evidenceIds: [],
          confidence: 1,
        ),
      ],
      id: 'recipe-child',
      createdAt: DateTime.utc(2026, 8, 31),
    );

    expect(recipe.request.params.prompt, '1girl, blue hair, standing');
    expect(result.recipe.id, 'recipe-child');
    expect(result.recipe.parentRecipeId, recipe.id);
    expect(
      result.recipe.request.params.prompt,
      '1girl, red hair, standing, soft lighting',
    );
    expect(result.recipe.acceptedPatch, hasLength(2));
    expect(result.inverse, hasLength(2));

    final reverted = PromptPatchService.apply(
      result.recipe,
      result.inverse,
      id: 'recipe-reverted',
    );
    expect(reverted.recipe.request.params.prompt, '1girl, blue hair, standing');
  });

  test('moves a token and produces a reversible operation', () {
    final recipe = _recipe();
    final result = PromptPatchService.apply(recipe, const [
      PromptPatchOperation(
        id: 'move-standing',
        op: 'move',
        target: 'main',
        before: 'standing',
        after: 0,
        reason: 'Put the pose cue first.',
        evidenceIds: [],
        confidence: 0.8,
      ),
    ]);

    expect(result.recipe.request.params.prompt, 'standing, 1girl, blue hair');
    final reverted = PromptPatchService.apply(result.recipe, result.inverse);
    expect(reverted.recipe.request.params.prompt, '1girl, blue hair, standing');
  });

  test('removes a token and restores its original position on inverse', () {
    final recipe = _recipe();
    final result = PromptPatchService.apply(recipe, const [
      PromptPatchOperation(
        id: 'remove-hair',
        op: 'remove',
        target: 'main',
        before: 'blue hair',
        reason: 'Temporarily remove the color cue.',
        evidenceIds: [],
        confidence: 0.8,
      ),
    ]);

    expect(result.recipe.request.params.prompt, '1girl, standing');
    final reverted = PromptPatchService.apply(result.recipe, result.inverse);
    expect(reverted.recipe.request.params.prompt, '1girl, blue hair, standing');
  });

  test(
    'applies explicit parameter changes and keeps binary references intact',
    () {
      final recipe = _recipe();
      final result = PromptPatchService.apply(recipe, const [
        PromptPatchOperation(
          id: 'steps',
          op: 'parameter',
          target: 'request:steps',
          after: 32,
          explicit: true,
          reason: 'Use more steps for this test.',
          evidenceIds: [],
          confidence: 1,
        ),
      ]);

      expect(result.recipe.request.params.steps, 32);
      expect(result.recipe.request.imageToImage, isNotNull);
      expect(result.recipe.request.vibeTransfers, hasLength(1));
      expect(result.recipe.request.preciseReferences, hasLength(1));
      expect(result.inverse.single.op, 'parameter');
      expect(result.inverse.single.after, 28);
    },
  );

  test('strict policy rejects protected identity, style, and parameters', () {
    final recipe = _recipe();
    final validation = PromptPatchService.validate(recipe, const [
      PromptPatchOperation(
        id: 'identity',
        op: 'replace',
        target: 'character:char-1',
        before: '1girl',
        after: '1boy',
        reason: 'Contradict identity.',
        evidenceIds: [],
        confidence: 1,
      ),
      PromptPatchOperation(
        id: 'pose',
        op: 'replace',
        target: 'main',
        before: 'standing',
        after: 'sitting',
        category: 'pose',
        reason: 'Change pose silently.',
        evidenceIds: [],
        confidence: 1,
      ),
      PromptPatchOperation(
        id: 'steps',
        op: 'parameter',
        target: 'request:steps',
        after: 40,
        reason: 'Change steps silently.',
        evidenceIds: [],
        confidence: 1,
      ),
    ]);

    expect(validation.valid, isEmpty);
    expect(validation.issues.map((issue) => issue.code), [
      PromptPatchIssueCode.locked,
      PromptPatchIssueCode.locked,
      PromptPatchIssueCode.locked,
    ]);
  });

  test('seed strategy is recorded and reversible as an explicit parameter', () {
    final applied = PromptPatchService.apply(
      _recipe(),
      const [],
      seedStrategy: ModificationSeedStrategy.specified,
      specifiedSeed: 987,
    );
    expect(applied.recipe.request.params.seed, 987);
    expect(applied.applied.single.target, 'request:seed');
    expect(applied.inverse.single.explicit, isTrue);

    final restored = PromptPatchService.apply(applied.recipe, applied.inverse);
    expect(restored.recipe.request.params.seed, _recipe().request.params.seed);
  });

  test('rejects missing tokens, duplicate claims, and invalid parameters', () {
    final recipe = _recipe();
    final validation = PromptPatchService.validate(recipe, const [
      PromptPatchOperation(
        id: 'missing',
        op: 'remove',
        target: 'main',
        before: 'not present',
        reason: 'Remove a missing token.',
        evidenceIds: [],
        confidence: 1,
      ),
      PromptPatchOperation(
        id: 'first',
        op: 'replace',
        target: 'main',
        before: 'blue hair',
        after: 'red hair',
        reason: 'First replacement.',
        evidenceIds: [],
        confidence: 1,
      ),
      PromptPatchOperation(
        id: 'second',
        op: 'remove',
        target: 'main',
        before: 'blue hair',
        reason: 'Conflicting replacement.',
        evidenceIds: [],
        confidence: 1,
      ),
      PromptPatchOperation(
        id: 'bad-steps',
        op: 'parameter',
        target: 'request:steps',
        after: 0,
        explicit: true,
        reason: 'Invalid steps.',
        evidenceIds: [],
        confidence: 1,
      ),
    ]);

    expect(validation.valid.map((operation) => operation.id), ['first']);
    expect(validation.issues.map((issue) => issue.code), [
      PromptPatchIssueCode.notFound,
      PromptPatchIssueCode.conflict,
      PromptPatchIssueCode.invalid,
    ]);
  });
}

PromptRecipe _recipe() {
  return PromptRecipe.create(
    id: 'recipe-root',
    sourceGalleryItemId: 'gallery-root',
    params: const ImageParams(
      prompt: '1girl, blue hair, standing',
      negativePrompt: 'lowres, bad hands',
      steps: 28,
      sourceImage: null,
    ),
    characters: const [
      RecipeCharacter(
        id: 'char-1',
        name: 'Alice',
        gender: 'female',
        prompt: '1girl, blue hair',
        negativePrompt: 'bad hands',
        enabled: true,
        center: RecipeCharacterCenter(x: 0.5, y: 0.5),
        corePrompt: 'short red hair',
        lockedTraits: ['red eyes'],
      ),
    ],
    imageToImage: const RecipeImageInputSnapshot(
      mimeType: 'image/png',
      filename: 'source.png',
      strength: 0.7,
      noise: 0,
      sourceGalleryItemId: 'source-gallery',
    ),
    preciseReferences: const [
      RecipePreciseReferenceSnapshot(
        id: 'precise-1',
        mimeType: 'image/png',
        filename: 'precise.png',
        type: 'style',
        strength: 1,
        fidelity: 1,
        sourceAssetId: 'asset-1',
      ),
    ],
    vibeTransfers: const [
      RecipeVibeTransferSnapshot(
        id: 'vibe-1',
        mimeType: 'image/png',
        filename: 'vibe.png',
        strength: 0.5,
        informationExtracted: 0.7,
        sourceAssetId: 'asset-2',
      ),
    ],
  );
}
