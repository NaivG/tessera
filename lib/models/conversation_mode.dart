/// 对话模式
enum ConversationMode {
  /// 普通对话
  normal,

  /// AI 先制定计划后逐步执行
  plan,

  /// AI 可调用子 Agent 执行任务
  agent,

  /// Plan 后拆分多个子 Agent 并行执行
  agentCluster;

  /// 从字符串名称解析
  static ConversationMode fromName(String name) {
    return ConversationMode.values.firstWhere(
      (m) => m.name == name,
      orElse: () => ConversationMode.normal,
    );
  }
}