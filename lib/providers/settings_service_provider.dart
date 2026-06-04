import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/settings_service.dart';

/// SettingsService 实例提供者（一次性创建，单例）
final settingsServiceProvider = Provider<SettingsService>((ref) {
  return SettingsService();
});
