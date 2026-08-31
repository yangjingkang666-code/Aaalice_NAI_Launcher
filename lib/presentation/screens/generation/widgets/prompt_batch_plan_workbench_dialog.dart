import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/localization_extension.dart';
import '../../../../data/models/recipe/modification_seed_strategy.dart';
import '../../../../data/models/recipe/prompt_recipe.dart';
import '../../../../data/services/ai_batch_plan_service.dart';
import '../../../../data/services/prompt_patch_service.dart';
import '../../../prompt_assistant/services/prompt_assistant_service.dart';
import '../../../providers/replication_queue_provider.dart';

/// Review surface for Sprint 8.4 AI batch proposals.
///
/// The dialog only requests a text plan and adds explicitly selected items to
/// the existing serial queue. It never starts generation and never persists a
/// child recipe implicitly.
class PromptBatchPlanWorkbenchDialog extends ConsumerStatefulWidget {
  const PromptBatchPlanWorkbenchDialog({required this.recipe, super.key});

  final PromptRecipe recipe;

  static Future<int?> show(BuildContext context, PromptRecipe recipe) {
    return showDialog<int>(
      context: context,
      builder: (_) => PromptBatchPlanWorkbenchDialog(recipe: recipe),
    );
  }

  @override
  ConsumerState<PromptBatchPlanWorkbenchDialog> createState() =>
      _PromptBatchPlanWorkbenchDialogState();
}

class _PromptBatchPlanWorkbenchDialogState
    extends ConsumerState<PromptBatchPlanWorkbenchDialog> {
  final _instruction = TextEditingController(text: '生成一组不同姿势，保持角色身份、画风和画幅不变');
  final _specifiedSeed = TextEditingController();
  List<AiBatchPlanItem> _items = const [];
  List<String> _warnings = const [];
  ModificationSeedStrategy _seedStrategy = ModificationSeedStrategy.base;
  int _requestedCount = 4;
  bool _proposing = false;
  bool _adding = false;

  @override
  void dispose() {
    _instruction.dispose();
    _specifiedSeed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final size = MediaQuery.of(context).size;
    return Dialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: (size.width * .94).clamp(460.0, 980.0),
          maxHeight: (size.height * .9).clamp(480.0, 840.0),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.auto_awesome_motion_rounded),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.promptBatch_title,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: l10n.common_close,
                    onPressed: _adding ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              Text(
                l10n.promptBatch_reviewHint,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _instruction,
                      enabled: !_proposing && !_adding,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: l10n.promptBatch_instruction,
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 120,
                    child: DropdownButtonFormField<int>(
                      initialValue: _requestedCount,
                      decoration: InputDecoration(
                        labelText: l10n.promptBatch_count,
                        isDense: true,
                      ),
                      items: [
                        for (var count = 1; count <= 16; count++)
                          DropdownMenuItem(value: count, child: Text('$count')),
                      ],
                      onChanged: _proposing || _adding
                          ? null
                          : (value) => setState(() {
                              _requestedCount = value ?? _requestedCount;
                            }),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _buildSeedSelector(context),
              const SizedBox(height: 10),
              Expanded(
                child: _items.isEmpty
                    ? Center(
                        child: Text(
                          l10n.promptBatch_empty,
                          textAlign: TextAlign.center,
                        ),
                      )
                    : ListView.builder(
                        itemCount: _items.length,
                        itemBuilder: (context, index) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _buildItemCard(context, index),
                        ),
                      ),
              ),
              if (_warnings.isNotEmpty) ...[
                const SizedBox(height: 6),
                _buildWarnings(context),
              ],
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _proposing || _adding ? null : _propose,
                    icon: _proposing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.auto_awesome),
                    label: Text(l10n.promptBatch_propose),
                  ),
                  TextButton(
                    onPressed: _adding ? null : () => Navigator.pop(context),
                    child: Text(l10n.common_cancel),
                  ),
                  FilledButton.icon(
                    onPressed:
                        _items.any((item) => item.enabled) &&
                            !_proposing &&
                            !_adding
                        ? _addSelected
                        : null,
                    icon: _adding
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.playlist_add_rounded),
                    label: Text(l10n.promptBatch_addSelected),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSeedSelector(BuildContext context) {
    final l10n = context.l10n;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<ModificationSeedStrategy>(
              initialValue: _seedStrategy,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: l10n.promptPatch_seedStrategy,
                isDense: true,
              ),
              items: [
                DropdownMenuItem(
                  value: ModificationSeedStrategy.base,
                  child: Text(l10n.promptPatch_seedBase),
                ),
                DropdownMenuItem(
                  value: ModificationSeedStrategy.random,
                  child: Text(l10n.promptPatch_seedRandom),
                ),
                DropdownMenuItem(
                  value: ModificationSeedStrategy.specified,
                  child: Text(l10n.promptPatch_seedSpecified),
                ),
              ],
              onChanged: _proposing || _adding
                  ? null
                  : (value) {
                      if (value == null) return;
                      setState(() => _seedStrategy = value);
                    },
            ),
            if (_seedStrategy == ModificationSeedStrategy.specified) ...[
              const SizedBox(height: 6),
              TextField(
                controller: _specifiedSeed,
                enabled: !_proposing && !_adding,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: l10n.promptPatch_seedValue,
                  isDense: true,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildItemCard(BuildContext context, int index) {
    final item = _items[index];
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
        child: Column(
          children: [
            Row(
              children: [
                Checkbox(
                  value: item.enabled,
                  onChanged: item.operations.isEmpty || _adding
                      ? null
                      : (value) => _replaceItem(
                          index,
                          item.copyWith(enabled: value ?? false),
                        ),
                ),
                CircleAvatar(
                  radius: 14,
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item.summary,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                IconButton(
                  tooltip: '编辑',
                  onPressed: _adding ? null : () => _editItem(index),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                ),
                IconButton(
                  tooltip: '上移',
                  onPressed: index == 0 || _adding
                      ? null
                      : () => _moveItem(index, -1),
                  icon: const Icon(Icons.keyboard_arrow_up),
                ),
                IconButton(
                  tooltip: '下移',
                  onPressed: index == _items.length - 1 || _adding
                      ? null
                      : () => _moveItem(index, 1),
                  icon: const Icon(Icons.keyboard_arrow_down),
                ),
                IconButton(
                  tooltip: context.l10n.common_delete,
                  onPressed: _adding ? null : () => _removeItem(index),
                  icon: const Icon(Icons.delete_outline, size: 18),
                ),
              ],
            ),
            for (final operation in item.operations)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Padding(
                  padding: const EdgeInsets.only(left: 48, right: 8, bottom: 2),
                  child: Text(
                    '${operation.op} · ${operation.category} · ${_operationValue(operation)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            if (item.conflictWarnings.isNotEmpty)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(left: 42, top: 4),
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer.withValues(
                    alpha: .55,
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  item.conflictWarnings.join('；'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildWarnings(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        _warnings.join('；'),
        style: TextStyle(color: theme.colorScheme.onTertiaryContainer),
      ),
    );
  }

  Future<void> _propose() async {
    final instruction = _instruction.text.trim();
    if (instruction.isEmpty) {
      setState(() => _warnings = [context.l10n.promptBatch_needInstruction]);
      return;
    }
    setState(() {
      _proposing = true;
      _warnings = const [];
    });
    try {
      final proposal = await ref
          .read(promptAssistantServiceProvider)
          .proposeBatchPlan(
            widget.recipe,
            sessionId: 'batch-plan-${DateTime.now().microsecondsSinceEpoch}',
            instruction: instruction,
            requestedCount: _requestedCount,
          );
      if (!mounted) return;
      setState(() {
        _items = proposal.plan.items;
        _warnings = proposal.plan.warnings;
      });
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _warnings = [context.l10n.promptBatch_failed(error.toString())],
      );
    } finally {
      if (mounted) setState(() => _proposing = false);
    }
  }

  Future<void> _addSelected() async {
    int? specifiedSeed;
    if (_seedStrategy == ModificationSeedStrategy.specified) {
      specifiedSeed = int.tryParse(_specifiedSeed.text.trim());
      if (specifiedSeed == null ||
          specifiedSeed < 0 ||
          specifiedSeed > ModificationSeedStrategyResolver.maxSeed) {
        setState(() => _warnings = [context.l10n.promptBatch_invalidSeed]);
        return;
      }
    }
    final selected = _items.where((item) => item.enabled).toList();
    final remaining = ref
        .read(replicationQueueNotifierProvider)
        .remainingCapacity;
    if (selected.length > remaining) {
      setState(
        () => _warnings = [context.l10n.promptBatch_queueCapacity(remaining)],
      );
      return;
    }
    setState(() {
      _adding = true;
      _warnings = const [];
    });
    try {
      final tasks = [
        for (final item in selected)
          AiBatchPlanService.materializeTask(
            widget.recipe,
            item,
            seedStrategy: _seedStrategy,
            specifiedSeed: specifiedSeed,
          ),
      ];
      final count = await ref
          .read(replicationQueueNotifierProvider.notifier)
          .addAll(tasks);
      if (!mounted) return;
      if (count != tasks.length) {
        setState(() => _warnings = [context.l10n.promptBatch_partialAdd]);
        return;
      }
      Navigator.of(context).pop(count);
    } catch (error) {
      if (!mounted) return;
      setState(() => _warnings = [error.toString()]);
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _editItem(int index) async {
    final item = _items[index];
    final summary = TextEditingController(text: item.summary);
    final afterControllers = [
      for (final operation in item.operations)
        TextEditingController(text: _operationValue(operation)),
    ];
    final edited = await showDialog<AiBatchPlanItem>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(context.l10n.promptBatch_editItem),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: summary,
                  decoration: InputDecoration(
                    labelText: context.l10n.promptBatch_summary,
                  ),
                ),
                for (
                  var operationIndex = 0;
                  operationIndex < item.operations.length;
                  operationIndex++
                ) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: afterControllers[operationIndex],
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText:
                          '${item.operations[operationIndex].category} · after',
                    ),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.l10n.common_cancel),
            ),
            FilledButton(
              onPressed: () {
                final operations = [
                  for (
                    var operationIndex = 0;
                    operationIndex < item.operations.length;
                    operationIndex++
                  )
                    _copyOperation(
                      item.operations[operationIndex],
                      after: afterControllers[operationIndex].text.trim(),
                    ),
                ];
                Navigator.pop(
                  context,
                  item.copyWith(
                    summary: summary.text.trim().isEmpty
                        ? item.summary
                        : summary.text.trim(),
                    operations: operations,
                  ),
                );
              },
              child: Text(context.l10n.common_save),
            ),
          ],
        ),
      ),
    );
    summary.dispose();
    for (final controller in afterControllers) {
      controller.dispose();
    }
    if (!mounted || edited == null) return;
    final validation = PromptPatchService.validate(
      widget.recipe,
      edited.operations,
      policy: AiBatchPlanService.batchLockPolicy,
    );
    final validIds = validation.valid.map((operation) => operation.id).toSet();
    final validOperations = edited.operations
        .where((operation) => validIds.contains(operation.id))
        .toList(growable: false);
    _replaceItem(
      index,
      edited.copyWith(
        operations: validOperations,
        enabled: edited.enabled && validOperations.isNotEmpty,
        conflictWarnings: [
          ...edited.conflictWarnings,
          ...validation.issues.map((issue) => issue.message),
        ],
      ),
    );
  }

  PromptPatchOperation _copyOperation(
    PromptPatchOperation operation, {
    required String after,
  }) {
    return PromptPatchOperation(
      id: operation.id,
      op: operation.op,
      target: operation.target,
      category: operation.category,
      before: operation.before,
      after: operation.op == 'remove' || operation.op == 'keep'
          ? operation.after
          : operation.op == 'move'
          ? int.tryParse(after) ?? after
          : after,
      reason: operation.reason,
      evidenceIds: operation.evidenceIds,
      confidence: operation.confidence,
      explicit: false,
      tokenId: operation.tokenId,
    );
  }

  String _operationValue(PromptPatchOperation operation) {
    final value = operation.after;
    if (value == null) return operation.before?.toString() ?? '';
    return value is String ? value : value.toString();
  }

  void _replaceItem(int index, AiBatchPlanItem item) {
    if (index < 0 || index >= _items.length) return;
    setState(() {
      final items = [..._items]..[index] = item;
      _items = items;
    });
  }

  void _removeItem(int index) {
    setState(() {
      final items = [..._items]..removeAt(index);
      _items = items;
    });
  }

  void _moveItem(int index, int delta) {
    final target = index + delta;
    if (target < 0 || target >= _items.length) return;
    setState(() {
      final items = [..._items];
      final item = items.removeAt(index);
      items.insert(target, item);
      _items = items;
    });
  }
}
