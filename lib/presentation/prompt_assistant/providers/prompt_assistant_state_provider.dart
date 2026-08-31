import 'package:flutter_riverpod/flutter_riverpod.dart';

class PromptAssistantOperationState {
  final bool expanded;
  final bool hovering;
  final bool processing;
  final String? action;
  final String? error;
  final int generation;

  const PromptAssistantOperationState({
    this.expanded = false,
    this.hovering = false,
    this.processing = false,
    this.action,
    this.error,
    this.generation = 0,
  });

  PromptAssistantOperationState copyWith({
    bool? expanded,
    bool? hovering,
    bool? processing,
    String? action,
    bool clearAction = false,
    String? error,
    int? generation,
    bool clearError = false,
  }) {
    return PromptAssistantOperationState(
      expanded: expanded ?? this.expanded,
      hovering: hovering ?? this.hovering,
      processing: processing ?? this.processing,
      action: clearAction ? null : action ?? this.action,
      error: clearError ? null : (error ?? this.error),
      generation: generation ?? this.generation,
    );
  }
}

final promptAssistantStateProvider =
    StateNotifierProvider<
      PromptAssistantStateNotifier,
      Map<String, PromptAssistantOperationState>
    >((ref) => PromptAssistantStateNotifier());

class PromptAssistantStateNotifier
    extends StateNotifier<Map<String, PromptAssistantOperationState>> {
  PromptAssistantStateNotifier() : super(const {});

  PromptAssistantOperationState getState(String sessionId) {
    return state[sessionId] ?? const PromptAssistantOperationState();
  }

  void _put(String sessionId, PromptAssistantOperationState value) {
    state = {...state, sessionId: value};
  }

  void setExpanded(String sessionId, bool expanded) {
    _put(sessionId, getState(sessionId).copyWith(expanded: expanded));
  }

  void setHovering(String sessionId, bool hovering) {
    _put(sessionId, getState(sessionId).copyWith(hovering: hovering));
  }

  int startProcessing(String sessionId, String action) {
    final generation = getState(sessionId).generation + 1;
    _put(
      sessionId,
      getState(sessionId).copyWith(
        processing: true,
        action: action,
        generation: generation,
        clearError: true,
      ),
    );
    return generation;
  }

  void finishProcessing(String sessionId, {int? generation}) {
    if (!_isCurrent(sessionId, generation)) {
      return;
    }
    _put(
      sessionId,
      getState(sessionId).copyWith(processing: false, clearAction: true),
    );
  }

  void setError(String sessionId, String error, {int? generation}) {
    if (!_isCurrent(sessionId, generation)) {
      return;
    }
    _put(
      sessionId,
      getState(
        sessionId,
      ).copyWith(processing: false, clearAction: true, error: error),
    );
  }

  /// Invalidates the current stream before provider cancellation is awaited.
  /// Any queued `onError`/`onDone` callbacks from the old stream will then be
  /// ignored by callers holding the previous generation.
  void cancelProcessing(String sessionId) {
    final current = getState(sessionId);
    _put(
      sessionId,
      current.copyWith(
        processing: false,
        clearAction: true,
        generation: current.generation + 1,
      ),
    );
  }

  bool isCurrent(String sessionId, int generation) =>
      _isCurrent(sessionId, generation);

  bool _isCurrent(String sessionId, int? generation) =>
      generation == null || getState(sessionId).generation == generation;
}
