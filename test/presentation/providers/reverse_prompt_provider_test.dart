import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/presentation/providers/reverse_prompt_provider.dart';

void main() {
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
}
