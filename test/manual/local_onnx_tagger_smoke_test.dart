import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/data/services/local_onnx_model_service.dart';
import 'package:nai_launcher/data/services/local_onnx_tagger_service.dart';
import 'package:nai_launcher/data/services/local_tagger_execution_strategy.dart';
import 'package:onnxruntime_v2/onnxruntime_v2.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final environment = Platform.environment;
  final runSmokeTest = environment['NAI_ONNX_TAGGER_SMOKE'] == '1';

  test(
    'runs configured JoyTag/WD EVA02 ONNX models on a real image',
    () async {
      final imagePath =
          environment['NAI_ONNX_IMAGE'] ??
          p.join(Directory.current.path, 'assets', 'icons', 'Icon.png');
      final image = File(imagePath);
      expect(
        await image.exists(),
        isTrue,
        reason: 'Set NAI_ONNX_IMAGE to an existing image file.',
      );

      final models = <LocalOnnxModelDescriptor>[];
      final joyTagPath = environment['NAI_JOYTAG_MODEL'];
      if (joyTagPath != null && joyTagPath.trim().isNotEmpty) {
        models.add(
          LocalOnnxModelDescriptor(
            name: p.basename(joyTagPath),
            path: joyTagPath,
            kind: LocalOnnxModelKind.joyTag,
            labelsPath:
                environment['NAI_JOYTAG_LABELS'] ??
                p.join(p.dirname(joyTagPath), 'top_tags.txt'),
          ),
        );
      }

      final wdEva02Path = environment['NAI_WD_EVA02_MODEL'];
      if (wdEva02Path != null && wdEva02Path.trim().isNotEmpty) {
        models.add(
          LocalOnnxModelDescriptor(
            name: p.basename(wdEva02Path),
            path: wdEva02Path,
            kind: LocalOnnxModelKind.wd14Tagger,
            labelsPath:
                environment['NAI_WD_EVA02_LABELS'] ??
                p.join(p.dirname(wdEva02Path), 'selected_tags.csv'),
          ),
        );
      }
      expect(
        models,
        isNotEmpty,
        reason:
            'Set NAI_JOYTAG_MODEL and/or NAI_WD_EVA02_MODEL to run the smoke test.',
      );

      // ignore: avoid_print
      print('available_providers=${OrtEnv.instance.availableProviders()}');
      final preference = switch (environment['NAI_ONNX_TAGGER_PREFERENCE']
          ?.toLowerCase()) {
        'cpu' => LocalTaggerExecutionPreference.cpu,
        'directml' ||
        'direct_ml' ||
        'dml' => LocalTaggerExecutionPreference.directMl,
        _ => LocalTaggerExecutionPreference.automatic,
      };
      final service = LocalOnnxTaggerService(executionPreference: preference);
      final imageBytes = await image.readAsBytes();
      for (final model in models) {
        final stopwatch = Stopwatch()..start();
        final result = await service.tagImage(
          imageBytes: imageBytes,
          model: model,
          generalThreshold: 0.35,
          characterThreshold: 0.35,
        );
        stopwatch.stop();
        expect(result.tags, isNotEmpty, reason: model.name);
        // ignore: avoid_print
        print(
          '${model.name} provider=${result.executionProvider.displayName} '
          'elapsed_ms=${stopwatch.elapsedMilliseconds} '
          'tags=${result.tags.take(10).map((tag) => '${tag.name}:${tag.score.toStringAsFixed(3)}').join(', ')}',
        );
      }
    },
    skip: !runSmokeTest,
    timeout: const Timeout(Duration(minutes: 15)),
  );
}
