import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/utils/prompt_replace_cleanup.dart';

void main() {
  test('removes empty top-level entries left by replace-all', () {
    final result = cleanPromptAfterReplaceAll('alpha, , beta,, gamma,');

    expect(result.text, 'alpha, beta, gamma');
    expect(result.caretOffset, result.text.length);
  });

  test('preserves grouped and quoted commas', () {
    final result = cleanPromptAfterReplaceAll(
      'alpha, (artist, style:1.1), "quoted, value", , beta',
    );

    expect(result.text, 'alpha, (artist, style:1.1), "quoted, value", beta');
  });

  test('keeps line breaks from a removed prompt entry', () {
    final result = cleanPromptAfterReplaceAll('alpha,\n , beta');

    expect(result.text, 'alpha,\n beta');
  });

  test('returns the original text when there is nothing to clean', () {
    const text = 'alpha, (artist, style:1.1), beta';

    final result = cleanPromptAfterReplaceAll(text, caretOffset: 8);

    expect(result.text, text);
    expect(result.caretOffset, 8);
  });

  test('maps the caret into the surviving segment', () {
    final result = cleanPromptAfterReplaceAll('alpha, , beta', caretOffset: 10);

    expect(result.text, 'alpha, beta');
    expect(result.caretOffset, 8);
  });
}
