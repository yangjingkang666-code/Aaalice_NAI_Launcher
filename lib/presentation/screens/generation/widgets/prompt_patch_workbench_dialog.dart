import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/utils/localization_extension.dart';
import '../../../../data/models/recipe/prompt_recipe.dart';
import '../../../../data/services/prompt_patch_service.dart';
import '../../../services/prompt_recipe_application_service.dart';

/// A small, explicit Prompt Patch workbench.
///
/// The workbench deliberately starts with manual operations. This keeps the
/// first Flutter integration deterministic and safe while leaving a clean
/// surface for a future AI proposal provider to populate the same rows.
class PromptPatchWorkbenchDialog extends ConsumerStatefulWidget {
  const PromptPatchWorkbenchDialog({required this.recipe, super.key});

  final PromptRecipe recipe;

  static Future<AppliedPromptPatch?> show(
    BuildContext context,
    PromptRecipe recipe,
  ) {
    return showDialog<AppliedPromptPatch>(
      context: context,
      builder: (_) => PromptPatchWorkbenchDialog(recipe: recipe),
    );
  }

  @override
  ConsumerState<PromptPatchWorkbenchDialog> createState() =>
      _PromptPatchWorkbenchDialogState();
}

class _PromptPatchWorkbenchDialogState
    extends ConsumerState<PromptPatchWorkbenchDialog> {
  final List<_PatchDraft> _drafts = [];
  List<PromptPatchValidationIssue> _issues = const [];
  bool _applying = false;

  @override
  void initState() {
    super.initState();
    _addDraft();
  }

  @override
  void dispose() {
    for (final draft in _drafts) {
      draft.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final size = MediaQuery.of(context).size;
    final maxWidth = size.width.isFinite ? size.width * .96 : 960.0;
    final maxHeight = size.height.isFinite ? size.height * .9 : 760.0;

    return Dialog(
      key: const ValueKey('prompt-patch-workbench'),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth.clamp(420.0, 960.0),
          maxHeight: maxHeight.clamp(420.0, 820.0),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.edit_note_rounded),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.promptPatch_title,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: l10n.common_close,
                    onPressed: _applying
                        ? null
                        : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                l10n.promptPatch_protectedHint,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 10),
              _buildRecipeSummary(context),
              const SizedBox(height: 10),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_drafts.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Text(
                            l10n.promptPatch_empty,
                            textAlign: TextAlign.center,
                          ),
                        )
                      else
                        for (var index = 0; index < _drafts.length; index++)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _buildDraftCard(context, index),
                          ),
                      if (_issues.isNotEmpty) _buildIssues(context),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _applying ? null : _addDraft,
                    icon: const Icon(Icons.add),
                    label: Text(l10n.promptPatch_addOperation),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _applying
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: Text(l10n.common_cancel),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _applying || _drafts.isEmpty ? null : _apply,
                    icon: _applying
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check),
                    label: Text(l10n.promptPatch_apply),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecipeSummary(BuildContext context) {
    final params = widget.recipe.request.params;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Recipe ${widget.recipe.id}',
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const SizedBox(height: 4),
            Text(
              '主 Prompt：${params.prompt.isEmpty ? "（空）" : params.prompt}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (params.negativePrompt.isNotEmpty)
              Text(
                '负向 Prompt：${params.negativePrompt}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDraftCard(BuildContext context, int index) {
    final l10n = context.l10n;
    final draft = _drafts[index];
    final operationNeedsBefore = switch (draft.op) {
      'remove' || 'replace' || 'move' => true,
      _ => false,
    };
    final operationNeedsAfter = switch (draft.op) {
      'add' || 'replace' || 'move' || 'parameter' => true,
      _ => false,
    };
    final showCategory = draft.op != 'parameter' && draft.op != 'keep';

    return Card(
      key: ValueKey('prompt-patch-operation-${draft.id}'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: draft.op,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: l10n.promptPatch_operation,
                      isDense: true,
                    ),
                    items: [
                      for (final op in _operationValues)
                        DropdownMenuItem(
                          value: op,
                          child: Text(_operationLabel(context, op)),
                        ),
                    ],
                    onChanged: _applying
                        ? null
                        : (value) {
                            if (value == null) return;
                            setState(() {
                              draft.op = value;
                              _issues = const [];
                            });
                          },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<String>(
                    initialValue: draft.target,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: l10n.promptPatch_target,
                      isDense: true,
                    ),
                    items: [
                      for (final target in _targetChoices)
                        DropdownMenuItem(
                          value: target.value,
                          child: Text(
                            target.label,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: _applying
                        ? null
                        : (value) {
                            if (value == null) return;
                            setState(() {
                              draft.target = value;
                              _issues = const [];
                            });
                          },
                  ),
                ),
                IconButton(
                  tooltip: l10n.common_delete,
                  onPressed: _applying ? null : () => _removeDraft(index),
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            if (operationNeedsBefore || operationNeedsAfter) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (operationNeedsBefore)
                    Expanded(
                      child: TextField(
                        controller: draft.before,
                        enabled: !_applying,
                        decoration: InputDecoration(
                          labelText: l10n.promptPatch_before,
                          isDense: true,
                        ),
                      ),
                    ),
                  if (operationNeedsBefore && operationNeedsAfter)
                    const SizedBox(width: 8),
                  if (operationNeedsAfter)
                    Expanded(
                      child: TextField(
                        controller: draft.after,
                        enabled: !_applying,
                        keyboardType: draft.op == 'move'
                            ? TextInputType.number
                            : TextInputType.text,
                        decoration: InputDecoration(
                          labelText: draft.op == 'move'
                              ? '${l10n.promptPatch_after}（索引）'
                              : l10n.promptPatch_after,
                          isDense: true,
                        ),
                      ),
                    ),
                ],
              ),
            ],
            if (showCategory) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: draft.category,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Category（可选）',
                  isDense: true,
                ),
                items: [
                  const DropdownMenuItem(value: '', child: Text('Other')),
                  for (final category in _categoryValues)
                    DropdownMenuItem(value: category, child: Text(category)),
                ],
                onChanged: _applying
                    ? null
                    : (value) => setState(() => draft.category = value ?? ''),
              ),
            ],
            const SizedBox(height: 8),
            TextField(
              controller: draft.reason,
              enabled: !_applying,
              decoration: InputDecoration(
                labelText: l10n.promptPatch_reason,
                isDense: true,
              ),
            ),
            CheckboxListTile(
              value: draft.explicit,
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.promptPatch_explicit),
              onChanged: _applying
                  ? null
                  : (value) => setState(() => draft.explicit = value ?? false),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIssues(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 2),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.l10n.promptPatch_validation,
            style: TextStyle(
              color: theme.colorScheme.onErrorContainer,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          for (final issue in _issues)
            Text(
              '• ${issue.message}',
              style: TextStyle(color: theme.colorScheme.onErrorContainer),
            ),
        ],
      ),
    );
  }

  void _addDraft() {
    setState(() {
      _drafts.add(_PatchDraft());
      _issues = const [];
    });
  }

  void _removeDraft(int index) {
    if (index < 0 || index >= _drafts.length) return;
    setState(() {
      _drafts.removeAt(index).dispose();
      _issues = const [];
    });
  }

  Future<void> _apply() async {
    final operations = <PromptPatchOperation>[];
    for (final draft in _drafts) {
      operations.add(_toOperation(draft));
    }

    final validation = PromptPatchService.validate(widget.recipe, operations);
    if (!validation.isValid) {
      setState(() => _issues = validation.issues);
      return;
    }

    setState(() {
      _applying = true;
      _issues = const [];
    });
    try {
      final result = await ref
          .read(promptRecipeApplicationServiceProvider)
          .applyPatch(widget.recipe.id, operations);
      if (!mounted) return;
      if (result == null) {
        setState(() {
          _issues = const [
            PromptPatchValidationIssue(
              operationId: 'apply',
              code: PromptPatchIssueCode.notFound,
              message: '配方已不存在，无法应用补丁',
            ),
          ];
        });
        return;
      }
      Navigator.of(context).pop(result);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _issues = [
          PromptPatchValidationIssue(
            operationId: 'apply',
            code: PromptPatchIssueCode.invalid,
            message: error.toString(),
          ),
        ];
      });
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  PromptPatchOperation _toOperation(_PatchDraft draft) {
    final beforeText = draft.before.text.trim();
    final afterText = draft.after.text.trim();
    Object? before = beforeText.isEmpty ? null : beforeText;
    Object? after = afterText.isEmpty ? null : afterText;
    if (draft.op == 'move') {
      after = int.tryParse(afterText) ?? after;
    } else if (draft.op == 'parameter') {
      after = _parseParameterValue(draft.target, afterText);
      before = null;
    }
    return PromptPatchOperation(
      id: draft.id,
      op: draft.op,
      target: draft.target,
      category: draft.category.isEmpty ? null : draft.category,
      before: before,
      after: after,
      reason: draft.reason.text.trim(),
      evidenceIds: const [],
      confidence: 1,
      explicit: draft.explicit,
    );
  }

  Object? _parseParameterValue(String target, String value) {
    final field = target.startsWith('request:')
        ? target.substring('request:'.length)
        : '';
    if (const {
      'width',
      'height',
      'steps',
      'seed',
      'ucPreset',
    }.contains(field)) {
      return int.tryParse(value) ?? value;
    }
    if (const {'scale', 'cfg', 'cfgRescale'}.contains(field)) {
      return double.tryParse(value) ?? value;
    }
    if (const {'qualityToggle', 'transparentBackground'}.contains(field)) {
      final normalized = value.toLowerCase();
      if (normalized == 'true' || normalized == '是' || normalized == '1') {
        return true;
      }
      if (normalized == 'false' || normalized == '否' || normalized == '0') {
        return false;
      }
    }
    return value;
  }

  String _operationLabel(BuildContext context, String value) {
    final l10n = context.l10n;
    return switch (value) {
      'add' => l10n.common_add,
      'remove' => l10n.common_delete,
      'replace' => l10n.common_replace,
      'move' => l10n.common_move,
      'keep' => 'Keep / 保留',
      'parameter' => 'Parameter / 参数',
      _ => value,
    };
  }

  static const _operationValues = [
    'add',
    'remove',
    'replace',
    'move',
    'keep',
    'parameter',
  ];

  static const _categoryValues = [
    'subject',
    'appearance',
    'clothing',
    'pose',
    'composition',
    'scene',
    'lighting',
    'camera',
    'style',
    'quality',
  ];

  List<_TargetChoice> get _targetChoices {
    final choices = <_TargetChoice>[
      const _TargetChoice('main', '主 Prompt'),
      const _TargetChoice('negative', '负向 Prompt'),
      const _TargetChoice('request:model', 'request:model'),
      const _TargetChoice('request:width', 'request:width'),
      const _TargetChoice('request:height', 'request:height'),
      const _TargetChoice('request:steps', 'request:steps'),
      const _TargetChoice('request:seed', 'request:seed'),
      const _TargetChoice('request:sampler', 'request:sampler'),
      const _TargetChoice('request:scale', 'request:scale'),
      const _TargetChoice('request:cfgRescale', 'request:cfgRescale'),
      const _TargetChoice('request:qualityToggle', 'request:qualityToggle'),
      const _TargetChoice('request:qualityTier', 'request:qualityTier'),
      const _TargetChoice('request:ucPreset', 'request:ucPreset'),
      const _TargetChoice(
        'request:transparentBackground',
        'request:transparentBackground',
      ),
    ];
    for (final character in widget.recipe.characters) {
      choices.add(
        _TargetChoice(
          'character:${character.id}',
          '角色：${character.name.isEmpty ? character.id : character.name}',
        ),
      );
    }
    return choices;
  }
}

class _PatchDraft {
  _PatchDraft()
    : id = const Uuid().v4(),
      before = TextEditingController(),
      after = TextEditingController(),
      reason = TextEditingController(text: '用户手动修改');

  final String id;
  String op = 'add';
  String target = 'main';
  String category = '';
  bool explicit = false;
  final TextEditingController before;
  final TextEditingController after;
  final TextEditingController reason;

  void dispose() {
    before.dispose();
    after.dispose();
    reason.dispose();
  }
}

class _TargetChoice {
  const _TargetChoice(this.value, this.label);

  final String value;
  final String label;
}
