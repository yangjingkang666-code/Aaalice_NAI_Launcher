import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/recipe/prompt_recipe.dart';
import '../../data/repositories/prompt_recipe_repository.dart';
import '../../data/services/prompt_patch_service.dart';
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
    _applyRestored(restored);
    return restored;
  }

  /// Applies a recipe with transient assets explicitly selected by the user.
  ///
  /// Assets are never written back to the recipe repository. A missing
  /// selection simply remains missing and is reported by the returned result.
  Future<PromptRecipeRestorationResult?> applyWithAttachments(
    String recipeId,
    PromptRecipeAttachments attachments,
  ) async {
    if (recipeId.isEmpty) return null;
    final recipe = await _ref
        .read(promptRecipeRepositoryProvider)
        .get(recipeId);
    if (recipe == null) return null;

    final restored = PromptRecipeRestorationService.restore(
      recipe,
      attachments: attachments,
    );
    _applyRestored(restored, keepAssets: true);
    return restored;
  }

  /// Validates, persists, and applies a Prompt Patch as a child recipe.
  ///
  /// The operation is intentionally explicit: an invalid or locked proposal
  /// throws [PromptPatchException] and leaves both the repository and editor
  /// untouched.
  Future<AppliedPromptPatch?> applyPatch(
    String recipeId,
    Iterable<PromptPatchOperation> operations, {
    PromptPatchLockPolicy policy = PromptPatchLockPolicy.strict,
  }) async {
    if (recipeId.isEmpty) return null;
    final repository = _ref.read(promptRecipeRepositoryProvider);
    final recipe = await repository.get(recipeId);
    if (recipe == null) return null;

    final applied = PromptPatchService.apply(
      recipe,
      operations,
      policy: policy,
    );
    await repository.save(applied.recipe);

    final restored = PromptRecipeRestorationService.restore(applied.recipe);
    _applyRestored(restored);
    return applied;
  }

  void _applyRestored(
    PromptRecipeRestorationResult restored, {
    bool keepAssets = false,
  }) {
    final paramsNotifier = _ref.read(generationParamsNotifierProvider.notifier);
    if (keepAssets) {
      paramsNotifier.applyRestoredParamsWithAssets(restored.params);
    } else {
      paramsNotifier.applyRestoredParams(restored.params);
    }
    _ref
        .read(characterPromptNotifierProvider.notifier)
        .replaceAllWithGlobalAiChoice(
          restored.characters,
          globalAiChoice: restored.globalAiChoice,
        );
  }
}
