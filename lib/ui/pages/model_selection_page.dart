import 'package:flutter/material.dart';

import '../../core/core.dart';
import '../../state/settings_state.dart';

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

    return Scaffold(
      appBar: AppBar(title: const Text('模型选择')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionHeader('主模型（文本 LLM）'),
          const SizedBox(height: 4),
          Text(
            '最基础的文本对话任务交给哪个模型',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          const SizedBox(height: 8),
          _buildSlotTile(
            label: _config.mainModel.displayLabel(_state),
            subtitle: '主模型',
            onTap: () => _pickModel((slot) {
              if (slot != null) _state.setMainModel(slot);
            }, filterType: ModelType.text),
          ),

          const Divider(height: 32),

          _sectionHeader('输入模态'),
          const SizedBox(height: 4),
          Text(
            '处理用户输入的图片、音频、视频时使用哪个模型。'
            '若主模型支持该模态，可选择"使用主模型"。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          const SizedBox(height: 8),
          ...ModelTag.values
              .where((t) => t != ModelTag.text)
              .map(_buildInputRow),

          const Divider(height: 32),

          _sectionHeader('输出模态'),
          const SizedBox(height: 4),
          Text(
            '生成图片、视频、语音等非文本输出时使用哪个模型。',
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

          _sectionHeader('LLM 辅助功能'),
          const SizedBox(height: 4),
          Text(
            '话题检测、记忆整理、内容总结等辅助任务。留空默认使用主模型。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          const SizedBox(height: 8),
          _buildOtherRow(
            'topic_detection',
            '话题检测',
            '检测对话话题、意图分类',
            canUseMain: true,
          ),
          _buildOtherRow(
            'memory_organization',
            '记忆整理',
            '整理长期记忆、知识提取',
            canUseMain: true,
          ),
          _buildOtherRow(
            'content_summarization',
            '内容总结',
            '对话/文档摘要生成',
            canUseMain: true,
          ),

          const Divider(height: 32),

          _sectionHeader('其他模型'),
          const SizedBox(height: 4),
          Text(
            '嵌入（Embedding）、排序（Ranking）等专用模型。'
            '话题检测/记忆整理/内容总结等 LLM 辅助功能请在上方选择。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          const SizedBox(height: 8),
          _buildOtherRow('embedding', '嵌入模型', '用于文本嵌入向量生成'),
          _buildOtherRow('ranking', '排序模型', '用于搜索结果重排序'),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  // ── 输入模态行 ──

  Widget _buildInputRow(ModelTag tag) {
    final theme = Theme.of(context);
    final slot = _config.inputModalities[tag];
    final mainOk = _mainSupports(tag);

    final String currentLabel;
    if (slot != null) {
      currentLabel = slot.displayLabel(_state);
    } else if (mainOk) {
      currentLabel = '使用主模型';
    } else {
      currentLabel = '未配置';
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
                Text(tag.displayName, style: theme.textTheme.titleSmall),
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
                      clearLabel: mainOk ? '使用主模型' : '清除',
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
                label: const Text('使用主模型', style: TextStyle(fontSize: 12)),
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
    final slot = _config.outputModalities[type];
    final currentLabel = slot != null ? slot.displayLabel(_state) : '未配置';

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
                    type.displayName,
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
    final slot = _config.otherModels[key];
    final String currentLabel;
    if (slot != null) {
      currentLabel = slot.displayLabel(_state);
    } else if (canUseMain) {
      currentLabel = '使用主模型';
    } else {
      currentLabel = '未配置';
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
                clearLabel: canUseMain ? '使用主模型' : '清除选择',
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
                label: const Text('使用主模型', style: TextStyle(fontSize: 12)),
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
    String clearLabel = '清除选择',
    ModelType? filterType,
    ModelTag? filterTag,
  }) async {
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('未找到可用的模型，请先在设置中添加对应模型')));
      }
      return;
    }

    final result = await showDialog<ModelSlot?>(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return AlertDialog(
          title: const Text('选择模型'),
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
                    ? ' \u00b7 ${entry.model.tagsLabel}'
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
                    '${entry.provider.displayName}${entry.model.type == ModelType.text ? "" : " \u00b7 ${entry.model.type.displayName}"}$tagsStr',
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
              child: const Text('取消'),
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
