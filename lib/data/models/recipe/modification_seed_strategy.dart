import 'dart:math';

import '../image/image_params.dart';

/// Explicit seed behavior for a recipe modification.
enum ModificationSeedStrategy { base, random, specified }

extension ModificationSeedStrategyLabel on ModificationSeedStrategy {
  String get label => switch (this) {
    ModificationSeedStrategy.base => '沿用基础图 Seed',
    ModificationSeedStrategy.random => '随机 Seed',
    ModificationSeedStrategy.specified => '指定 Seed',
  };
}

abstract final class ModificationSeedStrategyResolver {
  static const int maxSeed = 0xffffffff;

  static ImageParams apply(
    ImageParams params,
    ModificationSeedStrategy strategy, {
    int? specifiedSeed,
  }) {
    switch (strategy) {
      case ModificationSeedStrategy.base:
        return params;
      case ModificationSeedStrategy.random:
        // -1 is intentionally kept in the editor. Queue insertion materializes
        // it once, so retries reuse one seed instead of silently changing it.
        return params.copyWith(seed: -1);
      case ModificationSeedStrategy.specified:
        final seed = specifiedSeed;
        if (seed == null || seed < 0 || seed > maxSeed) {
          throw const FormatException(
            'Specified Seed must be between 0 and 4294967295.',
          );
        }
        return params.copyWith(seed: seed);
    }
  }

  static int createRandomSeed() => Random.secure().nextInt(maxSeed + 1);
}
