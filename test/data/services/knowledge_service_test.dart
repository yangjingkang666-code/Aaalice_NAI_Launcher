import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/autocomplete/completion_models.dart';
import 'package:nai_launcher/core/autocomplete/tag_catalog_repository.dart';
import 'package:nai_launcher/core/autocomplete/zh_dictionary_service.dart';
import 'package:nai_launcher/data/models/knowledge/knowledge_models.dart';
import 'package:nai_launcher/data/models/recipe/prompt_recipe.dart';
import 'package:nai_launcher/data/services/knowledge/knowledge_service.dart';

void main() {
  test('normalizes remote rows and creates matching evidence', () async {
    final provider = DanbooruSearchKnowledgeProvider(
      baseUrl: 'https://primary.example',
      request: (endpoint, method, path, data, timeout) async =>
          Response<dynamic>(
            requestOptions: RequestOptions(path: path),
            statusCode: 200,
            data: {
              'results': [
                {
                  'name': 'blue_eyes',
                  'cn_name': '蓝眼睛',
                  'category': 'Appearance',
                  'final_score': 0.92,
                  'post_count': 1200,
                  'wiki': 'eye color',
                },
              ],
            },
          ),
    );

    final result = await provider.retrieve(
      const KnowledgeQuery(text: '蓝眼睛', limit: 20),
    );
    expect(result.provider, contains('primary.example'));
    expect(result.candidates.single.tag, 'blue_eyes');
    expect(result.candidates.single.category, 'appearance');
    expect(result.candidates.single.zh, '蓝眼睛');
    expect(result.candidates.single.postCount, 1200);
    expect(result.evidence.single.source, 'danbooru-search');
    expect(result.evidence.single.description, 'eye color');
  });

  test('uses the configured backup endpoint after a primary failure', () async {
    final calls = <String>[];
    final provider = DanbooruSearchKnowledgeProvider(
      baseUrl: 'https://primary.example',
      fallbackUrls: const ['https://backup.example'],
      request: (endpoint, method, path, data, timeout) async {
        calls.add('$endpoint$path');
        if (endpoint.contains('primary')) {
          throw TimeoutException('cold start');
        }
        return Response<dynamic>(
          requestOptions: RequestOptions(path: path),
          statusCode: 200,
          data: [
            {'tag': '1girl', 'category': 'General', 'score': 0.8},
          ],
        );
      },
    );

    final result = await provider.retrieve(const KnowledgeQuery(text: 'girl'));
    expect(result.candidates.single.tag, '1girl');
    expect(result.warning, contains('primary.example'));
    expect(calls, contains('https://backup.example/api/search'));
  });

  test(
    'local provider resolves Chinese dictionary candidates offline',
    () async {
      final provider = LocalTagKnowledgeProvider(
        catalog: TagCatalogRepository(),
        dictionary: _FakeDictionary(),
      );

      final result = await provider.retrieve(
        const KnowledgeQuery(text: '蓝眼睛', includeRelated: false),
      );
      expect(result.provider, 'local-tag-db');
      expect(result.candidates.single.tag, 'blue_eyes');
      expect(result.candidates.single.zh, '蓝眼睛');
      expect(result.evidence.single.source, 'local-tag-db');
    },
  );

  test(
    'fallback provider marks degraded results and preserves evidence',
    () async {
      const provider = FallbackKnowledgeProvider(
        _ThrowingProvider(),
        _FixedProvider(),
      );
      final result = await provider.retrieve(
        const KnowledgeQuery(text: 'girl'),
      );
      expect(result.degraded, isTrue);
      expect(result.candidates.single.tag, '1girl');
      expect(result.warning, contains('降级'));
    },
  );

  test(
    'fallback provider retries when the primary index has no matches',
    () async {
      const provider = FallbackKnowledgeProvider(
        _EmptyProvider(),
        _FixedProvider(),
        fallbackLabel: '远程服务',
      );
      final result = await provider.retrieve(const KnowledgeQuery(text: 'new'));
      expect(result.degraded, isTrue);
      expect(result.candidates.single.tag, '1girl');
      expect(result.warning, contains('远程服务'));
    },
  );

  test('merged provider keeps the strongest tag and all evidence', () async {
    const provider = MergedKnowledgeProvider([
      _FixedProvider(),
      _DuplicateProvider(),
    ]);
    final result = await provider.retrieve(const KnowledgeQuery(text: 'girl'));
    expect(result.candidates.single.tag, '1girl');
    expect(result.candidates.single.score, 0.9);
    expect(result.evidence, hasLength(2));
  });
}

class _FakeDictionary extends ZhDictionaryService {
  @override
  Future<List<CompletionCandidate>> search(CompletionQuery query) async => [
    const CompletionCandidate(
      canonicalTag: 'blue_eyes',
      category: TagCategory.general,
      postCount: 800,
      matchKind: CompletionMatchKind.chineseExact,
      sources: {CompletionSourceKind.zhDictionary},
      translation: '蓝眼睛',
    ),
  ];
}

class _ThrowingProvider implements KnowledgeProvider {
  const _ThrowingProvider();

  @override
  Future<KnowledgeHealth> health() async => const KnowledgeHealth(
    available: false,
    provider: 'throwing',
    message: 'offline',
  );

  @override
  Future<KnowledgeResult> retrieve(KnowledgeQuery query) {
    return Future<KnowledgeResult>.error(StateError('offline'));
  }
}

class _EmptyProvider implements KnowledgeProvider {
  const _EmptyProvider();

  @override
  Future<KnowledgeHealth> health() async => const KnowledgeHealth(
    available: true,
    provider: 'empty',
    message: 'empty',
  );

  @override
  Future<KnowledgeResult> retrieve(KnowledgeQuery query) async =>
      const KnowledgeResult(
        candidates: [],
        evidence: [],
        provider: 'empty',
        degraded: false,
      );
}

class _DuplicateProvider implements KnowledgeProvider {
  const _DuplicateProvider();

  @override
  Future<KnowledgeHealth> health() async => const KnowledgeHealth(
    available: true,
    provider: 'duplicate',
    message: 'duplicate',
  );

  @override
  Future<KnowledgeResult> retrieve(KnowledgeQuery query) async =>
      const KnowledgeResult(
        candidates: [
          KnowledgeCandidate(tag: '1girl', category: 'subject', score: 0.9),
        ],
        evidence: [
          RetrievalEvidence(
            id: 'duplicate-evidence',
            source: 'duplicate',
            query: 'girl',
            tag: '1girl',
            category: 'subject',
            score: 0.9,
          ),
        ],
        provider: 'duplicate',
        degraded: false,
      );
}

class _FixedProvider implements KnowledgeProvider {
  const _FixedProvider();

  @override
  Future<KnowledgeHealth> health() async => const KnowledgeHealth(
    available: true,
    provider: 'local-tag-db',
    message: 'ok',
  );

  @override
  Future<KnowledgeResult> retrieve(KnowledgeQuery query) async =>
      const KnowledgeResult(
        candidates: [KnowledgeCandidate(tag: '1girl', category: 'general')],
        evidence: [
          RetrievalEvidence(
            id: 'fixed-evidence',
            source: 'fixed',
            query: 'girl',
            tag: '1girl',
            category: 'general',
          ),
        ],
        provider: 'local-tag-db',
        degraded: false,
      );
}
