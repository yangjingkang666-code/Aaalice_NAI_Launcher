/// Versioned wire types shared by the local Agent control server and clients.
const agentControlProtocolName = 'aaalice-agent-control';
const agentControlProtocolVersion = '1';

class AgentControlProtocolException implements Exception {
  const AgentControlProtocolException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'AgentControlProtocolException($code): $message';
}

class AgentControlCommand {
  const AgentControlCommand({
    required this.requestId,
    required this.method,
    required this.params,
    this.idempotencyKey,
  });

  factory AgentControlCommand.fromJson(Map<String, dynamic> json) {
    final requestId = _requiredString(json, 'request_id', maxLength: 128);
    final method = _requiredString(json, 'method', maxLength: 128);
    if (json['protocol'] != agentControlProtocolName) {
      throw const AgentControlProtocolException(
        'invalid_protocol',
        'protocol must identify aaalice-agent-control.',
      );
    }
    if (json['version'] != agentControlProtocolVersion) {
      throw const AgentControlProtocolException(
        'unsupported_version',
        'Only agent-control protocol version 1 is supported.',
      );
    }
    final rawParams = json['params'];
    if (rawParams != null && rawParams is! Map) {
      throw const AgentControlProtocolException(
        'invalid_params',
        'params must be a JSON object.',
      );
    }
    final params = <String, dynamic>{};
    if (rawParams is Map) {
      for (final entry in rawParams.entries) {
        if (entry.key is! String) {
          throw const AgentControlProtocolException(
            'invalid_params',
            'params object keys must be strings.',
          );
        }
        params[entry.key as String] = entry.value;
      }
    }
    final rawIdempotencyKey = json['idempotency_key'];
    if (rawIdempotencyKey != null && rawIdempotencyKey is! String) {
      throw const AgentControlProtocolException(
        'invalid_idempotency_key',
        'idempotency_key must be a string.',
      );
    }
    final idempotencyKey = (rawIdempotencyKey as String?)?.trim();
    if (idempotencyKey != null &&
        (idempotencyKey.isEmpty || idempotencyKey.length > 128)) {
      throw const AgentControlProtocolException(
        'invalid_idempotency_key',
        'idempotency_key must contain 1 to 128 characters.',
      );
    }
    return AgentControlCommand(
      requestId: requestId,
      method: method,
      params: params,
      idempotencyKey: idempotencyKey,
    );
  }

  final String requestId;
  final String method;
  final Map<String, dynamic> params;
  final String? idempotencyKey;

  Map<String, dynamic> toJson() => {
    'protocol': agentControlProtocolName,
    'version': agentControlProtocolVersion,
    'request_id': requestId,
    'method': method,
    'params': params,
    if (idempotencyKey != null) 'idempotency_key': idempotencyKey,
  };
}

class AgentControlError {
  const AgentControlError({
    required this.code,
    required this.message,
    this.details,
  });

  final String code;
  final String message;
  final Map<String, dynamic>? details;

  Map<String, dynamic> toJson() => {
    'code': code,
    'message': message,
    if (details != null) 'details': details,
  };
}

class AgentControlCommandResult {
  const AgentControlCommandResult.success([this.result = const {}])
    : error = null;

  const AgentControlCommandResult.failure(this.error) : result = null;

  final Map<String, dynamic>? result;
  final AgentControlError? error;

  bool get ok => error == null;
}

class AgentControlResponse {
  const AgentControlResponse({
    required this.requestId,
    required this.result,
    required this.error,
    this.cached = false,
  });

  factory AgentControlResponse.success(
    String requestId,
    Map<String, dynamic> result, {
    bool cached = false,
  }) => AgentControlResponse(
    requestId: requestId,
    result: result,
    error: null,
    cached: cached,
  );

  factory AgentControlResponse.failure(
    String requestId,
    AgentControlError error, {
    bool cached = false,
  }) => AgentControlResponse(
    requestId: requestId,
    result: null,
    error: error,
    cached: cached,
  );

  final String requestId;
  final Map<String, dynamic>? result;
  final AgentControlError? error;
  final bool cached;

  bool get ok => error == null;

  int get httpStatusCode {
    final code = error?.code;
    return switch (code) {
      'unauthorized' => 401,
      'forbidden' || 'blocked' => 403,
      'not_found' => 404,
      'method_not_allowed' => 405,
      'conflict' || 'busy' => 409,
      'payload_too_large' => 413,
      'timeout' => 504,
      null => 200,
      _ => 400,
    };
  }

  Map<String, dynamic> toJson() => {
    'protocol': agentControlProtocolName,
    'version': agentControlProtocolVersion,
    'request_id': requestId,
    'ok': ok,
    if (result != null) 'result': result,
    if (error != null) 'error': error!.toJson(),
    if (cached) 'cached': true,
  };
}

class AgentControlMethod {
  const AgentControlMethod({
    required this.name,
    required this.description,
    required this.parameters,
    this.readOnly = false,
    this.mayConsumeAnlas = false,
  });

  final String name;
  final String description;
  final Map<String, dynamic> parameters;
  final bool readOnly;
  final bool mayConsumeAnlas;

  Map<String, dynamic> toJson() => {
    'name': name,
    'description': description,
    'parameters': parameters,
    'read_only': readOnly,
    'may_consume_anlas': mayConsumeAnlas,
  };
}

class AgentControlCapabilities {
  const AgentControlCapabilities({required this.methods});

  final List<AgentControlMethod> methods;

  bool supports(String method) => methods.any((item) => item.name == method);

  Map<String, dynamic> toJson() => {
    'protocol': agentControlProtocolName,
    'version': agentControlProtocolVersion,
    'transport': 'http-loopback',
    'authentication': 'bearer',
    'methods': methods.map((item) => item.toJson()).toList(growable: false),
  };
}

String _requiredString(
  Map<String, dynamic> json,
  String key, {
  required int maxLength,
}) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty || value.length > maxLength) {
    throw AgentControlProtocolException(
      'invalid_$key',
      '$key must be a non-empty string of at most $maxLength characters.',
    );
  }
  return value.trim();
}
