import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/storage/local_storage_service.dart';
import '../../core/utils/app_logger.dart';
import '../models/project/project_workspace.dart';

/// Manages the optional project workspace on disk.
///
/// A workspace is deliberately additive: when no project is selected the
/// existing image-save path and Hive stores keep working unchanged. Once a
/// project is selected, generated images are saved below `images/` and
/// project-owned JSON is kept below `.novelai-cn/`.
class ProjectWorkspaceService {
  ProjectWorkspaceService({
    LocalStorageService? storage,
    Future<Directory> Function()? documentsDirectoryResolver,
    DateTime Function()? now,
    String Function()? idGenerator,
  }) : _storage = storage ?? LocalStorageService(),
       _documentsDirectoryResolver =
           documentsDirectoryResolver ?? getApplicationDocumentsDirectory,
       _now = now ?? DateTime.now,
       _idGenerator = idGenerator ?? (() => const Uuid().v4());

  static final ProjectWorkspaceService instance = ProjectWorkspaceService();

  static const String projectFolderName = '.novelai-cn';
  static const String imagesFolderName = 'images';
  static const String metadataFolderName = 'metadata';
  static const String recipesFolderName = 'recipes';
  static const String projectFileName = 'project.json';
  static const String knowledgeFileName = 'knowledge.json';

  static const Set<String> supportedImageExtensions = {
    '.png',
    '.jpg',
    '.jpeg',
    '.webp',
  };

  final LocalStorageService _storage;
  final Future<Directory> Function() _documentsDirectoryResolver;
  final DateTime Function() _now;
  final String Function() _idGenerator;

  ProjectWorkspace? _current;

  /// Returns the selected workspace, loading it from settings when needed.
  Future<ProjectWorkspace?> loadCurrent({bool ensureLayout = true}) async {
    final configuredPath = _storage.getProjectWorkspacePath();
    if (configuredPath == null || configuredPath.isEmpty) {
      _current = null;
      return null;
    }

    final canonicalPath = await _canonicalDirectoryPath(configuredPath);
    final descriptorPath = p.join(
      canonicalPath,
      projectFolderName,
      projectFileName,
    );
    ProjectWorkspace? workspace;
    var loadedDescriptor = false;
    final descriptor = File(descriptorPath);
    if (await descriptor.exists()) {
      try {
        final decoded = jsonDecode(await descriptor.readAsString());
        if (decoded is Map) {
          workspace = ProjectWorkspace.fromJson(
            Map<String, dynamic>.from(decoded),
          ).copyWith(path: canonicalPath);
          loadedDescriptor = true;
        }
      } catch (error, stackTrace) {
        AppLogger.w(
          'Ignoring malformed project descriptor: $error',
          'ProjectWorkspace',
        );
        AppLogger.d(stackTrace.toString(), 'ProjectWorkspace');
      }
    }
    workspace ??= ProjectWorkspace(
      id: _idGenerator(),
      path: canonicalPath,
      name: _defaultProjectName(canonicalPath),
      createdAt: _now().toUtc(),
      lastOpenedAt: _now().toUtc(),
    );

    if (ensureLayout) {
      await _ensureLayout(workspace);
      if (!loadedDescriptor || workspace.path != configuredPath) {
        await _writeDescriptor(workspace);
      }
    }
    _current = workspace;
    if (configuredPath != canonicalPath) {
      await _storage.setProjectWorkspacePath(canonicalPath);
    }
    return workspace;
  }

  /// Opens or creates a project directory and makes it the active workspace.
  Future<ProjectWorkspace> open(String path, {String? name}) async {
    final canonicalPath = await _canonicalDirectoryPath(path);
    final descriptor = File(
      p.join(canonicalPath, projectFolderName, projectFileName),
    );
    ProjectWorkspace? workspace;
    if (await descriptor.exists()) {
      try {
        final decoded = jsonDecode(await descriptor.readAsString());
        if (decoded is Map) {
          workspace =
              ProjectWorkspace.fromJson(
                Map<String, dynamic>.from(decoded),
              ).copyWith(
                path: canonicalPath,
                name: name?.trim().isNotEmpty == true ? name!.trim() : null,
                lastOpenedAt: _now().toUtc(),
              );
        }
      } catch (error) {
        AppLogger.w(
          'Creating a fresh project descriptor: $error',
          'ProjectWorkspace',
        );
      }
    }
    workspace ??= ProjectWorkspace(
      id: _idGenerator(),
      path: canonicalPath,
      name: name?.trim().isNotEmpty == true
          ? name!.trim()
          : _defaultProjectName(canonicalPath),
      createdAt: _now().toUtc(),
      lastOpenedAt: _now().toUtc(),
    );
    await _ensureLayout(workspace);
    await _writeDescriptor(workspace);
    await _storage.setProjectWorkspacePath(canonicalPath);
    _current = workspace;
    return workspace;
  }

  /// Leaves project mode and restores the legacy global gallery path.
  Future<void> close() async {
    _current = null;
    await _storage.setProjectWorkspacePath(null);
  }

  Future<ProjectWorkspace?> current() => loadCurrent();

  /// Returns the active project's image root, or null when project mode is off.
  Future<String?> getCurrentImagesPath({bool ensure = true}) async {
    final workspace = _current ?? await loadCurrent(ensureLayout: ensure);
    if (workspace == null) return null;
    if (ensure) await Directory(workspace.imagesPath).create(recursive: true);
    return workspace.imagesPath;
  }

  Future<Directory?> getCurrentProjectDataDirectory({
    bool ensure = true,
  }) async {
    final workspace = _current ?? await loadCurrent(ensureLayout: ensure);
    if (workspace == null) return null;
    final directory = Directory(workspace.projectDataPath);
    if (ensure) await directory.create(recursive: true);
    return directory;
  }

  Future<Directory?> getCurrentRecipesDirectory({bool ensure = true}) async {
    final workspace = _current ?? await loadCurrent(ensureLayout: ensure);
    if (workspace == null) return null;
    final directory = Directory(workspace.recipesPath);
    if (ensure) await directory.create(recursive: true);
    return directory;
  }

  Future<Directory?> getCurrentKnowledgeDirectory({bool ensure = true}) async {
    final workspace = _current ?? await loadCurrent(ensureLayout: ensure);
    if (workspace == null) return null;
    final directory = Directory(workspace.projectDataPath);
    if (ensure) await directory.create(recursive: true);
    return directory;
  }

  /// Resolves the old global image root without considering the active project.
  Future<String> legacyImagesPath() async {
    final customPath = _storage.getImageSavePath();
    if (customPath != null && customPath.trim().isNotEmpty) {
      return p.normalize(customPath.trim());
    }
    final documents = await _documentsDirectoryResolver();
    return p.join(documents.path, 'NAI_Launcher', imagesFolderName);
  }

  /// Copies legacy images into the active workspace without deleting or
  /// overwriting any existing files.
  Future<ProjectWorkspaceMigrationResult> importLegacyImages() async {
    final workspace = _current ?? await loadCurrent();
    if (workspace == null) {
      throw StateError('Open a project before importing legacy images.');
    }
    final sourcePath = await legacyImagesPath();
    final source = Directory(sourcePath);
    if (!await source.exists()) return const ProjectWorkspaceMigrationResult();
    final targetRoot = Directory(workspace.imagesPath);
    await targetRoot.create(recursive: true);
    // If the legacy root itself came from another project, carry its
    // portable metadata mirror along with the images as well.
    final sourceMetadataRoot = Directory(
      p.join(p.dirname(source.path), projectFolderName, metadataFolderName),
    );
    final errors = <String>[];
    var copied = 0;
    var skipped = 0;
    try {
      await for (final entity in source.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File || !_isSupportedImage(entity.path)) continue;
        final relative = p.relative(entity.path, from: source.path);
        if (relative.startsWith('..') || p.isAbsolute(relative)) continue;
        final destination = File(p.join(targetRoot.path, relative));
        try {
          if (await destination.exists()) {
            skipped++;
            continue;
          }
          await destination.parent.create(recursive: true);
          await entity.copy(destination.path);
          final sourceSidecar = File(
            p.join(sourceMetadataRoot.path, '$relative.json'),
          );
          if (await sourceSidecar.exists()) {
            final targetSidecar = await sidecarFileForImage(
              destination.path,
              ensure: true,
            );
            if (targetSidecar != null && !await targetSidecar.exists()) {
              await sourceSidecar.copy(targetSidecar.path);
            }
          }
          copied++;
        } catch (error) {
          errors.add('${entity.path}: $error');
        }
      }
    } catch (error) {
      errors.add('$sourcePath: $error');
    }
    return ProjectWorkspaceMigrationResult(
      copiedImages: copied,
      skippedImages: skipped,
      errors: errors,
    );
  }

  /// Returns the JSON sidecar path for a project-owned image.
  Future<File?> sidecarFileForImage(
    String imagePath, {
    bool ensure = false,
  }) async {
    final workspace = _current ?? await loadCurrent(ensureLayout: ensure);
    if (workspace == null) return null;
    final absoluteImage = p.normalize(File(imagePath).absolute.path);
    final imageRoot = p.normalize(
      Directory(workspace.imagesPath).absolute.path,
    );
    if (!_isWithin(imageRoot, absoluteImage)) return null;
    final relative = p.relative(absoluteImage, from: imageRoot);
    if (relative.isEmpty ||
        relative.startsWith('..') ||
        p.isAbsolute(relative)) {
      return null;
    }
    final sidecar = File(p.join(workspace.metadataPath, '$relative.json'));
    if (ensure) await sidecar.parent.create(recursive: true);
    return sidecar;
  }

  Future<void> writeImageSidecar({
    required String imagePath,
    String? imageId,
    String? recipeId,
    Map<String, dynamic>? metadata,
  }) async {
    // Sidecars are an optional project index. A read-only metadata directory
    // must never turn an otherwise successful image save into a failed save.
    try {
      final sidecar = await sidecarFileForImage(imagePath, ensure: true);
      if (sidecar == null) return;
      final workspace = _current ?? await loadCurrent();
      final imageRoot = workspace?.imagesPath;
      final absoluteImagePath = p.normalize(File(imagePath).absolute.path);
      final relativePath = imageRoot == null
          ? p.basename(absoluteImagePath)
          : p.relative(absoluteImagePath, from: imageRoot);
      final payload = <String, dynamic>{
        'schemaVersion': 1,
        'relativePath': relativePath,
        if (imageId != null && imageId.isNotEmpty) 'imageId': imageId,
        if (recipeId != null && recipeId.isNotEmpty) 'recipeId': recipeId,
        if (metadata != null) 'metadata': metadata,
        'updatedAt': _now().toUtc().millisecondsSinceEpoch,
      };
      await _writeJsonAtomically(sidecar, payload);
    } catch (error, stackTrace) {
      AppLogger.w('写入项目图片 sidecar 失败: $error', 'ProjectWorkspace');
      AppLogger.d(stackTrace.toString(), 'ProjectWorkspace');
    }
  }

  /// Moves the metadata sidecar that mirrors an image's relative path. This
  /// keeps prompt metadata attached when users organize a project gallery.
  Future<void> moveImageSidecar(
    String oldImagePath,
    String newImagePath,
  ) async {
    try {
      final oldSidecar = await sidecarFileForImage(oldImagePath);
      final newSidecar = await sidecarFileForImage(newImagePath);
      if (oldSidecar == null ||
          newSidecar == null ||
          p.normalize(oldSidecar.path) == p.normalize(newSidecar.path)) {
        return;
      }
      if (!await oldSidecar.exists() || await newSidecar.exists()) return;
      await newSidecar.parent.create(recursive: true);
      await oldSidecar.rename(newSidecar.path);
      await _removeEmptyParents(oldSidecar.parent);
    } catch (error, stackTrace) {
      AppLogger.w('移动项目图片 sidecar 失败: $error', 'ProjectWorkspace');
      AppLogger.d(stackTrace.toString(), 'ProjectWorkspace');
    }
  }

  /// Removes the metadata sidecar that mirrors a project-owned image.
  ///
  /// Deleting an image must not leave a stale prompt/recipe record that can
  /// be picked up by a later project import or backup. The operation is
  /// best-effort for the same reason as [writeImageSidecar].
  Future<void> deleteImageSidecar(String imagePath) async {
    try {
      final sidecar = await sidecarFileForImage(imagePath);
      if (sidecar == null || !await sidecar.exists()) return;
      await sidecar.delete();
      await _removeEmptyParents(sidecar.parent);
    } catch (error, stackTrace) {
      AppLogger.w('删除项目图片 sidecar 失败: $error', 'ProjectWorkspace');
      AppLogger.d(stackTrace.toString(), 'ProjectWorkspace');
    }
  }

  /// Moves or removes a metadata directory mirroring a gallery folder.
  Future<void> moveFolderSidecars(
    String oldFolderPath,
    String newFolderPath, {
    bool delete = false,
  }) async {
    try {
      final workspace = _current ?? await loadCurrent(ensureLayout: false);
      if (workspace == null) return;
      final root = p.normalize(Directory(workspace.imagesPath).absolute.path);
      final oldAbsolute = p.normalize(Directory(oldFolderPath).absolute.path);
      if (!_isWithin(root, oldAbsolute) || oldAbsolute == root) return;
      final relative = p.relative(oldAbsolute, from: root);
      if (relative.isEmpty ||
          relative.startsWith('..') ||
          p.isAbsolute(relative)) {
        return;
      }
      final oldSidecarDir = Directory(p.join(workspace.metadataPath, relative));
      if (!await oldSidecarDir.exists()) return;
      if (delete) {
        await oldSidecarDir.delete(recursive: true);
        await _removeEmptyParents(oldSidecarDir.parent);
        return;
      }
      final newAbsolute = p.normalize(Directory(newFolderPath).absolute.path);
      if (!_isWithin(root, newAbsolute) || newAbsolute == root) return;
      final newRelative = p.relative(newAbsolute, from: root);
      if (newRelative.isEmpty ||
          newRelative.startsWith('..') ||
          p.isAbsolute(newRelative)) {
        return;
      }
      final newSidecarDir = Directory(
        p.join(workspace.metadataPath, newRelative),
      );
      if (await newSidecarDir.exists()) return;
      await newSidecarDir.parent.create(recursive: true);
      await oldSidecarDir.rename(newSidecarDir.path);
      await _removeEmptyParents(oldSidecarDir.parent);
    } catch (error, stackTrace) {
      AppLogger.w('整理项目文件夹 sidecar 失败: $error', 'ProjectWorkspace');
      AppLogger.d(stackTrace.toString(), 'ProjectWorkspace');
    }
  }

  Future<Map<String, dynamic>?> readImageSidecar(String imagePath) async {
    final sidecar = await sidecarFileForImage(imagePath);
    if (sidecar == null || !await sidecar.exists()) return null;
    try {
      final decoded = jsonDecode(await sidecar.readAsString());
      if (decoded is! Map) return null;
      final result = Map<String, dynamic>.from(decoded);
      if (result['schemaVersion'] != 1) return null;
      return result;
    } catch (error) {
      AppLogger.w(
        'Ignoring malformed image sidecar: $error',
        'ProjectWorkspace',
      );
      return null;
    }
  }

  Future<String> _canonicalDirectoryPath(String rawPath) async {
    final trimmed = rawPath.trim();
    if (trimmed.isEmpty) throw const FormatException('Project path is empty.');
    final directory = Directory(trimmed);
    await directory.create(recursive: true);
    return p.normalize(await directory.resolveSymbolicLinks());
  }

  Future<void> _ensureLayout(ProjectWorkspace workspace) async {
    await Directory(workspace.imagesPath).create(recursive: true);
    await Directory(workspace.metadataPath).create(recursive: true);
    await Directory(workspace.recipesPath).create(recursive: true);
  }

  Future<void> _writeDescriptor(ProjectWorkspace workspace) async {
    await _writeJsonAtomically(
      File(workspace.descriptorPath),
      workspace.toJson(),
    );
  }

  Future<void> _writeJsonAtomically(
    File target,
    Map<String, dynamic> payload,
  ) async {
    await target.parent.create(recursive: true);
    final temp = File('${target.path}.tmp-${_idGenerator()}');
    try {
      await temp.writeAsString(jsonEncode(payload), flush: true);
      try {
        await temp.rename(target.path);
      } on FileSystemException {
        if (await target.exists()) await target.delete();
        await temp.rename(target.path);
      }
    } finally {
      if (await temp.exists()) {
        try {
          await temp.delete();
        } catch (_) {}
      }
    }
  }

  Future<void> _removeEmptyParents(Directory directory) async {
    final workspace = _current;
    if (workspace == null) return;
    final metadataRoot = p.normalize(
      Directory(workspace.metadataPath).absolute.path,
    );
    var current = p.normalize(directory.absolute.path);
    while (_isWithin(metadataRoot, current) && current != metadataRoot) {
      final dir = Directory(current);
      try {
        if ((await dir.list(followLinks: false).isEmpty)) {
          await dir.delete();
          current = p.normalize(dir.parent.absolute.path);
        } else {
          break;
        }
      } catch (_) {
        break;
      }
    }
  }

  bool _isSupportedImage(String path) =>
      supportedImageExtensions.contains(p.extension(path).toLowerCase());

  bool _isWithin(String root, String candidate) {
    if (Platform.isWindows) {
      return p.isWithin(root.toLowerCase(), candidate.toLowerCase());
    }
    return p.isWithin(root, candidate);
  }

  String _defaultProjectName(String path) {
    final name = p.basename(path);
    return name.isEmpty ? 'Project' : name;
  }
}
