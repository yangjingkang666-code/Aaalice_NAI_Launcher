import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path/path.dart' as p;

import '../../core/constants/storage_keys.dart';
import '../../core/utils/app_logger.dart';
import '../models/recipe/prompt_recipe.dart';
import '../models/project/project_workspace.dart';
import '../services/project_workspace_service.dart';

/// Hive-backed storage for binary-free prompt recipes.
///
/// Records are stored as JSON strings so this repository does not require a
/// Hive type adapter and remains portable across desktop/mobile platforms.
class HivePromptRecipeRepository implements PromptRecipeRepository {
  HivePromptRecipeRepository({Box<String>? box, String? boxName})
    : _box = box,
      _boxName = boxName ?? StorageKeys.promptRecipesBox;

  final String _boxName;
  Box<String>? _box;

  Future<Box<String>> _getBox() async {
    final current = _box;
    if (current != null && current.isOpen) return current;
    if (Hive.isBoxOpen(_boxName)) {
      _box = Hive.box<String>(_boxName);
    } else {
      _box = await Hive.openBox<String>(_boxName);
    }
    return _box!;
  }

  @override
  Future<PromptRecipe?> get(String id) async {
    if (id.isEmpty) return null;
    final box = await _getBox();
    final raw = box.get(id);
    if (raw == null || raw.isEmpty) return null;
    try {
      return PromptRecipe.decode(raw);
    } catch (error, stackTrace) {
      AppLogger.w(
        'Ignoring malformed prompt recipe $id: $error',
        'PromptRecipeRepository',
      );
      AppLogger.d(stackTrace.toString(), 'PromptRecipeRepository');
      return null;
    }
  }

  @override
  Future<PromptRecipe?> getByGalleryItemId(String galleryItemId) async {
    if (galleryItemId.isEmpty) return null;
    final recipes = await list();
    for (final recipe in recipes) {
      if (recipe.sourceGalleryItemId == galleryItemId ||
          recipe.request.imageToImage?.sourceGalleryItemId == galleryItemId) {
        return recipe;
      }
    }
    return null;
  }

  @override
  Future<List<PromptRecipe>> list() async {
    final box = await _getBox();
    final recipes = <PromptRecipe>[];
    for (final raw in box.values) {
      try {
        recipes.add(PromptRecipe.decode(raw));
      } catch (error, stackTrace) {
        AppLogger.w(
          'Ignoring malformed prompt recipe record: $error',
          'PromptRecipeRepository',
        );
        AppLogger.d(stackTrace.toString(), 'PromptRecipeRepository');
      }
    }
    recipes.sort((a, b) {
      final byDate = b.createdAt.compareTo(a.createdAt);
      return byDate != 0 ? byDate : b.id.compareTo(a.id);
    });
    return List.unmodifiable(recipes);
  }

  @override
  Future<List<PromptRecipe>> listChildren(String parentRecipeId) async {
    if (parentRecipeId.isEmpty) return const [];
    final recipes = await list();
    return List.unmodifiable(
      recipes.where((recipe) => recipe.parentRecipeId == parentRecipeId),
    );
  }

  @override
  Future<PromptRecipe> save(PromptRecipe recipe) async {
    final encoded = recipe.encode();
    await (await _getBox()).put(recipe.id, encoded);
    return recipe;
  }

  @override
  Future<void> remove(String id) async {
    if (id.isEmpty) return;
    await (await _getBox()).delete(id);
  }

  Future<void> clear() async => (await _getBox()).clear();
}

/// Routes recipes to the active project when project mode is enabled.
///
/// The Hive repository remains the compatibility store for users without a
/// project. Project files are intentionally one JSON document per recipe so a
/// project can be backed up, inspected, or moved without a Hive dependency.
class ProjectAwarePromptRecipeRepository implements PromptRecipeRepository {
  ProjectAwarePromptRecipeRepository({
    ProjectWorkspaceService? workspace,
    PromptRecipeRepository? legacy,
  }) : _workspace = workspace ?? ProjectWorkspaceService.instance,
       _legacy = legacy ?? HivePromptRecipeRepository();

  final ProjectWorkspaceService _workspace;
  final PromptRecipeRepository _legacy;

  @override
  Future<PromptRecipe?> get(String id) async {
    if (id.isEmpty) return null;
    final file = await _recipeFile(id);
    if (file == null) return _legacy.get(id);
    if (!await file.exists()) return null;
    return _decodeFile(file);
  }

  @override
  Future<PromptRecipe?> getByGalleryItemId(String galleryItemId) async {
    if (galleryItemId.isEmpty) return null;
    final recipes = await list();
    for (final recipe in recipes) {
      if (recipe.sourceGalleryItemId == galleryItemId ||
          recipe.request.imageToImage?.sourceGalleryItemId == galleryItemId) {
        return recipe;
      }
    }
    return null;
  }

  @override
  Future<List<PromptRecipe>> list() async {
    final directory = await _recipesDirectory();
    if (directory == null) return _legacy.list();
    if (!await directory.exists()) return const [];
    final recipes = <PromptRecipe>[];
    try {
      await for (final entity in directory.list(followLinks: false)) {
        if (entity is! File ||
            p.extension(entity.path).toLowerCase() != '.json') {
          continue;
        }
        final recipe = await _decodeFile(entity);
        if (recipe != null) recipes.add(recipe);
      }
    } catch (error, stackTrace) {
      AppLogger.w('读取项目配方目录失败: $error', 'PromptRecipeRepository');
      AppLogger.d(stackTrace.toString(), 'PromptRecipeRepository');
    }
    recipes.sort(_sortRecipes);
    return List.unmodifiable(recipes);
  }

  @override
  Future<List<PromptRecipe>> listChildren(String parentRecipeId) async {
    if (parentRecipeId.isEmpty) return const [];
    final recipes = await list();
    return List.unmodifiable(
      recipes.where((recipe) => recipe.parentRecipeId == parentRecipeId),
    );
  }

  @override
  Future<PromptRecipe> save(PromptRecipe recipe) async {
    final file = await _recipeFile(recipe.id);
    if (file == null) return _legacy.save(recipe);
    await file.parent.create(recursive: true);
    await _writeAtomically(file, recipe.encode());
    return recipe;
  }

  @override
  Future<void> remove(String id) async {
    if (id.isEmpty) return;
    final file = await _recipeFile(id);
    if (file == null) {
      await _legacy.remove(id);
      return;
    }
    if (await file.exists()) await file.delete();
  }

  /// Imports existing Hive recipes into the active project without replacing
  /// project files that already exist.
  Future<ProjectWorkspaceMigrationResult> migrateLegacyRecipes() async {
    final directory = await _recipesDirectory();
    if (directory == null) return const ProjectWorkspaceMigrationResult();
    await directory.create(recursive: true);
    final errors = <String>[];
    var copied = 0;
    var skipped = 0;
    for (final recipe in await _legacy.list()) {
      try {
        final file = File(
          p.join(directory.path, _safeRecipeFileName(recipe.id)),
        );
        if (await file.exists()) {
          skipped++;
          continue;
        }
        await _writeAtomically(file, recipe.encode());
        copied++;
      } catch (error) {
        errors.add('${recipe.id}: $error');
      }
    }
    return ProjectWorkspaceMigrationResult(
      copiedRecipes: copied,
      skippedRecipes: skipped,
      errors: errors,
    );
  }

  Future<Directory?> _recipesDirectory() async =>
      _workspace.getCurrentRecipesDirectory();

  Future<File?> _recipeFile(String id) async {
    if (id.isEmpty) return null;
    final directory = await _recipesDirectory();
    if (directory == null) return null;
    return File(p.join(directory.path, _safeRecipeFileName(id)));
  }

  Future<PromptRecipe?> _decodeFile(File file) async {
    try {
      return PromptRecipe.decode(await file.readAsString());
    } catch (error, stackTrace) {
      AppLogger.w(
        'Ignoring malformed project prompt recipe ${p.basename(file.path)}: $error',
        'PromptRecipeRepository',
      );
      AppLogger.d(stackTrace.toString(), 'PromptRecipeRepository');
      return null;
    }
  }

  Future<void> _writeAtomically(File target, String content) async {
    final temporary = File(
      '${target.path}.tmp-${DateTime.now().microsecondsSinceEpoch}',
    );
    await temporary.parent.create(recursive: true);
    try {
      await temporary.writeAsString(content, flush: true);
      try {
        await temporary.rename(target.path);
      } on FileSystemException {
        if (await target.exists()) await target.delete();
        await temporary.rename(target.path);
      }
    } finally {
      if (await temporary.exists()) {
        try {
          await temporary.delete();
        } catch (_) {}
      }
    }
  }

  int _sortRecipes(PromptRecipe a, PromptRecipe b) {
    final byDate = b.createdAt.compareTo(a.createdAt);
    return byDate != 0 ? byDate : b.id.compareTo(a.id);
  }

  String _safeRecipeFileName(String id) {
    final sanitized = id.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final value = sanitized.isEmpty ? 'recipe' : sanitized;
    return '$value.json';
  }
}

/// Application-scoped access point for the recipe store.
final promptRecipeRepositoryProvider = Provider<PromptRecipeRepository>(
  (ref) => ProjectAwarePromptRecipeRepository(),
);
