import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/data/models/recipe/prompt_recipe.dart';
import 'package:nai_launcher/data/services/prompt_semantic_organization_service.dart';

PromptSemanticEntry _entry(
  String text, {
  String category = 'other',
  String source = 'imported',
}) {
  return PromptSemanticEntry(
    id: 'id-$text',
    text: text,
    category: category,
    source: source,
    localTagHit: source == 'tag-db',
    confidence: source == 'tag-db' ? 1 : 0.45,
    kind: 'natural-phrase',
  );
}

void main() {
  test('merges valid AI classification and translation per item', () {
    final result = PromptSemanticOrganizationService.parseAndMerge(
      '{"items":[{"text":"red-purple eyes","category":"appearance","kind":"natural-phrase","translation":"红紫色眼睛","confidence":0.86}]}',
      [_entry('red-purple eyes')],
    );

    expect(result.entries.single.category, 'appearance');
    expect(result.entries.single.source, 'ai');
    expect(result.translations['red-purple eyes'], '红紫色眼睛');
  });

  test('keeps local and manual categories when AI conflicts', () {
    final result = PromptSemanticOrganizationService.parseAndMerge(
      '{"items":[{"text":"blue_eyes","category":"clothing","translation":"蓝眼睛"},{"text":"custom","category":"style","translation":"自定义"}]}',
      [
        _entry('blue_eyes', category: 'appearance', source: 'tag-db'),
        _entry('custom', category: 'scene', source: 'manual'),
      ],
    );

    expect(result.entries[0].category, 'appearance');
    expect(result.entries[0].source, 'tag-db');
    expect(result.entries[1].category, 'scene');
    expect(result.entries[1].source, 'manual');
    expect(result.translations['blue_eyes'], '蓝眼睛');
  });

  test('degrades malformed rows without dropping the whole response', () {
    final result = PromptSemanticOrganizationService.parseAndMerge(
      '{"items":[{"text":"ok phrase","category":"scene","confidence":0.7},{"text":3,"category":"scene"}]}',
      [_entry('ok phrase')],
    );

    expect(result.entries.single.category, 'scene');
    expect(result.warnings, isNotEmpty);
  });

  test('does not add assistant-invented phrases to the structured prompt', () {
    final result = PromptSemanticOrganizationService.parseAndMerge(
      '{"items":[{"text":"invented phrase","category":"scene","kind":"natural-phrase","confidence":0.9}]}',
      [_entry('1girl', category: 'subject')],
    );

    expect(result.entries, hasLength(1));
    expect(result.entries.single.text, '1girl');
    expect(result.warnings, isNotEmpty);
  });
}
