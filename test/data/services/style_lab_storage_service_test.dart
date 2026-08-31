import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/storage/local_storage_service.dart';
import 'package:nai_launcher/data/models/image/image_params.dart';
import 'package:nai_launcher/data/models/style_lab/style_lab_models.dart';
import 'package:nai_launcher/data/services/style_lab_storage_service.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('nai_style_lab_');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('project sessions are isolated from global settings', () async {
    final storage = _MemoryStorage();
    final projectService = StyleLabStorageService(
      storage: storage,
      projectDataDirectoryResolver: () async => root,
    );
    final session = StyleLabSession.initial(
      const ImageParams(prompt: 'project prompt'),
    );
    await projectService.save(session);

    final restored = await projectService.load();
    expect(restored?.basePrompt, 'project prompt');
    expect(await File('${root.path}/style-lab.json').exists(), isTrue);

    final anotherProject = await Directory.systemTemp.createTemp(
      'nai_style_lab_other_',
    );
    addTearDown(() async {
      if (await anotherProject.exists()) {
        await anotherProject.delete(recursive: true);
      }
    });
    final empty = StyleLabStorageService(
      storage: storage,
      projectDataDirectoryResolver: () async => anotherProject,
    );
    expect(await empty.load(), isNull);
  });

  test('falls back to the settings box when no project is active', () async {
    final storage = _MemoryStorage();
    final service = StyleLabStorageService(
      storage: storage,
      projectDataDirectoryResolver: () async => null,
    );
    final session = StyleLabSession.initial(
      const ImageParams(prompt: 'global prompt'),
    );
    await service.save(session);
    final restored = await service.load();
    expect(restored?.basePrompt, 'global prompt');
  });
}

class _MemoryStorage extends LocalStorageService {
  final values = <String, Object?>{};

  @override
  T? getSetting<T>(String key, {T? defaultValue}) {
    return (values[key] as T?) ?? defaultValue;
  }

  @override
  Future<void> setSetting<T>(String key, T value) async {
    values[key] = value;
  }
}
