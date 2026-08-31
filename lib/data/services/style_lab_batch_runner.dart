import '../models/style_lab/style_lab_models.dart';

/// A single progress snapshot emitted by [StyleLabBatchRunner].
class StyleLabBatchProgress {
  const StyleLabBatchProgress({
    required this.variant,
    required this.attempted,
    required this.total,
    required this.succeeded,
  });

  final StyleLabVariant variant;
  final int attempted;
  final int total;
  final bool succeeded;

  double get fraction => total == 0 ? 1 : attempted / total;
}

/// Captures failures without stopping the rest of a batch.
class StyleLabBatchFailure {
  const StyleLabBatchFailure({required this.variant, required this.error});

  final StyleLabVariant variant;
  final Object error;
}

/// Deterministic, sequential batch orchestration for the style laboratory.
///
/// The runner deliberately knows nothing about image APIs or billing. The
/// caller supplies one generation callback, which makes ordering, retry and
/// cancellation behavior testable without sending paid requests.
class StyleLabBatchRunSummary {
  const StyleLabBatchRunSummary({
    required this.total,
    required this.completed,
    required this.failed,
    required this.cancelled,
    required this.failures,
  });

  final int total;
  final int completed;
  final int failed;
  final bool cancelled;
  final List<StyleLabBatchFailure> failures;

  int get attempted => completed + failed;
  bool get allCompleted => !cancelled && completed == total && failed == 0;
}

class StyleLabBatchRunner {
  const StyleLabBatchRunner();

  Future<StyleLabBatchRunSummary> run(
    Iterable<StyleLabVariant> variants, {
    required Future<bool> Function(StyleLabVariant variant) generate,
    bool Function()? shouldStop,
    void Function(StyleLabBatchProgress progress)? onProgress,
  }) async {
    final work = List<StyleLabVariant>.unmodifiable(variants);
    final failures = <StyleLabBatchFailure>[];
    var completed = 0;
    var failed = 0;
    var cancelled = false;

    for (final variant in work) {
      if (shouldStop?.call() ?? false) {
        cancelled = true;
        break;
      }

      var succeeded = false;
      try {
        succeeded = await generate(variant);
      } catch (error) {
        failures.add(StyleLabBatchFailure(variant: variant, error: error));
      }

      if (succeeded) {
        completed++;
      } else {
        failed++;
        if (failures.every((failure) => failure.variant.id != variant.id)) {
          failures.add(
            StyleLabBatchFailure(
              variant: variant,
              error: StateError('generation callback returned false'),
            ),
          );
        }
      }
      onProgress?.call(
        StyleLabBatchProgress(
          variant: variant,
          attempted: completed + failed,
          total: work.length,
          succeeded: succeeded,
        ),
      );
    }

    return StyleLabBatchRunSummary(
      total: work.length,
      completed: completed,
      failed: failed,
      cancelled: cancelled,
      failures: List<StyleLabBatchFailure>.unmodifiable(failures),
    );
  }
}
