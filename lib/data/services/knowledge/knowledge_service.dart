import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../../../core/autocomplete/completion_models.dart';
import '../../../core/autocomplete/tag_catalog_repository.dart';
import '../../../core/autocomplete/zh_dictionary_service.dart';
import '../../../core/database/services/cooccurrence_service.dart';
import '../../../core/utils/app_logger.dart';
import '../../models/knowledge/knowledge_models.dart';
import '../../models/recipe/prompt_recipe.dart';

const defaultDanbooruSearchUrl = 'https://sakizuki-danboorusearch.hf.space';
const defaultDanbooruSearchFallbackUrl =
    'https://sakizuki-danboorusearchonline.ms.show';

typedef KnowledgeRequest =
    Future<Response<dynamic>> Function(
      String endpoint,
      String method,
      String path,
      Object? data,
      Duration timeout,
    );

/// Offline semantic provider backed by the bundled catalog and optional
/// Chinese dictionary. It is deterministic and remains useful without a
/// network connection.
class LocalTagKnowledgeProvider implements KnowledgeProvider {
  LocalTagKnowledgeProvider({
    required this.catalog,
    this.dictionary,
    this.cooccurrenceLoader,
  });

  final TagCatalogRepository catalog;
  final ZhDictionaryService? dictionary;
  final Future<CooccurrenceService?> Function()? cooccurrenceLoader;

  @override
  Future<KnowledgeHealth> health() async {
    try {
      await catalog.initialize();
      return const KnowledgeHealth(
        available: true,
        provider: 'local-tag-db',
        message: '本地 Tag 库可用',
      );
    } catch (error) {
      return KnowledgeHealth(
        available: false,
        provider: 'local-tag-db',
        message: '本地 Tag 库不可用：$error',
      );
    }
  }

  @override
  Future<KnowledgeResult> retrieve(KnowledgeQuery rawQuery) async {
    final query = rawQuery.normalized();
    if (query.text.isEmpty) {
      return const KnowledgeResult(
        candidates: [],
        evidence: [],
        provider: 'local-tag-db',
        degraded: false,
      );
    }

    final terms = _splitTerms(query.text);
    final candidates = <KnowledgeCandidate>[];
    final seen = <String>{};
    for (final term in terms) {
      final completionQuery = CompletionQuery(
        fullText: query.text,
        cursorPosition: query.text.length,
        token: term,
        replacementRange: TextReplacementRange(start: 0, end: term.length),
        existingTags: const {},
        limit: query.limit,
        locale: 'zh',
      );
      final sources = <List<CompletionCandidate>>[];
      if (completionQuery.isChinese && dictionary != null) {
        try {
          sources.add(await dictionary!.search(completionQuery));
        } catch (error) {
          AppLogger.w(
            'Chinese dictionary retrieval failed: $error',
            'Knowledge',
          );
        }
      } else {
        try {
          sources.add(await catalog.search(completionQuery));
        } catch (error) {
          AppLogger.w('Local catalog retrieval failed: $error', 'Knowledge');
        }
      }
      for (final source in sources) {
        for (var index = 0; index < source.length; index++) {
          final item = source[index];
          final key = item.canonicalTag.trim().toLowerCase();
          if (key.isEmpty || !seen.add(key)) continue;
          final score = item.score > 0
              ? item.score.clamp(0.0, 1.0).toDouble()
              : (1 - index / source.length.clamp(1, query.limit))
                    .clamp(0.0, 1.0)
                    .toDouble();
          candidates.add(
            KnowledgeCandidate(
              tag: item.canonicalTag,
              category: item.category.name,
              zh: item.translation,
              postCount: item.postCount,
              score: score,
            ),
          );
        }
      }
    }

    candidates.sort((a, b) {
      final score = b.score.compareTo(a.score);
      if (score != 0) return score;
      final popularity = b.postCount.compareTo(a.postCount);
      return popularity != 0 ? popularity : a.tag.compareTo(b.tag);
    });
    final bounded = candidates.take(query.limit).toList(growable: false);
    final evidence = <RetrievalEvidence>[
      for (var index = 0; index < bounded.length; index++)
        RetrievalEvidence(
          id: 'local:${bounded[index].tag}:$index',
          source: 'local-tag-db',
          query: query.text,
          tag: bounded[index].tag,
          zh: bounded[index].zh,
          category: bounded[index].category,
          postCount: bounded[index].postCount,
          score: bounded[index].score,
        ),
    ];

    if (query.includeRelated &&
        bounded.isNotEmpty &&
        cooccurrenceLoader != null) {
      try {
        final service = await cooccurrenceLoader!();
        if (service != null) {
          final relatedSeen = seen.toSet();
          for (final candidate in bounded.take(8)) {
            final related = await service.getRelatedTags(
              candidate.tag,
              limit: 6,
            );
            for (final item in related) {
              final key = item.tag.trim().toLowerCase();
              if (key.isEmpty || !relatedSeen.add(key)) continue;
              final record = await catalog.recordsByCanonicalTag([item.tag]);
              final catalogItem = record[item.tag.trim().toLowerCase()];
              final relatedCandidate = KnowledgeCandidate(
                tag: item.tag,
                category: catalogItem?.category.name ?? 'general',
                postCount: catalogItem?.postCount ?? 0,
                score: item.score.clamp(0.0, 1.0).toDouble(),
                related: true,
              );
              evidence.add(
                RetrievalEvidence(
                  id: 'related:${candidate.tag}:${item.tag}',
                  source: 'cooccurrence',
                  query: candidate.tag,
                  tag: relatedCandidate.tag,
                  category: relatedCandidate.category,
                  postCount: relatedCandidate.postCount,
                  score: relatedCandidate.score,
                ),
              );
            }
          }
        }
      } catch (error) {
        AppLogger.w('Cooccurrence retrieval failed: $error', 'Knowledge');
      }
    }
    return KnowledgeResult(
      candidates: bounded,
      evidence: List.unmodifiable(evidence),
      provider: 'local-tag-db',
      degraded: false,
    );
  }

  List<String> _splitTerms(String text) {
    final values = text
        .split(RegExp(r'[,，、\n]+'))
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    return values.isEmpty ? [text.trim()] : values;
  }
}

/// Remote provider compatible with the public DanbooruSearch service used by
/// the original open-source implementation. Every request has an endpoint
/// fallback and never prevents the local provider from working.
class DanbooruSearchKnowledgeProvider implements KnowledgeProvider {
  DanbooruSearchKnowledgeProvider({
    String? baseUrl,
    List<String>? fallbackUrls,
    Dio? dio,
    Duration timeout = const Duration(seconds: 90),
    Duration healthTimeout = const Duration(seconds: 65),
    KnowledgeRequest? request,
  }) : endpoints = _uniqueUrls([
         baseUrl ?? defaultDanbooruSearchUrl,
         ...(fallbackUrls ??
             (baseUrl == null ? [defaultDanbooruSearchFallbackUrl] : const [])),
       ]),
       _dio = dio ?? Dio(),
       _timeout = timeout,
       _healthTimeout = healthTimeout,
       _requestOverride = request;

  final List<String> endpoints;
  final Dio _dio;
  final Duration _timeout;
  final Duration _healthTimeout;
  final KnowledgeRequest? _requestOverride;

  @override
  Future<KnowledgeHealth> health() async {
    final failures = <String>[];
    for (final endpoint in endpoints) {
      try {
        var response = await _request(
          endpoint,
          method: 'GET',
          path: '/api/health',
          timeout: _healthTimeout,
        );
        if (response.statusCode == 404) {
          response = await _request(
            endpoint,
            method: 'GET',
            path: '/health',
            timeout: _healthTimeout,
          );
        }
        if ((response.statusCode ?? 500) >= 200 &&
            (response.statusCode ?? 500) < 300) {
          return KnowledgeHealth(
            available: true,
            provider: 'danbooru-search',
            message: '语义检索服务可用（${_serviceLabel(endpoint)}）',
          );
        }
        failures.add('${_serviceLabel(endpoint)} HTTP ${response.statusCode}');
      } catch (error) {
        failures.add('${_serviceLabel(endpoint)}：${_friendlyError(error)}');
      }
    }
    return KnowledgeHealth(
      available: false,
      provider: 'danbooru-search',
      message: '语义检索服务不可用：${failures.join('；')}',
    );
  }

  @override
  Future<KnowledgeResult> retrieve(KnowledgeQuery rawQuery) async {
    final query = rawQuery.normalized();
    final failures = <String>[];
    final body = {
      'query': query.text,
      'top_k': 5,
      'limit': query.limit,
      'popularity_weight': 0.15,
      'show_nsfw': true,
      'use_segmentation': true,
      'target_layers': ['英文', '中文扩展词', '释义', '中文核心词'],
      'target_categories': ['General', 'Character', 'Copyright'],
      'group_mode': 'diverse',
      'max_per_group': 3,
    };
    for (final endpoint in endpoints) {
      try {
        var response = await _request(
          endpoint,
          method: 'POST',
          path: '/api/search',
          data: body,
          timeout: _timeout,
        );
        if (response.statusCode == 404) {
          response = await _request(
            endpoint,
            method: 'POST',
            path: '/search',
            data: body,
            timeout: _timeout,
          );
        }
        if ((response.statusCode ?? 500) < 200 ||
            (response.statusCode ?? 500) >= 300) {
          failures.add(
            '${_serviceLabel(endpoint)} HTTP ${response.statusCode}',
          );
          continue;
        }
        final rows = _normalizeRows(response.data).take(query.limit).toList();
        if (rows.isEmpty) {
          failures.add('${_serviceLabel(endpoint)} 返回空结果');
          continue;
        }
        final evidence = <RetrievalEvidence>[
          for (var index = 0; index < rows.length; index++)
            RetrievalEvidence(
              id: 'danbooru:${rows[index].tag}:$index',
              source: rows[index].related ? 'cooccurrence' : 'danbooru-search',
              query: query.text,
              tag: rows[index].tag,
              zh: rows[index].zh,
              category: rows[index].category,
              score: rows[index].score,
              postCount: rows[index].postCount,
              description: rows[index].description,
            ),
        ];
        return KnowledgeResult(
          candidates: [
            for (final row in rows)
              KnowledgeCandidate(
                tag: row.tag,
                zh: row.zh,
                category: _coreCategory(row.category),
                postCount: row.postCount,
                score: row.score,
                description: row.description,
                related: row.related,
              ),
          ],
          evidence: List.unmodifiable(evidence),
          provider: 'danbooru-search:${_serviceLabel(endpoint)}',
          degraded: false,
          warning: failures.isEmpty
              ? null
              : '主语义端点暂不可用，已自动切换：${failures.join('；')}',
        );
      } catch (error) {
        failures.add('${_serviceLabel(endpoint)}：${_friendlyError(error)}');
      }
    }
    throw StateError(
      failures.join('；').isEmpty ? '语义服务没有返回结果' : failures.join('；'),
    );
  }

  Future<Response<dynamic>> _request(
    String endpoint, {
    required String method,
    required String path,
    Object? data,
    required Duration timeout,
  }) async {
    final override = _requestOverride;
    if (override != null) {
      return override(endpoint, method, path, data, timeout);
    }
    final future = _dio.request<dynamic>(
      '$endpoint$path',
      data: data,
      options: Options(
        method: method,
        headers: const {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        validateStatus: (_) => true,
      ),
    );
    return future.timeout(timeout);
  }

  List<_RemoteRow> _normalizeRows(Object? payload) {
    Object? values = payload;
    if (payload is String) values = jsonDecode(payload);
    if (values is Map) {
      values = values['results'] ?? values['data'] ?? values['tags'];
    }
    if (values is! List) throw const FormatException('语义服务返回格式不受支持');
    return [
      for (final raw in values)
        if (raw is Map)
          if (_text(raw['tag'] ?? raw['name'] ?? raw['tag_name']).isNotEmpty)
            _RemoteRow(
              tag: _text(raw['tag'] ?? raw['name'] ?? raw['tag_name']),
              zh: _text(
                raw['zh'] ??
                    raw['cn_name'] ??
                    raw['translation'] ??
                    raw['chinese'],
              ),
              category: _text(raw['category']).isEmpty
                  ? 'other'
                  : _text(raw['category']),
              score: _number(
                raw['final_score'] ??
                    raw['semantic_score'] ??
                    raw['score'] ??
                    raw['similarity'],
              ),
              postCount: _number(
                raw['count'] ?? raw['postCount'] ?? raw['post_count'],
              ).round().clamp(0, 0x7fffffff).toInt(),
              description: _text(raw['description'] ?? raw['wiki']).isEmpty
                  ? null
                  : _text(raw['description'] ?? raw['wiki']),
              related: raw['related'] == true,
            ),
    ];
  }

  static List<String> _uniqueUrls(Iterable<String> values) => [
    ...<String>{
      for (final value in values)
        if (value.trim().isNotEmpty)
          value.trim().replaceAll(RegExp(r'/+$'), ''),
    },
  ];

  static String _text(Object? value) => value is String ? value.trim() : '';

  static double _number(Object? value) {
    if (value is num && value.isFinite) return value.toDouble();
    if (value is String) return double.tryParse(value.trim()) ?? 0;
    return 0;
  }

  static String _coreCategory(String value) {
    final key = value.toLowerCase();
    if (key.contains('cloth') || key.contains('outfit')) return 'clothing';
    if (key.contains('pose') || key.contains('action')) return 'pose';
    if (key.contains('scene') ||
        key.contains('background') ||
        key.contains('object')) {
      return 'scene';
    }
    if (key.contains('light')) return 'lighting';
    if (key.contains('camera')) return 'camera';
    if (key.contains('style') || key.contains('reference')) return 'style';
    if (key.contains('adult')) return 'adult';
    if (key.contains('quality')) return 'quality';
    if (key.contains('appearance') || key.contains('expression')) {
      return 'appearance';
    }
    if (key.contains('negative')) return 'negative';
    return 'subject';
  }

  static String _serviceLabel(String value) {
    try {
      final uri = Uri.parse(value);
      if (uri.host.contains('hf.space')) return '官方 HF';
      if (uri.host.contains('ms.show')) return '官方 ModelScope';
      return uri.host.isEmpty ? '自定义端点' : uri.host;
    } catch (_) {
      return '自定义端点';
    }
  }

  static String _friendlyError(Object error) {
    final message = error.toString();
    if (error is TimeoutException ||
        message.toLowerCase().contains('timeout')) {
      return '连接超时或服务仍在冷启动';
    }
    if (error is DioException) {
      if (error.type == DioExceptionType.connectionError) return '网络连接失败';
      return error.message ?? '网络请求失败';
    }
    final sanitized = message.replaceAll(RegExp(r'https?://[^\s]+'), '语义服务地址');
    return sanitized.substring(0, sanitized.length.clamp(0, 180));
  }
}

class _RemoteRow {
  const _RemoteRow({
    required this.tag,
    required this.zh,
    required this.category,
    required this.score,
    required this.postCount,
    required this.description,
    required this.related,
  });

  final String tag;
  final String zh;
  final String category;
  final double score;
  final int postCount;
  final String? description;
  final bool related;
}

class FallbackKnowledgeProvider implements KnowledgeProvider {
  const FallbackKnowledgeProvider(
    this.primary,
    this.fallback, {
    this.fallbackLabel = '备用检索服务',
  });

  final KnowledgeProvider primary;
  final KnowledgeProvider fallback;
  final String fallbackLabel;

  @override
  Future<KnowledgeHealth> health() async {
    final primaryHealth = await primary.health();
    if (primaryHealth.available) return primaryHealth;
    final fallbackHealth = await fallback.health();
    return KnowledgeHealth(
      available: fallbackHealth.available,
      provider: fallbackHealth.provider,
      message: '${primaryHealth.message}；已降级到 ${fallbackHealth.message}',
    );
  }

  @override
  Future<KnowledgeResult> retrieve(KnowledgeQuery query) async {
    Object? primaryError;
    try {
      final result = await primary.retrieve(query);
      // An empty local index is not a failure, but it should still give a
      // configured remote provider a chance to discover a new tag.
      if (result.candidates.isNotEmpty || query.normalized().text.isEmpty) {
        return result;
      }
    } catch (error) {
      primaryError = error;
    }
    final result = await fallback.retrieve(query);
    final reason = primaryError == null
        ? '本地 Tag 库没有匹配项'
        : '本地检索不可用：$primaryError';
    return KnowledgeResult(
      candidates: result.candidates,
      evidence: result.evidence,
      provider: result.provider,
      degraded: true,
      warning: '$reason，已降级并切换到$fallbackLabel',
    );
  }
}

/// Merges project vocabulary and bundled/remote knowledge while preserving
/// the strongest candidate and every evidence record for auditability.
class MergedKnowledgeProvider implements KnowledgeProvider {
  const MergedKnowledgeProvider(this.providers);

  final List<KnowledgeProvider> providers;

  @override
  Future<KnowledgeHealth> health() async {
    final health = await Future.wait(
      providers.map((provider) => provider.health()),
    );
    final available = health.where((item) => item.available).toList();
    if (available.isNotEmpty) {
      return KnowledgeHealth(
        available: true,
        provider: available.map((item) => item.provider).join('+'),
        message: available.map((item) => item.message).join('；'),
      );
    }
    return KnowledgeHealth(
      available: false,
      provider: health.map((item) => item.provider).join('+'),
      message: health.map((item) => item.message).join('；'),
    );
  }

  @override
  Future<KnowledgeResult> retrieve(KnowledgeQuery query) async {
    final candidatesByKey = <String, KnowledgeCandidate>{};
    final evidenceByKey = <String, RetrievalEvidence>{};
    final providersUsed = <String>[];
    final warnings = <String>[];
    var degraded = false;
    for (final provider in providers) {
      try {
        final result = await provider.retrieve(query);
        if (result.candidates.isNotEmpty) providersUsed.add(result.provider);
        degraded = degraded || result.degraded;
        if (result.warning != null && result.warning!.isNotEmpty) {
          warnings.add(result.warning!);
        }
        for (final candidate in result.candidates) {
          final key = candidate.tag.trim().toLowerCase();
          if (key.isEmpty) continue;
          final current = candidatesByKey[key];
          if (current == null || _isStronger(candidate, current)) {
            candidatesByKey[key] = candidate;
          }
        }
        for (final item in result.evidence) {
          evidenceByKey[item.id] = item;
        }
      } catch (error) {
        degraded = true;
        warnings.add('${provider.runtimeType}: $error');
      }
    }
    final candidates = candidatesByKey.values.toList()..sort(_compareCandidate);
    final bounded = candidates.take(query.normalized().limit).toList();
    // Keep related/secondary evidence even when the visible candidate list is
    // capped. Recipes should explain every retrieval input that informed a
    // later manual choice.
    final evidence = evidenceByKey.values.toList(growable: false);
    return KnowledgeResult(
      candidates: List.unmodifiable(bounded),
      evidence: List.unmodifiable(evidence),
      provider: providersUsed.isEmpty ? 'knowledge' : providersUsed.join('+'),
      degraded: degraded,
      warning: warnings.isEmpty ? null : warnings.join('；'),
    );
  }

  static bool _isStronger(
    KnowledgeCandidate candidate,
    KnowledgeCandidate current,
  ) {
    if (candidate.score != current.score) {
      return candidate.score > current.score;
    }
    if (candidate.postCount != current.postCount) {
      return candidate.postCount > current.postCount;
    }
    return candidate.zh != null && current.zh == null;
  }

  static int _compareCandidate(
    KnowledgeCandidate left,
    KnowledgeCandidate right,
  ) {
    final score = right.score.compareTo(left.score);
    if (score != 0) return score;
    final count = right.postCount.compareTo(left.postCount);
    return count != 0 ? count : left.tag.compareTo(right.tag);
  }
}

class KnowledgeManager {
  const KnowledgeManager(this.provider);

  final KnowledgeProvider provider;

  Future<KnowledgeHealth> inspect() => provider.health();

  Future<KnowledgeResult> search(String text, {int limit = 120}) =>
      provider.retrieve(KnowledgeQuery(text: text, limit: limit));
}
