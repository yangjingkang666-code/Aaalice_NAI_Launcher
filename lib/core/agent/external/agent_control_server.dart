import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'agent_control_protocol.dart';

typedef AgentControlCommandHandler =
    Future<AgentControlCommandResult> Function(AgentControlCommand command);
typedef AgentControlStatusHandler = Future<Map<String, dynamic>> Function();
typedef AgentControlConcurrencyDecider =
    bool Function(AgentControlCommand command);

class AgentControlServerInfo {
  const AgentControlServerInfo({
    required this.host,
    required this.port,
    required this.token,
  });

  final String host;
  final int port;
  final String token;

  String get baseUrl => 'http://$host:$port';

  Map<String, dynamic> toJson() => {
    'protocol': agentControlProtocolName,
    'version': agentControlProtocolVersion,
    'base_url': baseUrl,
    'host': host,
    'port': port,
    'token': token,
  };
}

/// Local-only HTTP transport for external agents.
///
/// The server is intentionally opt-in. It binds to IPv4 loopback, requires a
/// bearer token on every endpoint, serializes command execution (apart from
/// explicitly admitted reads or interrupt commands), and keeps idempotent
/// responses in a small bounded cache. It does not expose a second tool or
/// permission implementation; the supplied handler remains the policy
/// boundary owned by the application.
class AgentControlServer {
  AgentControlServer({
    required this.capabilities,
    required this.handleCommand,
    required this.readStatus,
    this.canRunConcurrently,
    this.authToken,
    this.maxBodyBytes = 1024 * 1024,
    this.commandTimeout = const Duration(minutes: 15),
    this.maxCachedCommands = 128,
  }) : assert(maxBodyBytes > 0),
       assert(maxCachedCommands > 0);

  final AgentControlCapabilities capabilities;
  final AgentControlCommandHandler handleCommand;
  final AgentControlStatusHandler readStatus;

  /// Explicitly admits short-lived reads or interrupt commands while a
  /// long-running command is active. All other commands remain serialized.
  final AgentControlConcurrencyDecider? canRunConcurrently;
  final String? authToken;
  final int maxBodyBytes;
  final Duration commandTimeout;
  final int maxCachedCommands;

  HttpServer? _httpServer;
  AgentControlServerInfo? _info;
  Future<void> _commandTail = Future<void>.value();
  final Map<String, _CachedCommand> _cachedCommands = {};

  bool get isRunning => _httpServer != null;
  AgentControlServerInfo get info {
    final value = _info;
    if (value == null) {
      throw StateError('Agent control server has not been started.');
    }
    return value;
  }

  Future<AgentControlServerInfo> start({int port = 0}) async {
    if (_httpServer != null) return info;
    final token = authToken?.trim().isNotEmpty == true
        ? authToken!.trim()
        : _createToken();
    if (token.length < 16) {
      throw ArgumentError.value(
        token,
        'authToken',
        'Agent control tokens must contain at least 16 characters.',
      );
    }
    final server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      port,
      shared: false,
    );
    _httpServer = server;
    _info = AgentControlServerInfo(
      host: InternetAddress.loopbackIPv4.host,
      port: server.port,
      token: token,
    );
    unawaited(_serve(server));
    return info;
  }

  Future<void> stop() async {
    final server = _httpServer;
    _httpServer = null;
    _info = null;
    _cachedCommands.clear();
    if (server != null) await server.close(force: true);
  }

  Future<void> writeDescriptor(File file) async {
    final descriptor = info;
    await file.parent.create(recursive: true);
    final temp = File(
      '${file.path}.tmp-${DateTime.now().microsecondsSinceEpoch}',
    );
    await temp.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(descriptor.toJson())}\n',
      flush: true,
    );
    if (await file.exists()) await file.delete();
    await temp.rename(file.path);
  }

  Future<void> _serve(HttpServer server) async {
    await for (final request in server) {
      unawaited(_handleSafely(request));
    }
  }

  Future<void> _handleSafely(HttpRequest request) async {
    try {
      await _handle(request);
    } catch (error) {
      await _write(
        request.response,
        AgentControlResponse.failure(
          '',
          AgentControlError(code: 'internal', message: '$error'),
        ),
      );
    }
  }

  Future<void> _handle(HttpRequest request) async {
    if (!_authorized(request)) {
      await _write(
        request.response,
        AgentControlResponse.failure(
          '',
          const AgentControlError(
            code: 'unauthorized',
            message: 'A valid bearer token is required.',
          ),
        ),
      );
      return;
    }

    final path = request.uri.path;
    if (request.method == 'GET' && path == '/v1/capabilities') {
      await _writeMap(request.response, capabilities.toJson());
      return;
    }
    if (request.method == 'GET' && path == '/v1/status') {
      try {
        final status = await readStatus().timeout(commandTimeout);
        await _writeMap(request.response, {
          'protocol': agentControlProtocolName,
          'version': agentControlProtocolVersion,
          'ok': true,
          'status': status,
        });
      } on TimeoutException {
        await _write(
          request.response,
          AgentControlResponse.failure(
            '',
            const AgentControlError(
              code: 'timeout',
              message: 'Status request timed out.',
            ),
          ),
        );
      } catch (error) {
        await _write(
          request.response,
          AgentControlResponse.failure(
            '',
            AgentControlError(code: 'internal', message: '$error'),
          ),
        );
      }
      return;
    }
    if (path == '/v1/commands') {
      if (request.method != 'POST') {
        await _write(
          request.response,
          AgentControlResponse.failure(
            '',
            const AgentControlError(
              code: 'method_not_allowed',
              message: 'Use POST for command requests.',
            ),
          ),
        );
        return;
      }
      final command = await _decodeCommand(request);
      if (command == null) return;
      if (!capabilities.supports(command.method)) {
        await _write(
          request.response,
          AgentControlResponse.failure(
            command.requestId,
            AgentControlError(
              code: 'not_found',
              message: 'Unknown command: ${command.method}.',
            ),
          ),
        );
        return;
      }
      final response = canRunConcurrently?.call(command) == true
          ? await _execute(command)
          : await _enqueue(command);
      await _write(request.response, response);
      return;
    }

    await _write(
      request.response,
      AgentControlResponse.failure(
        '',
        const AgentControlError(
          code: 'not_found',
          message: 'Endpoint not found.',
        ),
      ),
    );
  }

  Future<AgentControlCommand?> _decodeCommand(HttpRequest request) async {
    try {
      final raw = await _readBody(request);
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        throw const AgentControlProtocolException(
          'invalid_request',
          'Request body must be a JSON object.',
        );
      }
      final json = <String, dynamic>{};
      for (final entry in decoded.entries) {
        if (entry.key is! String) {
          throw const AgentControlProtocolException(
            'invalid_request',
            'Request object keys must be strings.',
          );
        }
        json[entry.key as String] = entry.value;
      }
      return AgentControlCommand.fromJson(json);
    } on AgentControlProtocolException catch (error) {
      await _write(
        request.response,
        AgentControlResponse.failure(
          '',
          AgentControlError(code: error.code, message: error.message),
        ),
      );
      return null;
    } on FormatException {
      await _write(
        request.response,
        AgentControlResponse.failure(
          '',
          const AgentControlError(
            code: 'invalid_json',
            message: 'Request body is not valid JSON.',
          ),
        ),
      );
      return null;
    } on _PayloadTooLargeException {
      await _write(
        request.response,
        AgentControlResponse.failure(
          '',
          const AgentControlError(
            code: 'payload_too_large',
            message: 'Request body exceeds the maximum size.',
          ),
        ),
      );
      return null;
    }
  }

  Future<String> _readBody(HttpRequest request) async {
    final bytes = <int>[];
    await for (final chunk in request) {
      if (bytes.length + chunk.length > maxBodyBytes) {
        throw const _PayloadTooLargeException();
      }
      bytes.addAll(chunk);
    }
    return utf8.decode(bytes);
  }

  Future<AgentControlResponse> _enqueue(AgentControlCommand command) {
    final next = _commandTail.then((_) => _execute(command));
    _commandTail = next.then<void>((_) {}, onError: (_, __) {});
    return next;
  }

  Future<AgentControlResponse> _execute(AgentControlCommand command) async {
    final key = command.idempotencyKey;
    final fingerprint = jsonEncode({
      'method': command.method,
      'params': command.params,
    });
    if (key != null) {
      final cached = _cachedCommands[key];
      if (cached != null) {
        if (cached.fingerprint != fingerprint) {
          return AgentControlResponse.failure(
            command.requestId,
            const AgentControlError(
              code: 'conflict',
              message: 'idempotency_key was already used for another command.',
            ),
          );
        }
        return AgentControlResponse(
          requestId: command.requestId,
          result: cached.response.result,
          error: cached.response.error,
          cached: true,
        );
      }
    }

    AgentControlResponse response;
    try {
      final result = await handleCommand(command).timeout(commandTimeout);
      response = result.ok
          ? AgentControlResponse.success(command.requestId, result.result!)
          : AgentControlResponse.failure(command.requestId, result.error!);
    } on TimeoutException {
      response = AgentControlResponse.failure(
        command.requestId,
        const AgentControlError(
          code: 'timeout',
          message: 'Command execution timed out.',
        ),
      );
    } catch (error) {
      response = AgentControlResponse.failure(
        command.requestId,
        AgentControlError(code: 'internal', message: '$error'),
      );
    }

    if (key != null) {
      _cachedCommands[key] = _CachedCommand(
        fingerprint: fingerprint,
        response: response,
      );
      while (_cachedCommands.length > maxCachedCommands) {
        _cachedCommands.remove(_cachedCommands.keys.first);
      }
    }
    return response;
  }

  bool _authorized(HttpRequest request) {
    final authorization = request.headers.value(
      HttpHeaders.authorizationHeader,
    );
    final expected = 'Bearer ${info.token}';
    return authorization == expected;
  }

  Future<void> _writeMap(HttpResponse response, Map<String, dynamic> body) {
    response.statusCode = 200;
    return _writeJson(response, body);
  }

  Future<void> _write(HttpResponse response, AgentControlResponse body) {
    response.statusCode = body.httpStatusCode;
    return _writeJson(response, body.toJson());
  }

  Future<void> _writeJson(
    HttpResponse response,
    Map<String, dynamic> body,
  ) async {
    response.headers.contentType = ContentType.json;
    response.headers.set('cache-control', 'no-store');
    response.add(utf8.encode(jsonEncode(body)));
    await response.close();
  }

  static String _createToken() {
    final random = Random.secure();
    return base64UrlEncode(List<int>.generate(32, (_) => random.nextInt(256)));
  }
}

class _CachedCommand {
  const _CachedCommand({required this.fingerprint, required this.response});

  final String fingerprint;
  final AgentControlResponse response;
}

class _PayloadTooLargeException implements Exception {
  const _PayloadTooLargeException();
}
