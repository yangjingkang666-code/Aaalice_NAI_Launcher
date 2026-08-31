import 'package:flutter/widgets.dart';

/// Feature-local copy keeps the laboratory usable while its wording is still
/// settling. The rest of the application remains on the generated ARB
/// catalogue; English is the safe fallback for unsupported locales.
class StyleLabCopy {
  const StyleLabCopy._(this._languageCode);

  factory StyleLabCopy.of(BuildContext context) {
    return StyleLabCopy._(Localizations.localeOf(context).languageCode);
  }

  final String _languageCode;

  bool get _zh => _languageCode == 'zh';
  bool get _ja => _languageCode == 'ja';

  String get title => _zh
      ? '画风实验室'
      : _ja
      ? '画風ラボ'
      : 'Style Lab';
  String get subtitle => _zh
      ? '随机画师串版 · 同 Seed A/B 对照 · 手动收藏'
      : _ja
      ? 'ランダム画家チェーン · 同一 Seed の A/B 比較'
      : 'Random artist chains · same-seed A/B comparison';
  String get basePrompt => _zh
      ? '主体提示词'
      : _ja
      ? 'ベースプロンプト'
      : 'Base prompt';
  String get auxiliaryPrompt => _zh
      ? '辅助提示词'
      : _ja
      ? '補助プロンプト'
      : 'Auxiliary prompt';
  String get artistPool => _zh
      ? '画师池'
      : _ja
      ? '画家プール'
      : 'Artist pool';
  String get artistPoolHint => _zh
      ? '每行一个，可写 artist:name|热度；留空使用离线精选池'
      : 'One per line. Optional `artist:name|popularity`; empty uses the offline pool.';
  String get loadLocalArtists => _zh
      ? '载入本地热门画师'
      : _ja
      ? 'ローカル人気画家を読込'
      : 'Load local popular artists';
  String get localArtistsReady => _zh
      ? '已载入本地画师池，可继续编辑后抽签。'
      : _ja
      ? 'ローカル画家プールを読み込みました。'
      : 'Local artist pool loaded; edit it before drawing if needed.';
  String get localArtistsUnavailable => _zh
      ? '本地 Tag 数据库不可用，已保留离线精选池。'
      : _ja
      ? 'ローカル Tag DB を利用できないため標準プールを使います。'
      : 'The local Tag database is unavailable; the offline pool is kept.';
  String get stylePool => _zh
      ? '风格变异池'
      : _ja
      ? 'スタイル変異プール'
      : 'Style mutation pool';
  String get stylePoolHint => _zh
      ? '支持 random|分类|词 和 always|分类|词；分类：artStyle / medium / color / lighting'
      : 'Use random|category|tag or always|category|tag. Categories: artStyle, medium, color, lighting.';
  String get pairCount => _zh
      ? '对照组数'
      : _ja
      ? '比較セット数'
      : 'A/B pairs';
  String get artistCount => _zh
      ? '每串画师数'
      : _ja
      ? 'チェーン長'
      : 'Artists per chain';
  String get artistWeight => _zh
      ? '画师权重范围'
      : _ja
      ? '画家ウェイト'
      : 'Artist weight';
  String get styleCount => _zh
      ? '变异词数'
      : _ja
      ? '変異語数'
      : 'Mutation terms';
  String get mutateStyles => _zh
      ? '启用风格变异'
      : _ja
      ? 'スタイル変異'
      : 'Mutate style terms';
  String get mutateHint => _zh
      ? 'A 保持原始画师串，B 只额外加入风格词；主体、画师串、Seed 和生成参数保持一致。'
      : 'A keeps the artist chain; B adds style terms. Subject, chain, seed and generation settings stay fixed.';
  String get seedMode => _zh
      ? 'Seed 模式'
      : _ja
      ? 'Seed モード'
      : 'Seed mode';
  String get randomSeed => _zh
      ? '每组随机'
      : _ja
      ? 'セットごとにランダム'
      : 'Random per pair';
  String get fixedSeed => _zh
      ? '固定 Seed'
      : _ja
      ? '固定 Seed'
      : 'Fixed seed';
  String get fixedSeedHint => _zh
      ? '固定 Seed 数值'
      : _ja
      ? '固定 Seed の値'
      : 'Fixed seed value';
  String get draw => _zh
      ? '重新抽签'
      : _ja
      ? '抽選'
      : 'Draw';
  String get generateBatch => _zh
      ? '生成全部 A/B'
      : _ja
      ? 'A/B を生成'
      : 'Generate all A/B';
  String get stop => _zh
      ? '停止'
      : _ja
      ? '停止'
      : 'Stop';
  String get syncParams => _zh
      ? '同步当前生成参数'
      : _ja
      ? '現在の生成設定を同期'
      : 'Sync generation settings';
  String get poolDefaults => _zh
      ? '使用离线精选池'
      : _ja
      ? 'オフライン標準プール'
      : 'Use offline curated pools';
  String get results => _zh
      ? '抽签结果'
      : _ja
      ? '抽選結果'
      : 'Draw results';
  String get favorites => _zh
      ? '收藏'
      : _ja
      ? 'お気に入り'
      : 'Favorites';
  String get emptyResults => _zh
      ? '还没有抽签结果。调整参数后点击“重新抽签”。'
      : 'No draw yet. Adjust the controls and press Draw.';
  String get emptyFavorites => _zh
      ? '收藏会保留在当前项目工作区。'
      : 'Favorites are kept in the active project workspace.';
  String pair(int index) => _zh
      ? '对照组 ${index + 1}'
      : _ja
      ? '比較 ${index + 1}'
      : 'Pair ${index + 1}';
  String get plain => _zh
      ? 'A · 原始画师串'
      : _ja
      ? 'A · 元のチェーン'
      : 'A · Plain chain';
  String get mutated => _zh
      ? 'B · 风格变异'
      : _ja
      ? 'B · スタイル変異'
      : 'B · Mutated style';
  String get pending => _zh
      ? '待生成'
      : _ja
      ? '待機中'
      : 'Pending';
  String get generating => _zh
      ? '生成中'
      : _ja
      ? '生成中'
      : 'Generating';
  String get completed => _zh
      ? '已完成'
      : _ja
      ? '完了'
      : 'Completed';
  String get failed => _zh
      ? '失败'
      : _ja
      ? '失敗'
      : 'Failed';
  String get generate => _zh
      ? '生成'
      : _ja
      ? '生成'
      : 'Generate';
  String get retry => _zh
      ? '重试'
      : _ja
      ? '再試行'
      : 'Retry';
  String get favorite => _zh
      ? '收藏'
      : _ja
      ? 'お気に入り'
      : 'Favorite';
  String get unfavorite => _zh
      ? '取消收藏'
      : _ja
      ? 'お気に入り解除'
      : 'Unfavorite';
  String get apply => _zh
      ? '应用到生成页'
      : _ja
      ? '生成画面へ適用'
      : 'Apply to generator';
  String get copyPrompt => _zh
      ? '复制提示词'
      : _ja
      ? 'プロンプトをコピー'
      : 'Copy prompt';
  String get copied => _zh
      ? '已复制提示词'
      : _ja
      ? 'コピーしました'
      : 'Prompt copied';
  String get needPrompt => _zh ? '请先填写主体提示词。' : 'Enter a base prompt first.';
  String get generationBusy => _zh
      ? '当前已有生成任务，请稍后再试。'
      : 'Another generation is running. Try again later.';
  String get needGeneratedImage =>
      _zh ? '请先生成该变体，再收藏。' : 'Generate this variant before favoriting it.';
  String get drawDone => _zh ? '已生成新的 A/B 对照组。' : 'New A/B pairs are ready.';
  String get batchDone => _zh ? '批量生成完成。' : 'Batch generation completed.';
  String get stopped =>
      _zh ? '已停止后续生成。' : 'Remaining generations were stopped.';
  String get applied => _zh
      ? '已应用到生成页，可继续调整后出图。'
      : 'Applied to the generator. Review settings before generating.';
  String get noImage => _zh
      ? '暂无图像'
      : _ja
      ? '画像なし'
      : 'No image';
  String get seed => 'Seed';
  String get model => _zh
      ? '模型'
      : _ja
      ? 'モデル'
      : 'Model';
  String get settingsNote => _zh
      ? '实验室会复用当前生成页的模型、尺寸、步数和采样器；生成时会暂时移除角色、Vibe 与参考图，确保 A/B 可比。'
      : 'The lab reuses model, size, steps and sampler from the generator. Characters, Vibe and image references are removed for a fair A/B test.';
  String get refresh => _zh
      ? '刷新'
      : _ja
      ? '更新'
      : 'Refresh';
  String get remove => _zh
      ? '移除'
      : _ja
      ? '削除'
      : 'Remove';
}
