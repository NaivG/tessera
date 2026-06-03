import 'package:flutter/material.dart';

import '../../core/core.dart';
import '../../l10n/model_localization.dart';
import '../../state/settings_state.dart';
import 'package:tessera/l10n/app_localizations.dart';

/// 模型选择设置页
///
/// 配置各能力方向应使用哪个模型：
/// - 主模型（文本 LLM）
/// - 输入模态模型（视觉/音频/视频）
/// - 输出模态模型（文生图/文生视频/文生语音）
/// - LLM 辅助功能（话题检测/记忆整理/内容总结）
/// - 其他模型（嵌入/排序）
class ModelSelectionPage extends StatefulWidget {
  final SettingsState settingsState;

  const ModelSelectionPage({super.key, required this.settingsState});

  @override
  State<ModelSelectionPage> createState() => _ModelSelectionPageState();
}

class _ModelSelectionPageState extends State<ModelSelectionPage> {
  @override
  void initState() {
    super.initState();
    widget.settingsState.addListener(_onStateChanged);
  }

  @override
  void dispose() {
    widget.settingsState.removeListener(_onStateChanged);
    super.dispose();
  }

  void _onStateChanged() {
    if (!mounted) return;
    setState(() {});
  }

  SettingsState get _state => widget.settingsState;
  ModelSelectionConfig get _config => _state.modelSelectionConfig;

  List<_ModelEntry> get _allModels {
    final entries = <_ModelEntry>[];
    final configs = _state.providerConfigs;
    for (final provider in configs) {
      for (final model in provider.models) {
        entries.add(_ModelEntry(provider, model));
      }
    }
    return entries;
  }

  ModelInfo? get _mainModelInfo => _config.mainModel.getModelInfo(_state);

  bool _mainSupports(ModelTag tag) =>
      _mainModelInfo?.tags.contains(tag) ?? false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.modelSelectionAppBarTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionHeader(l10n.modelSelectionSectionMain),
          const SizedBox(height: 4),
          Text(
            l10n.modelSelectionMainSubtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          const SizedBox(height: 8),
          _buildSlotTile(
            label: _config.mainModel.displayLabel(_state),
            subtitle: l10n.modelSelectionMainLabel,
            onTap: () => _pickModel((slot) {
              if (slot != null) _state.setMainModel(slot);
            }, filterType: ModelType.text),
          ),

          const Divider(height: 32),

          _sectionHeader(l10n.modelSelectionSectionInput),
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
              .map(_buildInputRow),

          const Divider(height: 32),

          _sectionHeader(l10n.modelSelectionSectionOutput),
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
              .map(_buildOutputRow),

          const Divider(height: 32),

          _sectionHeader(l10n.modelSelectionSectionLlm),
          const SizedBox(height: 4),
          Text(
            l10n.modelSelectionLlmSubtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          const SizedBox(height: 8),
          _buildOtherRow(
            'topic_detection',
            l10n.modelSelectionTopicDetection,
            l10n.modelSelectionTopicDetectionHint,
            canUseMain: true,
          ),
          _buildOtherRow(
            'memory_organization',
            l10n.modelSelectionMemoryOrganization,
            l10n.modelSelectionMemoryOrganizationHint,
            canUseMain: true,
          ),
          _buildOtherRow(
            'content_summarization',
            l10n.modelSelectionContentSummarization,
            l10n.modelSelectionContentSummarizationHint,
            canUseMain: true,
          ),

          const Divider(height: 32),

          _sectionHeader(l10n.modelSelectionSectionOther),
          const SizedBox(height: 4),
          Text(
            l10n.modelSelectionOtherSubtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          const SizedBox(height: 8),
          _buildOtherRow(
            'embedding',
            l10n.modelSelectionSectionEmbedding,
            l10n.modelSelectionEmbeddingHint,
          ),
          _buildOtherRow(
            'ranking',
            l10n.modelSelectionRankingModel,
            l10n.modelSelectionRankingHint,
          ),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  // ── 输入模态行 ──

  Widget _buildInputRow(ModelTag tag) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final slot = _config.inputModalities[tag];
    final mainOk = _mainSupports(tag);

    final String currentLabel;
    if (slot != null) {
      currentLabel = slot.displayLabel(_state);
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
                      (newSlot) => _state.setInputModality(tag, newSlot),
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
                onPressed: () => _state.setInputModality(tag, null),
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

  Widget _buildOutputRow(ModelType type) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final slot = _config.outputModalities[type];
    final currentLabel = slot != null
        ? slot.displayLabel(_state)
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
                (newSlot) => _state.setOutputModality(type, newSlot),
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

  ModelType? _otherKeyToType(String key) {
    return switch (key) {
      'embedding' => ModelType.embedding,
      'ranking' => ModelType.ranking,
      'topic_detection' => ModelType.text,
      'memory_organization' => ModelType.text,
      'content_summarization' => ModelType.text,
      _ => null,
    };
  }

  Widget _buildOtherRow(
    String key,
    String label,
    String hint, {
    bool canUseMain = false,
  }) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final slot = _config.otherModels[key];
    final String currentLabel;
    if (slot != null) {
      currentLabel = slot.displayLabel(_state);
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
                (newSlot) => _state.setOtherModel(key, newSlot),
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
                onPressed: () => _state.setOtherModel(key, null),
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

  Widget _buildSlotTile({
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

  Future<void> _pickModel(
    void Function(ModelSlot? slot) onSelected, {
    bool allowClear = false,
    String clearLabel = '',
    ModelType? filterType,
    ModelTag? filterTag,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    if (clearLabel.isEmpty) clearLabel = l10n.modelSelectionClearSelection;
    var allModels = _allModels;
    if (filterType != null) {
      allModels = allModels.where((e) => e.model.type == filterType).toList();
    }
    if (filterTag != null) {
      allModels = allModels
          .where((e) => e.model.tags.contains(filterTag))
          .toList();
    }
    if (allModels.isEmpty) {
      if (mounted) {
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
              itemCount: allModels.length + (allowClear ? 1 : 0),
              itemBuilder: (ctx, index) {
                if (allowClear && index == allModels.length) {
                  return ListTile(
                    leading: Icon(Icons.clear, color: theme.colorScheme.error),
                    title: Text(
                      clearLabel,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                    onTap: () => Navigator.pop(ctx, _clearSentinel),
                  );
                }

                final entry = allModels[index];
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
      // 用户点击了"清除选择" → 传递 null 表示未设置
      onSelected(null);
    } else if (result != null) {
      onSelected(result);
    }
  }

  // ── 辅助组件 ──

  Widget _sectionHeader(String title) {
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

  Widget _buildTagChip(ThemeData theme, ModelTag tag) {
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

  Widget _buildTypeChip(ThemeData theme, ModelType type) {
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
