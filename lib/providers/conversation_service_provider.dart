import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/conversation_service.dart';

/// ConversationService 实例提供者（一次性创建，单例）
final conversationServiceProvider = Provider<ConversationService>((ref) {
  return ConversationService();
});
