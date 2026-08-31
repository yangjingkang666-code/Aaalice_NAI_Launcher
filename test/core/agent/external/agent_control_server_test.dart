import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/agent/external/agent_control_protocol.dart';
import 'package:nai_launcher/core/agent/external/agent_control_server.dart';

void main() {
  late AgentControlServer server;
  late Completer<void> blockingStarted;
  late Completer<void> releaseBlock;

  setUp(() async {
    blockingStarted = Completer<void>();
    releaseBlock = Completer<void>();
    server = AgentControlServer(
      capabilities: const AgentControlCapabilities(
        methods: [
          AgentControlMethod(
            name: 'test.echo',
            description: 'Echo test payload.',
            parameters: {
              'type': 'object',
              'properties': {
                'value': {'type': 'string'},
              },
            },
          ),
          AgentControlMethod(
            name: 'test.block',
            description: 'Hold the serialized lane for a concurrency test.',
            parameters: {},
          ),
          AgentControlMethod(
            name: 'test.interrupt',
            description: 'Short command admitted during a blocking command.',
            parameters: {},
          ),
        ],
      ),
      readStatus: () async => const {'state': 'idle'},
      handleCommand: (command) async {
        if (command.method == 'test.block') {
          blockingStarted.complete();
          await releaseBlock.future;
        }
        return AgentControlCommandResult.success({
          'value': command.params['value'],
          'method': command.method,
        });
      },
      canRunConcurrently: (command) => command.method == 'test.interrupt',
      authToken: 'test-token-1234567890',
    );
    await server.start();
  });

  tearDown(() => server.stop());

  Future<(int, Map<String, dynamic>)> getJson(
    String path, {
    String? token,
  }) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(
        Uri.parse('${server.info.baseUrl}$path'),
      );
      if (token != null) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      }
      final response = await request.close();
      final body =
          jsonDecode(await response.transform(utf8.decoder).join())
              as Map<String, dynamic>;
      return (response.statusCode, body);
    } finally {
      client.close(force: true);
    }
  }

  Future<(int, Map<String, dynamic>)> postJson(
    String path,
    Map<String, dynamic> body, {
    String? token,
  }) async {
    final client = HttpClient();
    try {
      final request = await client.postUrl(
        Uri.parse('${server.info.baseUrl}$path'),
      );
      request.headers.contentType = ContentType.json;
      if (token != null) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      }
      request.write(jsonEncode(body));
      final response = await request.close();
      final decoded =
          jsonDecode(await response.transform(utf8.decoder).join())
              as Map<String, dynamic>;
      return (response.statusCode, decoded);
    } finally {
      client.close(force: true);
    }
  }

  test('requires bearer auth and exposes capabilities/status', () async {
    final unauthorized = await getJson('/v1/status');
    expect(unauthorized.$1, 401);
    expect(unauthorized.$2['error']['code'], 'unauthorized');

    final capabilities = await getJson(
      '/v1/capabilities',
      token: server.info.token,
    );
    expect(capabilities.$1, 200);
    expect(capabilities.$2['version'], agentControlProtocolVersion);
    expect(
      (capabilities.$2['methods'] as List)
          .map((method) => method['name'])
          .toList(),
      contains('test.echo'),
    );

    final status = await getJson('/v1/status', token: server.info.token);
    expect(status.$1, 200);
    expect(status.$2['status']['state'], 'idle');
  });

  test('serializes commands and replays idempotent requests', () async {
    final first = await postJson('/v1/commands', {
      'protocol': agentControlProtocolName,
      'version': agentControlProtocolVersion,
      'request_id': 'request-1',
      'method': 'test.echo',
      'params': {'value': 'hello'},
      'idempotency_key': 'same-operation',
    }, token: server.info.token);
    expect(first.$1, 200);
    expect(first.$2['result']['value'], 'hello');

    final replay = await postJson('/v1/commands', {
      'protocol': agentControlProtocolName,
      'version': agentControlProtocolVersion,
      'request_id': 'request-2',
      'method': 'test.echo',
      'params': {'value': 'hello'},
      'idempotency_key': 'same-operation',
    }, token: server.info.token);
    expect(replay.$1, 200);
    expect(replay.$2['request_id'], 'request-2');
    expect(replay.$2['cached'], true);

    final conflict = await postJson('/v1/commands', {
      'protocol': agentControlProtocolName,
      'version': agentControlProtocolVersion,
      'request_id': 'request-3',
      'method': 'test.echo',
      'params': {'value': 'different'},
      'idempotency_key': 'same-operation',
    }, token: server.info.token);
    expect(conflict.$1, 409);
    expect(conflict.$2['error']['code'], 'conflict');
  });

  test(
    'rejects malformed and unknown commands before handler execution',
    () async {
      final malformed = await postJson('/v1/commands', {
        'method': 'test.echo',
      }, token: server.info.token);
      expect(malformed.$1, 400);
      expect(malformed.$2['error']['code'], 'invalid_request_id');

      final unsupported = await postJson('/v1/commands', {
        'protocol': agentControlProtocolName,
        'version': '999',
        'request_id': 'unsupported-version',
        'method': 'test.echo',
      }, token: server.info.token);
      expect(unsupported.$1, 400);
      expect(unsupported.$2['error']['code'], 'unsupported_version');

      final unknown = await postJson('/v1/commands', {
        'protocol': agentControlProtocolName,
        'version': agentControlProtocolVersion,
        'request_id': 'unknown',
        'method': 'test.unknown',
      }, token: server.info.token);
      expect(unknown.$1, 404);
      expect(unknown.$2['error']['code'], 'not_found');

      final invalidParams = await postJson('/v1/commands', {
        'protocol': agentControlProtocolName,
        'version': agentControlProtocolVersion,
        'request_id': 'invalid-params',
        'method': 'test.echo',
        'params': ['not-a-json-object'],
      }, token: server.info.token);
      expect(invalidParams.$1, 400);
      expect(invalidParams.$2['error']['code'], 'invalid_params');
    },
  );

  test('admits an interrupt without waiting behind a long command', () async {
    final blocking = postJson('/v1/commands', {
      'protocol': agentControlProtocolName,
      'version': agentControlProtocolVersion,
      'request_id': 'blocking',
      'method': 'test.block',
    }, token: server.info.token);
    await blockingStarted.future;

    final interrupt = await postJson('/v1/commands', {
      'protocol': agentControlProtocolName,
      'version': agentControlProtocolVersion,
      'request_id': 'interrupt',
      'method': 'test.interrupt',
    }, token: server.info.token);
    expect(interrupt.$1, 200);
    expect(interrupt.$2['result']['method'], 'test.interrupt');

    releaseBlock.complete();
    final completed = await blocking;
    expect(completed.$1, 200);
    expect(completed.$2['result']['method'], 'test.block');
  });
}
