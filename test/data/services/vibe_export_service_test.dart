import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/core/utils/vibe_image_embedder.dart';
import 'package:nai_launcher/data/models/vibe/vibe_export_format.dart';
import 'package:nai_launcher/data/models/vibe/vibe_library_entry.dart';
import 'package:nai_launcher/data/services/vibe_export_service.dart';

void main() {
  late Directory tempDirectory;
  late File carrier;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp(
      'vibe_export_service_test_',
    );
    carrier = File('${tempDirectory.path}${Platform.pathSeparator}carrier.png');
    await carrier.writeAsBytes(_createInMemoryPngBytes());
  });

  tearDown(() async {
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test('exports an embedded PNG that can be read back', () async {
    final outputDirectory = Directory(
      '${tempDirectory.path}${Platform.pathSeparator}output',
    );
    final service = VibeExportService(
      exportDirectoryResolver: () async => outputDirectory.path,
    );
    final entry = VibeLibraryEntry.create(
      name: 'Test Vibe',
      vibeDisplayName: 'Test Vibe',
      vibeEncoding: 'YmFzZTY0X2VuY29kaW5n',
    );

    final outputPath = await service.exportAsEmbeddedImage(
      entry,
      options: VibeExportOptions.embeddedImage(targetImagePath: carrier.path),
    );

    expect(outputPath, isNotNull);
    final output = File(outputPath!);
    expect(await output.exists(), isTrue);
    final extracted = await VibeImageEmbedder.extractVibeFromImage(
      await output.readAsBytes(),
    );
    expect(extracted.vibes.single.vibeEncoding, entry.vibeEncoding);
  });

  test('returns null when the carrier image is unavailable', () async {
    final service = VibeExportService(
      exportDirectoryResolver: () async => tempDirectory.path,
    );
    final entry = VibeLibraryEntry.create(
      name: 'Missing Carrier',
      vibeDisplayName: 'Missing Carrier',
      vibeEncoding: 'encoded',
    );

    final outputPath = await service.exportAsEmbeddedImage(
      entry,
      options: VibeExportOptions.embeddedImage(
        targetImagePath:
            '${tempDirectory.path}${Platform.pathSeparator}missing.png',
      ),
    );

    expect(outputPath, isNull);
  });
}

List<int> _createInMemoryPngBytes() {
  const base64Png =
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO6qv0YAAAAASUVORK5CYII=';
  return base64Decode(base64Png);
}
