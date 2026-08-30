import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/prompt_recipe_repository.dart';
import '../providers/character_prompt_provider.dart';
import '../providers/generation/generation_params_notifier.dart';
import 'prompt_recipe_restoration_service.dart';

/// Loads a recipe and applies its safe, binary-free snapshot to the editor.
final promptRecipeApplicationServiceProvider =
    Provider<PromptRecipeApplicationService>(
      (ref) => PromptRecipeApplicationService(ref),
    );

class PromptRecipeApplicationService {
  const PromptRecipeApplicationService(this._ref);

  final Ref _ref;

  Future<PromptRecipeRestorationResult?> apply(String recipeId) async {
    if (recipeId.isEmpty) return null;
    final recipe = await _ref
        .read(promptRecipeRepositoryProvider)
        .get(recipeId);
    if (recipe == null) return null;

    final restored = PromptRecipeRestorationService.restore(recipe);
    _ref
        .read(generationParamsNotifierProvider.notifier)
        .applyRestoredParams(restored.params);
    _ref
        .read(characterPromptNotifierProvider.notifier)
        .replaceAllWithGlobalAiChoice(
          restored.characters,
          globalAiChoice: restored.globalAiChoice,
        );
    return restored;
  }
}
