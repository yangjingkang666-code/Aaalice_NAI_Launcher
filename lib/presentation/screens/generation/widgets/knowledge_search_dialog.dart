import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/utils/localization_extension.dart';
import '../../../../data/models/knowledge/knowledge_models.dart';
import '../../../../data/models/recipe/prompt_recipe.dart';
import '../../../../data/services/prompt_semantic_entry_builder.dart';
import '../../../providers/knowledge_provider.dart';
import '../../../providers/prompt_semantic_provider.dart';
import '../../../widgets/common/app_toast.dart';

/// Explicit semantic retrieval UI. Results are never silently written into a
/// prompt; users choose which individual candidate to copy or add to the
/// current semantic draft.
class KnowledgeSearchDialog extends ConsumerStatefulWidget {
  const KnowledgeSearchDialog({
    required this.prompt,
    this.initialEntries,
    this.initialTranslations,
    this.initialRetrievalEvidence,
    super.key,
  });

  final String prompt;
  final List<PromptSemanticEntry>? initialEntries;
  final Map<String, String>? initialTranslations;
  final List<RetrievalEvidence>? initialRetrievalEvidence;

  static Future<void> show(
    BuildContext context, {
    required String prompt,
    List<PromptSemanticEntry>? initialEntries,
    Map<String, String>? initialTranslations,
    List<RetrievalEvidence>? initialRetrievalEvidence,
  }) => showDialog<void>(
    context: context,
    builder: (_) => KnowledgeSearchDialog(
      prompt: prompt,
      initialEntries: initialEntries,
      initialTranslations: initialTranslations,
      initialRetrievalEvidence: initialRetrievalEvidence,
    ),
  );

  @override
  ConsumerState<KnowledgeSearchDialog> createState() =>
      _KnowledgeSearchDialogState();
}

class _KnowledgeSearchDialogState extends ConsumerState<KnowledgeSearchDialog> {
  late final TextEditingController _controller;
  KnowledgeResult? _result;
  String? _error;
  bool _loading = false;
  int _searchGeneration = 0;
  final Set<String> _addingTags = <String>{};
  late List<PromptSemanticEntry> _workingEntries;
  late Map<String, String> _workingTranslations;
  late List<RetrievalEvidence> _workingEvidence;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.prompt);
    final draft = ref.read(promptSemanticDraftProvider);
    final draftMatches = draft.matchesPrompt(widget.prompt);
    _workingEntries = List.of(
      widget.initialEntries ??
          (draftMatches
              ? draft.entries
              : PromptSemanticEntryBuilder.buildSync(widget.prompt).entries),
    );
    _workingTranslations = Map.of(
      widget.initialTranslations ??
          (draftMatches ? draft.translations : const <String, String>{}),
    );
    _workingEvidence = List.of(
      widget.initialRetrievalEvidence ??
          (draftMatches
              ? draft.retrievalEvidence
              : const <RetrievalEvidence>[]),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    if (_loading) return;
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final generation = ++_searchGeneration;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await ref.read(knowledgeManagerProvider).search(text);
      if (!mounted || generation != _searchGeneration) return;
      setState(() => _result = result);
    } catch (error) {
      if (mounted && generation == _searchGeneration) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted && generation == _searchGeneration) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _addToDraft(KnowledgeCandidate candidate) async {
    final key = candidate.tag.trim().toLowerCase();
    if (!_addingTags.add(key)) return;
    if (_workingEntries.any((entry) => entry.text.toLowerCase() == key)) {
      _addingTags.remove(key);
      return;
    }
    try {
      // Accepted candidates become portable project vocabulary. With no
      // active project the store is a no-op, so the normal draft workflow is
      // unchanged.
      await ref.read(projectKnowledgeStoreProvider).upsert(candidate);
      if (!mounted) return;
      _workingEntries.add(
        PromptSemanticEntry(
          id: const Uuid().v4(),
          text: candidate.tag,
          category: _semanticCategory(candidate.category),
          source: 'knowledge',
          localTagHit: true,
          confidence: candidate.score.clamp(0.0, 1.0).toDouble(),
          kind: 'tag',
        ),
      );
      final evidenceById = <String, RetrievalEvidence>{
        for (final evidence in _workingEvidence) evidence.id: evidence,
      };
      for (final evidence in _result?.evidence ?? const <RetrievalEvidence>[]) {
        evidenceById[evidence.id] = evidence;
      }
      _workingEvidence = evidenceById.values.toList(growable: false);
      ref
          .read(promptSemanticDraftProvider.notifier)
          .apply(
            prompt: widget.prompt,
            entries: _workingEntries,
            translations: _workingTranslations,
            retrievalEvidence: _workingEvidence,
          );
      setState(() {});
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      _addingTags.remove(key);
    }
  }

  Future<void> _copy(String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (mounted) {
      AppToast.success(context, context.l10n.image_copiedToClipboard);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = _result;
    final viewport = MediaQuery.sizeOf(context);
    final dialogWidth = viewport.width < 760 ? viewport.width - 32 : 720.0;
    final dialogHeight = (viewport.height - 160).clamp(320.0, 560.0).toDouble();
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.travel_explore_rounded),
          const SizedBox(width: 10),
          Expanded(child: Text(context.l10n.prompt_semanticOrganize)),
        ],
      ),
      content: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _controller,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: context.l10n.prompt_searchHint,
                labelText: context.l10n.common_search,
              ),
              onSubmitted: (_) => _search(),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: _loading ? null : _search,
                icon: _loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.search),
                label: Text(context.l10n.common_search),
              ),
            ),
            if (result != null) ...[
              const SizedBox(height: 8),
              Text(
                '${result.provider}${result.degraded ? ' · fallback' : ''}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (result.warning != null)
                Text(
                  result.warning!,
                  style: TextStyle(color: theme.colorScheme.tertiary),
                ),
            ],
            if (_error != null)
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            const SizedBox(height: 8),
            Expanded(
              child: result == null
                  ? Center(child: Text(context.l10n.prompt_semanticNoPrompt))
                  : result.candidates.isEmpty
                  ? Center(child: Text(context.l10n.search_noResults))
                  : ListView.separated(
                      itemCount: result.candidates.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) =>
                          _buildCandidate(result.candidates[index]),
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.common_close),
        ),
      ],
    );
  }

  Widget _buildCandidate(KnowledgeCandidate candidate) {
    final evidence = _result?.evidence
        .where((item) => item.tag == candidate.tag)
        .firstOrNull;
    return ListTile(
      dense: true,
      title: Text(candidate.tag),
      subtitle: Text(
        [
          if (candidate.zh != null && candidate.zh!.isNotEmpty) candidate.zh!,
          candidate.category,
          if (candidate.postCount > 0) 'posts: ${candidate.postCount}',
          if (evidence?.source != null) evidence!.source,
        ].join(' · '),
      ),
      trailing: Wrap(
        spacing: 2,
        children: [
          IconButton(
            tooltip: context.l10n.common_copy,
            onPressed: () => _copy(candidate.tag),
            icon: const Icon(Icons.copy_outlined),
          ),
          IconButton(
            tooltip: context.l10n.common_add,
            onPressed: () => _addToDraft(candidate),
            icon: const Icon(Icons.add_circle_outline),
          ),
        ],
      ),
    );
  }

  String _semanticCategory(String value) {
    const supported = {
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
    };
    return supported.contains(value) ? value : 'other';
  }
}
