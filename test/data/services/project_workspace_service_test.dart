import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/storage/local_storage_service.dart';
import 'package:nai_launcher/data/services/project_workspace_service.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late Directory documents;
  late _FakeStorage storage;
  late int idIndex;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('nai_project_workspace_');
    documents = Directory(p.join(root.path, 'documents'));
    await documents.create(recursive: true);
    storage = _FakeStorage();
    idIndex = 0;
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  ProjectWorkspaceService createService() => ProjectWorkspaceService(
    storage: storage,
    documentsDirectoryResolver: () async => documents,
    now: () => DateTime.utc(2026, 8, 31, 12),
    idGenerator: () => 'project-${++idIndex}',
  );

  test('opens a portable layout and restores the descriptor', () async {
    final service = createService();
    final workspace = await service.open(p.join(root.path, 'art'));

    expect(workspace.id, 'project-1');
    expect(await Directory(workspace.imagesPath).exists(), isTrue);
    expect(await Directory(workspace.metadataPath).exists(), isTrue);
    expect(await Directory(workspace.recipesPath).exists(), isTrue);
    expect(
      jsonDecode(
        await File(workspace.descriptorPath).readAsString(),
      )['schemaVersion'],
      1,
    );

    final restored = await ProjectWorkspaceService(
      storage: storage,
      documentsDirectoryResolver: () async => documents,
      now: () => DateTime.utc(2026, 8, 31, 13),
      idGenerator: () => 'unexpected',
    ).loadCurrent();
    expect(restored!.id, workspace.id);
    expect(restored.path, workspace.path);
  });

  test(
    'writes and reads image sidecars while rejecting outside files',
    () async {
      final service = createService();
      final workspace = await service.open(p.join(root.path, 'project'));
      final image = File(p.join(workspace.imagesPath, '2026', 'one.png'));
      await image.parent.create(recursive: true);
      await image.writeAsBytes([1, 2, 3]);

      await service.writeImageSidecar(
        imagePath: image.path,
        imageId: 'image-1',
        recipeId: 'recipe-1',
        metadata: const {'prompt': 'a girl'},
      );
      final sidecar = await service.sidecarFileForImage(image.path);
      expect(sidecar, isNotNull);
      expect(await sidecar!.exists(), isTrue);
      expect(
        (await service.readImageSidecar(image.path))!['recipeId'],
        'recipe-1',
      );
      expect(
        await service.sidecarFileForImage(p.join(root.path, 'outside.png')),
        isNull,
      );
    },
  );

  test('imports legacy images without overwriting project files', () async {
    final legacy = Directory(p.join(root.path, 'legacy-images'));
    final legacyImage = File(p.join(legacy.path, 'nested', 'one.png'));
    await legacyImage.parent.create(recursive: true);
    await legacyImage.writeAsBytes([1, 2, 3]);
    storage.imageSavePath = legacy.path;

    final service = createService();
    final workspace = await service.open(p.join(root.path, 'project'));
    final existing = File(p.join(workspace.imagesPath, 'nested', 'one.png'));
    await existing.parent.create(recursive: true);
    await existing.writeAsBytes([9]);

    final first = await service.importLegacyImages();
    expect(first.copiedImages, 0);
    expect(first.skippedImages, 1);
    expect(await existing.readAsBytes(), [9]);

    final secondLegacy = File(p.join(legacy.path, 'two.jpg'));
    await secondLegacy.writeAsBytes([4, 5]);
    final second = await service.importLegacyImages();
    expect(second.copiedImages, 1);
    expect(await File(p.join(workspace.imagesPath, 'two.jpg')).readAsBytes(), [
      4,
      5,
    ]);
  });

  test('moves image and folder sidecars with gallery organization', () async {
    final service = createService();
    final workspace = await service.open(p.join(root.path, 'project'));
    final image = File(p.join(workspace.imagesPath, 'old', 'one.png'));
    await image.parent.create(recursive: true);
    await image.writeAsBytes([1]);
    await service.writeImageSidecar(
      imagePath: image.path,
      metadata: const {'prompt': 'a girl'},
    );

    final movedImage = p.join(workspace.imagesPath, 'new', 'one.png');
    await File(movedImage).parent.create(recursive: true);
    await service.moveImageSidecar(image.path, movedImage);
    expect(await service.readImageSidecar(movedImage), isNotNull);
    expect(await service.readImageSidecar(image.path), isNull);

    await service.deleteImageSidecar(movedImage);
    expect(await service.readImageSidecar(movedImage), isNull);

    await service.writeImageSidecar(
      imagePath: movedImage,
      metadata: const {'prompt': 'a girl'},
    );

    final movedFolder = p.join(workspace.imagesPath, 'renamed');
    await service.moveFolderSidecars(
      p.join(workspace.imagesPath, 'new'),
      movedFolder,
    );
    expect(
      await service.readImageSidecar(p.join(movedFolder, 'one.png')),
      isNotNull,
    );

    await service.moveFolderSidecars(movedFolder, movedFolder, delete: true);
    expect(
      await service.readImageSidecar(p.join(movedFolder, 'one.png')),
      isNull,
    );
  });
}

class _FakeStorage extends LocalStorageService {
  String? workspacePath;
  String? imageSavePath;

  @override
  String? getProjectWorkspacePath() => workspacePath;

  @override
  Future<void> setProjectWorkspacePath(String? path) async {
    workspacePath = path;
  }

  @override
  String? getImageSavePath() => imageSavePath;
}
