import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../../core/agent/agent.dart';
import '../../../core/agent/external/agent_control_protocol.dart';
import '../../../core/agent/external/agent_control_server.dart';
import '../../../data/models/image/image_params.dart';
import '../../../data/models/style_lab/style_lab_models.dart';
import '../../../data/services/style_lab_service.dart';
import '../providers/agent_chat_notifier.dart';

/// Application-owned command bridge for the opt-in local Agent API.
///
/// This class intentionally delegates conversation execution to
/// [AgentChatNotifier]. It never invokes generation providers directly, so
/// the existing permission controller, Anlas estimator and audit sink remain
/// the only write/billing boundary.
class AgentExternalControlService {
  AgentExternalControlService({
    required AgentChatNotifier Function() readAgent,
    Directory? supportDirectory,
    String? authToken,
    this.port = 0,
  }) : _readAgent = readAgent,
       _supportDirectory = supportDirectory,
       _authToken = authToken;

  static const descriptorFileName = 'agent-control-v1.json';

  static const capabilities = AgentControlCapabilities(
    methods: [
      AgentControlMethod(
        name: 'agent.status',
        description: 'Read the current Aaalice Agent run and approval status.',
        readOnly: true,
        parameters: {
          'type': 'object',
          'properties': {},
          'additionalProperties': false,
        },
      ),
      AgentControlMethod(
        name: 'agent.send',
        description:
            'Send a prompt to the active Aaalice Agent session. Generation '
            'tools still follow the in-app permission and Anlas approval flow.',
        mayConsumeAnlas: true,
        parameters: {
          'type': 'object',
          'properties': {
            'text': {'type': 'string', 'minLength': 1, 'maxLength': 32000},
            'follow_up': {'type': 'boolean'},
          },
          'required': ['text'],
          'additionalProperties': false,
        },
      ),
      AgentControlMethod(
        name: 'agent.abort',
        description: 'Abort the active Aaalice Agent run.',
        parameters: {
          'type': 'object',
          'properties': {},
          'additionalProperties': false,
        },
      ),
      AgentControlMethod(
        name: 'style_lab.plan',
        description:
            'Draw reproducible random artist-chain A/B prompt pairs offline; '
            'this command never calls an image provider or consumes Anlas.',
        readOnly: true,
        parameters: {
          'type': 'object',
          'properties': {
            'base_prompt': {'type': 'string', 'maxLength': 16000},
            'auxiliary_prompt': {'type': 'string', 'maxLength': 16000},
            'artist_pool': {'type': 'string', 'maxLength': 32000},
            'style_pool': {'type': 'string', 'maxLength': 32000},
            'pair_count': {'type': 'integer', 'minimum': 1, 'maximum': 12},
            'min_artists': {'type': 'integer', 'minimum': 1, 'maximum': 8},
            'max_artists': {'type': 'integer', 'minimum': 1, 'maximum': 8},
            'artist_weight_min': {
              'type': 'number',
              'minimum': 0.1,
              'maximum': 2,
            },
            'artist_weight_max': {
              'type': 'number',
              'minimum': 0.1,
              'maximum': 2,
            },
            'min_style_tokens': {'type': 'integer', 'minimum': 0, 'maximum': 8},
            'max_style_tokens': {'type': 'integer', 'minimum': 0, 'maximum': 8},
            'mutate_styles': {'type': 'boolean'},
            'seed_mode': {
              'type': 'string',
              'enum': ['randomPerPair', 'fixed'],
            },
            'fixed_seed': {'type': 'integer'},
            'draw_seed': {'type': 'integer'},
          },
          'additionalProperties': false,
        },
      ),
    ],
  );

  final AgentChatNotifier Function() _readAgent;
  final Directory? _supportDirectory;
  final String? _authToken;
  final int port;
  final StyleLabService _styleLabService = StyleLabService();

  AgentControlServer? _server;
  File? _descriptorFile;
  Future<void>? _startInFlight;

  bool get isRunning => _server?.isRunning ?? false;
  AgentControlServerInfo? get serverInfo =>
      _server?.isRunning == true ? _server!.info : null;

  Future<void> start() {
    if (isRunning) return Future<void>.value();
    final inFlight = _startInFlight;
    if (inFlight != null) return inFlight;
    late final Future<void> future;
    future = _startInternal().whenComplete(() {
      if (identical(_startInFlight, future)) _startInFlight = null;
    });
    _startInFlight = future;
    return future;
  }

  Future<void> _startInternal() async {
    final server = AgentControlServer(
      capabilities: capabilities,
      readStatus: _readStatus,
      handleCommand: handleCommand,
      canRunConcurrently: _canRunConcurrently,
      authToken: _authToken,
    );
    final info = await server.start(port: port);
    _server = server;
    try {
      final supportDirectory =
          _supportDirectory ?? await getApplicationSupportDirectory();
      final descriptor = File(
        '${supportDirectory.path}${Platform.pathSeparator}agent'
        '${Platform.pathSeparator}$descriptorFileName',
      );
      await server.writeDescriptor(descriptor);
      _descriptorFile = descriptor;
      // Keep the endpoint discoverable through the descriptor, but never
      // print the bearer token to logs or the console.
      assert(info.baseUrl.isNotEmpty);
    } catch (_) {
      // Do not leave an authenticated listener alive when discovery metadata
      // cannot be written (for example, a read-only support directory).
      await server.stop();
      _server = null;
      rethrow;
    }
  }

  Future<void> stop() async {
    final inFlight = _startInFlight;
    if (inFlight != null) {
      try {
        await inFlight;
      } catch (_) {
        // The start future already cleaned up its listener on failure.
      }
    }
    final server = _server;
    _server = null;
    final descriptor = _descriptorFile;
    _descriptorFile = null;
    await server?.stop();
    if (descriptor != null && await descriptor.exists()) {
      await descriptor.delete();
    }
  }

  Future<AgentControlCommandResult> handleCommand(
    AgentControlCommand command,
  ) async {
    try {
      return switch (command.method) {
        'agent.status' => AgentControlCommandResult.success(
          await _readStatus(),
        ),
        'agent.send' => await _send(command.params),
        'agent.abort' => await _abort(),
        'style_lab.plan' => _planStyleLab(command.params),
        _ => AgentControlCommandResult.failure(
          AgentControlError(
            code: 'not_found',
            message: 'Unknown command: ${command.method}.',
          ),
        ),
      };
    } on _ExternalControlValidationError catch (error) {
      return AgentControlCommandResult.failure(
        AgentControlError(code: 'invalid_params', message: error.message),
      );
    } catch (error) {
      return AgentControlCommandResult.failure(
        AgentControlError(code: 'internal', message: '$error'),
      );
    }
  }

  bool _canRunConcurrently(AgentControlCommand command) {
    return switch (command.method) {
      // Status and planning are read-only and must not wait behind a long
      // generation request. Abort is the interrupt path for that request.
      'agent.status' || 'agent.abort' || 'style_lab.plan' => true,
      // A follow-up is intentionally admitted while a run is active so the
      // existing notifier can enqueue it instead of waiting for the run.
      'agent.send' => command.params['follow_up'] == true,
      _ => false,
    };
  }

  Future<Map<String, dynamic>> _readStatus() async {
    final state = _readAgent().currentState;
    final approval = state.approvalRequest;
    return {
      'initialized': state.initialized,
      'status': state.status.name,
      'work_phase': state.workPhase.name,
      'session_id': state.activeSessionId,
      'route_ready': state.routeReady,
      'route_label': state.routeLabel,
      'queued_messages': state.queuedMessages.length,
      'message_count': state.messages.length,
      'active_tool_count': state.activities
          .where(
            (activity) => activity.status == AgentToolActivityStatus.running,
          )
          .length,
      'approval': approval == null
          ? null
          : {
              'tool_call_id': approval.toolCallId,
              'tool_name': approval.toolName,
              'estimated_anlas': approval.estimatedAnlas,
            },
      if (state.error.isNotEmpty) 'error': _boundedText(state.error),
    };
  }

  Future<AgentControlCommandResult> _send(Map<String, dynamic> params) async {
    final text = _requiredText(params, 'text', maxLength: 32000);
    final followUp = _optionalBool(params, 'follow_up') ?? false;
    final notifier = _readAgent();
    final stateBefore = notifier.currentState;
    if (stateBefore.status == AgentChatRunStatus.running && !followUp) {
      return const AgentControlCommandResult.failure(
        AgentControlError(
          code: 'busy',
          message: 'The active Agent run is busy; set follow_up=true to queue.',
        ),
      );
    }
    final beforeCount = stateBefore.messages.length;
    final accepted = await notifier.sendContent([
      UserTextContent(text),
    ], followUp: followUp);
    if (!accepted) {
      return const AgentControlCommandResult.failure(
        AgentControlError(
          code: 'rejected',
          message: 'The Aaalice Agent did not accept the prompt.',
        ),
      );
    }
    final stateAfter = notifier.currentState;
    final appended = stateAfter.messages.skip(beforeCount).toList();
    const maxReturnedMessages = 32;
    final omitted = appended.length > maxReturnedMessages;
    final returnedMessages = omitted
        ? appended.skip(appended.length - maxReturnedMessages)
        : appended;
    return AgentControlCommandResult.success({
      'accepted': true,
      'session_id': stateAfter.activeSessionId,
      'queued': followUp && stateBefore.status == AgentChatRunStatus.running,
      'status': stateAfter.status.name,
      'messages': [
        for (final message in returnedMessages) _messageToJson(message),
      ],
      if (omitted) 'messages_truncated': true,
    });
  }

  Future<AgentControlCommandResult> _abort() async {
    await _readAgent().abort();
    return const AgentControlCommandResult.success({'aborted': true});
  }

  AgentControlCommandResult _planStyleLab(Map<String, dynamic> params) {
    final seedModeName = _optionalText(params, 'seed_mode');
    final seedMode = switch (seedModeName) {
      null || '' => StyleLabSeedMode.randomPerPair,
      'randomPerPair' => StyleLabSeedMode.randomPerPair,
      'fixed' => StyleLabSeedMode.fixed,
      _ => throw const _ExternalControlValidationError(
        'seed_mode must be randomPerPair or fixed.',
      ),
    };
    final session = StyleLabSession.initial(const ImageParams()).copyWith(
      basePrompt: _optionalText(params, 'base_prompt') ?? '',
      auxiliaryPrompt: _optionalText(params, 'auxiliary_prompt') ?? '',
      artistPool: _optionalText(params, 'artist_pool') ?? '',
      stylePool: _optionalText(params, 'style_pool') ?? '',
      pairCount: _boundedInt(
        params,
        'pair_count',
        fallback: 4,
        min: 1,
        max: 12,
      ),
      minArtists: _boundedInt(
        params,
        'min_artists',
        fallback: 2,
        min: 1,
        max: 8,
      ),
      maxArtists: _boundedInt(
        params,
        'max_artists',
        fallback: 4,
        min: 1,
        max: 8,
      ),
      artistWeightMin: _boundedDouble(
        params,
        'artist_weight_min',
        fallback: 0.65,
        min: 0.1,
        max: 2,
      ),
      artistWeightMax: _boundedDouble(
        params,
        'artist_weight_max',
        fallback: 1.15,
        min: 0.1,
        max: 2,
      ),
      minStyleTokens: _boundedInt(
        params,
        'min_style_tokens',
        fallback: 2,
        min: 0,
        max: 8,
      ),
      maxStyleTokens: _boundedInt(
        params,
        'max_style_tokens',
        fallback: 4,
        min: 0,
        max: 8,
      ),
      mutateStyles: _optionalBool(params, 'mutate_styles') ?? true,
      seedMode: seedMode,
      fixedSeed: _boundedInt(
        params,
        'fixed_seed',
        fallback: 123456,
        min: 0,
        max: 2147483647,
      ),
      drawSeed: _boundedInt(
        params,
        'draw_seed',
        fallback: DateTime.now().millisecondsSinceEpoch,
        min: 0,
        max: 2147483647,
      ),
    );
    final pairs = _styleLabService.generatePairs(session);
    return AgentControlCommandResult.success({
      'charged': false,
      'pair_count': pairs.length,
      'variant_count': pairs.fold<int>(
        0,
        (total, pair) => total + pair.variants.length,
      ),
      'pairs': pairs.map((pair) => pair.toJson()).toList(growable: false),
    });
  }

  static Map<String, dynamic> _messageToJson(Message message) {
    return switch (message) {
      UserMessage() => {'role': 'user', 'text': _boundedText(message.text)},
      AssistantMessage() => {
        'role': 'assistant',
        'text': _boundedText(message.text),
        'stop_reason': message.stopReason.name,
        if (message.errorMessage != null)
          'error': _boundedText(message.errorMessage!),
        if (message.toolCalls.isNotEmpty)
          'tool_calls': [
            for (final call in message.toolCalls)
              {'id': call.id, 'name': call.name},
          ],
      },
      ToolResultMessage() => {
        'role': 'tool_result',
        'tool_call_id': message.toolCallId,
        'tool_name': message.toolName,
        'text': _boundedText(message.text),
        'is_error': message.isError,
      },
      _ => {'role': message.role},
    };
  }

  static String _requiredText(
    Map<String, dynamic> params,
    String key, {
    required int maxLength,
  }) {
    final value = _optionalText(params, key);
    if (value == null || value.isEmpty || value.length > maxLength) {
      throw _ExternalControlValidationError(
        '$key must be a non-empty string of at most $maxLength characters.',
      );
    }
    return value;
  }

  static String? _optionalText(Map<String, dynamic> params, String key) {
    final value = params[key];
    if (value == null) return null;
    if (value is! String) {
      throw _ExternalControlValidationError('$key must be a string.');
    }
    return value.trim();
  }

  static bool? _optionalBool(Map<String, dynamic> params, String key) {
    final value = params[key];
    if (value == null) return null;
    if (value is! bool) {
      throw _ExternalControlValidationError('$key must be a boolean.');
    }
    return value;
  }

  static int _boundedInt(
    Map<String, dynamic> params,
    String key, {
    required int fallback,
    required int min,
    required int max,
  }) {
    final value = params[key];
    if (value == null) return fallback;
    if (value is! num || value.toInt() != value) {
      throw _ExternalControlValidationError('$key must be an integer.');
    }
    return value.toInt().clamp(min, max);
  }

  static double _boundedDouble(
    Map<String, dynamic> params,
    String key, {
    required double fallback,
    required double min,
    required double max,
  }) {
    final value = params[key];
    if (value == null) return fallback;
    if (value is! num || !value.isFinite) {
      throw _ExternalControlValidationError('$key must be a finite number.');
    }
    return value.toDouble().clamp(min, max);
  }

  static String _boundedText(String value) {
    const maxLength = 32000;
    return value.length <= maxLength
        ? value
        : '${value.substring(0, maxLength)}\n[truncated]';
  }
}

class _ExternalControlValidationError implements Exception {
  const _ExternalControlValidationError(this.message);

  final String message;
}
