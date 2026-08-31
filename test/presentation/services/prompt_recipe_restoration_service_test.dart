import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/data/models/character/character_prompt.dart';
import 'package:nai_launcher/data/models/image/image_params.dart';
import 'package:nai_launcher/data/models/recipe/prompt_recipe.dart';
import 'package:nai_launcher/data/models/vibe/vibe_reference.dart';
import 'package:nai_launcher/presentation/services/prompt_recipe_restoration_service.dart';

void main() {
  test('restores editor-safe params and preserves coordinate characters', () {
    final recipe = PromptRecipe.create(
      params: const ImageParams(
        prompt: '1girl, blue eyes',
        action: ImageGenerationAction.img2img,
        useCoords: true,
      ),
      characters: const [
        RecipeCharacter(
          id: 'character-1',
          name: 'Alice',
          gender: 'female',
          prompt: '1girl, blue eyes',
          negativePrompt: 'bad anatomy',
          enabled: true,
          center: RecipeCharacterCenter(x: 1.2, y: -0.2),
        ),
      ],
      imageToImage: const RecipeImageInputSnapshot(
        sourceGalleryItemId: 'gallery-source',
        mimeType: 'image/png',
        filename: 'source.png',
        strength: 0.7,
        noise: 0.1,
        unavailable: true,
      ),
      preciseReferences: const [
        RecipePreciseReferenceSnapshot(
          id: 'precise-1',
          mimeType: 'image/png',
          filename: 'precise.png',
          type: 'character',
          strength: 0.8,
          fidelity: 0.9,
          unavailable: true,
        ),
      ],
      vibeTransfers: const [
        RecipeVibeTransferSnapshot(
          id: 'vibe-1',
          mimeType: 'image/png',
          filename: 'vibe.png',
          strength: 0.4,
          informationExtracted: 0.6,
          unavailable: true,
        ),
      ],
    );

    final restored = PromptRecipeRestorationService.restore(recipe);

    expect(restored.params.action, ImageGenerationAction.generate);
    expect(restored.params.sourceImage, isNull);
    expect(restored.params.vibeReferencesV4, isEmpty);
    expect(restored.params.preciseReferences, isEmpty);
    expect(restored.globalAiChoice, isFalse);
    expect(restored.hasUnavailableReferences, isTrue);
    expect(restored.unavailableVibeCount, 1);
    expect(restored.unavailablePreciseReferenceCount, 1);
    expect(restored.characters, hasLength(1));
    final character = restored.characters.single;
    expect(character.id, 'character-1');
    expect(character.gender, CharacterGender.female);
    expect(character.positionMode, CharacterPositionMode.custom);
    expect(character.customPosition!.column, 1);
    expect(character.customPosition!.row, 0);
  });

  test('uses AI placement when the recipe did not request coordinate mode', () {
    final recipe = PromptRecipe.create(
      params: const ImageParams(prompt: 'two characters', useCoords: false),
      characters: const [
        RecipeCharacter(
          id: 'character-1',
          name: 'Unknown',
          gender: null,
          prompt: 'two characters',
          negativePrompt: '',
          enabled: false,
          center: RecipeCharacterCenter(x: 0.2, y: 0.8),
        ),
      ],
    );

    final restored = PromptRecipeRestorationService.restore(recipe);
    expect(restored.globalAiChoice, isTrue);
    expect(
      restored.characters.single.positionMode,
      CharacterPositionMode.aiChoice,
    );
    expect(restored.characters.single.customPosition, isNull);
    expect(restored.characters.single.gender, CharacterGender.other);
    expect(restored.characters.single.enabled, isFalse);
  });

  test('reattaches only explicitly selected assets and reports the rest', () {
    final recipe = PromptRecipe.create(
      params: const ImageParams(
        prompt: 'img2img recipe',
        action: ImageGenerationAction.img2img,
        strength: 0.42,
        noise: 0.13,
      ),
      imageToImage: const RecipeImageInputSnapshot(
        sourceGalleryItemId: 'source-1',
        mimeType: 'image/png',
        filename: 'source.png',
        strength: 0.8,
        noise: 0.2,
        unavailable: true,
      ),
      preciseReferences: const [
        RecipePreciseReferenceSnapshot(
          id: 'precise-1',
          mimeType: 'image/png',
          filename: 'character.png',
          type: 'character',
          strength: 0.75,
          fidelity: 0.9,
          unavailable: true,
        ),
        RecipePreciseReferenceSnapshot(
          id: 'precise-2',
          mimeType: 'image/png',
          filename: 'style.png',
          type: 'style',
          strength: 0.5,
          fidelity: 0.6,
          unavailable: true,
        ),
      ],
      vibeTransfers: const [
        RecipeVibeTransferSnapshot(
          id: 'vibe-1',
          mimeType: 'image/png',
          filename: 'vibe.png',
          strength: 0.4,
          informationExtracted: 0.65,
          unavailable: true,
        ),
      ],
    );

    final restored = PromptRecipeRestorationService.restore(
      recipe,
      attachments: PromptRecipeAttachments(
        sourceImage: Uint8List.fromList([1, 2, 3]),
        preciseReferences: {
          'precise-1': Uint8List.fromList([4, 5, 6]),
        },
        vibeReferences: {
          'vibe-1': VibeReference(
            displayName: 'picked-vibe.png',
            vibeEncoding: '',
            rawImageData: Uint8List.fromList([7, 8, 9]),
          ),
        },
      ),
    );

    expect(restored.params.action, ImageGenerationAction.img2img);
    expect(restored.params.sourceImage, orderedEquals([1, 2, 3]));
    expect(restored.params.strength, 0.8);
    expect(restored.params.noise, 0.2);
    expect(restored.params.preciseReferences, hasLength(1));
    expect(restored.params.preciseReferences.single.type.name, 'character');
    expect(restored.params.vibeReferencesV4, hasLength(1));
    expect(restored.params.vibeReferencesV4.single.displayName, 'vibe.png');
    expect(restored.params.vibeReferencesV4.single.strength, 0.4);
    expect(restored.reattachedImageInput, isTrue);
    expect(restored.reattachedPreciseReferenceCount, 1);
    expect(restored.reattachedVibeCount, 1);
    expect(restored.hasUnavailableImageInput, isFalse);
    expect(restored.unavailablePreciseReferenceCount, 1);
    expect(restored.unavailableVibeCount, 0);
  });

  test('ignores empty or unusable attachments without weakening safety', () {
    final recipe = PromptRecipe.create(
      params: const ImageParams(prompt: 'safe'),
      preciseReferences: const [
        RecipePreciseReferenceSnapshot(
          id: 'precise-1',
          mimeType: 'image/png',
          filename: 'missing.png',
          type: 'style',
          strength: 1,
          fidelity: 1,
          unavailable: true,
        ),
      ],
      vibeTransfers: const [
        RecipeVibeTransferSnapshot(
          id: 'vibe-1',
          mimeType: 'image/png',
          filename: 'missing.png',
          strength: 0.5,
          informationExtracted: 0.5,
          unavailable: true,
        ),
      ],
    );

    final restored = PromptRecipeRestorationService.restore(
      recipe,
      attachments: PromptRecipeAttachments(
        preciseReferences: {'precise-1': Uint8List(0)},
        vibeReferences: {
          'vibe-1': const VibeReference(displayName: 'empty', vibeEncoding: ''),
        },
      ),
    );

    expect(restored.params.preciseReferences, isEmpty);
    expect(restored.params.vibeReferencesV4, isEmpty);
    expect(restored.hasUnavailableReferences, isTrue);
    expect(restored.unavailablePreciseReferenceCount, 1);
    expect(restored.unavailableVibeCount, 1);
  });
}
