import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/localization_extension.dart';
import '../../../../core/utils/vibe_file_parser.dart';
import '../../../../data/models/recipe/prompt_recipe.dart';
import '../../../../data/models/vibe/vibe_reference.dart';
import '../../../../data/services/precise_ref_library_storage_service.dart';
import '../../../../data/services/vibe_library_storage_service.dart';
import '../../../../presentation/providers/precise_ref_library_provider.dart';
import '../../../../presentation/providers/vibe_library_provider.dart';
import '../../../../presentation/services/prompt_recipe_restoration_service.dart';
import '../../precise_ref_library/widgets/precise_ref_selector_dialog.dart';
import '../../vibe_library/widgets/vibe_selector_dialog.dart';

/// Lets the user explicitly supply the transient bytes missing from a recipe.
///
/// The dialog intentionally has no automatic matching. A selected file is
/// held only in memory and returned to the caller for one editor application.
class PromptRecipeAssetReattachmentDialog extends ConsumerStatefulWidget {
  const PromptRecipeAssetReattachmentDialog({super.key, required this.recipe});

  final PromptRecipe recipe;

  static Future<PromptRecipeAttachments?> show(
    BuildContext context,
    PromptRecipe recipe,
  ) {
    return showDialog<PromptRecipeAttachments>(
      context: context,
      builder: (context) => PromptRecipeAssetReattachmentDialog(recipe: recipe),
    );
  }

  @override
  ConsumerState<PromptRecipeAssetReattachmentDialog> createState() =>
      _PromptRecipeAssetReattachmentDialogState();
}

class _PromptRecipeAssetReattachmentDialogState
    extends ConsumerState<PromptRecipeAssetReattachmentDialog> {
  static const _imageExtensions = ['png', 'jpg', 'jpeg', 'webp', 'gif', 'bmp'];
  static const _vibeExtensions = [
    ..._imageExtensions,
    'naiv4vibe',
    'naiv4vibebundle',
  ];

  Uint8List? _sourceImage;
  final Map<String, VibeReference> _vibeReferences = {};
  final Map<String, Uint8List> _preciseReferences = {};
  bool _isPicking = false;
  String? _error;

  RecipeGenerationSnapshot get _snapshot => widget.recipe.request;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final hasRows =
        _snapshot.imageToImage != null ||
        _snapshot.vibeTransfers.isNotEmpty ||
        _snapshot.preciseReferences.isNotEmpty;

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.attach_file, color: theme.colorScheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      l10n.promptRecipe_reattachTitle,
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: l10n.common_cancel,
                    onPressed: _isPicking
                        ? null
                        : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                l10n.promptRecipe_reattachDescription,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _error!,
                    style: TextStyle(color: theme.colorScheme.onErrorContainer),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              if (!hasRows)
                Text(l10n.promptRecipe_missingAssets)
              else
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      if (_snapshot.imageToImage != null)
                        _buildSourceRow(_snapshot.imageToImage!),
                      for (
                        var index = 0;
                        index < _snapshot.vibeTransfers.length;
                        index++
                      )
                        _buildVibeRow(_snapshot.vibeTransfers[index], index),
                      for (
                        var index = 0;
                        index < _snapshot.preciseReferences.length;
                        index++
                      )
                        _buildPreciseRow(
                          _snapshot.preciseReferences[index],
                          index,
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isPicking
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: Text(l10n.common_cancel),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _isPicking ? null : _finish,
                    icon: const Icon(Icons.check),
                    label: Text(l10n.promptRecipe_reattachDone),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSourceRow(RecipeImageInputSnapshot source) {
    return _AssetRow(
      icon: Icons.image_outlined,
      title: context.l10n.promptRecipe_reattachSource,
      subtitle: source.filename,
      attached: _sourceImage != null,
      onPick: _pickSource,
      onLibraryPick: _pickSourceFromLibrary,
    );
  }

  Widget _buildVibeRow(RecipeVibeTransferSnapshot transfer, int index) {
    final key = _vibeKey(transfer, index);
    return _AssetRow(
      icon: Icons.style_outlined,
      title: context.l10n.promptRecipe_reattachVibe,
      subtitle: transfer.filename,
      attached: _vibeReferences.containsKey(key),
      onPick: () => _pickVibe(transfer, key),
      onLibraryPick: () => _pickVibeFromLibrary(key),
    );
  }

  Widget _buildPreciseRow(RecipePreciseReferenceSnapshot reference, int index) {
    final key = _preciseKey(reference, index);
    return _AssetRow(
      icon: Icons.face_retouching_natural_outlined,
      title: context.l10n.promptRecipe_reattachPrecise,
      subtitle: reference.filename,
      attached: _preciseReferences.containsKey(key),
      onPick: () => _pickPrecise(key),
      onLibraryPick: () => _pickPreciseFromLibrary(key),
    );
  }

  Future<void> _pickSource() async {
    final picked = await _pickBytes(_imageExtensions);
    if (picked == null) return;
    setState(() {
      _sourceImage = picked;
      _error = null;
    });
  }

  Future<void> _pickPrecise(String key) async {
    final picked = await _pickBytes(_imageExtensions);
    if (picked == null) return;
    setState(() {
      _preciseReferences[key] = picked;
      _error = null;
    });
  }

  Future<void> _pickSourceFromLibrary() async {
    final l10n = context.l10n;
    final selected = await PreciseRefSelectorDialog.show(
      context,
      multiSelect: false,
    );
    if (!mounted || selected == null || selected.isEmpty) return;
    final bytes = await ref
        .read(preciseRefLibraryStorageServiceProvider)
        .readImageBytes(selected.first.id);
    if (!mounted) return;
    if (bytes == null || bytes.isEmpty) {
      setState(() => _error = l10n.preciseRefLib_imageMissing);
      return;
    }
    setState(() {
      _sourceImage = bytes;
      _error = null;
    });
    unawaited(
      ref
          .read(preciseRefLibraryNotifierProvider.notifier)
          .recordUsage(selected.first.id),
    );
  }

  Future<void> _pickPreciseFromLibrary(String key) async {
    final l10n = context.l10n;
    final selected = await PreciseRefSelectorDialog.show(
      context,
      multiSelect: false,
    );
    if (!mounted || selected == null || selected.isEmpty) return;
    final bytes = await ref
        .read(preciseRefLibraryStorageServiceProvider)
        .readImageBytes(selected.first.id);
    if (!mounted) return;
    if (bytes == null || bytes.isEmpty) {
      setState(() => _error = l10n.preciseRefLib_imageMissing);
      return;
    }
    setState(() {
      _preciseReferences[key] = bytes;
      _error = null;
    });
    unawaited(
      ref
          .read(preciseRefLibraryNotifierProvider.notifier)
          .recordUsage(selected.first.id),
    );
  }

  Future<void> _pickVibeFromLibrary(String key) async {
    final l10n = context.l10n;
    final result = await VibeSelectorDialog.show(
      context: context,
      showReplaceOption: false,
      title: l10n.promptRecipe_reattachVibe,
    );
    if (!mounted || result == null || result.selectedEntries.isEmpty) return;
    if (result.selectedEntries.length != 1) {
      setState(() => _error = l10n.promptRecipe_vibeFileInvalid);
      return;
    }
    final selected = result.selectedEntries.single;
    final fullEntry = await ref
        .read(vibeLibraryStorageServiceProvider)
        .getEntry(selected.id);
    if (!mounted) return;
    final vibe = (fullEntry ?? selected).toVibeReference();
    if (!vibe.hasVibeEncoding && !vibe.canReencodeFromRawSource) {
      setState(() => _error = l10n.promptRecipe_vibeFileInvalid);
      return;
    }
    setState(() {
      _vibeReferences[key] = vibe;
      _error = null;
    });
    unawaited(
      ref.read(vibeLibraryNotifierProvider.notifier).recordUsage(selected.id),
    );
  }

  Future<void> _pickVibe(
    RecipeVibeTransferSnapshot snapshot,
    String key,
  ) async {
    final l10n = context.l10n;
    final picked = await _pickFile(_vibeExtensions);
    if (picked == null) return;
    try {
      final references = await VibeFileParser.parseFile(
        picked.name,
        picked.bytes,
        defaultStrength: snapshot.strength,
      );
      if (!mounted) return;
      if (references.length != 1) {
        setState(() => _error = l10n.promptRecipe_vibeFileInvalid);
        return;
      }
      setState(() {
        _vibeReferences[key] = references.single;
        _error = null;
      });
    } catch (_) {
      if (mounted) setState(() => _error = l10n.promptRecipe_vibeFileInvalid);
    }
  }

  Future<Uint8List?> _pickBytes(List<String> extensions) async {
    final picked = await _pickFile(extensions);
    return picked?.bytes;
  }

  Future<_PickedRecipeFile?> _pickFile(List<String> extensions) async {
    if (_isPicking) return null;
    setState(() {
      _isPicking = true;
      _error = null;
    });
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: extensions,
        allowMultiple: false,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return null;
      final file = result.files.single;
      final bytes =
          file.bytes ??
          (file.path == null ? null : await File(file.path!).readAsBytes());
      if (bytes == null || bytes.isEmpty) return null;
      return _PickedRecipeFile(name: file.name, bytes: bytes);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
      return null;
    } finally {
      if (mounted) setState(() => _isPicking = false);
    }
  }

  void _finish() {
    Navigator.of(context).pop(
      PromptRecipeAttachments(
        sourceImage: _sourceImage,
        vibeReferences: _vibeReferences,
        preciseReferences: _preciseReferences,
      ),
    );
  }

  String _vibeKey(RecipeVibeTransferSnapshot transfer, int index) =>
      transfer.id.isEmpty ? 'vibe-$index' : transfer.id;

  String _preciseKey(RecipePreciseReferenceSnapshot reference, int index) =>
      reference.id ?? 'precise-$index';
}

final class _PickedRecipeFile {
  const _PickedRecipeFile({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;
}

class _AssetRow extends StatelessWidget {
  const _AssetRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.attached,
    required this.onPick,
    this.onLibraryPick,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool attached;
  final VoidCallback onPick;
  final VoidCallback? onLibraryPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon, color: theme.colorScheme.primary),
        title: Text(title),
        subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            OutlinedButton.icon(
              onPressed: onPick,
              icon: Icon(attached ? Icons.check : Icons.attach_file, size: 16),
              label: Text(
                attached
                    ? context.l10n.promptRecipe_attachmentReady
                    : context.l10n.promptRecipe_chooseFile,
              ),
            ),
            if (onLibraryPick != null) ...[
              const SizedBox(width: 4),
              IconButton(
                tooltip: context.l10n.vibe_addFromLibraryTitle,
                onPressed: onLibraryPick,
                icon: const Icon(Icons.library_books_outlined, size: 18),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
