import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/storage_keys.dart';
import '../../core/storage/local_storage_service.dart';
import 'dual_local_onnx_tagger_service.dart';
import 'local_onnx_model_service.dart';
import 'local_onnx_tagger_service.dart';
import 'local_tagger_execution_strategy.dart';

final localTaggerManagerServiceProvider = Provider<LocalTaggerManagerService>((
  ref,
) {
  return LocalTaggerManagerService(
    modelService: ref.read(localOnnxModelServiceProvider),
    storage: ref.read(localStorageServiceProvider),
  );
});

/// Validation result for one user-provided JoyTag/WD EVA02 model.
class LocalTaggerModelStatus {
  const LocalTaggerModelStatus({
    required this.model,
    required this.role,
    required this.modelAvailable,
    required this.labelsAvailable,
    required this.labelsValid,
    required this.modelSizeBytes,
    required this.labelCount,
    this.issue,
  });

  final LocalOnnxModelDescriptor model;
  final DualLocalTaggerRole? role;
  final bool modelAvailable;
  final bool labelsAvailable;
  final bool labelsValid;
  final int modelSizeBytes;
  final int labelCount;
  final String? issue;

  bool get isKnownRole => role != null;
  bool get isReady => isKnownRole && modelAvailable && labelsValid;

  String get roleName => role?.label ?? '未识别';
}

/// Snapshot consumed by settings and reverse-prompt surfaces.
class LocalTaggerEnvironmentStatus {
  const LocalTaggerEnvironmentStatus({
    required this.directory,
    required this.models,
    required this.preference,
    required this.executionStrategy,
  });

  final String directory;
  final List<LocalTaggerModelStatus> models;
  final LocalTaggerExecutionPreference preference;
  final LocalTaggerExecutionStrategy executionStrategy;

  LocalTaggerExecutionProvider get preferredProvider =>
      executionStrategy.preferredProvider;

  bool get hasJoyTag => models.any(
    (model) => model.role == DualLocalTaggerRole.joyTag && model.isReady,
  );

  bool get hasWdEva02 => models.any(
    (model) => model.role == DualLocalTaggerRole.wdEva02 && model.isReady,
  );

  bool get hasPair => hasJoyTag && hasWdEva02;

  int get readyModelCount => models.where((model) => model.isReady).length;

  int get knownModelCount => models.where((model) => model.isKnownRole).length;
}

/// Owns local tagger discovery, validation, and device-policy persistence.
///
/// This service never downloads a model. It only inspects files the user has
/// imported or selected, which keeps model provenance explicit and makes a
/// failed label companion visible before inference starts.
class LocalTaggerManagerService {
  LocalTaggerManagerService({
    required this.modelService,
    required this.storage,
    LocalOnnxTaggerService? tagger,
    bool? isWindows,
  }) : tagger = tagger ?? const LocalOnnxTaggerService(),
       isWindows = isWindows ?? Platform.isWindows;

  final LocalOnnxModelService modelService;
  final LocalStorageService storage;
  final LocalOnnxTaggerService tagger;
  final bool isWindows;

  LocalTaggerExecutionPreference get executionPreference =>
      LocalTaggerExecutionPreference.fromStorage(
        storage.getSetting<Object>(StorageKeys.onnxTaggerExecutionPreference),
      );

  Future<void> setExecutionPreference(
    LocalTaggerExecutionPreference preference,
  ) async {
    await storage.setSetting(
      StorageKeys.onnxTaggerExecutionPreference,
      preference.storageValue,
    );
  }

  Future<LocalTaggerEnvironmentStatus> inspect({String? directoryPath}) async {
    final descriptors = await modelService.scanTaggerModels(
      directoryPath: directoryPath,
    );
    final statuses = await Future.wait(descriptors.map(_inspectModel));
    final preference = executionPreference;
    return LocalTaggerEnvironmentStatus(
      directory: directoryPath?.trim().isNotEmpty == true
          ? directoryPath!.trim()
          : modelService.taggerDirectory,
      models: List.unmodifiable(statuses),
      preference: preference,
      executionStrategy: LocalTaggerExecutionStrategy(
        preference: preference,
        isWindows: isWindows,
      ),
    );
  }

  Future<LocalTaggerModelStatus> _inspectModel(
    LocalOnnxModelDescriptor model,
  ) async {
    final role = DualLocalOnnxTaggerService.roleFor(model);
    var modelAvailable = false;
    var modelSizeBytes = 0;
    try {
      final file = File(model.path);
      modelAvailable = await file.exists();
      if (modelAvailable) {
        modelSizeBytes = await file.length();
      }
    } catch (_) {
      modelAvailable = false;
    }

    final labelsPath = model.labelsPath;
    var labelsAvailable = false;
    var labelsValid = false;
    var labelCount = 0;
    String? issue;
    if (labelsPath == null || labelsPath.trim().isEmpty) {
      issue = 'missing_labels';
    } else {
      try {
        labelsAvailable = await File(labelsPath).exists();
        if (!labelsAvailable) {
          issue = 'missing_labels';
        } else {
          final labels = await tagger.loadLabels(labelsPath);
          labelCount = labels.length;
          labelsValid = labels.isNotEmpty;
          if (!labelsValid) issue = 'invalid_labels';
        }
      } catch (_) {
        issue = 'invalid_labels';
      }
    }
    if (!modelAvailable) issue = 'missing_model';

    return LocalTaggerModelStatus(
      model: model,
      role: role,
      modelAvailable: modelAvailable,
      labelsAvailable: labelsAvailable,
      labelsValid: labelsValid,
      modelSizeBytes: modelSizeBytes,
      labelCount: labelCount,
      issue: issue,
    );
  }
}
