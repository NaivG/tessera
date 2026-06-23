import '../models/conversation_mode.dart';
import 'app_localizations.dart';

/// 为 [AppLocalizations] 提供对话模式的本地化便捷方法。
///
/// 用法:
/// ```dart
/// final l10n = AppLocalizations.of(context)!;
/// final name = l10n.modeName(ConversationMode.plan); // "计划" / "Plan"
/// ```
extension ConversationModeLocalization on AppLocalizations {
  /// 返回 [ConversationMode] 的本地化显示名称。
  String modeName(ConversationMode mode) {
    return switch (mode) {
      ConversationMode.normal => modeNormal,
      ConversationMode.plan => modePlan,
      ConversationMode.agent => modeAgent,
      ConversationMode.agentCluster => modeAgentCluster,
    };
  }
}