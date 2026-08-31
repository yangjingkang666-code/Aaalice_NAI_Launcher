import 'dart:io';

import 'package:flutter/material.dart';

import '../../../data/models/style_lab/style_lab_models.dart';
import '../../providers/generation/generation_models.dart';
import 'style_lab_copy.dart';

class StyleLabControls extends StatelessWidget {
  const StyleLabControls({
    super.key,
    required this.copy,
    required this.baseController,
    required this.auxiliaryController,
    required this.artistController,
    required this.styleController,
    required this.fixedSeedController,
    required this.pairCount,
    required this.artistRange,
    required this.artistWeightRange,
    required this.styleRange,
    required this.mutateStyles,
    required this.seedMode,
    required this.isBusy,
    required this.onPairCountChanged,
    required this.onArtistRangeChanged,
    required this.onArtistWeightChanged,
    required this.onStyleRangeChanged,
    required this.onMutateChanged,
    required this.onSeedModeChanged,
    required this.onDraw,
    required this.onGenerateAll,
    required this.onStop,
    required this.onSyncParams,
    required this.onUseDefaults,
    required this.onLoadLocalArtists,
    this.onFormChanged,
  });

  final StyleLabCopy copy;
  final TextEditingController baseController;
  final TextEditingController auxiliaryController;
  final TextEditingController artistController;
  final TextEditingController styleController;
  final TextEditingController fixedSeedController;
  final int pairCount;
  final RangeValues artistRange;
  final RangeValues artistWeightRange;
  final RangeValues styleRange;
  final bool mutateStyles;
  final StyleLabSeedMode seedMode;
  final bool isBusy;
  final ValueChanged<int> onPairCountChanged;
  final ValueChanged<RangeValues> onArtistRangeChanged;
  final ValueChanged<RangeValues> onArtistWeightChanged;
  final ValueChanged<RangeValues> onStyleRangeChanged;
  final ValueChanged<bool> onMutateChanged;
  final ValueChanged<StyleLabSeedMode> onSeedModeChanged;
  final VoidCallback onDraw;
  final VoidCallback onGenerateAll;
  final VoidCallback onStop;
  final VoidCallback onSyncParams;
  final VoidCallback onUseDefaults;
  final VoidCallback onLoadLocalArtists;
  final VoidCallback? onFormChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(copy.basePrompt, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            TextField(
              controller: baseController,
              minLines: 3,
              maxLines: 6,
              textInputAction: TextInputAction.newline,
              decoration: const InputDecoration(
                border: InputBorder.none,
                filled: true,
              ),
              onChanged: (_) => onFormChanged?.call(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: auxiliaryController,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: copy.auxiliaryPrompt,
                border: InputBorder.none,
                filled: true,
              ),
              onChanged: (_) => onFormChanged?.call(),
            ),
            const SizedBox(height: 16),
            _SectionLabel(label: copy.artistPool),
            const SizedBox(height: 4),
            Text(copy.artistPoolHint, style: theme.textTheme.bodySmall),
            const SizedBox(height: 6),
            TextField(
              controller: artistController,
              minLines: 4,
              maxLines: 8,
              decoration: const InputDecoration(
                border: InputBorder.none,
                filled: true,
              ),
              onChanged: (_) => onFormChanged?.call(),
            ),
            const SizedBox(height: 16),
            _SectionLabel(label: copy.stylePool),
            const SizedBox(height: 4),
            Text(copy.stylePoolHint, style: theme.textTheme.bodySmall),
            const SizedBox(height: 6),
            TextField(
              controller: styleController,
              minLines: 4,
              maxLines: 9,
              decoration: const InputDecoration(
                border: InputBorder.none,
                filled: true,
              ),
              onChanged: (_) => onFormChanged?.call(),
            ),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 4,
              children: [
                TextButton.icon(
                  onPressed: onLoadLocalArtists,
                  icon: const Icon(Icons.storage_outlined, size: 16),
                  label: Text(copy.loadLocalArtists),
                ),
                TextButton.icon(
                  onPressed: onUseDefaults,
                  icon: const Icon(Icons.auto_awesome, size: 16),
                  label: Text(copy.poolDefaults),
                ),
              ],
            ),
            const Divider(height: 20),
            _SliderSetting(
              label: copy.pairCount,
              valueLabel: '$pairCount',
              child: Slider(
                value: pairCount.toDouble(),
                min: 1,
                max: 12,
                divisions: 11,
                label: '$pairCount',
                onChanged: (value) => onPairCountChanged(value.round()),
              ),
            ),
            _RangeSetting(
              label: copy.artistCount,
              values: artistRange,
              min: 1,
              max: 8,
              divisions: 7,
              valueLabel:
                  '${artistRange.start.round()}–${artistRange.end.round()}',
              onChanged: onArtistRangeChanged,
            ),
            _RangeSetting(
              label: copy.artistWeight,
              values: artistWeightRange,
              min: 0.1,
              max: 2,
              divisions: 19,
              valueLabel:
                  '${artistWeightRange.start.toStringAsFixed(1)}–${artistWeightRange.end.toStringAsFixed(1)}',
              onChanged: onArtistWeightChanged,
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: Text(copy.mutateStyles),
              subtitle: Text(copy.mutateHint),
              value: mutateStyles,
              onChanged: onMutateChanged,
            ),
            if (mutateStyles)
              _RangeSetting(
                label: copy.styleCount,
                values: styleRange,
                min: 0,
                max: 8,
                divisions: 8,
                valueLabel:
                    '${styleRange.start.round()}–${styleRange.end.round()}',
                onChanged: onStyleRangeChanged,
              ),
            const SizedBox(height: 4),
            Text(copy.seedMode, style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            SegmentedButton<StyleLabSeedMode>(
              segments: [
                ButtonSegment(
                  value: StyleLabSeedMode.randomPerPair,
                  icon: const Icon(Icons.casino_outlined),
                  label: Text(copy.randomSeed),
                ),
                ButtonSegment(
                  value: StyleLabSeedMode.fixed,
                  icon: const Icon(Icons.lock_outline),
                  label: Text(copy.fixedSeed),
                ),
              ],
              selected: {seedMode},
              onSelectionChanged: (selection) {
                if (selection.isNotEmpty) onSeedModeChanged(selection.first);
              },
            ),
            if (seedMode == StyleLabSeedMode.fixed) ...[
              const SizedBox(height: 8),
              TextField(
                controller: fixedSeedController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: copy.fixedSeedHint,
                  border: InputBorder.none,
                  filled: true,
                ),
                onChanged: (_) => onFormChanged?.call(),
              ),
            ],
            const SizedBox(height: 12),
            Text(copy.settingsNote, style: theme.textTheme.bodySmall),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: isBusy ? null : onSyncParams,
              icon: const Icon(Icons.sync),
              label: Text(copy.syncParams),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: isBusy ? null : onDraw,
                    icon: const Icon(Icons.casino),
                    label: Text(copy.draw),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: isBusy ? null : onGenerateAll,
                    icon: const Icon(Icons.auto_awesome),
                    label: Text(copy.generateBatch),
                  ),
                ),
              ],
            ),
            if (isBusy) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: onStop,
                icon: const Icon(Icons.stop_circle_outlined),
                label: Text(copy.stop),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class StyleLabResultsView extends StatelessWidget {
  const StyleLabResultsView({
    super.key,
    required this.copy,
    required this.pairs,
    required this.favorites,
    required this.images,
    required this.favoriteIds,
    required this.onGenerate,
    required this.onToggleFavorite,
    required this.onApply,
    required this.onApplyFavorite,
    required this.onCopy,
    required this.onPreview,
    required this.onRemoveFavorite,
  });

  final StyleLabCopy copy;
  final List<StyleLabPair> pairs;
  final List<StyleLabFavorite> favorites;
  final Map<String, GeneratedImage> images;
  final Set<String> favoriteIds;
  final ValueChanged<StyleLabVariant> onGenerate;
  final ValueChanged<StyleLabVariant> onToggleFavorite;
  final ValueChanged<StyleLabVariant> onApply;
  final ValueChanged<StyleLabFavorite> onApplyFavorite;
  final ValueChanged<String> onCopy;
  final ValueChanged<GeneratedImage> onPreview;
  final ValueChanged<StyleLabFavorite> onRemoveFavorite;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ResultsHeader(copy: copy, count: pairs.length),
        if (pairs.isEmpty)
          _EmptyState(icon: Icons.casino_outlined, text: copy.emptyResults)
        else
          for (var index = 0; index < pairs.length; index++)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _PairCard(
                copy: copy,
                index: index,
                pair: pairs[index],
                images: images,
                favoriteIds: favoriteIds,
                onGenerate: onGenerate,
                onToggleFavorite: onToggleFavorite,
                onApply: onApply,
                onCopy: onCopy,
                onPreview: onPreview,
              ),
            ),
        const SizedBox(height: 12),
        _FavoritesSection(
          copy: copy,
          favorites: favorites,
          onApply: onApplyFavorite,
          onCopy: onCopy,
          onRemove: onRemoveFavorite,
        ),
      ],
    );
  }
}

class _PairCard extends StatelessWidget {
  const _PairCard({
    required this.copy,
    required this.index,
    required this.pair,
    required this.images,
    required this.favoriteIds,
    required this.onGenerate,
    required this.onToggleFavorite,
    required this.onApply,
    required this.onCopy,
    required this.onPreview,
  });

  final StyleLabCopy copy;
  final int index;
  final StyleLabPair pair;
  final Map<String, GeneratedImage> images;
  final Set<String> favoriteIds;
  final ValueChanged<StyleLabVariant> onGenerate;
  final ValueChanged<StyleLabVariant> onToggleFavorite;
  final ValueChanged<StyleLabVariant> onApply;
  final ValueChanged<String> onCopy;
  final ValueChanged<GeneratedImage> onPreview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final artistLabels = pair.artists.map((artist) => artist.name).toList();
    final mutationLabels = pair.mutations
        .map((token) => token.value)
        .where((value) => value.isNotEmpty)
        .toList();
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    copy.pair(index),
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                Text(
                  '${copy.seed}: ${pair.seed}',
                  style: theme.textTheme.labelMedium,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final label in artistLabels)
                  Chip(
                    avatar: const Icon(Icons.brush_outlined, size: 15),
                    label: Text(label),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            if (mutationLabels.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                mutationLabels.join(' · '),
                style: theme.textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, constraints) {
                final sideBySide = constraints.maxWidth >= 680;
                final cards = [
                  for (final variant in pair.variants)
                    _VariantCard(
                      copy: copy,
                      variant: variant,
                      image: images[variant.id],
                      isFavorite: favoriteIds.contains(variant.id),
                      onGenerate: () => onGenerate(variant),
                      onToggleFavorite: () => onToggleFavorite(variant),
                      onApply: () => onApply(variant),
                      onCopy: () => onCopy(variant.prompt),
                      onPreview: images[variant.id] == null
                          ? null
                          : () => onPreview(images[variant.id]!),
                    ),
                ];
                if (sideBySide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: cards[0]),
                      const SizedBox(width: 10),
                      Expanded(child: cards[1]),
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [cards[0], const SizedBox(height: 10), cards[1]],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _VariantCard extends StatelessWidget {
  const _VariantCard({
    required this.copy,
    required this.variant,
    required this.image,
    required this.isFavorite,
    required this.onGenerate,
    required this.onToggleFavorite,
    required this.onApply,
    required this.onCopy,
    required this.onPreview,
  });

  final StyleLabCopy copy;
  final StyleLabVariant variant;
  final GeneratedImage? image;
  final bool isFavorite;
  final VoidCallback onGenerate;
  final VoidCallback onToggleFavorite;
  final VoidCallback onApply;
  final VoidCallback onCopy;
  final VoidCallback? onPreview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final imagePath = variant.imagePath;
    final hasPath = imagePath != null && imagePath.isNotEmpty;
    final title = variant.kind == StyleLabVariantKind.plain
        ? copy.plain
        : copy.mutated;
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: theme.textTheme.titleSmall)),
              _StatusChip(copy: copy, status: variant.status),
            ],
          ),
          const SizedBox(height: 8),
          if (image != null)
            _ImagePreview(image: image!, onTap: onPreview)
          else if (hasPath)
            _FilePreview(path: imagePath, onTap: onPreview)
          else
            Container(
              height: 128,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                variant.status == StyleLabResultStatus.generating
                    ? Icons.hourglass_top
                    : Icons.image_outlined,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          const SizedBox(height: 8),
          SelectableText(
            variant.prompt,
            maxLines: 5,
            style: theme.textTheme.bodySmall,
          ),
          if (variant.error != null) ...[
            const SizedBox(height: 4),
            Text(
              variant.error!,
              style: TextStyle(color: theme.colorScheme.error),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 4),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 2,
            children: [
              IconButton(
                tooltip: copy.copyPrompt,
                onPressed: onCopy,
                icon: const Icon(Icons.copy_outlined, size: 19),
              ),
              IconButton(
                tooltip: copy.apply,
                onPressed: onApply,
                icon: const Icon(Icons.north_east_rounded, size: 19),
              ),
              IconButton(
                tooltip: copy.favorite,
                onPressed: onToggleFavorite,
                icon: Icon(
                  isFavorite ? Icons.favorite : Icons.favorite_border,
                  size: 19,
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: onGenerate,
                icon: Icon(
                  variant.status == StyleLabResultStatus.failed
                      ? Icons.refresh
                      : Icons.auto_awesome,
                  size: 17,
                ),
                label: Text(
                  variant.status == StyleLabResultStatus.failed
                      ? copy.retry
                      : copy.generate,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ImagePreview extends StatelessWidget {
  const _ImagePreview({required this.image, required this.onTap});

  final GeneratedImage image;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: image.width / image.height,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.memory(image.bytes, fit: BoxFit.cover),
        ),
      ),
    );
  }
}

class _FilePreview extends StatelessWidget {
  const _FilePreview({required this.path, required this.onTap});

  final String path;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(
            File(path),
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) =>
                const Center(child: Icon(Icons.broken_image_outlined)),
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.copy, required this.status});

  final StyleLabCopy copy;
  final StyleLabResultStatus status;

  @override
  Widget build(BuildContext context) {
    final label = switch (status) {
      StyleLabResultStatus.pending => copy.pending,
      StyleLabResultStatus.generating => copy.generating,
      StyleLabResultStatus.completed => copy.completed,
      StyleLabResultStatus.failed => copy.failed,
    };
    return Chip(
      label: Text(label),
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
    );
  }
}

class _ResultsHeader extends StatelessWidget {
  const _ResultsHeader({required this.copy, required this.count});

  final StyleLabCopy copy;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              copy.results,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          if (count > 0) Chip(label: Text('$count')),
        ],
      ),
    );
  }
}

class _FavoritesSection extends StatelessWidget {
  const _FavoritesSection({
    required this.copy,
    required this.favorites,
    required this.onApply,
    required this.onCopy,
    required this.onRemove,
  });

  final StyleLabCopy copy;
  final List<StyleLabFavorite> favorites;
  final ValueChanged<StyleLabFavorite> onApply;
  final ValueChanged<String> onCopy;
  final ValueChanged<StyleLabFavorite> onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      child: ExpansionTile(
        initiallyExpanded: favorites.isNotEmpty,
        title: Text(copy.favorites),
        subtitle: Text(
          favorites.isEmpty ? copy.emptyFavorites : '${favorites.length}',
        ),
        children: [
          if (favorites.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(copy.emptyFavorites),
              ),
            )
          else
            for (final favorite in favorites)
              ListTile(
                dense: true,
                leading: Icon(
                  favorite.kind == StyleLabVariantKind.mutated
                      ? Icons.auto_awesome
                      : Icons.brush_outlined,
                ),
                title: Text(
                  favorite.artistPrompt,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  favorite.prompt,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Wrap(
                  spacing: 0,
                  children: [
                    IconButton(
                      tooltip: copy.copyPrompt,
                      onPressed: () => onCopy(favorite.prompt),
                      icon: const Icon(Icons.copy_outlined, size: 18),
                    ),
                    IconButton(
                      tooltip: copy.apply,
                      onPressed: () => onApply(favorite),
                      icon: const Icon(Icons.north_east_rounded, size: 18),
                    ),
                    IconButton(
                      tooltip: copy.remove,
                      onPressed: () => onRemove(favorite),
                      icon: const Icon(Icons.delete_outline, size: 18),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(label, style: Theme.of(context).textTheme.titleMedium);
  }
}

class _SliderSetting extends StatelessWidget {
  const _SliderSetting({
    required this.label,
    required this.valueLabel,
    required this.child,
  });

  final String label;
  final String valueLabel;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(label)),
            Text(valueLabel, style: Theme.of(context).textTheme.labelMedium),
          ],
        ),
        child,
      ],
    );
  }
}

class _RangeSetting extends StatelessWidget {
  const _RangeSetting({
    required this.label,
    required this.values,
    required this.min,
    required this.max,
    required this.divisions,
    required this.valueLabel,
    required this.onChanged,
  });

  final String label;
  final RangeValues values;
  final double min;
  final double max;
  final int divisions;
  final String valueLabel;
  final ValueChanged<RangeValues> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(label)),
            Text(valueLabel, style: Theme.of(context).textTheme.labelMedium),
          ],
        ),
        RangeSlider(
          values: values,
          min: min,
          max: max,
          divisions: divisions,
          labels: RangeLabels(valueLabel, valueLabel),
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(28),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 36),
          const SizedBox(height: 10),
          Text(text, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
