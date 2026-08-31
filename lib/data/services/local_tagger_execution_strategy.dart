import 'dart:io';

/// User-facing preference for local JoyTag/WD EVA02 inference.
///
/// The preference is deliberately small and serializable so it can be shared
/// by the settings UI and the isolate-based ONNX runner without passing a
/// storage service into an isolate.
enum LocalTaggerExecutionPreference {
  automatic('automatic'),
  directMl('directml'),
  cpu('cpu');

  const LocalTaggerExecutionPreference(this.storageValue);

  final String storageValue;

  static LocalTaggerExecutionPreference fromStorage(Object? value) {
    final normalized = value?.toString().trim().toLowerCase();
    return switch (normalized) {
      'directml' || 'direct_ml' || 'dml' || 'gpu' => directMl,
      'cpu' => cpu,
      _ => automatic,
    };
  }
}

/// Provider actually used by a created ONNX session.
enum LocalTaggerExecutionProvider { directMl, cpu }

extension LocalTaggerExecutionProviderLabel on LocalTaggerExecutionProvider {
  String get displayName => switch (this) {
    LocalTaggerExecutionProvider.directMl => 'DirectML',
    LocalTaggerExecutionProvider.cpu => 'CPU',
  };
}

/// Resolves the provider to try first before a model session is created.
///
/// DirectML is only meaningful on Windows. The ONNX runner still performs a
/// second, guarded resolution at session creation time: a missing driver,
/// unsupported operator, or CPU-only runtime will transparently fall back to
/// CPU instead of making reverse prompting fail.
class LocalTaggerExecutionStrategy {
  LocalTaggerExecutionStrategy({
    this.preference = LocalTaggerExecutionPreference.automatic,
    bool? isWindows,
  }) : isWindows = isWindows ?? Platform.isWindows;

  final LocalTaggerExecutionPreference preference;
  final bool isWindows;

  bool get directMlEligible => isWindows;

  LocalTaggerExecutionProvider get preferredProvider {
    if (!isWindows || preference == LocalTaggerExecutionPreference.cpu) {
      return LocalTaggerExecutionProvider.cpu;
    }
    return LocalTaggerExecutionProvider.directMl;
  }

  String get explanation {
    if (!isWindows) {
      return '当前平台不支持 DirectML，使用 CPU';
    }
    if (preference == LocalTaggerExecutionPreference.cpu) {
      return '已固定使用 CPU';
    }
    return '优先尝试 DirectML；会话创建或推理失败时自动回退 CPU';
  }
}
