import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/autocomplete/autocomplete_providers.dart';
import '../../../data/models/image/image_params.dart';
import '../../../data/models/style_lab/style_lab_models.dart';
import '../../../data/services/style_lab_batch_runner.dart';
import '../../../data/services/style_lab_service.dart';
import '../../../data/services/style_lab_storage_service.dart';
import '../../providers/image_generation_provider.dart';
import '../../router/app_routes.dart';
import '../../widgets/common/app_toast.dart';
import 'style_lab_copy.dart';
import 'style_lab_widgets.dart';

/// Manual artist-chain style laboratory.
///
/// It intentionally keeps the experiment inspectable: drawing only creates
/// prompt pairs, while image generation happens after an explicit action on a
/// pair or on the whole batch.
class StyleLabScreen extends ConsumerStatefulWidget {
  const StyleLabScreen({super.key});

  @override
  ConsumerState<StyleLabScreen> createState() => _StyleLabScreenState();
}

class _StyleLabScreenState extends ConsumerState<StyleLabScreen> {
  final _baseController = TextEditingController();
  final _auxiliaryController = TextEditingController();
  final _artistController = TextEditingController();
  final _styleController = TextEditingController();
  final _fixedSeedController = TextEditingController(text: '123456');
  final _styleLabService = StyleLabService();
  static const _batchRunner = StyleLabBatchRunner();

  StyleLabSession? _session;
  final Map<String, GeneratedImage> _images = <String, GeneratedImage>{};
  int _pairCount = 4;
  RangeValues _artistRange = const RangeValues(2, 4);
  RangeValues _artistWeightRange = const RangeValues(0.65, 1.15);
  RangeValues _styleRange = const RangeValues(2, 4);
  bool _mutateStyles = true;
  StyleLabSeedMode _seedMode = StyleLabSeedMode.randomPerPair;
  bool _loading = true;
  bool _busy = false;
  bool _cancelRequested = false;
  Timer? _formPersistTimer;
  Future<void>? _persistInFlight;

  @override
  void initState() {
    super.initState();
    final params = ref.read(generationParamsNotifierProvider);
    _baseController.text = params.prompt;
    unawaited(_loadSession(params));
  }

  @override
  void dispose() {
    _baseController.dispose();
    _auxiliaryController.dispose();
    _artistController.dispose();
    _styleController.dispose();
    _fixedSeedController.dispose();
    _formPersistTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadSession(ImageParams currentParams) async {
    final loaded = await ref.read(styleLabStorageServiceProvider).load();
    if (!mounted) return;
    final session = loaded ?? StyleLabSession.initial(currentParams);
    _session = session;
    _baseController.text = session.basePrompt;
    _auxiliaryController.text = session.auxiliaryPrompt;
    _artistController.text = session.artistPool;
    _styleController.text = session.stylePool;
    _fixedSeedController.text = session.fixedSeed.toString();
    _pairCount = session.pairCount.clamp(1, 12);
    _artistRange = _safeRange(
      session.minArtists.toDouble(),
      session.maxArtists.toDouble(),
      1,
      8,
    );
    _artistWeightRange = _safeRange(
      session.artistWeightMin,
      session.artistWeightMax,
      0.1,
      2,
    );
    _styleRange = _safeRange(
      session.minStyleTokens.toDouble(),
      session.maxStyleTokens.toDouble(),
      0,
      8,
    );
    _mutateStyles = session.mutateStyles;
    _seedMode = session.seedMode;
    setState(() => _loading = false);
  }

  RangeValues _safeRange(
    double start,
    double end,
    double minValue,
    double maxValue,
  ) {
    final low = start.clamp(minValue, maxValue).toDouble();
    final high = end.clamp(minValue, maxValue).toDouble();
    return RangeValues(low, high < low ? low : high);
  }

  StyleLabSession _formSession({List<StyleLabPair>? pairs}) {
    final current =
        _session ??
        StyleLabSession.initial(ref.read(generationParamsNotifierProvider));
    final fixedSeed =
        int.tryParse(_fixedSeedController.text.trim()) ?? current.fixedSeed;
    final generationParams = current.generationParams.copyWith(
      prompt: _baseController.text.trim(),
    );
    return current.copyWith(
      basePrompt: _baseController.text.trim(),
      auxiliaryPrompt: _auxiliaryController.text.trim(),
      artistPool: _artistController.text,
      stylePool: _styleController.text,
      pairCount: _pairCount,
      minArtists: _artistRange.start.round(),
      maxArtists: _artistRange.end.round(),
      artistWeightMin: _artistWeightRange.start,
      artistWeightMax: _artistWeightRange.end,
      mutateStyles: _mutateStyles,
      minStyleTokens: _styleRange.start.round(),
      maxStyleTokens: _styleRange.end.round(),
      seedMode: _seedMode,
      fixedSeed: fixedSeed,
      pairs: pairs,
      generationParams: generationParams,
    );
  }

  void _setSession(StyleLabSession session, {bool persist = true}) {
    if (!mounted) return;
    setState(() => _session = session);
    if (persist) _queuePersist(session);
  }

  void _queuePersist(StyleLabSession session) {
    final previous = _persistInFlight ?? Future<void>.value();
    _persistInFlight = previous
        .then((_) => ref.read(styleLabStorageServiceProvider).save(session))
        .catchError((_) {});
  }

  void _onPairCountChanged(int value) {
    setState(() => _pairCount = value);
    _scheduleFormPersist();
  }

  void _onArtistRangeChanged(RangeValues values) {
    setState(() => _artistRange = values);
    _scheduleFormPersist();
  }

  void _onArtistWeightChanged(RangeValues values) {
    setState(() => _artistWeightRange = values);
    _scheduleFormPersist();
  }

  void _onStyleRangeChanged(RangeValues values) {
    setState(() => _styleRange = values);
    _scheduleFormPersist();
  }

  void _onSeedModeChanged(StyleLabSeedMode mode) {
    setState(() => _seedMode = mode);
    _scheduleFormPersist();
  }

  void _onMutateChanged(bool value) {
    setState(() => _mutateStyles = value);
    _scheduleFormPersist();
  }

  void _onUseDefaults() {
    _artistController.text = StyleLabService.defaultArtists
        .map((artist) => 'artist:${artist.name}|${artist.postCount}')
        .join('\n');
    _styleController.text = StyleLabService.defaultStylePool
        .map((item) => '${item.mode.name}|${item.category.name}|${item.value}')
        .join('\n');
    setState(() {});
    _scheduleFormPersist();
  }

  Future<void> _onLoadLocalArtists() async {
    if (_busy) return;
    final copy = StyleLabCopy.of(context);
    try {
      final records = await ref
          .read(tagCatalogRepositoryProvider)
          .popularArtists(limit: 500);
      if (!mounted) return;
      if (records.isEmpty) {
        AppToast.warning(context, copy.localArtistsUnavailable);
        return;
      }
      _artistController.text = records
          .map((record) => 'artist:${record.canonicalTag}|${record.postCount}')
          .join('\n');
      _scheduleFormPersist();
      AppToast.success(context, copy.localArtistsReady);
    } catch (_) {
      if (mounted) AppToast.warning(context, copy.localArtistsUnavailable);
    }
  }

  void _scheduleFormPersist() {
    _formPersistTimer?.cancel();
    _formPersistTimer = Timer(const Duration(milliseconds: 450), () {
      final session = _session;
      if (!mounted || session == null) return;
      _setSession(_formSession(pairs: session.pairs));
    });
  }

  void _onSyncParams() {
    final live = ref.read(generationParamsNotifierProvider);
    final session = _formSession().copyWith(
      generationParams: live.copyWith(prompt: _baseController.text.trim()),
    );
    _setSession(session);
    _showInfo(StyleLabCopy.of(context).syncParams);
  }

  void _onDraw() {
    final copy = StyleLabCopy.of(context);
    if (_baseController.text.trim().isEmpty) {
      AppToast.warning(context, copy.needPrompt);
      return;
    }
    final current = _formSession();
    final pairs = _styleLabService.generatePairs(current);
    _images.clear();
    _setSession(
      current.copyWith(
        pairs: pairs,
        // A new draw has a new random stream while still being reproducible
        // when the user records the draw seed in the session JSON.
        drawSeed: current.drawSeed + 1,
      ),
    );
    _showInfo(copy.drawDone);
  }

  Future<void> _onGenerateAll() async {
    final copy = StyleLabCopy.of(context);
    if (_session?.pairs.isEmpty ?? true) {
      _onDraw();
      if (_session?.pairs.isEmpty ?? true) return;
    }
    if (_busy) return;
    if (ref.read(imageGenerationNotifierProvider).isGenerating) {
      AppToast.warning(context, copy.generationBusy);
      return;
    }
    setState(() {
      _busy = true;
      _cancelRequested = false;
    });
    try {
      final variants = [for (final pair in _session!.pairs) ...pair.variants];
      final summary = await _batchRunner.run(
        variants,
        generate: (variant) async {
          await _generateVariant(variant, fromBatch: true);
          return _session?.pairs
                  .expand((pair) => pair.variants)
                  .firstWhere(
                    (candidate) => candidate.id == variant.id,
                    orElse: () => variant,
                  )
                  .status ==
              StyleLabResultStatus.completed;
        },
        shouldStop: () => _cancelRequested,
      );
      if (mounted) {
        _showInfo(
          summary.cancelled || _cancelRequested ? copy.stopped : copy.batchDone,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _generateVariant(
    StyleLabVariant variant, {
    bool fromBatch = false,
  }) async {
    final copy = StyleLabCopy.of(context);
    if (!fromBatch && _busy) return;
    if (!fromBatch && ref.read(imageGenerationNotifierProvider).isGenerating) {
      AppToast.warning(context, copy.generationBusy);
      return;
    }
    _replaceVariant(
      variant.id,
      variant.copyWith(
        status: StyleLabResultStatus.generating,
        clearError: true,
      ),
    );
    final params = _paramsForVariant(variant);
    final beforeIds = {
      ...ref
          .read(imageGenerationNotifierProvider)
          .displayImages
          .map((image) => image.id),
      ...ref
          .read(imageGenerationNotifierProvider)
          .currentImages
          .map((image) => image.id),
    };
    try {
      await ref
          .read(imageGenerationNotifierProvider.notifier)
          .generate(params, batchSizeOverride: 1);
      final state = ref.read(imageGenerationNotifierProvider);
      GeneratedImage? image;
      for (final candidate in [
        ...state.currentImages,
        ...state.displayImages,
      ]) {
        if (!beforeIds.contains(candidate.id)) {
          image = candidate;
          break;
        }
      }
      if (image == null) {
        throw StateError(state.errorMessage ?? copy.failed);
      }
      _images[variant.id] = image;
      _replaceVariant(
        variant.id,
        variant.copyWith(
          status: StyleLabResultStatus.completed,
          imageId: image.id,
          imagePath: image.filePath,
          recipeId: image.recipeId,
          clearError: true,
        ),
      );
    } catch (error) {
      _replaceVariant(
        variant.id,
        variant.copyWith(status: StyleLabResultStatus.failed, error: '$error'),
      );
      if (!fromBatch && mounted) AppToast.error(context, '$error');
    }
  }

  ImageParams _paramsForVariant(StyleLabVariant variant) {
    final ImageParams base =
        _session?.generationParams ??
        ref.read(generationParamsNotifierProvider);
    return base.copyWith(
      prompt: variant.prompt,
      seed: variant.seed,
      nSamples: 1,
      action: ImageGenerationAction.generate,
      sourceImage: null,
      maskImage: null,
      characters: const [],
      vibeReferencesV4: const [],
      preciseReferences: const [],
      upscaledEnhance: false,
      isEnhanceRequest: false,
      isOutpaint: false,
      inpaintMaskClosingIterations: 0,
      inpaintMaskExpansionIterations: 0,
    );
  }

  void _replaceVariant(String variantId, StyleLabVariant replacement) {
    final session = _session;
    if (session == null || !mounted) return;
    final pairs = [
      for (final pair in session.pairs)
        pair.copyWith(
          variants: [
            for (final variant in pair.variants)
              variant.id == variantId ? replacement : variant,
          ],
        ),
    ];
    _setSession(session.copyWith(pairs: pairs));
  }

  Future<void> _toggleFavorite(StyleLabVariant variant) async {
    var session = _session;
    if (session == null) return;
    final existing = session.favorites
        .where((favorite) => favorite.variantId == variant.id)
        .firstOrNull;
    if (existing != null) {
      _setSession(
        session.copyWith(
          favorites: session.favorites
              .where((favorite) => favorite.id != existing.id)
              .toList(growable: false),
        ),
      );
      return;
    }

    var image = _images[variant.id];
    if (image == null && variant.imagePath == null) {
      AppToast.info(context, StyleLabCopy.of(context).needGeneratedImage);
      return;
    }
    if (image != null && image.filePath == null) {
      final saved = await ref
          .read(imageGenerationNotifierProvider.notifier)
          .saveImagesForStyleLab([image], _paramsForVariant(variant));
      if (saved.isNotEmpty) {
        image = saved.first;
        _images[variant.id] = image;
        variant = variant.copyWith(imagePath: image.filePath);
        _replaceVariant(variant.id, variant);
        session = _session;
        if (session == null) return;
      }
    }
    final favorite = StyleLabFavorite.fromVariant(
      variant,
      model: session.generationParams.model,
      imageId: image?.id,
      imagePath: image?.filePath ?? variant.imagePath,
      recipeId: image?.recipeId ?? variant.recipeId,
    );
    _setSession(session.copyWith(favorites: [favorite, ...session.favorites]));
  }

  void _removeFavorite(StyleLabFavorite favorite) {
    final session = _session;
    if (session == null) return;
    _setSession(
      session.copyWith(
        favorites: session.favorites
            .where((item) => item.id != favorite.id)
            .toList(growable: false),
      ),
    );
  }

  void _applyVariant(StyleLabVariant variant) {
    _applyPrompt(variant.prompt, variant.seed);
  }

  void _applyFavorite(StyleLabFavorite favorite) {
    _applyPrompt(favorite.prompt, favorite.seed, model: favorite.model);
  }

  void _applyPrompt(String prompt, int seed, {String? model}) {
    final notifier = ref.read(generationParamsNotifierProvider.notifier);
    notifier.updatePrompt(prompt);
    notifier.updateSeed(seed);
    if (model != null && model.isNotEmpty) {
      notifier.updateModel(model, followDefaults: false);
    }
    final copy = StyleLabCopy.of(context);
    AppToast.success(context, copy.applied);
    context.go(AppRoutes.home);
  }

  Future<void> _copyPrompt(String prompt) async {
    await Clipboard.setData(ClipboardData(text: prompt));
    if (mounted) _showInfo(StyleLabCopy.of(context).copied);
  }

  void _preview(GeneratedImage image) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 4,
          child: Image.memory(image.bytes, fit: BoxFit.contain),
        ),
      ),
    );
  }

  void _onStop() {
    _cancelRequested = true;
    ref.read(imageGenerationNotifierProvider.notifier).cancel();
  }

  void _showInfo(String message) {
    if (!mounted) return;
    AppToast.info(context, message);
  }

  @override
  Widget build(BuildContext context) {
    final copy = StyleLabCopy.of(context);
    final session = _session;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(copy.title),
            Text(copy.subtitle, style: Theme.of(context).textTheme.labelSmall),
          ],
        ),
      ),
      body: _loading || session == null
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(
              builder: (context, constraints) {
                final controls = StyleLabControls(
                  copy: copy,
                  baseController: _baseController,
                  auxiliaryController: _auxiliaryController,
                  artistController: _artistController,
                  styleController: _styleController,
                  fixedSeedController: _fixedSeedController,
                  pairCount: _pairCount,
                  artistRange: _artistRange,
                  artistWeightRange: _artistWeightRange,
                  styleRange: _styleRange,
                  mutateStyles: _mutateStyles,
                  seedMode: _seedMode,
                  isBusy: _busy,
                  onPairCountChanged: _onPairCountChanged,
                  onArtistRangeChanged: _onArtistRangeChanged,
                  onArtistWeightChanged: _onArtistWeightChanged,
                  onStyleRangeChanged: _onStyleRangeChanged,
                  onMutateChanged: _onMutateChanged,
                  onSeedModeChanged: _onSeedModeChanged,
                  onDraw: _onDraw,
                  onGenerateAll: _onGenerateAll,
                  onStop: _onStop,
                  onSyncParams: _onSyncParams,
                  onUseDefaults: _onUseDefaults,
                  onLoadLocalArtists: _onLoadLocalArtists,
                  onFormChanged: _scheduleFormPersist,
                );
                final results = StyleLabResultsView(
                  copy: copy,
                  pairs: session.pairs,
                  favorites: session.favorites,
                  images: _images,
                  favoriteIds: session.favorites
                      .map((favorite) => favorite.variantId)
                      .toSet(),
                  onGenerate: (variant) => unawaited(_generateVariant(variant)),
                  onToggleFavorite: (variant) =>
                      unawaited(_toggleFavorite(variant)),
                  onApply: _applyVariant,
                  onApplyFavorite: _applyFavorite,
                  onCopy: (prompt) => unawaited(_copyPrompt(prompt)),
                  onPreview: _preview,
                  onRemoveFavorite: _removeFavorite,
                );
                if (constraints.maxWidth >= 1040) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 390,
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(20, 20, 12, 28),
                          child: controls,
                        ),
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(12, 20, 20, 28),
                          child: results,
                        ),
                      ),
                    ],
                  );
                }
                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(12, 16, 12, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [controls, const SizedBox(height: 20), results],
                  ),
                );
              },
            ),
    );
  }
}
