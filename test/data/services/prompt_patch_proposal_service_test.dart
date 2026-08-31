import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/data/models/image/image_params.dart';
import 'package:nai_launcher/data/models/recipe/prompt_recipe.dart';
import 'package:nai_launcher/data/services/prompt_patch_proposal_service.dart';

void main() {
  final recipe = PromptRecipe.create(
    id: 'recipe-1',
    params: const ImageParams(prompt: '1girl, blue eyes'),
    characters: const [
      RecipeCharacter(
        id: 'character-1',
        name: 'Alice',
        prompt: '1girl, blue eyes',
        negativePrompt: '',
        enabled: true,
        center: RecipeCharacterCenter(x: 0.5, y: 0.5),
        corePrompt: 'blue eyes',
        lockedTraits: ['blue eyes'],
      ),
    ],
  );

  test('parses a bounded JSON proposal and defaults safe metadata', () {
    final operations = PromptPatchProposalService.parse(
      '''```json
{"operations":[{"id":"op-1","op":"add","target":"main","after":"soft lighting","reason":"Improve readability."}]}
```''',
    );

    expect(operations, hasLength(1));
    expect(operations.single.id, 'op-1');
    expect(operations.single.after, 'soft lighting');
    expect(operations.single.evidenceIds, isEmpty);
    expect(operations.single.confidence, 0.5);
    expect(operations.single.explicit, isFalse);
  });

  test('validation is returned separately and protected edits stay rejected', () {
    final proposal = PromptPatchProposalService.parseAndValidate(
      jsonEncode({
        'operations': [
          {
            'id': 'op-1',
            'op': 'replace',
            'target': 'character:character-1',
            'before': 'blue eyes',
            'after': 'green eyes',
            'reason': 'Change the character identity.',
            'evidenceIds': const [],
            'confidence': 0.9,
            'explicit': false,
          },
        ],
      }),
      recipe,
    );

    expect(proposal.operations, hasLength(1));
    expect(proposal.isValid, isFalse);
    expect(
      proposal.validation.issues.any(
        (issue) => issue.code.name == 'locked',
      ),
      isTrue,
    );
  });

  test('assistant cannot self-grant explicit lock overrides', () {
    expect(
      () => PromptPatchProposalService.parse(
        jsonEncode({
          'operations': [
            {
              'id': 'op-1',
              'op': 'add',
              'target': 'main',
              'after': 'detail',
              'reason': 'reason',
              'evidenceIds': const [],
              'confidence': 1,
              'explicit': true,
            },
          ],
        }),
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects unknown fields, oversized values, and too many operations', () {
    expect(
      () => PromptPatchProposalService.parse(
        '{"operations":[{"id":"1","op":"add","target":"main","after":"x","reason":"r","evidenceIds":[],"confidence":1,"explicit":false,"run":"delete files"}]}',
      ),
      throwsA(isA<FormatException>()),
    );

    final oversized = jsonEncode({
      'operations': [
        {
          'id': '1',
          'op': 'add',
          'target': 'main',
          'after': 'x' * (PromptPatchProposalService.maxValueLength + 1),
          'reason': 'r',
          'evidenceIds': const [],
          'confidence': 1,
          'explicit': false,
        },
      ],
    });
    expect(
      () => PromptPatchProposalService.parse(oversized),
      throwsA(isA<FormatException>()),
    );

    final tooMany = {
      'operations': [
        for (var i = 0; i < PromptPatchProposalService.maxOperations + 1; i++)
          {
            'id': '$i',
            'op': 'keep',
            'target': 'main',
            'reason': 'keep',
            'evidenceIds': const [],
            'confidence': 0.5,
            'explicit': false,
          },
      ],
    };
    expect(
      () => PromptPatchProposalService.parse(jsonEncode(tooMany)),
      throwsA(isA<FormatException>()),
    );
  });

  test('user payload contains recipe metadata but never binary inputs', () {
    final payload = PromptPatchProposalService.buildUserContent(
      PromptRecipe.create(
        id: 'recipe-2',
        params: ImageParams(
          prompt: 'prompt',
          sourceImage: Uint8List.fromList([1, 2, 3]),
        ),
      ),
      userInstruction: 'add atmosphere',
    );

    expect(payload, contains('recipe-2'));
    expect(payload, contains('add atmosphere'));
    expect(payload, isNot(contains('sourceImage')));
    expect(payload, isNot(contains('1,2,3')));
  });
}
