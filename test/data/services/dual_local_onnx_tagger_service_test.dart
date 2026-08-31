import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/data/services/dual_local_onnx_tagger_service.dart';
import 'package:nai_launcher/data/services/local_onnx_model_service.dart';
import 'package:nai_launcher/data/services/local_onnx_tagger_service.dart';

void main() {
  const joy = LocalOnnxModelDescriptor(
    name: 'joytag_model.onnx',
    path: r'C:\models\joytag_model.onnx',
    kind: LocalOnnxModelKind.unknown,
  );
  const wd = LocalOnnxModelDescriptor(
    name: 'wd-eva02-large.onnx',
    path: r'C:\models\wd-eva02-large.onnx',
    kind: LocalOnnxModelKind.wd14Tagger,
  );

  test(
    'identifies JoyTag and WD EVA02 roles without guessing other models',
    () {
      expect(
        DualLocalOnnxTaggerService.roleFor(joy),
        DualLocalTaggerRole.joyTag,
      );
      expect(
        DualLocalOnnxTaggerService.roleFor(wd),
        DualLocalTaggerRole.wdEva02,
      );
      expect(DualLocalOnnxTaggerService.findPair([joy, wd]), isNotNull);
      const other = LocalOnnxModelDescriptor(
        name: 'custom.onnx',
        path: r'C:\models\custom.onnx',
        kind: LocalOnnxModelKind.unknown,
      );
      expect(DualLocalOnnxTaggerService.findPair([other]), isNull);
    },
  );

  test(
    'runs both models sequentially and preserves an individual failure',
    () async {
      final calls = <String>[];
      final service = DualLocalOnnxTaggerService(
        runner:
            ({
              required Uint8List imageBytes,
              required LocalOnnxModelDescriptor model,
              required double generalThreshold,
              required double characterThreshold,
            }) async {
              calls.add(model.name);
              if (model == wd) throw StateError('WD unavailable');
              return OnnxTaggerResult(
                model: model,
                tags: const [OnnxTaggerTag(name: '1girl', score: .99)],
              );
            },
      );
      final result = await service.tagImage(
        imageBytes: Uint8List.fromList(const [1, 2, 3]),
        models: const DualLocalTaggerModelSelection(joyTag: joy, wdEva02: wd),
      );

      expect(calls, [joy.name, wd.name]);
      expect(result.hasSuccess, isTrue);
      expect(result.combinedPrompt, '1girl');
      expect(result.evidence.last.succeeded, isFalse);
      expect(result.auditText, contains('WD EVA02'));
    },
  );
}
