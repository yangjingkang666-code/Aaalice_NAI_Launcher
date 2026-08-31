import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/autocomplete/autocomplete_providers.dart';
import '../../../../core/utils/localization_extension.dart';
import '../../../../data/models/recipe/prompt_recipe.dart';
import '../../../../data/services/prompt_semantic_entry_builder.dart';
import '../../../providers/prompt_semantic_provider.dart';
import '../../../prompt_assistant/services/prompt_assistant_service.dart';

/// Reviewable semantic classification for unknown prompt phrases.
class PromptSemanticWorkbenchDialog extends ConsumerStatefulWidget {
  const PromptSemanticWorkbenchDialog({required this.prompt, super.key});

  final String prompt;

  static Future<void> show(BuildContext context, {required String prompt}) {
    return showDialog<void>(
      context: context,
      builder: (_) => PromptSemanticWorkbenchDialog(prompt: prompt),
    );
  }

  @override
  ConsumerState<PromptSemanticWorkbenchDialog> createState() =>
      _PromptSemanticWorkbenchDialogState();
}

class _PromptSemanticWorkbenchDialogState
    extends ConsumerState<PromptSemanticWorkbenchDialog> {
  static const _categories = [
    'subject',
    'appearance',
    'expression',
    'clothing',
    'action',
    'pose',
    'adult',
    'object',
    'scene',
    'lighting',
    'camera',
    'composition',
    'style',
    'quality',
    'other',
  ];

  static const _categoryLabels = <String, String>{
    'subject': '主体',
    'appearance': '外貌',
    'expression': '表情',
    'clothing': '服装',
    'action': '动作',
    'pose': '姿势',
    'adult': '成人',
    'object': '物品',
    'scene': '场景',
    'lighting': '光线',
    'camera': '镜头',
    'composition': '构图',
    'style': '风格',
    'quality': '质量',
    'other': '其他 / 自然语言',
  };

  late List<PromptSemanticEntry> _entries;
  Map<String, String> _translations = const {};
  List<String> _warnings = const [];
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    final draft = ref.read(promptSemanticDraftProvider);
    _entries = draft.matchesPrompt(widget.prompt)
        ? List.of(draft.entries)
        : PromptSemanticEntryBuilder.buildSync(widget.prompt).entries;
    unawaited(_hydrateLocalCategories());
  }

  Future<void> _hydrateLocalCategories() async {
    final result = await PromptSemanticEntryBuilder.build(
      widget.prompt,
      existingEntries: _entries,
      resolveExactTags: ref.read(tagCatalogRepositoryProvider).resolveExactTags,
    );
    if (!mounted) return;
    setState(() => _entries = List.of(result.entries));
  }

  Future<void> _organize() async {
    final unknown = _entries.where(
      (entry) => entry.source != 'tag-db' && entry.source != 'manual',
    );
    if (!unknown.any(
      (entry) => entry.category == 'other' || entry.source == 'imported',
    )) {
      setState(() {
        _error = context.l10n.prompt_semanticNoUnknown;
        _warnings = const [];
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _warnings = const [];
    });
    try {
      final result = await ref
          .read(promptAssistantServiceProvider)
          .organizePrompt(
            widget.prompt,
            sessionId: 'prompt_semantic_workbench',
            entries: _entries,
          );
      if (!mounted) return;
      setState(() {
        _entries = List.of(result.entries);
        _translations = result.translations;
        _warnings = result.warnings;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _changeCategory(int index, String value) {
    final current = _entries[index];
    final next = current.copyWith(
      category: value,
      source: 'manual',
      confidence: 1,
    );
    setState(() => _entries[index] = next);
  }

  void _apply() {
    ref
        .read(promptSemanticDraftProvider.notifier)
        .apply(
          prompt: widget.prompt,
          entries: _entries,
          translations: _translations,
        );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxHeight = min(620.0, MediaQuery.sizeOf(context).height * 0.72);
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.auto_awesome_rounded),
          const SizedBox(width: 10),
          Expanded(child: Text(context.l10n.prompt_semanticOrganize)),
        ],
      ),
      content: SizedBox(
        width: min(760.0, MediaQuery.sizeOf(context).width - 48),
        height: maxHeight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              context.l10n.prompt_semanticOrganizeSubtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: _entries.isEmpty
                  ? Center(child: Text(context.l10n.prompt_semanticNoPrompt))
                  : ListView.separated(
                      itemCount: _entries.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) => _buildEntry(index),
                    ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                '${context.l10n.prompt_semanticAiFailed}: $_error',
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
            for (final warning in _warnings) ...[
              const SizedBox(height: 4),
              Text(
                warning,
                style: TextStyle(color: theme.colorScheme.tertiary),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.of(context).pop(),
          child: Text(context.l10n.common_cancel),
        ),
        TextButton.icon(
          onPressed: _loading ? null : _organize,
          icon: _loading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.auto_awesome, size: 18),
          label: Text(context.l10n.prompt_semanticOrganize),
        ),
        FilledButton(
          onPressed: _loading || _entries.isEmpty ? null : _apply,
          child: Text(context.l10n.common_apply),
        ),
      ],
    );
  }

  Widget _buildEntry(int index) {
    final entry = _entries[index];
    final translation = _translations[entry.text];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.text, softWrap: true),
                const SizedBox(height: 2),
                Text(
                  [
                    entry.source,
                    '${(entry.confidence * 100).round()}%',
                    if (translation != null) translation,
                  ].join(' · '),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          DropdownButton<String>(
            value: _categories.contains(entry.category)
                ? entry.category
                : 'other',
            onChanged: (value) {
              if (value != null) _changeCategory(index, value);
            },
            items: [
              for (final category in _categories)
                DropdownMenuItem(
                  value: category,
                  child: Text(_categoryLabels[category] ?? category),
                ),
            ],
          ),
          const SizedBox(width: 4),
          Icon(
            entry.source == 'tag-db'
                ? Icons.verified_outlined
                : entry.source == 'manual'
                ? Icons.edit_outlined
                : Icons.auto_awesome_outlined,
            size: 18,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}
