import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/recipe/prompt_recipe.dart';
import '../../data/models/recipe/modification_seed_strategy.dart';
import '../../data/repositories/prompt_recipe_repository.dart';
import '../../data/services/prompt_patch_service.dart';
import '../providers/character_prompt_provider.dart';
import '../providers/generation/generation_params_notifier.dart';
import '../providers/prompt_semantic_provider.dart';
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
    _applyRestored(
      restored,
      semanticEntries: recipe.mainPromptEntries,
      retrievalEvidence: recipe.retrievalEvidence,
    );
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
    _applyRestored(
      restored,
      keepAssets: true,
      semanticEntries: recipe.mainPromptEntries,
      retrievalEvidence: recipe.retrievalEvidence,
    );
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
    ModificationSeedStrategy seedStrategy = ModificationSeedStrategy.base,
    int? specifiedSeed,
  }) async {
    if (recipeId.isEmpty) return null;
    final repository = _ref.read(promptRecipeRepositoryProvider);
    final recipe = await repository.get(recipeId);
    if (recipe == null) return null;

    final applied = PromptPatchService.apply(
      recipe,
      operations,
      policy: policy,
      seedStrategy: seedStrategy,
      specifiedSeed: specifiedSeed,
    );
    await repository.save(applied.recipe);

    final restored = PromptRecipeRestorationService.restore(applied.recipe);
    _applyRestored(
      restored,
      semanticEntries: applied.recipe.mainPromptEntries,
      retrievalEvidence: applied.recipe.retrievalEvidence,
    );
    return applied;
  }

  void _applyRestored(
    PromptRecipeRestorationResult restored, {
    bool keepAssets = false,
    List<PromptSemanticEntry>? semanticEntries,
    List<RetrievalEvidence>? retrievalEvidence,
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
    if (semanticEntries != null) {
      _ref
          .read(promptSemanticDraftProvider.notifier)
          .apply(
            prompt: restored.params.prompt,
            entries: semanticEntries,
            retrievalEvidence: retrievalEvidence ?? const [],
          );
    }
  }
}
