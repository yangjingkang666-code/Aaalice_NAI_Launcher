import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../core/constants/storage_keys.dart';
import '../../core/utils/app_logger.dart';
import '../models/recipe/prompt_recipe.dart';

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

/// Application-scoped access point for the recipe store.
final promptRecipeRepositoryProvider = Provider<PromptRecipeRepository>(
  (ref) => HivePromptRecipeRepository(),
);
