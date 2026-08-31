import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/presentation/prompt_assistant/models/reverse_prompt_models.dart';

void main() {
  test('parses the structured reverse-prompt schema', () {
    final draft = ReversePromptDraft.parse(
      '''{"main_prompt":"1girl, blue eyes\\n, moonlit classroom","negative_prompt":"lowres","main_prompt_entries":[{"text":"blue eyes","category":"appearance","translation":"蓝眼睛","confidence":1.4}],"chinese_summary":"月光下的教室","warnings":["identity uncertain"]}''',
      routeFingerprint: 'provider/model/openaiChatCompletions',
      routeLabel: 'Provider / model',
    );

    expect(draft.positivePrompt, '1girl, blue eyes, moonlit classroom');
    expect(draft.negativePrompt, 'lowres');
    expect(draft.semanticEntries, hasLength(1));
    expect(draft.semanticEntries.single.category, 'appearance');
    expect(draft.semanticEntries.single.confidence, 1.0);
    expect(draft.chineseSummary, '月光下的教室');
    expect(draft.warnings, ['identity uncertain']);
    expect(draft.routeLabel, 'Provider / model');
    expect(draft.usedFallback, isFalse);
  });

  test('keeps plain-text provider output as an explicit fallback', () {
    final draft = ReversePromptDraft.parse(
      '1girl, standing, sunset, detailed background',
      routeLabel: 'Gateway / vision-model',
    );

    expect(
      draft.positivePrompt,
      '1girl, standing, sunset, detailed background',
    );
    expect(draft.usedFallback, isTrue);
    expect(draft.rawResponse, contains('sunset'));
    expect(draft.warnings, hasLength(1));
  });

  test('rejects an empty reverse-prompt response', () {
    expect(
      () => ReversePromptDraft.parse('   '),
      throwsA(isA<FormatException>()),
    );
  });
}
