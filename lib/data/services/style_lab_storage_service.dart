import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/storage/local_storage_service.dart';
import '../../core/utils/app_logger.dart';
import '../models/style_lab/style_lab_models.dart';
import 'project_workspace_service.dart';

final styleLabStorageServiceProvider = Provider<StyleLabStorageService>((ref) {
  return StyleLabStorageService(
    storage: ref.read(localStorageServiceProvider),
    workspace: ProjectWorkspaceService.instance,
  );
});

/// Persists the style-lab session in the active project when one is open and
/// falls back to the existing settings box otherwise.
class StyleLabStorageService {
  StyleLabStorageService({
    LocalStorageService? storage,
    ProjectWorkspaceService? workspace,
    Future<Directory?> Function()? projectDataDirectoryResolver,
  }) : _storage = storage ?? LocalStorageService(),
       _workspace = workspace ?? ProjectWorkspaceService.instance,
       _projectDataDirectoryResolver = projectDataDirectoryResolver;

  static const storageKey = 'styleLab.session.v1';
  static const fileName = 'style-lab.json';

  final LocalStorageService _storage;
  final ProjectWorkspaceService _workspace;
  final Future<Directory?> Function()? _projectDataDirectoryResolver;

  Future<StyleLabSession?> load() async {
    try {
      final file = await _projectFile(ensure: false);
      if (file != null) {
        if (await file.exists()) {
          final decoded = jsonDecode(await file.readAsString());
          if (decoded is Map) {
            return StyleLabSession.fromJson(
              Map<String, dynamic>.from(decoded),
            );
          }
        }
        // A selected project has its own namespace. Do not leak a previous
        // global session into a newly opened project.
        return null;
      }
    } catch (error, stackTrace) {
      AppLogger.w('画风实验室项目会话读取失败: $error', 'StyleLabStorage');
      AppLogger.d(stackTrace.toString(), 'StyleLabStorage');
    }

    final raw = _storage.getSetting<String>(storageKey);
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return StyleLabSession.fromJson(Map<String, dynamic>.from(decoded));
      }
    } catch (error, stackTrace) {
      AppLogger.w('画风实验室全局会话读取失败: $error', 'StyleLabStorage');
      AppLogger.d(stackTrace.toString(), 'StyleLabStorage');
    }
    return null;
  }

  Future<void> save(StyleLabSession session) async {
    final encoded = jsonEncode(session.toJson());
    final file = await _projectFile(ensure: true);
    if (file != null) {
      try {
        await file.parent.create(recursive: true);
        final temporary = File('${file.path}.tmp');
        await temporary.writeAsString(encoded, flush: true);
        if (await file.exists()) await file.delete();
        await temporary.rename(file.path);
        return;
      } catch (error, stackTrace) {
        AppLogger.w('画风实验室项目会话写入失败，回退全局设置: $error', 'StyleLabStorage');
        AppLogger.d(stackTrace.toString(), 'StyleLabStorage');
      }
    }
    try {
      await _storage.setSetting(storageKey, encoded);
    } catch (error, stackTrace) {
      // Isolated tests can construct the service before Hive is initialized.
      // The in-memory session in the screen remains the source of truth then.
      AppLogger.w('画风实验室全局会话写入失败: $error', 'StyleLabStorage');
      AppLogger.d(stackTrace.toString(), 'StyleLabStorage');
    }
  }

  Future<File?> _projectFile({required bool ensure}) async {
    final directory = _projectDataDirectoryResolver != null
        ? await _projectDataDirectoryResolver()
        : await _workspace.getCurrentProjectDataDirectory(ensure: ensure);
    if (directory == null) return null;
    if (ensure) await directory.create(recursive: true);
    return File(p.join(directory.path, fileName));
  }
}
