import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'local_onnx_model_service.dart';
import 'local_onnx_tagger_service.dart';

final dualLocalOnnxTaggerServiceProvider = Provider<DualLocalOnnxTaggerService>(
  (ref) => DualLocalOnnxTaggerService(
    tagger: ref.read(localOnnxTaggerServiceProvider),
  ),
);

enum DualLocalTaggerRole { joyTag, wdEva02 }

extension DualLocalTaggerRoleLabel on DualLocalTaggerRole {
  String get label => switch (this) {
    DualLocalTaggerRole.joyTag => 'JoyTag',
    DualLocalTaggerRole.wdEva02 => 'WD EVA02',
  };
}

class DualLocalTaggerModelSelection {
  const DualLocalTaggerModelSelection({
    required this.joyTag,
    required this.wdEva02,
  });

  final LocalOnnxModelDescriptor joyTag;
  final LocalOnnxModelDescriptor wdEva02;
}

class DualLocalTaggerEvidence {
  const DualLocalTaggerEvidence({
    required this.role,
    required this.model,
    required this.device,
    this.tags = const [],
    this.error,
  });

  final DualLocalTaggerRole role;
  final LocalOnnxModelDescriptor model;
  final String device;
  final List<OnnxTaggerTag> tags;
  final String? error;

  bool get succeeded => error == null;

  String get prompt => tags.map((tag) => tag.name).join(', ');
}

class DualLocalTaggerResult {
  const DualLocalTaggerResult({required this.evidence});

  final List<DualLocalTaggerEvidence> evidence;

  bool get hasSuccess => evidence.any((item) => item.succeeded);

  String get combinedPrompt {
    final seen = <String>{};
    return evidence
        .expand((item) => item.tags)
        .where((tag) => seen.add(tag.name.trim().toLowerCase()))
        .map((tag) => tag.name)
        .join(', ');
  }

  /// Compact audit text suitable for a review panel and for the cloud model's
  /// secondary evidence input. Errors are retained instead of being hidden.
  String get auditText => evidence
      .map(
        (item) => [
          '${item.role.label} · ${item.succeeded ? 'success' : 'failed'} · ${item.device}',
          if (item.succeeded) 'tags: ${item.prompt}',
          if (!item.succeeded) 'error: ${item.error}',
        ].join('\n'),
      )
      .join('\n\n');
}

typedef DualLocalTaggerRunner =
    Future<OnnxTaggerResult> Function({
      required Uint8List imageBytes,
      required LocalOnnxModelDescriptor model,
      required double generalThreshold,
      required double characterThreshold,
    });

/// Thin adapter for running JoyTag and WD EVA02 one after the other.
///
/// The models are user-provided ONNX files discovered by the existing model
/// service. No model is bundled or downloaded here. Running sequentially keeps
/// peak memory predictable on small Windows GPUs, and an individual failure is
/// retained as evidence while the other model continues.
class DualLocalOnnxTaggerService {
  DualLocalOnnxTaggerService({
    LocalOnnxTaggerService? tagger,
    DualLocalTaggerRunner? runner,
  }) : _tagger = tagger ?? const LocalOnnxTaggerService(),
       _runner = runner;

  final LocalOnnxTaggerService _tagger;
  final DualLocalTaggerRunner? _runner;

  static DualLocalTaggerRole? roleFor(LocalOnnxModelDescriptor model) {
    final value = '${model.name} ${model.path}'.toLowerCase();
    if (value.contains('joytag') || value.contains('joy-tag')) {
      return DualLocalTaggerRole.joyTag;
    }
    if (value.contains('eva02') ||
        value.contains('eva-02') ||
        value.contains('wd-eva') ||
        value.contains('wd14') ||
        value.contains('wd-v1-')) {
      return DualLocalTaggerRole.wdEva02;
    }
    return null;
  }

  static DualLocalTaggerModelSelection? findPair(
    Iterable<LocalOnnxModelDescriptor> models, {
    String? joyTagPath,
    String? wdEva02Path,
  }) {
    final list = models.toList(growable: false);
    LocalOnnxModelDescriptor? find(
      DualLocalTaggerRole role,
      String? selectedPath,
    ) {
      if (selectedPath != null) {
        for (final model in list) {
          if (model.path == selectedPath && roleFor(model) == role) {
            return model;
          }
        }
      }
      for (final model in list) {
        if (roleFor(model) == role) return model;
      }
      return null;
    }

    final joy = find(DualLocalTaggerRole.joyTag, joyTagPath);
    final wd = find(DualLocalTaggerRole.wdEva02, wdEva02Path);
    if (joy == null || wd == null || joy.path == wd.path) return null;
    return DualLocalTaggerModelSelection(joyTag: joy, wdEva02: wd);
  }

  Future<DualLocalTaggerResult> tagImage({
    required Uint8List imageBytes,
    required DualLocalTaggerModelSelection models,
    double generalThreshold = 0.35,
    double characterThreshold = 0.35,
  }) async {
    final evidence = <DualLocalTaggerEvidence>[];
    for (final item in [
      (DualLocalTaggerRole.joyTag, models.joyTag),
      (DualLocalTaggerRole.wdEva02, models.wdEva02),
    ]) {
      try {
        final runner = _runner;
        final result = runner == null
            ? await _tagger.tagImage(
                imageBytes: imageBytes,
                model: item.$2,
                generalThreshold: generalThreshold,
                characterThreshold: characterThreshold,
              )
            : await runner(
                imageBytes: imageBytes,
                model: item.$2,
                generalThreshold: generalThreshold,
                characterThreshold: characterThreshold,
              );
        evidence.add(
          DualLocalTaggerEvidence(
            role: item.$1,
            model: item.$2,
            device: 'ONNX Runtime（本地）',
            tags: result.tags,
          ),
        );
      } catch (error) {
        evidence.add(
          DualLocalTaggerEvidence(
            role: item.$1,
            model: item.$2,
            device: 'ONNX Runtime（本地）',
            error: error.toString(),
          ),
        );
      }
    }
    return DualLocalTaggerResult(evidence: List.unmodifiable(evidence));
  }
}
