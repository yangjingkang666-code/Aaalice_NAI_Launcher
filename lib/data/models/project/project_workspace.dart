import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

/// A portable project workspace used to isolate generated assets and durable
/// metadata from the legacy global gallery directory.
class ProjectWorkspace {
  const ProjectWorkspace({
    required this.id,
    required this.path,
    required this.name,
    required this.createdAt,
    required this.lastOpenedAt,
  });

  static const int schemaVersion = 1;

  final String id;
  final String path;
  final String name;
  final DateTime createdAt;
  final DateTime lastOpenedAt;

  String get projectDataPath => p.join(path, '.novelai-cn');
  String get imagesPath => p.join(path, 'images');
  String get metadataPath => p.join(projectDataPath, 'metadata');
  String get recipesPath => p.join(projectDataPath, 'recipes');
  String get knowledgePath => p.join(projectDataPath, 'knowledge.json');
  String get descriptorPath => p.join(projectDataPath, 'project.json');

  ProjectWorkspace copyWith({
    String? path,
    String? name,
    DateTime? lastOpenedAt,
  }) => ProjectWorkspace(
    id: id,
    path: path ?? this.path,
    name: name ?? this.name,
    createdAt: createdAt,
    lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
  );

  Map<String, dynamic> toJson() => {
    'schemaVersion': schemaVersion,
    'id': id,
    'path': path,
    'name': name,
    'createdAt': createdAt.toUtc().millisecondsSinceEpoch,
    'lastOpenedAt': lastOpenedAt.toUtc().millisecondsSinceEpoch,
  };

  String encode() => jsonEncode(toJson());

  factory ProjectWorkspace.fromJson(Map<String, dynamic> json) {
    final version = json['schemaVersion'];
    final id = json['id'];
    final path = json['path'];
    final name = json['name'];
    final createdAt = json['createdAt'];
    final lastOpenedAt = json['lastOpenedAt'];
    if (version != schemaVersion ||
        id is! String ||
        id.isEmpty ||
        path is! String ||
        path.trim().isEmpty ||
        name is! String ||
        name.trim().isEmpty ||
        createdAt is! int ||
        lastOpenedAt is! int ||
        createdAt < 0 ||
        lastOpenedAt < 0) {
      throw const FormatException('Invalid project workspace descriptor.');
    }
    return ProjectWorkspace(
      id: id,
      path: path,
      name: name,
      createdAt: DateTime.fromMillisecondsSinceEpoch(createdAt, isUtc: true),
      lastOpenedAt: DateTime.fromMillisecondsSinceEpoch(
        lastOpenedAt,
        isUtc: true,
      ),
    );
  }

  factory ProjectWorkspace.create({
    required String path,
    String? name,
    DateTime? now,
    String? id,
  }) {
    final timestamp = (now ?? DateTime.now()).toUtc();
    final normalizedPath = p.normalize(path);
    final resolvedName = name?.trim().isNotEmpty == true
        ? name!.trim()
        : p.basename(normalizedPath);
    return ProjectWorkspace(
      id: id ?? const Uuid().v4(),
      path: normalizedPath,
      name: resolvedName.isEmpty ? 'Project' : resolvedName,
      createdAt: timestamp,
      lastOpenedAt: timestamp,
    );
  }
}

/// Summary returned by a non-destructive legacy import.
class ProjectWorkspaceMigrationResult {
  const ProjectWorkspaceMigrationResult({
    this.copiedImages = 0,
    this.skippedImages = 0,
    this.copiedRecipes = 0,
    this.skippedRecipes = 0,
    this.errors = const [],
  });

  final int copiedImages;
  final int skippedImages;
  final int copiedRecipes;
  final int skippedRecipes;
  final List<String> errors;

  bool get hasErrors => errors.isNotEmpty;
  int get totalCopied => copiedImages + copiedRecipes;

  ProjectWorkspaceMigrationResult merge(
    ProjectWorkspaceMigrationResult other,
  ) => ProjectWorkspaceMigrationResult(
    copiedImages: copiedImages + other.copiedImages,
    skippedImages: skippedImages + other.skippedImages,
    copiedRecipes: copiedRecipes + other.copiedRecipes,
    skippedRecipes: skippedRecipes + other.skippedRecipes,
    errors: List.unmodifiable([...errors, ...other.errors]),
  );
}
