import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/cache/gallery_cache_manager.dart';
import '../../core/database/datasources/gallery_data_source.dart';
import '../../data/models/project/project_workspace.dart';
import '../../data/repositories/prompt_recipe_repository.dart';
import '../../data/services/gallery/unified_gallery_service.dart';
import '../../data/services/project_workspace_service.dart';
import 'gallery_folder_provider.dart';
import 'local_gallery_provider.dart';

class ProjectWorkspaceState {
  const ProjectWorkspaceState({
    this.current,
    this.isLoading = false,
    this.error,
    this.lastMigration,
  });

  final ProjectWorkspace? current;
  final bool isLoading;
  final String? error;
  final ProjectWorkspaceMigrationResult? lastMigration;

  ProjectWorkspaceState copyWith({
    ProjectWorkspace? current,
    bool clearCurrent = false,
    bool? isLoading,
    String? error,
    bool clearError = false,
    ProjectWorkspaceMigrationResult? lastMigration,
    bool clearLastMigration = false,
  }) => ProjectWorkspaceState(
    current: clearCurrent ? null : (current ?? this.current),
    isLoading: isLoading ?? this.isLoading,
    error: clearError ? null : (error ?? this.error),
    lastMigration: clearLastMigration
        ? null
        : (lastMigration ?? this.lastMigration),
  );
}

final projectWorkspaceProvider =
    StateNotifierProvider<ProjectWorkspaceNotifier, ProjectWorkspaceState>((
      ref,
    ) {
      final notifier = ProjectWorkspaceNotifier(ref);
      unawaited(notifier.load());
      return notifier;
    });

class ProjectWorkspaceNotifier extends StateNotifier<ProjectWorkspaceState> {
  ProjectWorkspaceNotifier(this._ref, {ProjectWorkspaceService? service})
    : _service = service ?? ProjectWorkspaceService.instance,
      super(const ProjectWorkspaceState(isLoading: true));

  final Ref _ref;
  final ProjectWorkspaceService _service;

  Future<void> load() async {
    try {
      final current = await _service.loadCurrent();
      if (!mounted) return;
      state = state.copyWith(
        current: current,
        clearCurrent: current == null,
        isLoading: false,
        clearError: true,
      );
    } catch (error) {
      if (!mounted) return;
      state = state.copyWith(isLoading: false, error: error.toString());
    }
  }

  Future<ProjectWorkspace?> openProject(String path, {String? name}) async {
    if (path.trim().isEmpty) return null;
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final workspace = await _service.open(path, name: name);
      if (!mounted) return workspace;
      state = state.copyWith(
        current: workspace,
        isLoading: false,
        clearError: true,
        clearLastMigration: true,
      );
      await _invalidateGallery();
      return workspace;
    } catch (error) {
      if (mounted) {
        state = state.copyWith(isLoading: false, error: error.toString());
      }
      return null;
    }
  }

  Future<void> closeProject() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _service.close();
      if (!mounted) return;
      state = state.copyWith(
        clearCurrent: true,
        isLoading: false,
        clearError: true,
        clearLastMigration: true,
      );
      await _invalidateGallery();
    } catch (error) {
      if (mounted) {
        state = state.copyWith(isLoading: false, error: error.toString());
      }
    }
  }

  Future<ProjectWorkspaceMigrationResult?> importLegacyContent() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final images = await _service.importLegacyImages();
      final repository = _ref.read(promptRecipeRepositoryProvider);
      final recipes = repository is ProjectAwarePromptRecipeRepository
          ? await repository.migrateLegacyRecipes()
          : const ProjectWorkspaceMigrationResult();
      final result = images.merge(recipes);
      if (!mounted) return result;
      state = state.copyWith(
        isLoading: false,
        lastMigration: result,
        clearError: true,
      );
      await _invalidateGallery();
      return result;
    } catch (error) {
      if (mounted) {
        state = state.copyWith(isLoading: false, error: error.toString());
      }
      return null;
    }
  }

  Future<void> _invalidateGallery() async {
    // Clear path-keyed memory caches before rebuilding providers. The SQLite
    // store is shared for backwards compatibility, while the fresh scanner
    // replaces the visible file set with the newly selected project.
    await GalleryCacheManager().clearL1MemoryCache();
    GalleryDataSource().clearCache();
    _ref.invalidate(galleryServiceProvider);
    _ref.invalidate(localGalleryNotifierProvider);
    _ref.invalidate(galleryFolderNotifierProvider);
  }
}
