import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/workspace_service.dart';

/// WorkspaceService 单例 Provider — 镜像 settingsServiceProvider 风格
final workspaceServiceProvider = Provider<WorkspaceService>(
  (ref) => WorkspaceService.instance,
);
