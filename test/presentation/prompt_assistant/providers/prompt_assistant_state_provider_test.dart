import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/presentation/prompt_assistant/providers/prompt_assistant_state_provider.dart';

void main() {
  test('new operations invalidate stale completion callbacks', () {
    final notifier = PromptAssistantStateNotifier();

    final firstGeneration = notifier.startProcessing('prompt', '翻译中');
    expect(notifier.isCurrent('prompt', firstGeneration), isTrue);

    final secondGeneration = notifier.startProcessing('prompt', '优化中');
    expect(secondGeneration, firstGeneration + 1);
    expect(notifier.isCurrent('prompt', firstGeneration), isFalse);
    expect(notifier.isCurrent('prompt', secondGeneration), isTrue);

    notifier.finishProcessing('prompt', generation: firstGeneration);
    expect(notifier.getState('prompt').processing, isTrue);
    expect(notifier.getState('prompt').action, '优化中');

    notifier.cancelProcessing('prompt');
    expect(notifier.getState('prompt').processing, isFalse);
    expect(notifier.getState('prompt').action, isNull);
    expect(notifier.isCurrent('prompt', secondGeneration), isFalse);
  });
}
