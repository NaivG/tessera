import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/core.dart';
import '../../l10n/model_localization.dart';
import '../../providers/providers.dart';
import 'package:tessera/l10n/app_localizations.dart';

/// 模型选择设置页
///
/// 配置各能力方向应使用哪个模型：
/// - 主模型（文本 LLM）
/// - 输入模态模型（视觉/音频/视频）
/// - 输出模态模型（文生图/文生视频/文生语音）
/// - LLM 辅助功能（话题检测/记忆整理/内容总结）
/// - 其他模型（嵌入/排序）
class ModelSelectionPage extends ConsumerWidget {
  const ModelSelectionPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final state = ref.watch(settingsProvider);
    final config = state.modelSelectionConfig;

    final allModels = _getAllModels(state);

    ModelInfo? mainModelInfo = config.mainModel.getModelInfo(state);
    bool mainSupports(ModelTag tag) => mainModelInfo?.tags.contains(tag) ?? false;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.modelSelectionAppBarTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionHeader(context, l10n.modelSelectionSectionMain),
          const SizedBox(height: 4),
          Text(
            l10n.modelSelectionMainSubtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          const SizedBox(height: 8),
          _buildSlotTile(context,
            label: config.mainModel.displayLabel(state),
            subtitle: l10n.modelSelectionMainLabel,
            onTap: () => _pickModel(
              context,
              ref,
              allModels,
              (slot) {
                if (slot != null) {
                  ref.read(settingsProvider.notifier).setMainModel(slot);
                }
              },
              filterType: ModelType.text,
            ),
          ),

          const Divider(height: 32),

          _sectionHeader(context, l10n.modelSelectionSectionInput),
          const SizedBox(height: 4),
          Text(
            '${l10n.modelSelectionInputSubtitle}${l10n.modelSelectionInputHint}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          const SizedBox(height: 8),
          ...ModelTag.values
              .where((t) => t != ModelTag.text)
              .map((tag) => _buildInputRow(
                    context,
                    ref,
                    state,
                    config,
                    allModels,
                    tag,
                    mainSupports(tag),
                  )),

          const Divider(height: 32),

          _sectionHeader(context, l10n.modelSelectionSectionOutput),
          const SizedBox(height: 4),
          Text(
            l10n.modelSelectionOutputSubtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          const SizedBox(height: 8),
          ...ModelType.values
              .where(
                (t) =>
                    t != ModelType.text &&
                    t != ModelType.embedding &&
                    t != ModelType.ranking,
              )
              .map((type) => _buildOutputRow(
                    context,
                    ref,
                    state,
                    config,
                    allModels,
                    type,
                  )),

          const Divider(height: 32),

          _sectionHeader(context, l10n.modelSelectionSectionLlm),
          const SizedBox(height: 4),
          Text(
            l10n.modelSelectionLlmSubtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          const SizedBox(height: 8),
          _buildOtherRow(
            context,
            ref,
            state,
            config,
            allModels,
            'topic_detection',
            l10n.modelSelectionTopicDetection,
            l10n.modelSelectionTopicDetectionHint,
            canUseMain: true,
          ),
          _buildOtherRow(
            context,
            ref,
            state,
            config,
            allModels,
            'memory_organization',
            l10n.modelSelectionMemoryOrganization,
            l10n.modelSelectionMemoryOrganizationHint,
            canUseMain: true,
          ),
          _buildOtherRow(
            context,
            ref,
            state,
            config,
            allModels,
            'content_summarization',
            l10n.modelSelectionContentSummarization,
            l10n.modelSelectionContentSummarizationHint,
            canUseMain: true,
          ),

          const Divider(height: 32),

          _sectionHeader(context, l10n.modelSelectionSectionOther),
          const SizedBox(height: 4),
          Text(
            l10n.modelSelectionOtherSubtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          const SizedBox(height: 8),
          _buildOtherRow(
            context,
            ref,
            state,
            config,
            allModels,
            'embedding',
            l10n.modelSelectionSectionEmbedding,
            l10n.modelSelectionEmbeddingHint,
          ),
          _buildOtherRow(
            context,
            ref,
            state,
            config,
            allModels,
            'ranking',
            l10n.modelSelectionRankingModel,
            l10n.modelSelectionRankingHint,
          ),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  // ── 模型列表 ──

  static List<_ModelEntry> _getAllModels(SettingsData state) {
    final entries = <_ModelEntry>[];
    final configs = state.providerConfigs;
    for (final provider in configs) {
      for (final model in provider.models) {
        entries.add(_ModelEntry(provider, model));
      }
    }
    return entries;
  }

  // ── 输入模态行 ──

  static Widget _buildInputRow(
    BuildContext context,
    WidgetRef ref,
    SettingsData state,
    ModelSelectionConfig config,
    List<_ModelEntry> allModels,
    ModelTag tag,
    bool mainOk,
  ) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final slot = config.inputModalities[tag];

    final String currentLabel;
    if (slot != null) {
      currentLabel = slot.displayLabel(state);
    } else if (mainOk) {
      currentLabel = l10n.modelSelectionUseMainModel;
    } else {
      currentLabel = l10n.modelSelectionNotConfigured;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _buildTagChip(theme, tag),
                const SizedBox(width: 8),
                Text(l10n.modelTagName(tag), style: theme.textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => _pickModel(
                      context,
                      ref,
                      allModels,
                      (newSlot) => ref
                          .read(settingsProvider.notifier)
                          .setInputModality(tag, newSlot),
                      allowClear: true,
                      clearLabel: mainOk
                          ? l10n.modelSelectionUseMainModel
                          : l10n.commonClear,
                      filterTag: tag,
                    ),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: theme.colorScheme.outlineVariant,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.input,
                            size: 16,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              currentLabel,
                              style: theme.textTheme.bodyMedium,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Icon(
                            Icons.arrow_drop_down,
                            color: theme.colorScheme.outline,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (mainOk && slot != null) ...[
              const SizedBox(height: 4),
              TextButton.icon(
                onPressed: () => ref
                    .read(settingsProvider.notifier)
                    .setInputModality(tag, null),
                icon: const Icon(Icons.undo, size: 14),
                label: Text(
                  l10n.modelSelectionUseMainModel,
                  style: const TextStyle(fontSize: 12),
                ),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── 输出模态行 ──

  static Widget _buildOutputRow(
    BuildContext context,
    WidgetRef ref,
    SettingsData state,
    ModelSelectionConfig config,
    List<_ModelEntry> allModels,
    ModelType type,
  ) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final slot = config.outputModalities[type];
    final currentLabel = slot != null
        ? slot.displayLabel(state)
        : l10n.modelSelectionNotConfigured;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _buildTypeChip(theme, type),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.modelTypeName(type),
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            InkWell(
              onTap: () => _pickModel(
                context,
                ref,
                allModels,
                (newSlot) => ref
                    .read(settingsProvider.notifier)
                    .setOutputModality(type, newSlot),
                allowClear: true,
                filterType: type,
              ),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.output,
                      size: 16,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        currentLabel,
                        style: theme.textTheme.bodyMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(
                      Icons.arrow_drop_down,
                      color: theme.colorScheme.outline,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 其他模型行 ──

  static ModelType? _otherKeyToType(String key) {
    return switch (key) {
      'embedding' => ModelType.embedding,
      'ranking' => ModelType.ranking,
      'topic_detection' => ModelType.text,
      'memory_organization' => ModelType.text,
      'content_summarization' => ModelType.text,
      _ => null,
    };
  }

  static Widget _buildOtherRow(
    BuildContext context,
    WidgetRef ref,
    SettingsData state,
    ModelSelectionConfig config,
    List<_ModelEntry> allModels,
    String key,
    String label,
    String hint, {
    bool canUseMain = false,
  }) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final slot = config.otherModels[key];
    final String currentLabel;
    if (slot != null) {
      currentLabel = slot.displayLabel(state);
    } else if (canUseMain) {
      currentLabel = l10n.modelSelectionUseMainModel;
    } else {
      currentLabel = l10n.modelSelectionNotConfigured;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: theme.textTheme.titleSmall),
                      Text(
                        hint,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            InkWell(
              onTap: () => _pickModel(
                context,
                ref,
                allModels,
                (newSlot) => ref
                    .read(settingsProvider.notifier)
                    .setOtherModel(key, newSlot),
                allowClear: true,
                clearLabel: canUseMain
                    ? l10n.modelSelectionUseMainModel
                    : l10n.modelSelectionClearSelection,
                filterType: _otherKeyToType(key),
              ),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.extension,
                      size: 16,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        currentLabel,
                        style: theme.textTheme.bodyMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(
                      Icons.arrow_drop_down,
                      color: theme.colorScheme.outline,
                    ),
                  ],
                ),
              ),
            ),
            if (canUseMain && slot != null) ...[
              const SizedBox(height: 4),
              TextButton.icon(
                onPressed: () => ref
                    .read(settingsProvider.notifier)
                    .setOtherModel(key, null),
                icon: const Icon(Icons.undo, size: 14),
                label: Text(
                  l10n.modelSelectionUseMainModel,
                  style: const TextStyle(fontSize: 12),
                ),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── 通用槽位行 ──

  static Widget _buildSlotTile(
    BuildContext context, {
    required String label,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(Icons.smart_toy, color: theme.colorScheme.primary),
        title: Text(label, overflow: TextOverflow.ellipsis),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.arrow_drop_down),
        onTap: onTap,
      ),
    );
  }

  // ── 模型选择对话框 ──

  /// 用于区分"清除选择"和"取消"的 sentinel 对象
  static final _clearSentinel = ModelSlot(providerConfigId: '', modelUid: '');

  static Future<void> _pickModel(
    BuildContext context,
    WidgetRef ref,
    List<_ModelEntry> allModels,
    void Function(ModelSlot? slot) onSelected, {
    bool allowClear = false,
    String clearLabel = '',
    ModelType? filterType,
    ModelTag? filterTag,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    if (clearLabel.isEmpty) clearLabel = l10n.modelSelectionClearSelection;
    var filtered = allModels;
    if (filterType != null) {
      filtered = filtered.where((e) => e.model.type == filterType).toList();
    }
    if (filterTag != null) {
      filtered =
          filtered.where((e) => e.model.tags.contains(filterTag)).toList();
    }
    if (filtered.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.modelSelectionNoModelsFound)),
        );
      }
      return;
    }

    final result = await showDialog<ModelSlot?>(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return AlertDialog(
          title: Text(l10n.modelSelectionPickTitle),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: filtered.length + (allowClear ? 1 : 0),
              itemBuilder: (ctx, index) {
                if (allowClear && index == filtered.length) {
                  return ListTile(
                    leading: Icon(Icons.clear, color: theme.colorScheme.error),
                    title: Text(
                      clearLabel,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                    onTap: () => Navigator.pop(ctx, _clearSentinel),
                  );
                }

                final entry = filtered[index];
                final isLLM = entry.model.type == ModelType.text;
                final tagsStr = entry.model.isMultimodal
                    ? ' \u00b7 ${l10n.modelTagsLabel(entry.model)}'
                    : '';

                return ListTile(
                  leading: Icon(
                    isLLM ? Icons.smart_toy : Icons.auto_awesome,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                  title: Text(
                    entry.model.id,
                    style: const TextStyle(fontSize: 14),
                  ),
                  subtitle: Text(
                    '${entry.provider.displayName}${entry.model.type == ModelType.text ? "" : " \u00b7 ${l10n.modelTypeName(entry.model.type)}"}$tagsStr',
                    style: const TextStyle(fontSize: 12),
                  ),
                  onTap: () => Navigator.pop(
                    ctx,
                    ModelSlot(
                      providerConfigId: entry.provider.id,
                      modelUid: entry.model.uid,
                    ),
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l10n.commonCancel),
            ),
          ],
        );
      },
    );

    if (result == _clearSentinel) {
      onSelected(null);
    } else if (result != null) {
      onSelected(result);
    }
  }

  // ── 辅助组件 ──

  static Widget _sectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
      ),
    );
  }

  static Widget _buildTagChip(ThemeData theme, ModelTag tag) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        tag.icon,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onTertiaryContainer,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  static Widget _buildTypeChip(ThemeData theme, ModelType type) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        type.shortName,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSecondaryContainer,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ModelEntry {
  final dynamic provider;
  final ModelInfo model;

  const _ModelEntry(this.provider, this.model);
}
