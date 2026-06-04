import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/memory_service.dart';

/// MemoryService 实例提供者
///
/// 退出时自动关闭数据库连接。
final memoryServiceProvider = Provider<MemoryService>((ref) {
  final service = MemoryService();
  ref.onDispose(() => service.close());
  return service;
});
