import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/data/models/image/image_params.dart';
import 'package:nai_launcher/data/models/recipe/prompt_recipe.dart';
import 'package:nai_launcher/data/services/ai_batch_plan_service.dart';

void main() {
  final recipe = PromptRecipe.create(
    id: 'base-recipe',
    params: const ImageParams(prompt: '1girl, portrait', seed: 123),
  );

  test('parses a bounded pose plan and keeps it review-only', () {
    final raw = jsonEncode({
      'items': [
        {
          'id': 'pose-1',
          'summary': '站立并看向镜头',
          'operations': [
            {
              'id': 'op-1',
              'op': 'add',
              'target': 'main',
              'category': 'pose',
              'after': 'standing, looking at viewer',
              'reason': '满足用户要求',
              'evidenceIds': [],
              'confidence': 0.9,
              'explicit': false,
            },
          ],
        },
      ],
    });

    final plan = AiBatchPlanService.parseAndValidate(raw, recipe);
    expect(plan.items, hasLength(1));
    expect(plan.items.single.enabled, isTrue);
    expect(plan.items.single.operations.single.category, 'pose');
  });

  test('rejects request parameter operations before they reach the queue', () {
    final raw = jsonEncode({
      'items': [
        {
          'id': 'unsafe',
          'summary': '改模型',
          'operations': [
            {
              'id': 'op-unsafe',
              'op': 'parameter',
              'target': 'request:model',
              'category': 'style',
              'after': 'other-model',
              'reason': 'unsafe',
              'evidenceIds': [],
              'confidence': 1,
              'explicit': false,
            },
          ],
        },
      ],
    });

    final plan = AiBatchPlanService.parseAndValidate(raw, recipe);
    expect(plan.items.single.enabled, isFalse);
    expect(plan.items.single.operations, isEmpty);
    expect(plan.items.single.conflictWarnings, isNotEmpty);
  });

  test('materializes an approved item as an immutable queue snapshot', () {
    const item = AiBatchPlanItem(
      id: 'pose-1',
      summary: 'standing',
      operations: [
        PromptPatchOperation(
          id: 'op-1',
          op: 'add',
          target: 'main',
          category: 'pose',
          after: 'standing',
          reason: 'user approved',
          evidenceIds: [],
          confidence: 1,
        ),
      ],
    );

    final task = AiBatchPlanService.materializeTask(recipe, item);
    expect(task.prompt, contains('standing'));
    expect(task.generationSnapshot, isNotNull);
    expect(task.seed, 123);
    expect(task.generationSnapshot!['params'], isA<Map>());
  });
}
