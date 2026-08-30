import '../../data/models/character/character_prompt.dart' as ui_character;
import '../../data/models/image/image_params.dart';
import '../../data/models/recipe/prompt_recipe.dart';

/// Result of restoring a binary-free recipe into editor state.
///
/// References whose bytes are intentionally absent from a recipe are reported
/// separately so the UI can ask the user to reattach them instead of sending
/// an invalid request.
class PromptRecipeRestorationResult {
  const PromptRecipeRestorationResult({
    required this.params,
    required this.characters,
    required this.globalAiChoice,
    required this.hasUnavailableImageInput,
    required this.unavailableVibeCount,
    required this.unavailablePreciseReferenceCount,
  });

  final ImageParams params;
  final List<ui_character.CharacterPrompt> characters;
  final bool globalAiChoice;
  final bool hasUnavailableImageInput;
  final int unavailableVibeCount;
  final int unavailablePreciseReferenceCount;

  bool get hasUnavailableReferences =>
      hasUnavailableImageInput ||
      unavailableVibeCount > 0 ||
      unavailablePreciseReferenceCount > 0;
}

/// Converts a persisted recipe into safe, editor-ready state.
///
/// Recipe records never contain image bytes. Any generation mode that needs a
/// source image is therefore restored as plain text generation until the user
/// supplies a new source. Vibe and Precise Reference entries are likewise
/// cleared while their missing counts remain available to the caller.
class PromptRecipeRestorationService {
  const PromptRecipeRestorationService._();

  static PromptRecipeRestorationResult restore(PromptRecipe recipe) {
    final snapshot = recipe.request;
    final requiresSourceImage = snapshot.imageToImage != null;
    final hasCharacters = recipe.characters.isNotEmpty;
    final useCoordinates = hasCharacters && snapshot.params.useCoords;
    final restoredCharacters = [
      for (final character in recipe.characters)
        _restoreCharacter(character, useCoordinates: useCoordinates),
    ];

    final restoredParams = snapshot.params.copyWith(
      sourceImage: null,
      maskImage: null,
      vibeReferencesV4: const [],
      preciseReferences: const [],
      characters: const [],
      // A source-less transformation cannot be sent safely, so always restore
      // the editor in the plain text-generation mode.
      action: ImageGenerationAction.generate,
      isOutpaint: false,
      isEnhanceRequest: false,
      inpaintMaskClosingIterations: 0,
      inpaintMaskExpansionIterations: 0,
    );

    return PromptRecipeRestorationResult(
      params: restoredParams,
      characters: List.unmodifiable(restoredCharacters),
      globalAiChoice: !useCoordinates,
      hasUnavailableImageInput: requiresSourceImage,
      unavailableVibeCount: snapshot.vibeTransfers.length,
      unavailablePreciseReferenceCount: snapshot.preciseReferences.length,
    );
  }

  static ui_character.CharacterPrompt _restoreCharacter(
    RecipeCharacter character, {
    required bool useCoordinates,
  }) {
    final customPosition = useCoordinates
        ? ui_character.CharacterPosition(
            mode: ui_character.CharacterPositionMode.custom,
            row: character.center.y.clamp(0.0, 1.0).toDouble(),
            column: character.center.x.clamp(0.0, 1.0).toDouble(),
          )
        : null;
    return ui_character.CharacterPrompt(
      id: character.id,
      name: character.name,
      gender: _restoreGender(character.gender, character.prompt),
      prompt: character.prompt,
      negativePrompt: character.negativePrompt,
      positionMode: useCoordinates
          ? ui_character.CharacterPositionMode.custom
          : ui_character.CharacterPositionMode.aiChoice,
      customPosition: customPosition,
      enabled: character.enabled,
    );
  }

  static ui_character.CharacterGender _restoreGender(
    String? value,
    String prompt,
  ) {
    switch (value?.toLowerCase()) {
      case 'female':
        return ui_character.CharacterGender.female;
      case 'male':
        return ui_character.CharacterGender.male;
      case 'other':
        return ui_character.CharacterGender.other;
    }
    final lowerPrompt = prompt.toLowerCase();
    if (lowerPrompt.contains('1girl') || lowerPrompt.contains('girl')) {
      return ui_character.CharacterGender.female;
    }
    if (lowerPrompt.contains('1boy') || lowerPrompt.contains('boy')) {
      return ui_character.CharacterGender.male;
    }
    return ui_character.CharacterGender.other;
  }
}
