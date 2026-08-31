import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/agent_external_control_service.dart';
import 'agent_chat_notifier.dart';

final agentExternalControlProvider = Provider<AgentExternalControlService>((
  ref,
) {
  final service = AgentExternalControlService(
    readAgent: () => ref.read(agentChatNotifierProvider.notifier),
    authToken: const String.fromEnvironment('AGENT_CONTROL_TOKEN'),
  );
  ref.onDispose(() => unawaited(service.stop()));
  return service;
});
