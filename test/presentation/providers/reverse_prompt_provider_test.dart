import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
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
}
