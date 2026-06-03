import 'package:flutter/material.dart';

import 'package:tessera/l10n/app_localizations.dart';

import '../../state/settings_state.dart';

/// 用户档案页面 — 编辑用户基础信息
///
/// 信息将注入系统提示的 Block 2 (User Profile & Long‑Term Memory)，
/// 用于 AI 个性化回复。
class UserProfilePage extends StatefulWidget {
  final SettingsState settingsState;

  const UserProfilePage({super.key, required this.settingsState});

  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage> {
  late final TextEditingController _displayNameCtrl;
  late final TextEditingController _aliasCtrl;
  late final TextEditingController _roleCtrl;
  late final TextEditingController _preferencesCtrl;
  late final TextEditingController _factsCtrl;

  bool _saving = false;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    final state = widget.settingsState;
    _displayNameCtrl = TextEditingController(text: state.userDisplayName);
    _aliasCtrl = TextEditingController(text: state.userAlias);
    _roleCtrl = TextEditingController(text: state.userRole);
    _preferencesCtrl = TextEditingController(text: state.userPreferences);
    _factsCtrl = TextEditingController(text: state.userFacts);

    // 监听变更标记
    for (final ctrl in [
      _displayNameCtrl,
      _aliasCtrl,
      _roleCtrl,
      _preferencesCtrl,
      _factsCtrl,
    ]) {
      ctrl.addListener(_onFieldChanged);
    }
  }

  void _onFieldChanged() {
    if (!_hasChanges) {
      setState(() => _hasChanges = true);
    }
  }

  @override
  void dispose() {
    for (final ctrl in [
      _displayNameCtrl,
      _aliasCtrl,
      _roleCtrl,
      _preferencesCtrl,
      _factsCtrl,
    ]) {
      ctrl.removeListener(_onFieldChanged);
      ctrl.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.settingsState.setUserProfile(
        displayName: _displayNameCtrl.text.trim(),
        alias: _aliasCtrl.text.trim(),
        role: _roleCtrl.text.trim(),
        preferences: _preferencesCtrl.text.trim(),
        facts: _factsCtrl.text.trim(),
      );
      setState(() => _hasChanges = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.profileSavedSnackbar),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _onWillPop() async {
    if (!_hasChanges) return true;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.profileUnsavedDialogTitle),
        content: Text(
          AppLocalizations.of(context)!.profileUnsavedDialogContent,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(AppLocalizations.of(context)!.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(AppLocalizations.of(context)!.profileLeave),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = widget.settingsState;
    final hasAnyContent =
        state.userDisplayName.isNotEmpty ||
        state.userAlias.isNotEmpty ||
        state.userRole.isNotEmpty ||
        state.userPreferences.isNotEmpty ||
        state.userFacts.isNotEmpty;

    return PopScope(
      canPop: !_hasChanges,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        final shouldPop = await _onWillPop();
        if (shouldPop && mounted) navigator.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(AppLocalizations.of(context)!.profileAppBarTitle),
          actions: [
            if (_hasChanges)
              TextButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save, size: 18),
                label: Text(
                  _saving
                      ? AppLocalizations.of(context)!.profileSaving
                      : AppLocalizations.of(context)!.profileSave,
                ),
              ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // 页面说明
            Card(
              color: theme.colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        AppLocalizations.of(context)!.profileInfoCard,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 基本信息
            _SectionHeader(AppLocalizations.of(context)!.profileSectionBasic),
            const SizedBox(height: 12),
            _buildTextField(
              controller: _displayNameCtrl,
              label: AppLocalizations.of(context)!.profileDisplayName,
              hint: AppLocalizations.of(context)!.profileDisplayNameHint,
              icon: Icons.badge_outlined,
            ),
            const SizedBox(height: 12),
            _buildTextField(
              controller: _aliasCtrl,
              label: AppLocalizations.of(context)!.profileAlias,
              hint: AppLocalizations.of(context)!.profileAliasHint,
              icon: Icons.alternate_email_outlined,
            ),
            const SizedBox(height: 12),
            _buildTextField(
              controller: _roleCtrl,
              label: AppLocalizations.of(context)!.profileRole,
              hint: AppLocalizations.of(context)!.profileRoleHint,
              icon: Icons.work_outline,
            ),

            const Divider(height: 32),

            // 个性化信息
            _SectionHeader(
              AppLocalizations.of(context)!.profileSectionPersonalization,
            ),
            const SizedBox(height: 12),
            _buildTextField(
              controller: _preferencesCtrl,
              label: AppLocalizations.of(context)!.profilePreferences,
              hint: AppLocalizations.of(context)!.profilePreferencesHint,
              icon: Icons.tune_outlined,
              maxLines: 4,
            ),
            const SizedBox(height: 12),
            _buildTextField(
              controller: _factsCtrl,
              label: AppLocalizations.of(context)!.profileFacts,
              hint: AppLocalizations.of(context)!.profileFactsHint,
              icon: Icons.fact_check_outlined,
              maxLines: 4,
            ),

            const SizedBox(height: 24),

            // 底部操作
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save),
              label: Text(
                _saving
                    ? AppLocalizations.of(context)!.profileSaving
                    : AppLocalizations.of(context)!.profileSaveButton,
              ),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 8),

            // 清除按钮
            if (hasAnyContent)
              TextButton.icon(
                onPressed: _confirmClear,
                icon: const Icon(Icons.delete_outline, size: 18),
                label: Text(AppLocalizations.of(context)!.profileClearButton),
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    String? hint,
    IconData? icon,
    int maxLines = 1,
  }) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 16, color: theme.colorScheme.primary),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              maxLines: maxLines,
              minLines: 1,
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant.withValues(
                    alpha: 0.6,
                  ),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                isDense: true,
              ),
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmClear() async {
    final theme = Theme.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.profileClearDialogTitle),
        content: Text(AppLocalizations.of(context)!.profileClearDialogContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(AppLocalizations.of(context)!.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              AppLocalizations.of(context)!.commonClear,
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      _displayNameCtrl.clear();
      _aliasCtrl.clear();
      _roleCtrl.clear();
      _preferencesCtrl.clear();
      _factsCtrl.clear();
      setState(() => _hasChanges = true);
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
