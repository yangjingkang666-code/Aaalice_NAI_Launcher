import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/storage/local_storage_service.dart';
import 'package:nai_launcher/data/models/knowledge/knowledge_models.dart';
import 'package:nai_launcher/data/services/knowledge/project_knowledge_store.dart';
import 'package:nai_launcher/data/services/project_workspace_service.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late _FakeStorage storage;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('nai_project_knowledge_');
    storage = _FakeStorage();
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  ProjectWorkspaceService workspaceService() => ProjectWorkspaceService(
    storage: storage,
    documentsDirectoryResolver: () async => root,
    idGenerator: () => 'workspace-id',
  );

  test('stores accepted candidates in the active project', () async {
    final workspace = workspaceService();
    await workspace.open(p.join(root.path, 'project'));
    final store = ProjectKnowledgeStore(workspace: workspace);
    await store.upsert(
      const KnowledgeCandidate(
        tag: 'high_ponytail',
        category: 'appearance',
        zh: '高马尾',
        postCount: 123,
        score: 0.8,
      ),
    );

    final file = File(
      p.join(root.path, 'project', '.novelai-cn', 'knowledge.json'),
    );
    expect(await file.exists(), isTrue);
    expect((await store.list()).single.zh, '高马尾');
    expect(
      (await store.search(const KnowledgeQuery(text: '马尾'))).single.tag,
      'high_ponytail',
    );
  });

  test('upsert replaces duplicate tags and remove deletes the file', () async {
    final workspace = workspaceService();
    await workspace.open(p.join(root.path, 'project'));
    final store = ProjectKnowledgeStore(workspace: workspace);
    await store.upsert(
      const KnowledgeCandidate(tag: 'blue_eyes', category: 'appearance'),
    );
    await store.upsert(
      const KnowledgeCandidate(
        tag: 'blue_eyes',
        category: 'appearance',
        zh: '蓝眼睛',
      ),
    );
    expect((await store.list()).single.zh, '蓝眼睛');
    await store.remove('blue_eyes');
    expect(await store.list(), isEmpty);
    expect(
      await File(
        p.join(workspacePath(root), '.novelai-cn', 'knowledge.json'),
      ).exists(),
      isFalse,
    );
  });

  test('is a no-op when no project is active', () async {
    final store = ProjectKnowledgeStore(workspace: workspaceService());
    expect(await store.isAvailable, isFalse);
    await store.upsert(
      const KnowledgeCandidate(tag: '1girl', category: 'subject'),
    );
    expect(await store.list(), isEmpty);
  });
}

String workspacePath(Directory root) => p.join(root.path, 'project');

class _FakeStorage extends LocalStorageService {
  String? workspacePath;

  @override
  String? getProjectWorkspacePath() => workspacePath;

  @override
  Future<void> setProjectWorkspacePath(String? path) async {
    workspacePath = path;
  }
}
