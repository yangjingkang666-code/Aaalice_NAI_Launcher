import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nai_launcher/core/storage/local_storage_service.dart';
import 'package:nai_launcher/core/storage/secure_storage_service.dart';
import 'package:nai_launcher/presentation/prompt_assistant/models/prompt_assistant_models.dart';
import 'package:nai_launcher/presentation/prompt_assistant/providers/prompt_assistant_config_provider.dart';
import 'package:nai_launcher/presentation/prompt_assistant/services/prompt_assistant_api_client.dart';
import 'package:nai_launcher/presentation/prompt_assistant/services/prompt_assistant_service.dart';
import 'package:nai_launcher/presentation/prompt_assistant/services/provider_adapters/prompt_assistant_adapter.dart';

class _MemoryLocalStorage extends LocalStorageService {
  final Map<String, Object?> _values = {};

  @override
  T? getSetting<T>(String key, {T? defaultValue}) {
    final value = _values[key];
    return value == null ? defaultValue : value as T;
  }

  @override
  Future<void> setSetting<T>(String key, T value) async {
    _values[key] = value;
  }
}

class _MemorySecureStorage extends SecureStorageService {
  @override
  Future<String?> getPromptAssistantApiKey(String providerId) async =>
      'test-key';
}

class _FakePromptAssistantApiClient extends PromptAssistantApiClient {
  _FakePromptAssistantApiClient() : super(dio: Dio());

  PromptAssistantRequest? lastRequest;

  @override
  Stream<StreamingChunk> complete({
    required PromptAssistantRequest request,
  }) async* {
    lastRequest = request;
    yield const StreamingChunk(delta: 'OK');
    yield const StreamingChunk(delta: '', done: true);
  }
}

void main() {
  test('provider connection check uses the routed chat model', () async {
    final apiClient = _FakePromptAssistantApiClient();
    final container = ProviderContainer(
      overrides: [
        localStorageServiceProvider.overrideWithValue(_MemoryLocalStorage()),
        secureStorageServiceProvider.overrideWithValue(_MemorySecureStorage()),
        promptAssistantServiceProvider.overrideWith(
          (ref) => PromptAssistantService(ref: ref, apiClient: apiClient),
        ),
      ],
    );
    addTearDown(container.dispose);

    final config = container.read(promptAssistantConfigProvider.notifier);
    await config.upsertProvider(
      const ProviderConfig(
        id: 'custom',
        name: 'Custom provider',
        baseUrl: 'https://example.test/v1',
      ),
    );
    await config.addManualModels('custom', const ['model-a', 'model-b']);
    await config.setRouting(
      PromptAssistantConfigState.defaults().routing.copyWithTask(
        taskType: AssistantTaskType.chat,
        providerId: 'custom',
        model: 'model-b',
      ),
    );

    final result = await container
        .read(promptAssistantServiceProvider)
        .testProviderConnection('custom');

    expect(result.model, 'model-b');
    expect(result.response, 'OK');
    expect(apiClient.lastRequest?.provider.id, 'custom');
    expect(apiClient.lastRequest?.model, 'model-b');
    expect(apiClient.lastRequest?.maxOutputTokens, 16);
    expect(
      apiClient.lastRequest?.reasoningMode,
      PromptAssistantReasoningMode.disabled,
    );
    final part = apiClient.lastRequest?.userParts.single;
    expect(part, isA<PromptAssistantTextPart>());
    expect((part! as PromptAssistantTextPart).text, 'Reply with OK.');
  });
}
