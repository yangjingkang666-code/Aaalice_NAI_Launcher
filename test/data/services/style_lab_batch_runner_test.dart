import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/data/models/image/image_params.dart';
import 'package:nai_launcher/data/models/style_lab/style_lab_models.dart';
import 'package:nai_launcher/data/services/style_lab_batch_runner.dart';
import 'package:nai_launcher/data/services/style_lab_service.dart';

void main() {
  StyleLabVariant variant(String id) => StyleLabVariant(
    id: id,
    kind: StyleLabVariantKind.plain,
    prompt: id,
    artistPrompt: 'artist:$id',
    mutationPrompt: '',
    seed: 1,
    createdAt: DateTime.utc(2026),
  );

  test(
    'runs a generated artist chain sequentially and reports progress',
    () async {
      final session = StyleLabSession.initial(const ImageParams()).copyWith(
        basePrompt: 'subject',
        pairCount: 6,
        minArtists: 2,
        maxArtists: 4,
        drawSeed: 99,
      );
      final pairs = StyleLabService().generatePairs(session);
      final seen = <String>[];
      final progress = <StyleLabBatchProgress>[];

      final summary = await const StyleLabBatchRunner().run(
        [for (final pair in pairs) ...pair.variants],
        generate: (item) async {
          seen.add(item.id);
          return true;
        },
        onProgress: progress.add,
      );

      expect(summary.total, 12);
      expect(summary.attempted, 12);
      expect(summary.completed, 12);
      expect(summary.failed, 0);
      expect(summary.allCompleted, isTrue);
      expect(summary.cancelled, isFalse);
      expect(seen, hasLength(12));
      expect(
        progress.map((item) => item.attempted),
        orderedEquals([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]),
      );
      expect(progress.last.fraction, 1);
    },
  );

  test(
    'keeps going after a failed variant and preserves the failure',
    () async {
      final first = variant('first');
      final second = variant('second');
      final third = variant('third');
      final summary = await const StyleLabBatchRunner().run([
        first,
        second,
        third,
      ], generate: (item) async => item.id != second.id);

      expect(summary.completed, 2);
      expect(summary.failed, 1);
      expect(summary.cancelled, isFalse);
      expect(summary.failures.single.variant.id, second.id);
    },
  );

  test(
    'stops before the next paid request when cancellation is requested',
    () async {
      final calls = <String>[];
      var stop = false;
      final summary = await const StyleLabBatchRunner().run(
        [variant('one'), variant('two'), variant('three')],
        generate: (item) async {
          calls.add(item.id);
          stop = true;
          return true;
        },
        shouldStop: () => stop,
      );

      expect(calls, ['one']);
      expect(summary.completed, 1);
      expect(summary.failed, 0);
      expect(summary.cancelled, isTrue);
      expect(summary.allCompleted, isFalse);
    },
  );
}
