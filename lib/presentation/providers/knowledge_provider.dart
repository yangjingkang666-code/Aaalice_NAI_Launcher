import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/autocomplete/autocomplete_providers.dart';
import '../../core/database/services/service_providers.dart';
import '../../data/models/knowledge/knowledge_models.dart';
import '../../data/services/knowledge/knowledge_service.dart';
import '../../data/services/knowledge/project_knowledge_store.dart';

final projectKnowledgeStoreProvider = Provider<ProjectKnowledgeStore>((ref) {
  return ProjectKnowledgeStore();
});

final projectKnowledgeProvider = Provider<ProjectKnowledgeProvider>((ref) {
  return ProjectKnowledgeProvider(
    store: ref.watch(projectKnowledgeStoreProvider),
  );
});

final localTagKnowledgeProvider = Provider<LocalTagKnowledgeProvider>((ref) {
  return LocalTagKnowledgeProvider(
    catalog: ref.watch(tagCatalogRepositoryProvider),
    dictionary: ref.watch(zhDictionaryServiceProvider),
    cooccurrenceLoader: () async {
      try {
        return await ref.read(cooccurrenceServiceProvider.future);
      } catch (_) {
        return null;
      }
    },
  );
});

final remoteKnowledgeProvider = Provider<DanbooruSearchKnowledgeProvider>((
  ref,
) {
  return DanbooruSearchKnowledgeProvider();
});

final knowledgeManagerProvider = Provider<KnowledgeManager>((ref) {
  final manager = KnowledgeManager(
    FallbackKnowledgeProvider(
      MergedKnowledgeProvider([
        ref.watch(projectKnowledgeProvider),
        ref.watch(localTagKnowledgeProvider),
      ]),
      ref.watch(remoteKnowledgeProvider),
      fallbackLabel: '远程语义服务',
    ),
  );
  return manager;
});

final knowledgeSearchProvider = FutureProvider.autoDispose
    .family<KnowledgeResult, KnowledgeQuery>((ref, query) {
      return ref.watch(knowledgeManagerProvider).provider.retrieve(query);
    });
