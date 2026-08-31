import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/data/models/image/image_params.dart';
import 'package:nai_launcher/data/models/recipe/prompt_recipe.dart';
import 'package:nai_launcher/presentation/providers/generation/generation_result_lifecycle_service.dart';
import 'package:nai_launcher/presentation/services/generation_history_storage_service.dart';

class _MemoryRecipeRepository implements PromptRecipeRepository {
  PromptRecipe? saved;

  @override
  Future<PromptRecipe?> get(String id) async => saved?.id == id ? saved : null;

  @override
  Future<PromptRecipe?> getByGalleryItemId(String galleryItemId) async => null;

  @override
  Future<List<PromptRecipe>> list() async =>
      saved == null ? const [] : [saved!];

  @override
  Future<List<PromptRecipe>> listChildren(String parentRecipeId) async => [
    if (saved?.parentRecipeId == parentRecipeId) saved!,
  ];

  @override
  Future<PromptRecipe> save(PromptRecipe recipe) async {
    saved = recipe;
    return recipe;
  }

  @override
  Future<void> remove(String id) async {
    if (saved?.id == id) saved = null;
  }
}

GenerationResultLifecycleService _service({
  PromptRecipeRepository? recipeRepository,
}) {
  return GenerationResultLifecycleService(
    GenerationResultLifecycleDependencies(
      historyStorage: GenerationHistoryStorageService(enabled: false),
      resolveGalleryRootPath: () async => null,
      addGalleryImages: (_) async => 0,
      refreshGallery: () async {},
      incrementStatistics: (_) async {},
      recipeRepository: recipeRepository,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'saves a reusable recipe without retaining source image bytes',
    () async {
      final repository = _MemoryRecipeRepository();
      final service = _service(recipeRepository: repository);
      const character = RecipeCharacter(
        id: 'character-1',
        name: 'Alice',
        gender: 'female',
        prompt: '1girl',
        negativePrompt: 'bad anatomy',
        enabled: true,
        center: RecipeCharacterCenter(x: 1, y: 2),
      );
      final params = const ImageParams(
        prompt: '1girl, blue eyes',
        sourceImage: null,
      ).copyWith(sourceImage: Uint8List.fromList([1, 2, 3]));

      final recipe = await service.saveRecipe(
        params: params,
        characters: const [character],
        parentRecipeId: 'parent-recipe',
        sourceGalleryItemId: 'gallery-item',
        provider: 'novelai',
        providerModel: 'nai-diffusion-4-full',
      );

      expect(recipe, same(repository.saved));
      expect(recipe, isNotNull);
      expect(recipe!.parentRecipeId, 'parent-recipe');
      expect(recipe.sourceGalleryItemId, 'gallery-item');
      expect(recipe.provider, 'novelai');
      expect(recipe.providerModel, 'nai-diffusion-4-full');
      expect(recipe.request.params.sourceImage, isNull);
      expect(recipe.request.params.prompt, '1girl, blue eyes');
      expect(recipe.characters, [character]);
      expect(recipe.mainPromptEntries.map((entry) => entry.text), [
        '1girl',
        'blue eyes',
      ]);
      expect(recipe.structuredMain['subject'], ['1girl']);
      expect(recipe.structuredMain['appearance'], ['blue eyes']);
    },
  );

  test(
    'keeps preview-only lifecycle calls in memory when storage is absent',
    () async {
      final recipe = await _service().saveRecipe(params: const ImageParams());

      expect(recipe, isNull);
    },
  );
}
