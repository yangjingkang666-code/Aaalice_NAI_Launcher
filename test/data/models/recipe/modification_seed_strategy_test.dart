import 'package:flutter_test/flutter_test.dart';
import 'package:nai_launcher/data/models/image/image_params.dart';
import 'package:nai_launcher/data/models/recipe/modification_seed_strategy.dart';

void main() {
  const params = ImageParams(prompt: 'base', seed: 123);

  test('base strategy preserves the recipe seed', () {
    expect(
      ModificationSeedStrategyResolver.apply(
        params,
        ModificationSeedStrategy.base,
      ),
      params,
    );
  });

  test('random strategy leaves an explicit queue marker', () {
    final result = ModificationSeedStrategyResolver.apply(
      params,
      ModificationSeedStrategy.random,
    );
    expect(result.seed, -1);
  });

  test('specified strategy validates the full unsigned 32-bit range', () {
    expect(
      ModificationSeedStrategyResolver.apply(
        params,
        ModificationSeedStrategy.specified,
        specifiedSeed: 0xffffffff,
      ).seed,
      0xffffffff,
    );
    expect(
      () => ModificationSeedStrategyResolver.apply(
        params,
        ModificationSeedStrategy.specified,
        specifiedSeed: -1,
      ),
      throwsFormatException,
    );
    expect(
      () => ModificationSeedStrategyResolver.apply(
        params,
        ModificationSeedStrategy.specified,
        specifiedSeed: 0x100000000,
      ),
      throwsFormatException,
    );
  });
}
