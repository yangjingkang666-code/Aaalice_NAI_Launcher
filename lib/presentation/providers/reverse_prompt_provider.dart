import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/storage_keys.dart';
import '../../core/storage/local_storage_service.dart';
import '../../data/models/character/character_prompt.dart';
import '../../data/services/dual_local_onnx_tagger_service.dart';
import '../../data/services/local_onnx_model_service.dart';
import '../../data/services/local_onnx_tagger_service.dart';
import '../prompt_assistant/models/prompt_assistant_models.dart';
import '../prompt_assistant/models/reverse_prompt_models.dart';
import '../prompt_assistant/services/prompt_assistant_api_client.dart';
import '../prompt_assistant/services/prompt_assistant_service.dart';
import '../utils/reverse_prompt_image_normalizer.dart';

final reversePromptProvider =
    StateNotifierProvider<ReversePromptNotifier, ReversePromptState>((ref) {
      return ReversePromptNotifier(ref);
    });

final reversePromptCharacterProvider =
    StateNotifierProvider<
      ReversePromptCharacterNotifier,
      CharacterPromptConfig
    >((ref) {
      return ReversePromptCharacterNotifier(ref);
    });

class ReversePromptCharacterNotifier
    extends StateNotifier<CharacterPromptConfig> {
  ReversePromptCharacterNotifier(this._ref)
    : super(const CharacterPromptConfig()) {
    _load();
  }

  final Ref _ref;

  LocalStorageService get _storage => _ref.read(localStorageServiceProvider);

  CharacterPrompt? get selectedCharacter {
    for (final character in state.characters) {
      if (character.enabled && character.prompt.trim().isNotEmpty) {
        return character;
      }
    }
    return null;
  }

  void _load() {
    final raw = _storage.getSetting<String>(
      StorageKeys.reversePromptCharacterConfigJson,
    );
    if (raw == null || raw.isEmpty) {
      return;
    }
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      state = CharacterPromptConfig.fromJson(decoded);
    } catch (_) {
      state = const CharacterPromptConfig();
    }
  }

  Future<void> _save() async {
    await _storage.setSetting(
      StorageKeys.reversePromptCharacterConfigJson,
      jsonEncode(state.toJson()),
    );
  }

  void setReplacementCharacter(CharacterPrompt character) {
    state = CharacterPromptConfig(
      characters: [character.copyWith(enabled: true)],
    );
    _save();
  }

  void clearReplacementCharacter() {
    state = const CharacterPromptConfig();
    _save();
  }
}

class ReversePromptImage {
  const ReversePromptImage({required this.id, required this.bytes, this.name});

  final String id;
  final Uint8List bytes;
  final String? name;
}

enum ReversePromptProcessingStage {
  preparing,
  onnxTagger,
  dualLocalTagger,
  llmReverse,
  integration,
  characterReplace,
}

enum ReversePromptStageStatus { running, succeeded, failed }

/// A small, UI-safe audit record for one reverse-prompt stage.
///
/// It deliberately contains route/model names and bounded output previews, but
/// never image bytes or API keys. The full provider response, when available,
/// remains in [ReversePromptDraft.rawResponse].
class ReversePromptStageAudit {
  const ReversePromptStageAudit({
    required this.stage,
    required this.status,
    this.routeLabel = '',
    this.outputPreview = '',
    this.error,
    this.rawResponse,
    this.durationMs,
  });

  final ReversePromptProcessingStage stage;
  final ReversePromptStageStatus status;
  final String routeLabel;
  final String outputPreview;
  final String? error;
  final String? rawResponse;
  final int? durationMs;

  ReversePromptStageAudit copyWith({
    ReversePromptStageStatus? status,
    String? routeLabel,
    String? outputPreview,
    String? error,
    bool clearError = false,
    String? rawResponse,
    bool clearRawResponse = false,
    int? durationMs,
  }) {
    return ReversePromptStageAudit(
      stage: stage,
      status: status ?? this.status,
      routeLabel: routeLabel ?? this.routeLabel,
      outputPreview: outputPreview ?? this.outputPreview,
      error: clearError ? null : error ?? this.error,
      rawResponse: clearRawResponse ? null : rawResponse ?? this.rawResponse,
      durationMs: durationMs ?? this.durationMs,
    );
  }
}

class _ReversePromptUiError implements Exception {
  const _ReversePromptUiError(this.key);

  final String key;
}

class ReversePromptState {
  const ReversePromptState({
    this.images = const [],
    this.useOnnxTagger = true,
    this.useDualLocalTagger = false,
    this.useLlmReverse = true,
    this.useCharacterReplace = false,
    this.selectedImageId,
    this.selectedTaggerModelPath,
    this.selectedJoyTaggerModelPath,
    this.selectedWdEva02ModelPath,
    this.selectedCharacterId,
    this.taggerGeneralThreshold = 0.35,
    this.taggerCharacterThreshold = 0.35,
    this.taggerPrompt = '',
    this.dualTaggerPrompt = '',
    this.llmPrompt = '',
    this.characterReplacePrompt = '',
    this.finalPrompt = '',
    this.draft,
    this.reviewPositivePrompt = '',
    this.reviewNegativePrompt = '',
    this.stageAudits = const [],
    this.lastRawResponse,
    this.isProcessing = false,
    this.processingStage,
    this.error,
  });

  final List<ReversePromptImage> images;
  final bool useOnnxTagger;
  final bool useDualLocalTagger;
  final bool useLlmReverse;
  final bool useCharacterReplace;
  final String? selectedImageId;
  final String? selectedTaggerModelPath;
  final String? selectedJoyTaggerModelPath;
  final String? selectedWdEva02ModelPath;
  final String? selectedCharacterId;
  final double taggerGeneralThreshold;
  final double taggerCharacterThreshold;
  final String taggerPrompt;
  final String dualTaggerPrompt;
  final String llmPrompt;
  final String characterReplacePrompt;
  final String finalPrompt;
  final ReversePromptDraft? draft;
  final String reviewPositivePrompt;
  final String reviewNegativePrompt;
  final List<ReversePromptStageAudit> stageAudits;
  final String? lastRawResponse;
  final bool isProcessing;
  final ReversePromptProcessingStage? processingStage;
  final String? error;

  bool get canRun =>
      images.isNotEmpty &&
      (useOnnxTagger || useDualLocalTagger || useLlmReverse);

  bool get hasReviewableDraft =>
      draft != null && reviewPositivePrompt.trim().isNotEmpty;

  ReversePromptImage? get selectedImage {
    final id = selectedImageId;
    if (id != null) {
      for (final image in images) {
        if (image.id == id) return image;
      }
    }
    return images.isEmpty ? null : images.first;
  }

  ReversePromptState copyWith({
    List<ReversePromptImage>? images,
    bool? useOnnxTagger,
    bool? useDualLocalTagger,
    bool? useLlmReverse,
    bool? useCharacterReplace,
    String? selectedImageId,
    bool clearSelectedImageId = false,
    String? selectedTaggerModelPath,
    bool clearSelectedTaggerModelPath = false,
    String? selectedJoyTaggerModelPath,
    bool clearSelectedJoyTaggerModelPath = false,
    String? selectedWdEva02ModelPath,
    bool clearSelectedWdEva02ModelPath = false,
    String? selectedCharacterId,
    bool clearSelectedCharacterId = false,
    double? taggerGeneralThreshold,
    double? taggerCharacterThreshold,
    String? taggerPrompt,
    String? dualTaggerPrompt,
    String? llmPrompt,
    String? characterReplacePrompt,
    String? finalPrompt,
    ReversePromptDraft? draft,
    bool clearDraft = false,
    String? reviewPositivePrompt,
    String? reviewNegativePrompt,
    List<ReversePromptStageAudit>? stageAudits,
    String? lastRawResponse,
    bool clearLastRawResponse = false,
    bool? isProcessing,
    ReversePromptProcessingStage? processingStage,
    bool clearProcessingStage = false,
    String? error,
    bool clearError = false,
  }) {
    return ReversePromptState(
      images: images ?? this.images,
      useOnnxTagger: useOnnxTagger ?? this.useOnnxTagger,
      useDualLocalTagger: useDualLocalTagger ?? this.useDualLocalTagger,
      useLlmReverse: useLlmReverse ?? this.useLlmReverse,
      useCharacterReplace: useCharacterReplace ?? this.useCharacterReplace,
      selectedImageId: clearSelectedImageId
          ? null
          : selectedImageId ?? this.selectedImageId,
      selectedTaggerModelPath: clearSelectedTaggerModelPath
          ? null
          : selectedTaggerModelPath ?? this.selectedTaggerModelPath,
      selectedJoyTaggerModelPath: clearSelectedJoyTaggerModelPath
          ? null
          : selectedJoyTaggerModelPath ?? this.selectedJoyTaggerModelPath,
      selectedWdEva02ModelPath: clearSelectedWdEva02ModelPath
          ? null
          : selectedWdEva02ModelPath ?? this.selectedWdEva02ModelPath,
      selectedCharacterId: clearSelectedCharacterId
          ? null
          : selectedCharacterId ?? this.selectedCharacterId,
      taggerGeneralThreshold:
          taggerGeneralThreshold ?? this.taggerGeneralThreshold,
      taggerCharacterThreshold:
          taggerCharacterThreshold ?? this.taggerCharacterThreshold,
      taggerPrompt: taggerPrompt ?? this.taggerPrompt,
      dualTaggerPrompt: dualTaggerPrompt ?? this.dualTaggerPrompt,
      llmPrompt: llmPrompt ?? this.llmPrompt,
      characterReplacePrompt:
          characterReplacePrompt ?? this.characterReplacePrompt,
      finalPrompt: finalPrompt ?? this.finalPrompt,
      draft: clearDraft ? null : draft ?? this.draft,
      reviewPositivePrompt: reviewPositivePrompt ?? this.reviewPositivePrompt,
      reviewNegativePrompt: reviewNegativePrompt ?? this.reviewNegativePrompt,
      stageAudits: stageAudits ?? this.stageAudits,
      lastRawResponse: clearLastRawResponse
          ? null
          : lastRawResponse ?? this.lastRawResponse,
      isProcessing: isProcessing ?? this.isProcessing,
      processingStage: clearProcessingStage
          ? null
          : processingStage ?? this.processingStage,
      error: clearError ? null : error ?? this.error,
    );
  }

  Map<String, dynamic> toPersistedJson() => {
    'useOnnxTagger': useOnnxTagger,
    'useDualLocalTagger': useDualLocalTagger,
    'useLlmReverse': useLlmReverse,
    'useCharacterReplace': useCharacterReplace,
    'selectedTaggerModelPath': selectedTaggerModelPath,
    'selectedJoyTaggerModelPath': selectedJoyTaggerModelPath,
    'selectedWdEva02ModelPath': selectedWdEva02ModelPath,
    'selectedCharacterId': selectedCharacterId,
    'taggerGeneralThreshold': taggerGeneralThreshold,
    'taggerCharacterThreshold': taggerCharacterThreshold,
  };

  factory ReversePromptState.fromPersistedJson(Map<String, dynamic> json) {
    final useOnnx = json['useOnnxTagger'] as bool? ?? true;
    final useDual = json['useDualLocalTagger'] as bool? ?? false;
    final useLlm = json['useLlmReverse'] as bool? ?? true;
    // Dual local tagging replaces the single-model ONNX stage. Older
    // persisted settings may contain both flags, so normalize the mutually
    // exclusive local choices while keeping at least one usable method.
    final normalizedOnnx = useDual ? false : (useOnnx || !useLlm);
    final normalizedLlm = useLlm || (!normalizedOnnx && !useDual);
    return ReversePromptState(
      useOnnxTagger: normalizedOnnx,
      useDualLocalTagger: useDual,
      useLlmReverse: normalizedLlm,
      useCharacterReplace: json['useCharacterReplace'] as bool? ?? false,
      selectedTaggerModelPath: json['selectedTaggerModelPath'] as String?,
      selectedJoyTaggerModelPath: json['selectedJoyTaggerModelPath'] as String?,
      selectedWdEva02ModelPath: json['selectedWdEva02ModelPath'] as String?,
      selectedCharacterId: json['selectedCharacterId'] as String?,
      taggerGeneralThreshold:
          (json['taggerGeneralThreshold'] as num?)?.toDouble() ??
          (json['taggerThreshold'] as num?)?.toDouble() ??
          0.35,
      taggerCharacterThreshold:
          (json['taggerCharacterThreshold'] as num?)?.toDouble() ??
          (json['taggerThreshold'] as num?)?.toDouble() ??
          0.35,
    );
  }
}

class ReversePromptNotifier extends StateNotifier<ReversePromptState> {
  ReversePromptNotifier(this._ref) : super(const ReversePromptState()) {
    _load();
  }

  final Ref _ref;

  LocalStorageService get _storage => _ref.read(localStorageServiceProvider);

  void _load() {
    final raw = _storage.getSetting<String>(StorageKeys.reversePromptStateJson);
    if (raw == null || raw.isEmpty) {
      return;
    }
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      state = ReversePromptState.fromPersistedJson(decoded);
    } catch (_) {
      state = const ReversePromptState();
    }
  }

  Future<void> _save() async {
    await _storage.setSetting(
      StorageKeys.reversePromptStateJson,
      jsonEncode(state.toPersistedJson()),
    );
  }

  Future<void> addImage(Uint8List bytes, {String? name}) async {
    final normalizedBytes = await _normalizeImage(bytes);
    final next = ReversePromptImage(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      bytes: normalizedBytes,
      name: name,
    );
    state = state.copyWith(
      images: [...state.images, next],
      selectedImageId: state.selectedImageId ?? next.id,
      clearError: true,
    );
  }

  Future<Uint8List> _normalizeImage(Uint8List bytes) async {
    try {
      return await ReversePromptImageNormalizer.normalize(bytes);
    } catch (_) {
      return bytes;
    }
  }

  void removeImage(String id) {
    final remaining = state.images.where((e) => e.id != id).toList();
    state = state.copyWith(
      images: remaining,
      selectedImageId: state.selectedImageId == id
          ? (remaining.isEmpty ? null : remaining.first.id)
          : state.selectedImageId,
      clearSelectedImageId: state.selectedImageId == id && remaining.isEmpty,
    );
  }

  void clearImages() {
    state = state.copyWith(images: const [], clearSelectedImageId: true);
  }

  void selectImage(String id) {
    if (state.images.any((image) => image.id == id)) {
      state = state.copyWith(selectedImageId: id);
    }
  }

  Future<void> setUseOnnxTagger(bool value) async {
    if (!value && !state.useLlmReverse && !state.useDualLocalTagger) {
      state = state.copyWith(useOnnxTagger: true);
      return;
    }
    state = state.copyWith(
      useOnnxTagger: value,
      useDualLocalTagger: value ? false : state.useDualLocalTagger,
    );
    await _save();
  }

  Future<void> setUseDualLocalTagger(bool value) async {
    if (!value && !state.useLlmReverse && !state.useOnnxTagger) {
      state = state.copyWith(useDualLocalTagger: true);
      return;
    }
    state = state.copyWith(
      useDualLocalTagger: value,
      useOnnxTagger: value ? false : state.useOnnxTagger,
    );
    await _save();
  }

  Future<void> setUseLlmReverse(bool value) async {
    if (!value && !state.useOnnxTagger && !state.useDualLocalTagger) {
      state = state.copyWith(useLlmReverse: true);
      return;
    }
    state = state.copyWith(useLlmReverse: value);
    await _save();
  }

  Future<void> setUseCharacterReplace(bool value) async {
    state = state.copyWith(useCharacterReplace: value);
    await _save();
  }

  Future<void> setSelectedTaggerModelPath(String? value) async {
    state = state.copyWith(
      selectedTaggerModelPath: value,
      clearSelectedTaggerModelPath: value == null,
    );
    await _save();
  }

  Future<void> setSelectedJoyTaggerModelPath(String? value) async {
    state = state.copyWith(
      selectedJoyTaggerModelPath: value,
      clearSelectedJoyTaggerModelPath: value == null,
    );
    await _save();
  }

  Future<void> setSelectedWdEva02ModelPath(String? value) async {
    state = state.copyWith(
      selectedWdEva02ModelPath: value,
      clearSelectedWdEva02ModelPath: value == null,
    );
    await _save();
  }

  Future<void> setSelectedCharacterId(String? value) async {
    state = state.copyWith(
      selectedCharacterId: value,
      clearSelectedCharacterId: value == null,
    );
    await _save();
  }

  Future<void> setTaggerGeneralThreshold(double value) async {
    state = state.copyWith(
      taggerGeneralThreshold: value.clamp(0.05, 0.95).toDouble(),
    );
    await _save();
  }

  Future<void> setTaggerCharacterThreshold(double value) async {
    state = state.copyWith(
      taggerCharacterThreshold: value.clamp(0.05, 0.95).toDouble(),
    );
    await _save();
  }

  Future<void> runChain() async {
    if (!state.canRun) {
      state = state.copyWith(error: 'reversePrompt_needImageAndMethod');
      return;
    }

    state = state.copyWith(
      isProcessing: true,
      processingStage: ReversePromptProcessingStage.preparing,
      taggerPrompt: '',
      dualTaggerPrompt: '',
      llmPrompt: '',
      characterReplacePrompt: '',
      finalPrompt: '',
      clearDraft: true,
      reviewPositivePrompt: '',
      reviewNegativePrompt: '',
      stageAudits: const [],
      clearLastRawResponse: true,
      clearError: true,
    );

    try {
      var currentPrompt = '';
      var localEvidence = '';
      final image = state.selectedImage;
      if (image == null) {
        throw const _ReversePromptUiError('reversePrompt_needImageAndMethod');
      }
      if (state.useDualLocalTagger) {
        final result = await _runDualLocalTaggerStage(image);
        currentPrompt = result.prompt;
        localEvidence = result.evidence;
      } else if (state.useOnnxTagger) {
        currentPrompt = await _runOnnxTaggerStage(image);
      }

      if (state.useLlmReverse) {
        final draft = await _runLlmReverseStage(
          image,
          taggerPrompt: currentPrompt,
        );
        currentPrompt = draft.positivePrompt;
        if (state.useDualLocalTagger &&
            localEvidence.trim().isNotEmpty &&
            currentPrompt.trim().isNotEmpty) {
          final integrated = await _runIntegrationStage(
            localEvidence: localEvidence,
            visualDescription: currentPrompt,
          );
          currentPrompt = integrated.positivePrompt;
        }
      }

      if (state.useCharacterReplace) {
        final character = _resolveSelectedCharacter();
        if (character == null || character.prompt.trim().isEmpty) {
          throw const _ReversePromptUiError(
            'reversePrompt_needReplacementCharacter',
          );
        }
        if (currentPrompt.trim().isEmpty) {
          throw const _ReversePromptUiError(
            'reversePrompt_needPromptForCharacterReplace',
          );
        }
        currentPrompt = await _runCharacterReplaceStage(
          inputPrompt: currentPrompt,
          character: character,
        );
      }

      state = state.copyWith(
        isProcessing: false,
        clearProcessingStage: true,
        finalPrompt: currentPrompt,
      );
    } catch (e) {
      final failedStage = state.processingStage;
      if (failedStage != null &&
          failedStage != ReversePromptProcessingStage.preparing) {
        _recordStageFailure(
          failedStage,
          e.toString(),
          rawResponse: e is PromptAssistantRequestException
              ? e.rawResponse
              : null,
        );
      }
      state = state.copyWith(
        isProcessing: false,
        clearProcessingStage: true,
        lastRawResponse: e is PromptAssistantRequestException
            ? e.rawResponse
            : null,
        clearLastRawResponse:
            e is! PromptAssistantRequestException || e.rawResponse == null,
        error: e is _ReversePromptUiError ? e.key : e.toString(),
      );
    }
  }

  /// Re-runs one failed/intermediate stage without silently calling later
  /// stages. The reviewer can inspect the new evidence and explicitly run the
  /// full chain again if downstream output should be regenerated.
  Future<void> retryStage(ReversePromptProcessingStage stage) async {
    if (state.isProcessing ||
        state.images.isEmpty ||
        stage == ReversePromptProcessingStage.preparing) {
      return;
    }
    state = state.copyWith(
      isProcessing: true,
      clearError: true,
      clearLastRawResponse: true,
    );
    try {
      final image = state.selectedImage;
      if (image == null) {
        throw const _ReversePromptUiError('reversePrompt_needImageAndMethod');
      }
      switch (stage) {
        case ReversePromptProcessingStage.onnxTagger:
          await _runOnnxTaggerStage(image);
        case ReversePromptProcessingStage.dualLocalTagger:
          await _runDualLocalTaggerStage(image);
        case ReversePromptProcessingStage.llmReverse:
          await _runLlmReverseStage(image, taggerPrompt: state.taggerPrompt);
        case ReversePromptProcessingStage.integration:
          final localEvidence = state.dualTaggerPrompt.trim();
          final visualDescription = state.llmPrompt.trim();
          if (localEvidence.isEmpty || visualDescription.isEmpty) {
            throw const _ReversePromptUiError(
              'reversePrompt_needIntegrationEvidence',
            );
          }
          await _runIntegrationStage(
            localEvidence: localEvidence,
            visualDescription: visualDescription,
          );
        case ReversePromptProcessingStage.characterReplace:
          final character = _resolveSelectedCharacter();
          final input = state.reviewPositivePrompt.trim().isNotEmpty
              ? state.reviewPositivePrompt
              : state.finalPrompt;
          if (character == null || character.prompt.trim().isEmpty) {
            throw const _ReversePromptUiError(
              'reversePrompt_needReplacementCharacter',
            );
          }
          if (input.trim().isEmpty) {
            throw const _ReversePromptUiError(
              'reversePrompt_needPromptForCharacterReplace',
            );
          }
          await _runCharacterReplaceStage(
            inputPrompt: input,
            character: character,
          );
        case ReversePromptProcessingStage.preparing:
          break;
      }
      state = state.copyWith(isProcessing: false, clearProcessingStage: true);
    } catch (e) {
      final failedStage = state.processingStage;
      if (failedStage != null &&
          failedStage != ReversePromptProcessingStage.preparing) {
        _recordStageFailure(
          failedStage,
          e.toString(),
          rawResponse: e is PromptAssistantRequestException
              ? e.rawResponse
              : null,
        );
      }
      state = state.copyWith(
        isProcessing: false,
        clearProcessingStage: true,
        lastRawResponse: e is PromptAssistantRequestException
            ? e.rawResponse
            : null,
        clearLastRawResponse:
            e is! PromptAssistantRequestException || e.rawResponse == null,
        error: e is _ReversePromptUiError ? e.key : e.toString(),
      );
    }
  }

  void setReviewPositivePrompt(String value) {
    state = state.copyWith(reviewPositivePrompt: value, finalPrompt: value);
  }

  void setReviewNegativePrompt(String value) {
    state = state.copyWith(reviewNegativePrompt: value);
  }

  void discardDraft() {
    state = state.copyWith(
      clearDraft: true,
      reviewPositivePrompt: '',
      reviewNegativePrompt: '',
      finalPrompt: '',
    );
  }

  Future<String> _runOnnxTaggerStage(ReversePromptImage image) async {
    _beginStage(ReversePromptProcessingStage.onnxTagger);
    final startedAt = DateTime.now();
    final model = await _resolveSelectedTaggerModel();
    final result = await _ref
        .read(localOnnxTaggerServiceProvider)
        .tagImage(
          imageBytes: image.bytes,
          model: model,
          generalThreshold: state.taggerGeneralThreshold,
          characterThreshold: state.taggerCharacterThreshold,
        );
    final prompt = result.prompt.trim();
    state = state.copyWith(
      taggerPrompt: prompt,
      finalPrompt: prompt,
      selectedTaggerModelPath: model.path,
    );
    _completeStage(
      ReversePromptProcessingStage.onnxTagger,
      routeLabel: model.name,
      output: prompt,
      durationMs: DateTime.now().difference(startedAt).inMilliseconds,
    );
    await _save();
    return prompt;
  }

  Future<({String prompt, String evidence})> _runDualLocalTaggerStage(
    ReversePromptImage image,
  ) async {
    _beginStage(ReversePromptProcessingStage.dualLocalTagger);
    final startedAt = DateTime.now();
    final models = await _resolveDualTaggerModels();
    final result = await _ref
        .read(dualLocalOnnxTaggerServiceProvider)
        .tagImage(
          imageBytes: image.bytes,
          models: models,
          generalThreshold: state.taggerGeneralThreshold,
          characterThreshold: state.taggerCharacterThreshold,
        );
    final prompt = result.combinedPrompt.trim();
    final evidence = result.auditText.trim();
    state = state.copyWith(
      dualTaggerPrompt: evidence,
      taggerPrompt: prompt,
      finalPrompt: prompt,
    );
    if (!result.hasSuccess) {
      throw const _ReversePromptUiError('reversePrompt_dualTaggerFailed');
    }
    _completeStage(
      ReversePromptProcessingStage.dualLocalTagger,
      routeLabel: '${models.joyTag.name} + ${models.wdEva02.name}',
      output: evidence,
      durationMs: DateTime.now().difference(startedAt).inMilliseconds,
    );
    await _save();
    return (prompt: prompt, evidence: evidence);
  }

  Future<ReversePromptDraft> _runLlmReverseStage(
    ReversePromptImage image, {
    required String taggerPrompt,
  }) async {
    _beginStage(ReversePromptProcessingStage.llmReverse);
    final startedAt = DateTime.now();
    final draft = await _ref
        .read(promptAssistantServiceProvider)
        .reverseImagePromptDraft(
          image.bytes,
          sessionId: 'reverse_prompt_panel',
          taggerPrompt: taggerPrompt,
        );
    state = state.copyWith(
      draft: draft,
      llmPrompt: draft.positivePrompt,
      finalPrompt: draft.positivePrompt,
      reviewPositivePrompt: draft.positivePrompt,
      reviewNegativePrompt: draft.negativePrompt,
      lastRawResponse: draft.rawResponse,
    );
    _completeStage(
      ReversePromptProcessingStage.llmReverse,
      routeLabel: draft.routeLabel,
      output: draft.positivePrompt,
      durationMs: DateTime.now().difference(startedAt).inMilliseconds,
    );
    return draft;
  }

  Future<ReversePromptDraft> _runIntegrationStage({
    required String localEvidence,
    required String visualDescription,
  }) async {
    _beginStage(ReversePromptProcessingStage.integration);
    final startedAt = DateTime.now();
    final integrated = await _ref
        .read(promptAssistantServiceProvider)
        .integrateReverseEvidenceDraft(
          localEvidence: localEvidence,
          visualDescription: visualDescription,
          sessionId: 'reverse_prompt_integrate',
        );
    state = state.copyWith(
      draft: integrated,
      finalPrompt: integrated.positivePrompt,
      reviewPositivePrompt: integrated.positivePrompt,
      reviewNegativePrompt: integrated.negativePrompt,
      lastRawResponse: integrated.rawResponse,
    );
    _completeStage(
      ReversePromptProcessingStage.integration,
      routeLabel: integrated.routeLabel,
      output: integrated.positivePrompt,
      durationMs: DateTime.now().difference(startedAt).inMilliseconds,
    );
    return integrated;
  }

  Future<String> _runCharacterReplaceStage({
    required String inputPrompt,
    required CharacterPrompt character,
  }) async {
    _beginStage(ReversePromptProcessingStage.characterReplace);
    final startedAt = DateTime.now();
    final prompt = await _runCharacterReplace(
      inputPrompt: inputPrompt,
      character: character,
    );
    final updatedDraft = state.draft?.copyWith(positivePrompt: prompt);
    state = state.copyWith(
      draft: updatedDraft,
      characterReplacePrompt: prompt,
      finalPrompt: prompt,
      reviewPositivePrompt: prompt,
    );
    _completeStage(
      ReversePromptProcessingStage.characterReplace,
      output: prompt,
      durationMs: DateTime.now().difference(startedAt).inMilliseconds,
    );
    return prompt;
  }

  void _beginStage(ReversePromptProcessingStage stage) {
    final audits =
        state.stageAudits
            .where((audit) => audit.stage != stage)
            .toList(growable: true)
          ..add(
            ReversePromptStageAudit(
              stage: stage,
              status: ReversePromptStageStatus.running,
            ),
          );
    state = state.copyWith(processingStage: stage, stageAudits: audits);
  }

  void _completeStage(
    ReversePromptProcessingStage stage, {
    String routeLabel = '',
    String output = '',
    int? durationMs,
  }) {
    final audits =
        state.stageAudits
            .where((audit) => audit.stage != stage)
            .toList(growable: true)
          ..add(
            ReversePromptStageAudit(
              stage: stage,
              status: ReversePromptStageStatus.succeeded,
              routeLabel: routeLabel,
              outputPreview: _auditPreview(output),
              durationMs: durationMs,
            ),
          );
    state = state.copyWith(stageAudits: audits);
  }

  void _recordStageFailure(
    ReversePromptProcessingStage stage,
    String error, {
    String? rawResponse,
  }) {
    final audits =
        state.stageAudits
            .where((audit) => audit.stage != stage)
            .toList(growable: true)
          ..add(
            ReversePromptStageAudit(
              stage: stage,
              status: ReversePromptStageStatus.failed,
              error: error,
              rawResponse: rawResponse,
            ),
          );
    state = state.copyWith(stageAudits: audits);
  }

  static String _auditPreview(String value) {
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= 160) return normalized;
    return '${normalized.substring(0, 160)}...';
  }

  Future<LocalOnnxModelDescriptor> _resolveSelectedTaggerModel() async {
    final models = await _ref
        .read(localOnnxModelServiceProvider)
        .scanTaggerModels();
    if (models.isEmpty) {
      throw const _ReversePromptUiError('reversePrompt_noOnnxModel');
    }
    final selectedPath = state.selectedTaggerModelPath;
    if (selectedPath != null) {
      for (final model in models) {
        if (model.path == selectedPath) {
          return model;
        }
      }
    }
    return models.first;
  }

  Future<DualLocalTaggerModelSelection> _resolveDualTaggerModels() async {
    final models = await _ref
        .read(localOnnxModelServiceProvider)
        .scanTaggerModels();
    final selection = DualLocalOnnxTaggerService.findPair(
      models,
      joyTagPath: state.selectedJoyTaggerModelPath,
      wdEva02Path: state.selectedWdEva02ModelPath,
    );
    if (selection == null) {
      throw const _ReversePromptUiError('reversePrompt_noDualTaggerModels');
    }
    if (selection.joyTag.path != state.selectedJoyTaggerModelPath ||
        selection.wdEva02.path != state.selectedWdEva02ModelPath) {
      state = state.copyWith(
        selectedJoyTaggerModelPath: selection.joyTag.path,
        selectedWdEva02ModelPath: selection.wdEva02.path,
      );
      await _save();
    }
    return selection;
  }

  CharacterPrompt? _resolveSelectedCharacter() {
    return _ref.read(reversePromptCharacterProvider.notifier).selectedCharacter;
  }

  Future<String> _runCharacterReplace({
    required String inputPrompt,
    required CharacterPrompt character,
  }) {
    return _collectStream(
      _ref
          .read(promptAssistantServiceProvider)
          .replaceCharacterPrompt(
            inputPrompt,
            sessionId: 'reverse_prompt_character_replace',
            characterName: character.name,
            characterPrompt: character.prompt,
          ),
    );
  }

  Future<String> _collectStream(Stream<StreamingChunk> stream) async {
    final buffer = StringBuffer();
    await for (final chunk in stream) {
      if (!chunk.done && chunk.delta.isNotEmpty) {
        buffer.write(chunk.delta);
      }
    }
    return buffer.toString().trim();
  }
}
