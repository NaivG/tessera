import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/conversation.dart';
import '../services/conversation_service.dart';

/// 对话列表状态管理 —— 响应式更新侧边栏
class ConversationListNotifier extends Notifier<List<Conversation>> {
  final ConversationService _convService = ConversationService();

  @override
  List<Conversation> build() {
    // 异步加载初始列表；初始返回空列表避免 null
    _load();
    return [];
  }

  Future<void> _load() async {
    try {
      final list = await _convService.listConversations();
      state = list;
    } catch (_) {
      state = [];
    }
  }

  /// 刷新整个列表（从数据库重新加载）
  Future<void> refresh() => _load();

  /// 新建或更新对话时调用 —— 插入列表头部，去重
  void upsert(Conversation conv) {
    state = [conv, ...state.where((c) => c.id != conv.id)];
  }

  /// 删除对话
  void remove(String id) {
    state = state.where((c) => c.id != id).toList();
  }

  /// 更新对话标题
  void updateTitle(String id, String newTitle) {
    state = state.map((c) {
      if (c.id == id) c.title = newTitle;
      return c;
    }).toList();
  }
}

/// 对话列表 provider
final conversationListProvider =
    NotifierProvider<ConversationListNotifier, List<Conversation>>(
  ConversationListNotifier.new,
);
