import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/storage/local_storage_service.dart';
import 'package:nai_launcher/data/models/image/image_params.dart';
import 'package:nai_launcher/data/models/recipe/prompt_recipe.dart';
import 'package:nai_launcher/data/repositories/prompt_recipe_repository.dart';
import 'package:nai_launcher/data/services/project_workspace_service.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late _FakeStorage storage;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('nai_project_recipe_');
    storage = _FakeStorage();
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  ProjectWorkspaceService workspaceService() => ProjectWorkspaceService(
    storage: storage,
    documentsDirectoryResolver: () async => root,
    idGenerator: () => 'workspace-id',
  );

  test(
    'routes project recipes to JSON files and keeps them isolated',
    () async {
      final workspace = workspaceService();
      final projectPath = p.join(root.path, 'project');
      await workspace.open(projectPath);
      final repository = ProjectAwarePromptRecipeRepository(
        workspace: workspace,
        legacy: _MemoryRepository(),
      );
      final recipe = PromptRecipe.create(
        id: 'recipe/unsafe',
        params: const ImageParams(prompt: '1girl'),
      );

      await repository.save(recipe);
      expect(await repository.get(recipe.id), isNotNull);
      expect((await repository.list()).single.id, recipe.id);
      expect(
        await File(
          p.join(projectPath, '.novelai-cn', 'recipes', 'recipe_unsafe.json'),
        ).exists(),
        isTrue,
      );
      await repository.remove(recipe.id);
      expect(await repository.get(recipe.id), isNull);
    },
  );

  test('migrates legacy recipes without overwriting project files', () async {
    final legacy = _MemoryRepository();
    final first = PromptRecipe.create(
      id: 'recipe-1',
      params: const ImageParams(prompt: 'first'),
    );
    await legacy.save(first);
    final workspace = workspaceService();
    await workspace.open(p.join(root.path, 'project'));
    final repository = ProjectAwarePromptRecipeRepository(
      workspace: workspace,
      legacy: legacy,
    );

    final imported = await repository.migrateLegacyRecipes();
    expect(imported.copiedRecipes, 1);
    final repeated = await repository.migrateLegacyRecipes();
    expect(repeated.skippedRecipes, 1);
    expect((await repository.list()).single.id, first.id);
  });

  test(
    'falls back to legacy repository when project mode is disabled',
    () async {
      final legacy = _MemoryRepository();
      final repository = ProjectAwarePromptRecipeRepository(
        workspace: workspaceService(),
        legacy: legacy,
      );
      final recipe = PromptRecipe.create(
        params: const ImageParams(prompt: 'legacy'),
      );
      await repository.save(recipe);
      expect(legacy.saved?.id, recipe.id);
    },
  );
}

class _MemoryRepository implements PromptRecipeRepository {
  final List<PromptRecipe> records = [];
  PromptRecipe? get saved => records.isEmpty ? null : records.first;

  @override
  Future<PromptRecipe?> get(String id) async =>
      records.where((recipe) => recipe.id == id).firstOrNull;

  @override
  Future<PromptRecipe?> getByGalleryItemId(String galleryItemId) async => null;

  @override
  Future<List<PromptRecipe>> list() async => List.unmodifiable(records);

  @override
  Future<List<PromptRecipe>> listChildren(String parentRecipeId) async =>
      records
          .where((recipe) => recipe.parentRecipeId == parentRecipeId)
          .toList();

  @override
  Future<PromptRecipe> save(PromptRecipe recipe) async {
    records.removeWhere((item) => item.id == recipe.id);
    records.add(recipe);
    return recipe;
  }

  @override
  Future<void> remove(String id) async =>
      records.removeWhere((item) => item.id == id);
}

class _FakeStorage extends LocalStorageService {
  String? workspacePath;

  @override
  String? getProjectWorkspacePath() => workspacePath;

  @override
  Future<void> setProjectWorkspacePath(String? path) async {
    workspacePath = path;
  }
}
