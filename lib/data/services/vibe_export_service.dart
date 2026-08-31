import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/utils/app_logger.dart';
import '../../core/utils/file_name_sanitizer.dart';
import '../../core/utils/novelai_vibe_codec.dart';
import '../../core/utils/vibe_image_embedder.dart';
import '../models/vibe/vibe_export_format.dart';
import '../models/vibe/vibe_library_entry.dart';
import '../models/vibe/vibe_reference.dart';

part 'vibe_export_service.g.dart';

/// Vibe 导出进度回调
typedef ExportProgressCallback =
    void Function({
      required int current,
      required int total,
      required String currentItem,
    });

/// Vibe 导出服务
///
/// 负责将 Vibe 库条目导出为不同格式
class VibeExportService {
  VibeExportService({Future<String> Function()? exportDirectoryResolver})
    : _exportDirectoryResolver = exportDirectoryResolver;

  static const String _tag = 'VibeExport';

  final Future<String> Function()? _exportDirectoryResolver;

  /// 导出为 Bundle 格式
  ///
  /// [entries] - 要导出的条目列表
  /// [options] - 导出选项
  /// [onProgress] - 进度回调
  Future<String?> exportAsBundle(
    List<VibeLibraryEntry> entries, {
    required VibeExportOptions options,
    ExportProgressCallback? onProgress,
  }) async {
    if (entries.isEmpty) {
      AppLogger.w('Cannot export empty entries to bundle', _tag);
      return null;
    }

    final stopwatch = Stopwatch()..start();

    try {
      final outputDir = await _getExportDirectory();
      final fileName = _generateFileName(
        options.fileName,
        'vibe-bundle',
        kNaiv4vibebundleExtension,
      );
      final filePath = p.join(outputDir, fileName);

      AppLogger.i(
        'Starting bundle export: ${entries.length} entries to $filePath',
        _tag,
      );

      final bundleData = await _buildBundleData(entries, options, onProgress);

      final file = File(filePath);
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(bundleData),
      );

      stopwatch.stop();
      AppLogger.i(
        'Bundle export completed: ${entries.length} entries in ${stopwatch.elapsedMilliseconds}ms',
        _tag,
      );

      return filePath;
    } catch (e, stackTrace) {
      stopwatch.stop();
      AppLogger.e('Bundle export failed', e, stackTrace, _tag);
      return null;
    }
  }

  /// 导出为嵌入图片格式
  ///
  /// [entry] - 要导出的条目
  /// [options] - 导出选项
  Future<String?> exportAsEmbeddedImage(
    VibeLibraryEntry entry, {
    required VibeExportOptions options,
  }) async {
    final targetPath = options.targetImagePath?.trim();
    if (targetPath == null || targetPath.isEmpty) {
      AppLogger.w('Embedded image export requires a carrier image', _tag);
      return null;
    }

    final stopwatch = Stopwatch()..start();
    try {
      final carrier = File(targetPath);
      if (!await carrier.exists()) {
        AppLogger.w('Carrier image does not exist: $targetPath', _tag);
        return null;
      }

      final reference = entry.toVibeReference().copyWith(
        vibeEncoding: options.includeEncoding ? entry.vibeEncoding : '',
        thumbnail: options.includeThumbnail ? entry.vibeThumbnail : null,
      );
      final embeddedBytes = await VibeImageEmbedder.embedVibeToImage(
        await carrier.readAsBytes(),
        reference,
      );

      final outputDirectory = Directory(await _getExportDirectory());
      await outputDirectory.create(recursive: true);
      final fileName = _generateFileName(
        options.fileName,
        '${entry.displayName}_vibe',
        'png',
      );
      var outputFile = File(p.join(outputDirectory.path, fileName));
      if (p.equals(outputFile.absolute.path, carrier.absolute.path)) {
        outputFile = File(
          p.join(
            outputDirectory.path,
            _generateFileName(null, '${entry.displayName}_vibe', 'png'),
          ),
        );
      }
      await outputFile.writeAsBytes(embeddedBytes, flush: true);

      stopwatch.stop();
      AppLogger.i(
        'Embedded image export completed: ${entry.displayName} in ${stopwatch.elapsedMilliseconds}ms',
        _tag,
      );
      return outputFile.path;
    } catch (e, stackTrace) {
      stopwatch.stop();
      AppLogger.e('Embedded image export failed', e, stackTrace, _tag);
      return null;
    }
  }

  /// 导出为纯编码格式
  ///
  /// [entries] - 要导出的条目列表
  /// [options] - 导出选项
  /// [onProgress] - 进度回调
  Future<String?> exportAsEncoding(
    List<VibeLibraryEntry> entries, {
    required VibeExportOptions options,
    ExportProgressCallback? onProgress,
  }) async {
    if (entries.isEmpty) {
      AppLogger.w('Cannot export empty entries to encoding list', _tag);
      return null;
    }

    final stopwatch = Stopwatch()..start();

    try {
      final outputDir = await _getExportDirectory();
      final fileName = _generateFileName(
        options.fileName,
        'vibe-encodings',
        'txt',
      );
      final filePath = p.join(outputDir, fileName);

      AppLogger.i(
        'Starting encoding export: ${entries.length} entries to $filePath',
        _tag,
      );

      final encodingList = <String>[];

      for (var i = 0; i < entries.length; i++) {
        final entry = entries[i];

        onProgress?.call(
          current: i,
          total: entries.length,
          currentItem: entry.displayName,
        );

        // 只导出具有有效编码的条目
        if (entry.vibeEncoding.isNotEmpty) {
          encodingList.add(entry.vibeEncoding);
          AppLogger.d(
            'Added encoding for: ${entry.displayName} (${i + 1}/${entries.length})',
            _tag,
          );
        } else {
          AppLogger.w(
            'Skipping entry without encoding: ${entry.displayName}',
            _tag,
          );
        }
      }

      if (encodingList.isEmpty) {
        AppLogger.w('No valid encodings to export', _tag);
        return null;
      }

      final file = File(filePath);
      await file.writeAsString(encodingList.join('\n'));

      onProgress?.call(
        current: entries.length,
        total: entries.length,
        currentItem: '',
      );

      stopwatch.stop();
      AppLogger.i(
        'Encoding export completed: ${encodingList.length} encodings in ${stopwatch.elapsedMilliseconds}ms',
        _tag,
      );

      return filePath;
    } catch (e, stackTrace) {
      stopwatch.stop();
      AppLogger.e('Encoding export failed', e, stackTrace, _tag);
      return null;
    }
  }

  /// 构建 Bundle 数据
  Future<Map<String, dynamic>> _buildBundleData(
    List<VibeLibraryEntry> entries,
    VibeExportOptions options,
    ExportProgressCallback? onProgress,
  ) async {
    final vibes = <VibeReference>[];

    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];

      onProgress?.call(
        current: i,
        total: entries.length,
        currentItem: entry.displayName,
      );

      final source = entry.toVibeReference();
      final vibe = options.includeEncoding
          ? source
          : source.copyWith(vibeEncoding: '');
      final hasImage =
          vibe.rawImageData?.isNotEmpty == true ||
          vibe.thumbnail?.isNotEmpty == true;
      if (vibe.vibeEncoding.isEmpty && !hasImage) {
        AppLogger.w(
          'Skipping entry without an image or encoding: ${entry.displayName}',
          _tag,
        );
        continue;
      }
      vibes.add(vibe);

      AppLogger.d(
        'Added to bundle: ${entry.displayName} (${i + 1}/${entries.length})',
        _tag,
      );
    }

    if (vibes.isEmpty) {
      throw StateError('No exportable Vibe entries');
    }
    return NovelAiVibeCodec.buildBundleMap(
      vibes,
      includeThumbnails: options.includeThumbnail,
      includeEncoding: options.includeEncoding,
    );
  }

  /// 获取导出目录
  Future<String> _getExportDirectory() async {
    final resolver = _exportDirectoryResolver;
    if (resolver != null) {
      return resolver();
    }

    try {
      final downloadsDir = await getDownloadsDirectory();
      if (downloadsDir != null) {
        return downloadsDir.path;
      }
    } catch (e) {
      AppLogger.w('Failed to get downloads directory: $e', _tag);
    }

    // 降级到应用文档目录
    final appDir = await getApplicationDocumentsDirectory();
    return appDir.path;
  }

  /// 生成文件名
  String _generateFileName(
    String? customName,
    String defaultBaseName,
    String extension,
  ) {
    final timestamp = DateTime.now();
    final formattedTime =
        '${timestamp.year}${_twoDigits(timestamp.month)}${_twoDigits(timestamp.day)}_'
        '${_twoDigits(timestamp.hour)}${_twoDigits(timestamp.minute)}${_twoDigits(timestamp.second)}';

    final baseName = customName?.trim().isNotEmpty == true
        ? customName!.trim()
        : '${defaultBaseName}_$formattedTime';

    // 清理文件名中的非法字符
    final sanitizedBaseName = _sanitizeFileName(baseName);

    return '$sanitizedBaseName.$extension';
  }

  /// 清理文件名中的非法字符
  String _sanitizeFileName(String fileName) {
    return FileNameSanitizer.sanitize(
      fileName,
      fallback: '',
      collapseWhitespace: true,
    );
  }

  /// 将数字格式化为两位字符串
  String _twoDigits(int n) => n.toString().padLeft(2, '0');
}

/// VibeExportService Provider
@riverpod
VibeExportService vibeExportService(Ref ref) {
  return VibeExportService();
}
