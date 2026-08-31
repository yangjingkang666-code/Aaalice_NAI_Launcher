import 'dart:convert';
import 'dart:io';

import '../../../core/utils/app_logger.dart';
import '../../models/knowledge/knowledge_models.dart';
import '../../models/recipe/prompt_recipe.dart';
import '../project_workspace_service.dart';

/// Portable, project-scoped knowledge entries.
///
/// The store is intentionally small and human-readable. It complements the
/// bundled catalog instead of copying the large SQLite database into every
/// project, and it gives users a place to keep accepted remote tags or local
/// prompt vocabulary that should travel with the project.
class ProjectKnowledgeStore {
  ProjectKnowledgeStore({ProjectWorkspaceService? workspace})
    : _workspace = workspace ?? ProjectWorkspaceService.instance;

  final ProjectWorkspaceService _workspace;
  Future<void> _writeQueue = Future<void>.value();

  Future<bool> get isAvailable async => await _file() != null;

  Future<List<KnowledgeCandidate>> list() async {
    final file = await _file();
    if (file == null || !await file.exists()) return const [];
    try {
      final decoded = jsonDecode(await file.readAsString());
      final rawEntries = decoded is Map ? decoded['entries'] : decoded;
      if (rawEntries is! List) return const [];
      final result = <KnowledgeCandidate>[];
      final seen = <String>{};
      for (final value in rawEntries) {
        final candidate = KnowledgeCandidate.tryFromJson(value);
        if (candidate == null) continue;
        final key = _key(candidate.tag);
        if (key.isEmpty || !seen.add(key)) continue;
        result.add(candidate);
      }
      result.sort(_compare);
      return List.unmodifiable(result);
    } catch (error, stackTrace) {
      AppLogger.w('读取项目知识库失败: $error', 'ProjectKnowledge');
      AppLogger.d(stackTrace.toString(), 'ProjectKnowledge');
      return const [];
    }
  }

  Future<void> upsert(KnowledgeCandidate candidate) async {
    if (candidate.tag.trim().isEmpty) return;
    final operation = _writeQueue.then<void>(
      (_) => _upsertNow(candidate),
      onError: (_, __) => _upsertNow(candidate),
    );
    _writeQueue = operation;
    await operation;
  }

  Future<void> remove(String tag) async {
    final operation = _writeQueue.then<void>(
      (_) => _removeNow(tag),
      onError: (_, __) => _removeNow(tag),
    );
    _writeQueue = operation;
    await operation;
  }

  Future<List<KnowledgeCandidate>> search(KnowledgeQuery rawQuery) async {
    final query = rawQuery.normalized();
    if (query.text.isEmpty) return const [];
    final terms = query.text
        .split(RegExp(r'[,，、\n]+'))
        .map((value) => value.trim().toLowerCase())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    final matches = <KnowledgeCandidate>[];
    for (final candidate in await list()) {
      final haystack = [
        candidate.tag,
        if (candidate.zh != null) candidate.zh!,
        if (candidate.description != null) candidate.description!,
      ].join(' ').toLowerCase();
      final score = _matchScore(haystack, terms);
      if (score <= 0) continue;
      matches.add(candidate.copyWith(score: score));
    }
    matches.sort(_compare);
    return List.unmodifiable(matches.take(query.limit));
  }

  Future<void> _upsertNow(KnowledgeCandidate candidate) async {
    final file = await _file(ensure: true);
    if (file == null) return;
    final entries = (await list()).toList();
    final key = _key(candidate.tag);
    final index = entries.indexWhere((item) => _key(item.tag) == key);
    if (index >= 0) {
      entries[index] = candidate.copyWith(related: false);
    } else {
      entries.add(candidate.copyWith(related: false));
    }
    entries.sort(_compare);
    await _write(file, entries);
  }

  Future<void> _removeNow(String tag) async {
    final file = await _file();
    if (file == null || !await file.exists()) return;
    final entries = (await list())
        .where((item) => _key(item.tag) != _key(tag))
        .toList(growable: false);
    if (entries.isEmpty) {
      await file.delete();
      return;
    }
    await _write(file, entries);
  }

  Future<File?> _file({bool ensure = false}) async {
    final workspace = await _workspace.current();
    if (workspace == null) return null;
    final file = File(workspace.knowledgePath);
    if (ensure) await file.parent.create(recursive: true);
    return file;
  }

  Future<void> _write(File target, List<KnowledgeCandidate> entries) async {
    await target.parent.create(recursive: true);
    final temp = File(
      '${target.path}.tmp-${DateTime.now().microsecondsSinceEpoch}',
    );
    final payload = <String, dynamic>{
      'schemaVersion': 1,
      'entries': [for (final entry in entries) entry.toJson()],
    };
    try {
      await temp.writeAsString(jsonEncode(payload), flush: true);
      try {
        await temp.rename(target.path);
      } on FileSystemException {
        if (await target.exists()) await target.delete();
        await temp.rename(target.path);
      }
    } finally {
      if (await temp.exists()) {
        try {
          await temp.delete();
        } catch (_) {}
      }
    }
  }

  static String _key(String value) => value.trim().toLowerCase();

  static int _compare(KnowledgeCandidate left, KnowledgeCandidate right) {
    final score = right.score.compareTo(left.score);
    if (score != 0) return score;
    final popularity = right.postCount.compareTo(left.postCount);
    return popularity != 0
        ? popularity
        : left.tag.toLowerCase().compareTo(right.tag.toLowerCase());
  }

  static double _matchScore(String haystack, List<String> terms) {
    var best = 0.0;
    for (final term in terms) {
      if (haystack == term) {
        best = best < 1.0 ? 1.0 : best;
      } else if (haystack.startsWith(term)) {
        best = best < 0.9 ? 0.9 : best;
      } else if (haystack.contains(term)) {
        best = best < 0.7 ? 0.7 : best;
      }
    }
    return best;
  }
}

class ProjectKnowledgeProvider implements KnowledgeProvider {
  ProjectKnowledgeProvider({ProjectKnowledgeStore? store})
    : _store = store ?? ProjectKnowledgeStore();

  final ProjectKnowledgeStore _store;

  @override
  Future<KnowledgeHealth> health() async {
    if (!await _store.isAvailable) {
      return const KnowledgeHealth(
        available: false,
        provider: 'project-knowledge',
        message: '未选择项目工作区',
      );
    }
    try {
      final count = (await _store.list()).length;
      return KnowledgeHealth(
        available: true,
        provider: 'project-knowledge',
        message: '项目知识库可用（$count 条）',
      );
    } catch (error) {
      return KnowledgeHealth(
        available: false,
        provider: 'project-knowledge',
        message: '项目知识库不可用：$error',
      );
    }
  }

  @override
  Future<KnowledgeResult> retrieve(KnowledgeQuery query) async {
    final candidates = await _store.search(query);
    return KnowledgeResult(
      candidates: candidates,
      evidence: [
        for (var index = 0; index < candidates.length; index++)
          RetrievalEvidence(
            id: 'project:${candidates[index].tag}:$index',
            source: 'project-knowledge',
            query: query.text,
            tag: candidates[index].tag,
            zh: candidates[index].zh,
            category: candidates[index].category,
            postCount: candidates[index].postCount,
            score: candidates[index].score,
            description: candidates[index].description,
          ),
      ],
      provider: 'project-knowledge',
      degraded: false,
    );
  }
}
