import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/constants/storage_keys.dart';
import 'package:nai_launcher/core/storage/local_storage_service.dart';
import 'package:nai_launcher/data/services/local_onnx_model_service.dart';
import 'package:nai_launcher/data/services/local_tagger_execution_strategy.dart';
import 'package:nai_launcher/data/services/local_tagger_manager_service.dart';

void main() {
  late Directory tempDirectory;
  late _MemoryLocalStorage storage;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp(
      'local_tagger_manager_service_test_',
    );
    storage = _MemoryLocalStorage();
  });

  tearDown(() async {
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test(
    'resolves DirectML preference with a CPU fallback on unsupported OS',
    () {
      final automatic = LocalTaggerExecutionStrategy(
        preference: LocalTaggerExecutionPreference.automatic,
        isWindows: true,
      );
      expect(automatic.directMlEligible, isTrue);
      expect(
        automatic.preferredProvider,
        LocalTaggerExecutionProvider.directMl,
      );

      final unsupported = LocalTaggerExecutionStrategy(
        preference: LocalTaggerExecutionPreference.directMl,
        isWindows: false,
      );
      expect(unsupported.directMlEligible, isFalse);
      expect(unsupported.preferredProvider, LocalTaggerExecutionProvider.cpu);
    },
  );

  test('inspects model roles and label companions before inference', () async {
    final joyPath = await File(
      '${tempDirectory.path}${Platform.pathSeparator}joytag.onnx',
    ).writeAsBytes([1, 2, 3]);
    final joyLabels = await File(
      '${tempDirectory.path}${Platform.pathSeparator}joy_labels.csv',
    ).writeAsString('name,category\n1girl,0\n');
    final wdPath = await File(
      '${tempDirectory.path}${Platform.pathSeparator}wd-eva02.onnx',
    ).writeAsBytes([4, 5, 6]);

    final modelService = _FakeModelService(
      storage,
      directory: tempDirectory.path,
      models: [
        LocalOnnxModelDescriptor(
          name: 'joytag.onnx',
          path: joyPath.path,
          kind: LocalOnnxModelKind.unknown,
          labelsPath: joyLabels.path,
        ),
        LocalOnnxModelDescriptor(
          name: 'wd-eva02.onnx',
          path: wdPath.path,
          kind: LocalOnnxModelKind.wd14Tagger,
        ),
      ],
    );
    final manager = LocalTaggerManagerService(
      modelService: modelService,
      storage: storage,
      isWindows: true,
    );

    final status = await manager.inspect();

    expect(status.models, hasLength(2));
    expect(status.hasJoyTag, isTrue);
    expect(status.hasWdEva02, isFalse);
    expect(status.hasPair, isFalse);
    expect(status.models.first.isReady, isTrue);
    expect(status.models.last.issue, 'missing_labels');
    expect(status.preferredProvider, LocalTaggerExecutionProvider.directMl);
  });

  test(
    'persists the selected execution preference for later inspections',
    () async {
      final modelService = _FakeModelService(
        storage,
        directory: tempDirectory.path,
        models: const [],
      );
      final manager = LocalTaggerManagerService(
        modelService: modelService,
        storage: storage,
        isWindows: true,
      );

      await manager.setExecutionPreference(LocalTaggerExecutionPreference.cpu);
      final status = await manager.inspect();

      expect(status.preference, LocalTaggerExecutionPreference.cpu);
      expect(storage.values[StorageKeys.onnxTaggerExecutionPreference], 'cpu');
      expect(status.preferredProvider, LocalTaggerExecutionProvider.cpu);
    },
  );
}

class _FakeModelService extends LocalOnnxModelService {
  _FakeModelService(
    super.storage, {
    required this.directory,
    required this.models,
  });

  final String directory;
  final List<LocalOnnxModelDescriptor> models;

  @override
  String get taggerDirectory => directory;

  @override
  Future<List<LocalOnnxModelDescriptor>> scanTaggerModels({
    String? directoryPath,
  }) async => models;
}

class _MemoryLocalStorage extends LocalStorageService {
  final Map<String, Object?> values = {};

  @override
  T? getSetting<T>(String key, {T? defaultValue}) {
    return values.containsKey(key) ? values[key] as T? : defaultValue;
  }

  @override
  Future<void> setSetting<T>(String key, T value) async {
    values[key] = value;
  }
}
