import 'package:flutter/material.dart';

import '../../models/llm_provider_config.dart';
import '../../models/model_info.dart';
import '../../llm/provider_factory.dart';
import '../../state/settings_state.dart';

/// 编辑模型页面
///
/// 替代原先的"添加模型"对话框，提供完整的模型编辑界面：
/// - 带自动补全的模型 ID 输入框（从 API 获取所有模型 ID）
/// - 添加图标按钮
/// - 已添加模型列表（可选中/删除）
///
/// 当从自动补全下拉中选择已有模型时，自动从 API 获取模型信息，
/// 并弹出类型与标签选择对话框供用户确认后添加。
class ModelEditPage extends StatefulWidget {
  final String providerId;
  final LlmProviderConfig config;
  final SettingsState settingsState;

  const ModelEditPage({
    super.key,
    required this.providerId,
    required this.config,
    required this.settingsState,
  });

  @override
  State<ModelEditPage> createState() => _ModelEditPageState();
}

class _ModelEditPageState extends State<ModelEditPage> {
  List<ModelInfo>? _allModels;
  bool _isLoadingModels = false;

  late final TextEditingController _searchController;
  late final FocusNode _searchFocusNode;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _searchFocusNode = FocusNode();
    _searchController.addListener(_onSearchChanged);
    widget.settingsState.addListener(_onStateChanged);
    _fetchModels();
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    widget.settingsState.removeListener(_onStateChanged);
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text;
    });
  }

  void _onStateChanged() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _fetchModels() async {
    if (_isLoadingModels) return;
    setState(() => _isLoadingModels = true);
    try {
      final provider = ProviderFactory.get(widget.config.format);
      final models = await provider.listAvailableModels(
        apiKey: widget.config.apiKey,
        baseUrl: widget.config.baseUrl,
      );
      if (mounted) {
        setState(() {
          _allModels = models;
          _isLoadingModels = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _allModels = [];
          _isLoadingModels = false;
        });
      }
    }
  }

  Iterable<String> _getSuggestions(String query) {
    if (_allModels == null || _allModels!.isEmpty) return const [];
    if (query.isEmpty) return _allModels!.map((m) => m.id);
    final lower = query.toLowerCase();
    return _allModels!
        .where((m) => m.id.toLowerCase().contains(lower))
        .map((m) => m.id);
  }

  // ==================== 模型操作 ====================

  /// 从自动补全下拉中选中了一个模型 ID
  Future<void> _onModelSelected(String modelId) async {
    final trimmed = modelId.trim();
    if (trimmed.isEmpty) return;

    // 优先使用已缓存的模型信息
    ModelInfo? existing = _allModels?.cast<ModelInfo?>().firstWhere(
      (m) => m!.id == trimmed,
      orElse: () => null,
    );

    ModelInfo? fetchedInfo;
    if (existing != null) {
      fetchedInfo = existing;
    } else {
      fetchedInfo = await _fetchModelInfo(trimmed);
    }

    if (mounted) {
      _showTypeTagDialog(trimmed, fetchedInfo);
    }
  }

  /// 点击添加按钮
  Future<void> _onAddPressed(String modelId) async {
    final trimmed = modelId.trim();
    if (trimmed.isEmpty) return;

    // 优先使用已缓存的模型信息
    ModelInfo? cached = _allModels?.cast<ModelInfo?>().firstWhere(
      (m) => m!.id == trimmed,
      orElse: () => null,
    );

    ModelInfo? fetchedInfo;
    if (cached != null) {
      fetchedInfo = cached;
    } else {
      fetchedInfo = await _fetchModelInfo(trimmed);
    }

    if (mounted) {
      _showTypeTagDialog(trimmed, fetchedInfo);
    }
  }

  /// 删除模型
  Future<void> _onDeleteModel(String modelUid) async {
    final model = widget.config.models.firstWhere(
      (m) => m.uid == modelUid,
      orElse: () => ModelInfo(id: ''),
    );
    if (model.id.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除模型'),
        content: Text('确定要删除模型「${model.id}」吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              '删除',
              style: TextStyle(color: Theme.of(ctx).colorScheme.error),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await widget.settingsState.removeModel(widget.providerId, modelUid);
    }
  }

  // ==================== API 调用 ====================

  Future<ModelInfo?> _fetchModelInfo(String modelId) async {
    try {
      final provider = ProviderFactory.get(widget.config.format);
      return await provider.getModelInfo(
        modelId,
        apiKey: widget.config.apiKey,
        baseUrl: widget.config.baseUrl,
      );
    } catch (_) {
      return null;
    }
  }

  // ==================== 类型/标签对话框 ====================

  /// 弹出模型类型与标签选择对话框
  ///
  /// [modelId] 模型 ID（只读展示）
  /// [fetchedInfo] 从 API 获取到的模型信息，用于预填充类型与标签；
  ///   为 null 时使用默认值（text 类型 + text 标签）
  Future<void> _showTypeTagDialog(
    String modelId,
    ModelInfo? fetchedInfo,
  ) async {
    final state = widget.settingsState;

    ModelType selectedType = fetchedInfo?.type ?? ModelType.text;
    final selectedTags = <ModelTag>{};
    if (fetchedInfo != null) {
      selectedTags.addAll(fetchedInfo.tags);
    }
    // LLM 类型至少要有一个 text 标签
    if (selectedType == ModelType.text && selectedTags.isEmpty) {
      selectedTags.add(ModelTag.text);
    }

    final result = await showDialog<ModelInfo>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDlgState) {
            final isLLM = selectedType == ModelType.text;
            final theme = Theme.of(ctx);

            return AlertDialog(
              title: Text('添加模型: $modelId'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 模型 ID（只读）
                    _DialogLabel('模型 ID'),
                    const SizedBox(height: 4),
                    Text(
                      modelId,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),

                    const SizedBox(height: 20),

                    // 类型选择
                    _DialogLabel('模型类型'),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: ModelType.values.map((t) {
                        final isSel = t == selectedType;
                        return ChoiceChip(
                          label: Text(
                            t.displayName,
                            style: const TextStyle(fontSize: 12),
                          ),
                          selected: isSel,
                          onSelected: (_) {
                            setDlgState(() {
                              selectedType = t;
                              if (t != ModelType.text) {
                                // 非 LLM 类型的模型更专职，不需要模态标签
                                selectedTags.clear();
                              } else {
                                // LLM 类型默认至少包含 text 标签
                                if (selectedTags.isEmpty) {
                                  selectedTags.add(ModelTag.text);
                                }
                              }
                            });
                          },
                          visualDensity: VisualDensity.compact,
                        );
                      }).toList(),
                    ),

                    // 标签选择（仅 LLM 类型）
                    if (isLLM) ...[
                      const SizedBox(height: 16),
                      _DialogLabel('模态标签'),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: ModelTag.values.map((tag) {
                          final isSel = selectedTags.contains(tag);
                          return FilterChip(
                            label: Text(
                              tag.displayName,
                              style: const TextStyle(fontSize: 12),
                            ),
                            selected: isSel,
                            onSelected: (v) {
                              setDlgState(() {
                                if (v) {
                                  selectedTags.add(tag);
                                } else {
                                  // 至少保留 text 标签
                                  if (tag != ModelTag.text ||
                                      selectedTags.length > 1) {
                                    selectedTags.remove(tag);
                                  }
                                }
                              });
                            },
                            visualDensity: VisualDensity.compact,
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '已选标签: '
                        '${selectedTags.map((t) => t.displayName).join(" + ")}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ],

                    // 从 API 获取到信息的提示
                    if (fetchedInfo != null) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 14,
                            color: theme.colorScheme.outline,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              '已从 API 获取到模型信息，请确认',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.outline,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () {
                    Navigator.pop(
                      ctx,
                      ModelInfo(
                        id: modelId,
                        type: selectedType,
                        tags: isLLM ? selectedTags.toList() : [],
                      ),
                    );
                  },
                  child: const Text('添加'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result != null) {
      await state.addModel(widget.providerId, result);
    }
  }

  // ==================== 构建 UI ====================

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final config = widget.config;

    return Scaffold(
      appBar: AppBar(title: Text('编辑模型 - ${config.displayName}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ===== 添加模型区域 =====
          Text(
            '添加模型',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),

          // 自动补全输入框
          if (_isLoadingModels && _allModels == null)
            _buildLoadingField(theme)
          else
            _buildAutocompleteField(theme),

          const SizedBox(height: 24),

          // ===== 已添加模型列表 =====
          Text(
            '已添加模型 (${config.models.length})',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),

          if (config.models.isEmpty)
            _buildEmptyModels(theme)
          else
            ...config.models.map((model) => _buildModelCard(theme, model)),

          const SizedBox(height: 16),
        ],
      ),
    );
  }

  /// 加载中的输入框
  Widget _buildLoadingField(ThemeData theme) {
    return TextField(
      enabled: false,
      decoration: InputDecoration(
        hintText: '正在获取模型列表…',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        isDense: true,
        suffixIcon: Padding(
          padding: const EdgeInsets.all(12),
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
    );
  }

  /// 搜索输入框 + 内联建议列表
  ///
  /// 替代原先的 [Autocomplete] 组件，将建议列表作为内联元素嵌入页面中，
  /// 避免 [Autocomplete] 的 [Overlay] 悬浮下拉遮挡下方内容。
  Widget _buildAutocompleteField(ThemeData theme) {
    final suggestions = _getSuggestions(_searchQuery).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _searchController,
          focusNode: _searchFocusNode,
          autocorrect: false,
          decoration: InputDecoration(
            hintText: '搜索或输入模型 ID…',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            isDense: true,
            suffixIcon: IconButton(
              icon: Icon(Icons.add_circle, color: theme.colorScheme.primary),
              onPressed: () => _onAddPressed(_searchController.text),
              tooltip: '添加模型',
            ),
          ),
          onSubmitted: (value) => _onAddPressed(value),
        ),

        // 内联建议列表
        if (suggestions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Card(
              margin: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 200),
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: suggestions.length,
                  itemBuilder: (context, index) {
                    final id = suggestions[index];
                    return InkWell(
                      onTap: () => _onSuggestionTap(id),
                      borderRadius: index == suggestions.length - 1
                          ? BorderRadius.vertical(bottom: Radius.circular(10))
                          : null,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.smart_toy_outlined, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                id,
                                style: theme.textTheme.bodyMedium,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// 点击内联建议项
  Future<void> _onSuggestionTap(String modelId) async {
    // 清空输入框并隐藏建议列表
    _searchController.clear();
    // 去掉焦点以收起键盘（可选）
    _searchFocusNode.unfocus();
    await _onModelSelected(modelId);
  }

  /// 空模型列表提示
  Widget _buildEmptyModels(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Icon(
            Icons.model_training,
            size: 40,
            color: theme.colorScheme.outline,
          ),
          const SizedBox(height: 8),
          Text(
            '尚未添加任何模型',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '在上方输入框中搜索或输入模型 ID 进行添加',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }

  /// 单个模型卡片
  Widget _buildModelCard(ThemeData theme, ModelInfo model) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            // 模型类型图标
            _buildModelTypeIcon(theme, model.type),
            const SizedBox(width: 10),
            // 模型 ID + 类型/标签描述
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    model.id,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _modelMetaLabel(model),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            // 操作按钮
            IconButton(
              icon: Icon(
                Icons.delete_outline,
                size: 20,
                color: theme.colorScheme.error,
              ),
              onPressed: () => _onDeleteModel(model.uid),
              tooltip: '删除模型',
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }

  /// 模型类型对应的小图标
  Widget _buildModelTypeIcon(ThemeData theme, ModelType type) {
    final (IconData icon, Color color) = switch (type) {
      ModelType.text => (Icons.text_fields, Colors.indigo),
      ModelType.image => (Icons.image, Colors.teal),
      ModelType.video => (Icons.movie, Colors.deepOrange),
      ModelType.speech => (Icons.multitrack_audio, Colors.pink),
      ModelType.embedding => (Icons.grid_view, Colors.blueGrey),
      ModelType.ranking => (Icons.sort, Colors.brown),
    };

    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, size: 20, color: color),
    );
  }

  /// 模型元信息描述文本，如 "LLM · 文本+视觉"
  String _modelMetaLabel(ModelInfo model) {
    final typeLabel = model.type.displayName;
    if (model.type != ModelType.text) return typeLabel;
    if (model.tags.isEmpty) return typeLabel;
    return '$typeLabel · ${model.tags.map((t) => t.displayName).join("+")}';
  }
}

// ==================== 辅助组件 ====================

class _DialogLabel extends StatelessWidget {
  final String text;

  const _DialogLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
    );
  }
}
