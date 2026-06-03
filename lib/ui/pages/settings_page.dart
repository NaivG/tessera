import 'package:flutter/material.dart';
import 'package:tessera/l10n/app_localizations.dart';
import 'package:tessera/l10n/app_localizations_en.dart';
import 'package:tessera/l10n/app_localizations_zh.dart';
import 'package:url_launcher/url_launcher.dart';

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
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: ListenableBuilder(
        listenable: state,
        builder: (context, _) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // --- 语言设置 ---
              _SectionHeader(l10n.settingsSectionLanguage),
              const SizedBox(height: 8),
              _buildLocaleSelector(theme, state, l10n),
              const Divider(height: 24),

              // --- 用户档案 ---
              _SectionHeader(l10n.settingsSectionUser),
              const SizedBox(height: 8),
              ListTile(
                leading: Icon(
                  Icons.person_outline,
                  color: theme.colorScheme.primary,
                ),
                title: Text(l10n.settingsUserProfile),
                subtitle: Text(
                  state.userDisplayName.isNotEmpty
                      ? state.userDisplayName
                      : l10n.settingsUserProfileSubtitle,
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
                tileColor: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.5,
                ),
                onTap: () {
                  Navigator.of(context).pushNamed('/profile');
                },
              ),
              const Divider(height: 24),

              // --- 提供商配置列表 ---
              _SectionHeader(l10n.settingsSectionLlmProviders),
              const SizedBox(height: 8),

              if (state.providerConfigs.isEmpty)
                _buildEmptyHint(theme, l10n)
              else
                ...state.providerConfigs.map(
                  (config) => _buildProviderCard(theme, config),
                ),

              const SizedBox(height: 12),

              // 添加提供商按钮
              OutlinedButton.icon(
                onPressed: () => _showAddProviderDialog(context),
                icon: const Icon(Icons.add, size: 18),
                label: Text(l10n.settingsAddProvider),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),

              const Divider(height: 24),

              // 模型选择入口
              _SectionHeader(l10n.settingsSectionModelSelection),
              const SizedBox(height: 8),
              ListTile(
                leading: Icon(Icons.tune, color: theme.colorScheme.primary),
                title: Text(l10n.settingsModelAssignment),
                subtitle: Text(l10n.settingsModelAssignmentSubtitle),
                trailing: const Icon(Icons.chevron_right),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                tileColor: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.5,
                ),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ModelSelectionPage(settingsState: state),
                    ),
                  );
                },
              ),

              const Divider(height: 40),

              // 请求设置
              _SectionHeader(l10n.settingsSectionRequest),
              const SizedBox(height: 8),
              SwitchListTile(
                title: Text(l10n.settingsStreamEnabled),
                subtitle: Text(l10n.settingsStreamEnabledSubtitle),
                value: state.streamEnabled,
                onChanged: (v) => state.setStreamEnabled(v),
              ),
              const Divider(height: 8),
              SwitchListTile(
                title: Text(l10n.settingsDeepThinking),
                subtitle: Text(l10n.settingsDeepThinkingSubtitle),
                value: state.deepThinkingEnabled,
                onChanged: (v) => state.setDeepThinkingEnabled(v),
              ),

              const Divider(height: 32),

              // 语音设置
              _SectionHeader(l10n.settingsSectionSpeech),
              const SizedBox(height: 8),
              SwitchListTile(
                title: Text(l10n.settingsTtsEnabled),
                subtitle: Text(l10n.settingsTtsEnabledSubtitle),
                value: state.ttsEnabled,
                onChanged: (v) => state.setTtsEnabled(v),
              ),
              SwitchListTile(
                title: Text(l10n.settingsSttEnabled),
                subtitle: Text(l10n.settingsSttEnabledSubtitle),
                value: state.sttEnabled,
                onChanged: (v) => state.setSttEnabled(v),
              ),

              const Divider(height: 32),

              // 提示词设置
              _SectionHeader(l10n.settingsSectionPrompt),
              const SizedBox(height: 8),
              SwitchListTile(
                title: Text(l10n.settingsLightweightMode),
                subtitle: Text(l10n.settingsLightweightModeSubtitle),
                value: state.lightweightSystemPrompt,
                onChanged: (v) => state.setLightweightSystemPrompt(v),
                secondary: Icon(
                  Icons.compress_outlined,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 8),
              _buildCustomPromptTile(theme, state),

              const Divider(height: 24),
              _SectionHeader(l10n.settingsSectionAbout),
              const SizedBox(height: 8),
              ListTile(
                leading: Icon(
                  Icons.info_outline,
                  color: theme.colorScheme.primary,
                ),
                title: const Text('Tessera'),
                subtitle: const Text('v1.0.0'),
                trailing: const Icon(Icons.chevron_right),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                tileColor: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.5,
                ),
                onTap: () => _showAboutDialog(context),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: Icon(
                  Icons.open_in_new,
                  color: theme.colorScheme.primary,
                ),
                title: const Text('GitHub'),
                subtitle: const Text('Check out the source code'),
                trailing: const Icon(Icons.chevron_right),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                tileColor: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.5,
                ),
                onTap: () {
                  final url = Uri.parse('https://github.com/NaivG/tessera');
                  launchUrl(url, mode: LaunchMode.externalApplication);
                },
              ),
            ],
          );
        },
      ),
    );
  }

  // ==================== 语言选择器 (对话框) ====================

  Widget _buildLocaleSelector(
    ThemeData theme,
    SettingsState state,
    AppLocalizations l10n,
  ) {
    final currentLocale = state.locale;

    // 直接实例化各语言类，获取目标语言的 localeDescription 和 createdBy
    final enL10n = AppLocalizationsEn();
    final zhL10n = AppLocalizationsZh();

    final currentLabel = switch (currentLocale) {
      'zh' => zhL10n.localeDescription,
      'en' => enL10n.localeDescription,
      _ => l10n.settingsLanguageSystem,
    };

    return ListTile(
      leading: Icon(Icons.language, color: theme.colorScheme.primary),
      title: Text(l10n.settingsSectionLanguage),
      subtitle: Text(
        currentLabel,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: const Icon(Icons.chevron_right),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      tileColor: theme.colorScheme.surfaceContainerHighest.withValues(
        alpha: 0.5,
      ),
      onTap: () =>
          _showLocaleDialog(theme, state, l10n, enL10n, zhL10n, currentLocale),
    );
  }

  void _showLocaleDialog(
    ThemeData theme,
    SettingsState state,
    AppLocalizations l10n,
    AppLocalizations enL10n,
    AppLocalizations zhL10n,
    String currentLocale,
  ) {
    showDialog<String>(
      context: context,
      builder: (ctx) {
        return SimpleDialog(
          title: Text(l10n.settingsSectionLanguage),
          children: [
            _buildLocaleOption(
              ctx,
              theme,
              'system',
              l10n.settingsLanguageSystem,
              null,
              currentLocale,
              state,
            ),
            _buildLocaleOption(
              ctx,
              theme,
              'zh',
              zhL10n.localeDescription,
              zhL10n.createdBy,
              currentLocale,
              state,
            ),
            _buildLocaleOption(
              ctx,
              theme,
              'en',
              enL10n.localeDescription,
              enL10n.createdBy,
              currentLocale,
              state,
            ),
          ],
        );
      },
    );
  }

  Widget _buildLocaleOption(
    BuildContext ctx,
    ThemeData theme,
    String value,
    String title,
    String? subtitle,
    String currentLocale,
    SettingsState state,
  ) {
    final isSelected = currentLocale == value;
    return RadioListTile<String>(
      title: Text(title),
      subtitle: subtitle != null && subtitle.isNotEmpty ? Text(subtitle) : null,
      value: value,
      groupValue: currentLocale,
      onChanged: (v) {
        if (v != null && v != currentLocale) {
          state.setLocale(v);
          Navigator.pop(ctx);
        }
      },
      selected: isSelected,
    );
  }

  // ==================== 提供商卡片 ====================

  Widget _buildProviderCard(ThemeData theme, LlmProviderConfig config) {
    final state = widget.settingsState;
    final l10n = AppLocalizations.of(context)!;
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
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'edit',
                      child: Text(l10n.settingsEdit),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text(
                        l10n.commonDelete,
                        style: const TextStyle(color: Colors.red),
                      ),
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
            if (!needsApiKey)
              _buildInfoRow(theme, 'API Key', l10n.settingsApiKeyOptional),

            // 模型列表
            if (config.models.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                l10n.settingsModelCount(config.models.length),
                style: theme.textTheme.labelMedium,
              ),
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
                    onDeleted: () =>
                        state.removeModel(providerId, modelInfo.uid),
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
              label: Text(
                l10n.settingsEditModel,
                style: const TextStyle(fontSize: 13),
              ),
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
    final suffix = tagsStr.isNotEmpty
        ? ' [$typeStr · $tagsStr]'
        : ' [$typeStr]';
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

  Widget _buildEmptyHint(ThemeData theme, AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Icon(Icons.cloud_off, size: 40, color: theme.colorScheme.outline),
          const SizedBox(height: 8),
          Text(
            l10n.settingsEmptyProviders,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.settingsEmptyProvidersSub,
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
    final l10n = AppLocalizations.of(context)!;
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
              title: Text(l10n.settingsAddProviderDialogTitle),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 格式选择
                    _DialogLabel(l10n.settingsProviderFormat),
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
                    _DialogLabel(l10n.settingsProviderNameLabel),
                    const SizedBox(height: 6),
                    TextField(
                      controller: nameCtrl,
                      decoration: InputDecoration(
                        hintText: l10n.settingsProviderNameHint,
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Base URL
                    _DialogLabel(l10n.settingsBaseUrl),
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
                    _DialogLabel(
                      needsApiKey
                          ? l10n.settingsApiKey
                          : l10n.settingsApiKeyOptional,
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: apiKeyCtrl,
                      obscureText: true,
                      enabled: needsApiKey,
                      decoration: InputDecoration(
                        hintText: needsApiKey
                            ? l10n.settingsApiKeyHint
                            : l10n.settingsApiKeyNotNeeded,
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
                  child: Text(l10n.commonCancel),
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
                  child: Text(l10n.settingsProviderAdd),
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
    final l10n = AppLocalizations.of(context)!;
    final nameCtrl = TextEditingController(text: config.name);
    final apiKeyCtrl = TextEditingController(text: config.apiKey);
    final baseUrlCtrl = TextEditingController(text: config.baseUrl);

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) {
        final needsApiKey = LlmProviderConfig.formatNeedsApiKey(config.format);
        return AlertDialog(
          title: Text(l10n.settingsEditProvider(config.displayName)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DialogLabel(l10n.settingsProviderNameLabel),
                const SizedBox(height: 6),
                TextField(
                  controller: nameCtrl,
                  decoration: InputDecoration(
                    hintText: l10n.settingsProviderNameHint,
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                _DialogLabel(l10n.settingsBaseUrl),
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
                _DialogLabel(
                  needsApiKey
                      ? l10n.settingsApiKey
                      : l10n.settingsApiKeyOptional,
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: apiKeyCtrl,
                  obscureText: true,
                  enabled: needsApiKey,
                  decoration: InputDecoration(
                    hintText: l10n.settingsApiKeyEditHint,
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
              child: Text(l10n.commonCancel),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx, {
                  'name': nameCtrl.text.trim(),
                  'baseUrl': baseUrlCtrl.text.trim(),
                  'apiKey': apiKeyCtrl.text.trim(),
                });
              },
              child: Text(l10n.commonSave),
            ),
          ],
        );
      },
    );

    if (result != null) {
      await state.updateProviderConfig(
        providerId,
        name: result['name'],
        apiKey: result['apiKey'],
        baseUrl: result['baseUrl'],
        clearName: result['name']!.isEmpty,
        clearApiKey: result['apiKey']!.isEmpty,
        clearBaseUrl: result['baseUrl']!.isEmpty,
      );
    }
  }

  Future<void> _confirmDeleteProvider(
    String providerId,
    LlmProviderConfig config,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.settingsDeleteConfirmTitle),
        content: Text(l10n.settingsDeleteConfirm(config.displayName)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: Text(l10n.commonDelete),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await widget.settingsState.removeProviderConfig(providerId);
    }
  }

  // ==================== 自定义提示词 ====================

  Widget _buildCustomPromptTile(ThemeData theme, SettingsState state) {
    final l10n = AppLocalizations.of(context)!;
    final prompt = state.userCustomPrompt;
    final hasContent = prompt.trim().isNotEmpty;

    return ListTile(
      leading: Icon(Icons.auto_awesome, color: theme.colorScheme.primary),
      title: Text(l10n.customPromptEditTitle),
      subtitle: Text(
        hasContent
            ? '${l10n.customPromptLength(prompt.length)} · ${prompt.length > 60 ? '${prompt.substring(0, 60)}…' : prompt}'
            : l10n.notSetting,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: const Icon(Icons.chevron_right),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      tileColor: theme.colorScheme.surfaceContainerHighest.withValues(
        alpha: 0.5,
      ),
      onTap: () => _showEditCustomPromptDialog(context),
    );
  }

  Future<void> _showEditCustomPromptDialog(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final state = widget.settingsState;
    final textCtrl = TextEditingController(text: state.userCustomPrompt);

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(l10n.customPromptEditTitle),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DialogLabel(l10n.systemPrompt),
                const SizedBox(height: 6),
                Text(
                  l10n.customPromptHint,
                  style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: textCtrl,
                  maxLines: 8,
                  minLines: 3,
                  decoration: InputDecoration(
                    hintText: l10n.customPromptHintTemplate,
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l10n.commonCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, textCtrl.text),
              child: Text(l10n.commonSave),
            ),
          ],
        );
      },
    );

    if (result != null) {
      await state.setUserCustomPrompt(result.trim());
    }
  }

  // ==================== 关于对话框 ====================

  void _showAboutDialog(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    showAboutDialog(
      context: context,
      applicationName: 'Tessera',
      applicationVersion: '1.0.0',
      applicationLegalese: '\u00a9 2026 NaivG',
      children: [
        const SizedBox(height: 8),
        Text(
          l10n.chatWelcomeSubtitle,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }
}

// ==================== 辅助组件 ====================

/// 设置页面的分组标题
class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader(this.label);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        label,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

/// 对话框中的标签
class _DialogLabel extends StatelessWidget {
  final String label;
  const _DialogLabel(this.label);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      label,
      style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
    );
  }
}
