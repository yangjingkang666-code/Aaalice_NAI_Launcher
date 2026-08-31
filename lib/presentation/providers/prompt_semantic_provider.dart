import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/nai_prompt_parser.dart';
import '../../data/models/recipe/prompt_recipe.dart';
import '../../data/services/prompt_semantic_entry_builder.dart';

/// The semantic draft belongs to the editor session, not to the API request.
/// Keeping it in a provider lets dialogs, history actions and recipe capture
/// share the same manual/AI classifications without mutating the prompt text.
class PromptSemanticDraftState {
  const PromptSemanticDraftState({
    this.prompt = '',
    this.entries = const [],
    this.translations = const {},
    this.retrievalEvidence = const [],
  });

  final String prompt;
  final List<PromptSemanticEntry> entries;
  final Map<String, String> translations;
  final List<RetrievalEvidence> retrievalEvidence;

  StructuredPrompt get structured => PromptSemanticEntryBuilder.buildSync(
    prompt,
    existingEntries: entries,
  ).structured;

  bool matchesPrompt(String value) =>
      NaiPromptParser.normalizeSegment(prompt) ==
      NaiPromptParser.normalizeSegment(value);

  PromptSemanticDraftState copyWith({
    String? prompt,
    List<PromptSemanticEntry>? entries,
    Map<String, String>? translations,
    List<RetrievalEvidence>? retrievalEvidence,
  }) {
    return PromptSemanticDraftState(
      prompt: prompt ?? this.prompt,
      entries: entries ?? this.entries,
      translations: translations ?? this.translations,
      retrievalEvidence: retrievalEvidence ?? this.retrievalEvidence,
    );
  }
}

final promptSemanticDraftProvider =
    StateNotifierProvider<
      PromptSemanticDraftNotifier,
      PromptSemanticDraftState
    >((ref) => PromptSemanticDraftNotifier());

class PromptSemanticDraftNotifier
    extends StateNotifier<PromptSemanticDraftState> {
  PromptSemanticDraftNotifier() : super(const PromptSemanticDraftState());

  void apply({
    required String prompt,
    required List<PromptSemanticEntry> entries,
    Map<String, String> translations = const {},
    List<RetrievalEvidence> retrievalEvidence = const [],
  }) {
    state = PromptSemanticDraftState(
      prompt: prompt,
      entries: List.unmodifiable(entries),
      translations: Map.unmodifiable(translations),
      retrievalEvidence: List.unmodifiable(retrievalEvidence),
    );
  }

  void clear() {
    state = const PromptSemanticDraftState();
  }
}
