import 'package:flutter/material.dart';

import '../../models/llm_provider_config.dart';
import '../../models/model_info.dart';
import '../../state/settings_state.dart';
import 'model_edit_page.dart';
import 'model_selection_page.dart';

/// 设置页面
///
/// 管理 LLM 提供商配置列表：
/// - 添加/删除/选择提供商配置
/// - 为每个配置编辑名称、API Key、Base URL
/// - 为每个配置添加/删除模型，选择当前模型
class SettingsPage extends StatefulWidget {
  final SettingsState settingsState;

  const SettingsPage({super.key, required this.settingsState});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = widget.settingsState;

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListenableBuilder(
        listenable: state,
        builder: (context, _) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // --- 用户档案 ---
              _SectionHeader('用户'),
              const SizedBox(height: 8),
              ListTile(
                leading: Icon(Icons.person_outline,
                    color: theme.colorScheme.primary),
                title: const Text('用户档案'),
                subtitle: Text(
                  state.userDisplayName.isNotEmpty
                      ? state.userDisplayName
                      : '设置个人信息以让 AI 更好地了解你',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                trailing: const Icon(Icons.chevron_right),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                tileColor: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.5),
                onTap: () {
                  Navigator.of(context).pushNamed('/profile');
                },
              ),
              const Divider(height: 24),

              // --- 提供商配置列表 ---
              _SectionHeader('LLM 提供商'),
              const SizedBox(height: 8),

              if (state.providerConfigs.isEmpty)
                _buildEmptyHint(theme)
              else
                ...state.providerConfigs.map(
                  (config) => _buildProviderCard(theme, config),
                ),

              const SizedBox(height: 12),

              // 添加提供商按钮
              OutlinedButton.icon(
                onPressed: () => _showAddProviderDialog(context),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('添加提供商'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),

              const Divider(height: 24),

              // 模型选择入口
              _SectionHeader('模型选择'),
              const SizedBox(height: 8),
              ListTile(
                leading: Icon(Icons.tune, color: theme.colorScheme.primary),
                title: const Text('模型分配'),
                subtitle: const Text('为各能力方向（文本/视觉/语音/嵌入等）指定模型'),
                trailing: const Icon(Icons.chevron_right),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                tileColor: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.5),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ModelSelectionPage(
                        settingsState: state,
                      ),
                    ),
                  );
                },
              ),

              const Divider(height: 40),

              // 请求设置
              _SectionHeader('请求'),
              const SizedBox(height: 8),
              SwitchListTile(
                title: const Text('启用流式请求'),
                subtitle: const Text('实时显示 AI 回复，关闭后等待完整回复'),
                value: state.streamEnabled,
                onChanged: (v) => state.setStreamEnabled(v),
              ),
              const Divider(height: 8),
              SwitchListTile(
                title: const Text('启用深度思考'),
                subtitle: const Text('显示模型的推理思考过程（部分模型默认开启）'),
                value: state.deepThinkingEnabled,
                onChanged: (v) => state.setDeepThinkingEnabled(v),
              ),

              const Divider(height: 32),

              // 语音设置
              _SectionHeader('语音'),
              const SizedBox(height: 8),
              SwitchListTile(
                title: const Text('启用文字转语音 (TTS)'),
                subtitle: const Text('AI 回复时自动朗读'),
                value: state.ttsEnabled,
                onChanged: (v) => state.setTtsEnabled(v),
              ),
              SwitchListTile(
                title: const Text('启用语音输入 (STT)'),
                subtitle: const Text('通过语音输入消息'),
                value: state.sttEnabled,
                onChanged: (v) => state.setSttEnabled(v),
              ),

              const Divider(height: 32),

              // 提示词设置
              _SectionHeader('提示词'),
              const SizedBox(height: 8),
              SwitchListTile(
                title: const Text('轻量模式'),
                subtitle: const Text(
                  '大幅缩减系统提示词，仅保留核心约束并不再限制安全指令，开启后跳过记忆加载。',
                ),
                value: state.lightweightSystemPrompt,
                onChanged: (v) => state.setLightweightSystemPrompt(v),
                secondary: Icon(Icons.compress_outlined,
                    color: theme.colorScheme.primary),
              ),
              const Divider(height: 8),
              _buildCustomPromptTile(theme, state),
            ],
          );
        },
      ),
    );
  }

  // ==================== 提供商卡片 ====================

  Widget _buildProviderCard(
    ThemeData theme,
    LlmProviderConfig config,
  ) {
    final state = widget.settingsState;
    final providerId = config.id;
    final needsApiKey = LlmProviderConfig.formatNeedsApiKey(config.format);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 头部：格式标签 + 状态 + 操作按钮
            Row(
              children: [
                _buildFormatChip(theme, config.format),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    config.displayName,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, size: 20),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('编辑')),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text('删除', style: TextStyle(color: Colors.red)),
                    ),
                  ],
                  onSelected: (action) {
                    switch (action) {
                      case 'edit':
                        _showEditProviderDialog(context, providerId, config);
                        break;
                      case 'delete':
                        _confirmDeleteProvider(providerId, config);
                        break;
                    }
                  },
                ),
              ],
            ),

            const SizedBox(height: 8),

            // 配置行
            if (config.baseUrl.isNotEmpty)
              _buildInfoRow(theme, 'Base URL', config.baseUrl),
            if (config.apiKey.isNotEmpty)
              _buildInfoRow(
                theme,
                'API Key',
                '${config.apiKey.substring(0, 8)}…',
              ),
            if (!needsApiKey) _buildInfoRow(theme, 'API Key', '(无需)'),

            // 模型列表
            if (config.models.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('模型 (${config.models.length}):', style: theme.textTheme.labelMedium),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                  children: config.models.map((modelInfo) {
                    return InputChip(
                      label: Text(
                        _modelChipLabel(modelInfo),
                        style: const TextStyle(fontSize: 12),
                      ),
                      onDeleted: () => state.removeModel(providerId, modelInfo.uid),
                      visualDensity: VisualDensity.compact,
                    );
                  }).toList(),
              ),
            ],

            const SizedBox(height: 4),
            // 编辑模型按钮
            TextButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ModelEditPage(
                      providerId: providerId,
                      config: config,
                      settingsState: state,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.edit, size: 16),
              label: const Text('编辑模型', style: TextStyle(fontSize: 13)),
            ),
          ],
        ),
      ),
    );
  }

  /// 模型 Chip 的标签文本：模型ID + 类型/标签简写
  String _modelChipLabel(ModelInfo model) {
    final typeStr = model.type.shortName;
    final tagsStr = model.isOmni
        ? 'omni'
        : (model.tags.length == 1 && model.tags.first == ModelTag.text
            ? ''
            : model.tagsShortLabel);
    final suffix = tagsStr.isNotEmpty ? ' [$typeStr · $tagsStr]' : ' [$typeStr]';
    return '${model.id}$suffix';
  }

  Widget _buildFormatChip(ThemeData theme, String format) {
    final (IconData icon, Color? color) = switch (format) {
      'openai' => (Icons.auto_awesome, Colors.teal),
      'anthropic' => (Icons.psychology, Colors.deepOrange),
      'ollama' => (Icons.computer, Colors.blueGrey),
      'google' => (Icons.lightbulb, Colors.amber),
      _ => (Icons.smart_toy, null),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: (color ?? theme.colorScheme.secondaryContainer).withValues(
          alpha: 0.3,
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            LlmProviderConfig.formatDisplayName(format),
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(ThemeData theme, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Text(
        '$label: $value',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildEmptyHint(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Icon(Icons.cloud_off, size: 40, color: theme.colorScheme.outline),
          const SizedBox(height: 8),
          Text(
            '尚未配置任何 LLM 提供商',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '点击下方按钮添加',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }

  // ==================== 对话框 ====================

  /// 添加提供商
  Future<void> _showAddProviderDialog(BuildContext context) async {
    final state = widget.settingsState;
    final nameCtrl = TextEditingController();
    final apiKeyCtrl = TextEditingController();
    final baseUrlCtrl = TextEditingController();
    String selectedFormat = 'openai';

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDlgState) {
            final needsApiKey = LlmProviderConfig.formatNeedsApiKey(
              selectedFormat,
            );
            return AlertDialog(
              title: const Text('添加 LLM 提供商'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 格式选择
                    _DialogLabel('提供商格式'),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      children: ['openai', 'anthropic', 'ollama', 'google'].map(
                        (fmt) {
                          final isSel = fmt == selectedFormat;
                          return ChoiceChip(
                            label: Text(
                              LlmProviderConfig.formatDisplayName(fmt),
                            ),
                            selected: isSel,
                            onSelected: (_) =>
                                setDlgState(() => selectedFormat = fmt),
                            visualDensity: VisualDensity.compact,
                          );
                        },
                      ).toList(),
                    ),
                    const SizedBox(height: 16),
                    // 名称
                    _DialogLabel('提供商名称（留空使用格式名称）'),
                    const SizedBox(height: 6),
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        hintText: '如: DeepSeek、自定义代理...',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Base URL
                    _DialogLabel('Base URL'),
                    const SizedBox(height: 6),
                    TextField(
                      controller: baseUrlCtrl,
                      decoration: InputDecoration(
                        hintText: LlmProviderConfig.defaultBaseUrlFor(
                          selectedFormat,
                        ),
                        isDense: true,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // API Key
                    _DialogLabel(needsApiKey ? 'API Key' : 'API Key（无需）'),
                    const SizedBox(height: 6),
                    TextField(
                      controller: apiKeyCtrl,
                      obscureText: true,
                      enabled: needsApiKey,
                      decoration: InputDecoration(
                        hintText: needsApiKey
                            ? '输入 API Key...'
                            : '(Ollama 不需要 API Key)',
                        isDense: true,
                        border: const OutlineInputBorder(),
                      ),
                    ),
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
                    Navigator.pop(ctx, {
                      'format': selectedFormat,
                      'name': nameCtrl.text.trim(),
                      'apiKey': apiKeyCtrl.text.trim(),
                      'baseUrl': baseUrlCtrl.text.trim(),
                    });
                  },
                  child: const Text('添加'),
                ),
              ],
            );
          },
        );
      },
    );

    // the widget might unmount later, so we don't dispose them here
    // nameCtrl.dispose();
    // apiKeyCtrl.dispose();
    // baseUrlCtrl.dispose();

    if (result != null) {
      await state.addProviderConfig(
        format: result['format']!,
        name: result['name']!,
        apiKey: result['apiKey']!,
        baseUrl: result['baseUrl']!,
      );
    }
  }

  /// 编辑提供商
  Future<void> _showEditProviderDialog(
    BuildContext context,
    String providerId,
    LlmProviderConfig config,
  ) async {
    final state = widget.settingsState;
    final nameCtrl = TextEditingController(text: config.name);
    final apiKeyCtrl = TextEditingController(text: config.apiKey);
    final baseUrlCtrl = TextEditingController(text: config.baseUrl);

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) {
        final needsApiKey = LlmProviderConfig.formatNeedsApiKey(config.format);
        return AlertDialog(
          title: Text('编辑 ${config.displayName}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DialogLabel('提供商名称（留空使用格式名称）'),
                const SizedBox(height: 6),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    hintText: '如: DeepSeek、自定义代理...',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                _DialogLabel('Base URL'),
                const SizedBox(height: 6),
                TextField(
                  controller: baseUrlCtrl,
                  decoration: InputDecoration(
                    hintText: LlmProviderConfig.defaultBaseUrlFor(
                      config.format,
                    ),
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                _DialogLabel(needsApiKey ? 'API Key' : 'API Key（无需）'),
                const SizedBox(height: 6),
                TextField(
                  controller: apiKeyCtrl,
                  obscureText: true,
                  enabled: needsApiKey,
                  decoration: const InputDecoration(
                    hintText: '留空不修改...',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
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
                Navigator.pop(ctx, {
                  'name': nameCtrl.text.trim(),
                  'apiKey': apiKeyCtrl.text.trim(),
                  'baseUrl': baseUrlCtrl.text.trim(),
                });
              },
              child: const Text('保存'),
            ),
          ],
        );
      },
    );

    // the widget might unmount later, so we don't dispose them here
    // nameCtrl.dispose();
    // apiKeyCtrl.dispose();
    // baseUrlCtrl.dispose();

    if (result != null) {
      await state.updateProviderConfig(
        providerId,
        name: result['name']!.isEmpty ? null : result['name'],
        apiKey: result['apiKey']!.isEmpty ? null : result['apiKey'],
        baseUrl: result['baseUrl']!.isEmpty ? null : result['baseUrl'],
        clearName: result['name']!.isEmpty,
        clearApiKey: result['apiKey']!.isEmpty,
        clearBaseUrl: result['baseUrl']!.isEmpty,
      );
    }
  }

  /// 确认删除提供商
  Future<void> _confirmDeleteProvider(
    String providerId,
    LlmProviderConfig config,
  ) async {
    final theme = Theme.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除提供商'),
        content: Text('确定要删除「${config.displayName}」及其所有模型配置吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('删除', style: TextStyle(color: theme.colorScheme.error)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await widget.settingsState.removeProviderConfig(providerId);
    }
  }

  // ==================== 自定义系统提示 ====================

  Widget _buildCustomPromptTile(ThemeData theme, SettingsState state) {
    final prompt = state.userCustomPrompt;
    final hasContent = prompt.trim().isNotEmpty;

    return ListTile(
      leading: Icon(Icons.auto_awesome, color: theme.colorScheme.primary),
      title: const Text('自定义提示词注入'),
      subtitle: Text(
        hasContent
            ? '${prompt.length} 个字符 · ${prompt.length > 60 ? '${prompt.substring(0, 60)}…' : prompt}'
            : '未设置',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: const Icon(Icons.chevron_right),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      tileColor: theme.colorScheme.surfaceContainerHighest
          .withValues(alpha: 0.5),
      onTap: () => _showEditCustomPromptDialog(context),
    );
  }

  Future<void> _showEditCustomPromptDialog(BuildContext context) async {
    final state = widget.settingsState;
    final textCtrl = TextEditingController(text: state.userCustomPrompt);

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('自定义提示词注入'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DialogLabel('系统提示词'),
                const SizedBox(height: 6),
                Text(
                  '在此输入的内容将注入到系统提示的 "用户自定义指令" 块中。留空则不注入。',
                  style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                        color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: textCtrl,
                  maxLines: 8,
                  minLines: 3,
                  decoration: const InputDecoration(
                    hintText: '例如：用简洁风格回答，优先使用中文…',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, textCtrl.text),
              child: const Text('保存'),
            ),
          ],
        );
      },
    );

    if (result != null) {
      await state.setUserCustomPrompt(result.trim());
    }
  }
}

// ==================== 辅助组件 ====================

class _SectionHeader extends StatelessWidget {
  final String text;

  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
    );
  }
}

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