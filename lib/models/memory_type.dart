/// 记忆类型枚举
///
/// 每种类型有不同的生命周期、遗忘阈值和提取策略。
enum MemoryType {
  /// 用户记忆：关于用户的偏好、身份、习惯等信息
  /// - 生命周期：永久（高重要性）
  /// - 遗忘阈值：0.05（几乎不遗忘）
  user,

  /// 知识记忆：事实、知识点、技术信息
  /// - 生命周期：永久（中等重要性）
  /// - 遗忘阈值：0.1
  knowledge,

  /// 事件记忆：发生过的事情、完成的任务
  /// - 生命周期：长期（中低重要性）
  /// - 遗忘阈值：0.2（较快遗忘）
  event,

  /// 对话记忆：当前对话的摘要
  /// - 生命周期：与对话同生命周期
  /// - 对话结束时统一清理
  conversational,

  /// 长期记忆：从上述类型人工确认提升而来的跨对话持久化记忆
  /// - 生命周期：永久
  longTerm,
}

/// 从字符串反序列化 MemoryType
MemoryType memoryTypeFromName(String name) {
  return MemoryType.values.firstWhere(
    (t) => t.name == name,
    orElse: () => MemoryType.event,
  );
}

/// 各记忆类型的遗忘阈值
///
/// 遗忘评分 = importance × confidence × timeDecay × accessDecay
/// 当遗忘评分 < 阈值时，移入归档表。
extension MemoryTypeForgetting on MemoryType {
  double get forgettingThreshold {
    switch (this) {
      case MemoryType.user:
      case MemoryType.longTerm:
        return 0.05;
      case MemoryType.knowledge:
        return 0.1;
      case MemoryType.event:
        return 0.2;
      case MemoryType.conversational:
        return 0.0; // 对话结束时统一清理，不参与遗忘评分
    }
  }
}
