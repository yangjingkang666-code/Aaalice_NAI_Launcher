import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/data/models/character/character_prompt.dart';
import 'package:nai_launcher/data/models/image/image_params.dart';
import 'package:nai_launcher/data/models/recipe/prompt_recipe.dart';
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
}
