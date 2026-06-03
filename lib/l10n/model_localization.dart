import '../models/model_info.dart';
import 'app_localizations.dart';

/// 为 [AppLocalizations] 提供模型类型/标签的本地化便捷方法。
///
/// 用法：
/// ```dart
/// final l10n = AppLocalizations.of(context)!;
/// final name = l10n.modelTypeName(ModelType.text);       // "文本生成" / "Text Generation"
/// final tag  = l10n.modelTagName(ModelTag.vision);         // "视觉" / "Vision"
/// final label = l10n.modelTagsLabel(someModel);            // "全模态" / "Omni-modal"
/// ```
extension ModelLocalization on AppLocalizations {
  /// 返回 [ModelType] 的本地化显示名称。
  String modelTypeName(ModelType type) {
    return switch (type) {
      ModelType.text => modelTypeText,
      ModelType.image => modelTypeImage,
      ModelType.video => modelTypeVideo,
      ModelType.speech => modelTypeSpeech,
      ModelType.embedding => modelTypeEmbedding,
      ModelType.ranking => modelTypeRanking,
    };
  }

  /// 返回 [ModelTag] 的本地化显示名称。
  String modelTagName(ModelTag tag) {
    return switch (tag) {
      ModelTag.text => modelTagText,
      ModelTag.vision => modelTagVision,
      ModelTag.audible => modelTagAudible,
      ModelTag.video => modelTagVideo,
    };
  }

  /// 返回 [ModelInfo] 标签组合的本地化描述字符串。
  ///
  /// - 全模态 → "全模态" / "Omni-modal"
  /// - 纯文本 → "纯文本" / "Text-only"
  /// - 组合   → "文本+视觉" / "Text+Vision"
  String modelTagsLabel(ModelInfo model) {
    if (model.isOmni) return modelTagsOmni;
    if (model.tags.length == 1 && model.tags.first == ModelTag.text) {
      return modelTagsTextOnly;
    }
    return model.tags.map(modelTagName).join('+');
  }
}
