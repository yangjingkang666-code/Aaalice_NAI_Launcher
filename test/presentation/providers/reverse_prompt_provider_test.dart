import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/storage/local_storage_service.dart';
import 'package:nai_launcher/presentation/prompt_assistant/models/prompt_assistant_models.dart';
import 'package:nai_launcher/presentation/prompt_assistant/models/reverse_prompt_models.dart';
import 'package:nai_launcher/presentation/prompt_assistant/services/prompt_assistant_api_client.dart';
import 'package:nai_launcher/presentation/prompt_assistant/services/prompt_assistant_service.dart';
import 'package:nai_launcher/presentation/providers/reverse_prompt_provider.dart';

void main() {
  test(
    'selected reverse image is explicit when multiple images are present',
    () {
      final first = ReversePromptImage(
        id: 'first',
        bytes: Uint8List.fromList([1]),
      );
      final second = ReversePromptImage(
        id: 'second',
        bytes: Uint8List.fromList([2]),
      );
      final state = ReversePromptState(
        images: [first, second],
        selectedImageId: second.id,
      );

      expect(state.selectedImage?.id, 'second');
    },
  );

  test('dual local mode remains selectable without cloud reverse', () {
    final state = ReversePromptState.fromPersistedJson({
      'useOnnxTagger': false,
      'useDualLocalTagger': true,
      'useLlmReverse': false,
    });

    expect(state.useDualLocalTagger, isTrue);
    expect(state.useOnnxTagger, isFalse);
    expect(state.useLlmReverse, isFalse);
    expect(state.canRun, isFalse);
  });

  test('legacy conflicting local flags normalize to dual-only mode', () {
    final state = ReversePromptState.fromPersistedJson({
      'useOnnxTagger': true,
      'useDualLocalTagger': true,
      'useLlmReverse': false,
    });

    expect(state.useDualLocalTagger, isTrue);
    expect(state.useOnnxTagger, isFalse);
    expect(state.useLlmReverse, isFalse);
  });

  test(
    'cancels an in-flight reverse request and ignores its late result',
    () async {
      final response = Completer<ReversePromptDraft>();
      late _BlockingPromptAssistantService assistant;
      final container = ProviderContainer(
        overrides: [
          localStorageServiceProvider.overrideWith(
            (ref) => _MemoryLocalStorage(),
          ),
          promptAssistantServiceProvider.overrideWith((ref) {
            assistant = _BlockingPromptAssistantService(ref, response);
            return assistant;
          }),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(reversePromptProvider.notifier);
      notifier.state = ReversePromptState(
        images: [
          ReversePromptImage(
            id: 'image',
            bytes: Uint8List.fromList(const [1, 2, 3]),
          ),
        ],
        useOnnxTagger: false,
        useLlmReverse: true,
      );

      final run = notifier.runChain();
      await Future<void>.delayed(Duration.zero);
      expect(assistant.started, isTrue);
      expect(notifier.state.isProcessing, isTrue);

      await notifier.cancel();
      expect(assistant.cancelledSessions, contains('reverse_prompt_panel'));
      expect(notifier.state.isProcessing, isFalse);
      expect(notifier.state.processingStage, isNull);
      expect(notifier.state.error, 'reversePrompt_cancelled');

      response.complete(
        const ReversePromptDraft(positivePrompt: 'late result'),
      );
      await run;

      expect(notifier.state.error, 'reversePrompt_cancelled');
      expect(notifier.state.finalPrompt, isNot('late result'));
    },
  );
}

class _BlockingPromptAssistantService extends PromptAssistantService {
  _BlockingPromptAssistantService(Ref ref, this.response)
    : super(
        ref: ref,
        apiClient: PromptAssistantApiClient(dio: Dio()),
      );

  final Completer<ReversePromptDraft> response;
  final List<String> cancelledSessions = [];
  bool started = false;

  @override
  Future<ReversePromptDraft> reverseImagePromptDraft(
    Uint8List imageBytes, {
    required String sessionId,
    String? taggerPrompt,
    AssistantTaskType taskType = AssistantTaskType.reverse,
  }) {
    started = true;
    return response.future;
  }

  @override
  Future<void> cancelCurrentTask({String? sessionId}) async {
    if (sessionId != null) cancelledSessions.add(sessionId);
  }
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
