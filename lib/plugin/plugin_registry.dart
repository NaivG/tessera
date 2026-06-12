import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../core/core.dart';
import 'lua_plugin_host.dart';
import 'plugin_manager.dart';
import 'plugin_metadata.dart';

// =============================================================================
// 插件注册表 — 管理插件生命周期，集成 ToolRegistry 与 SystemPromptBuilder
//
// 支持两种来源的插件：
// - 捆版插件（assets/plugins/）：随应用捆绑的只读插件
// - 已安装插件（documents/plugins/）：用户安装的可读写插件
// =============================================================================

/// [PluginRegistry] 的状态快照
class PluginRegistryState {
  /// 所有已扫描到的插件元数据（不管启用与否）
  final List<PluginMetadata> allPlugins;

  /// 当前已激活的插件（已 enable 且加载成功）
  final List<String> activePluginIds;

  const PluginRegistryState({
    this.allPlugins = const [],
    this.activePluginIds = const [],
  });

  List<PluginMetadata> get activePlugins =>
      allPlugins.where((p) => activePluginIds.contains(p.id)).toList();
}

/// 插件注册表 — 单例。
class PluginRegistry {
  // ---------------------------------------------------------------------------
  // 单例
  // ---------------------------------------------------------------------------

  PluginRegistry._internal();
  static final PluginRegistry _instance = PluginRegistry._internal();
  factory PluginRegistry() => _instance;

  // ---------------------------------------------------------------------------
  // 内部状态
  // ---------------------------------------------------------------------------

  /// 所有已发现的插件元数据（按 id 索引）
  final Map<String, PluginMetadata> _allMetadata = {};

  /// PluginManager 条目缓存（按相对 id 索引）
  final Map<String, PluginEntry> _allEntries = {};

  /// 已启用的插件宿主（pluginId → LuaPluginHost）
  final Map<String, LuaPluginHost> _activeHosts = {};

  /// 已注册的工具名 → 插件 ID 的映射（用于取消注册）
  final Map<String, String> _toolOwners = {};

  /// 插件相对 id → 来源
  final Map<String, PluginOrigin> _pluginOrigins = {};

  bool _scanned = false;

  // ---------------------------------------------------------------------------
  // 扫描
  // ---------------------------------------------------------------------------

  /// 扫描所有插件（捆版 + 已安装）。
  Future<void> scanAll() async {
    if (_scanned) return;

    // 扫描捆版插件
    final manager = PluginManager();
    final bundled = await manager.scanBundled();
    for (final entry in bundled) {
      _allEntries[entry.relativeId] = entry;
      _allMetadata[entry.metadata.id] = entry.metadata;
      _pluginOrigins[entry.relativeId] = PluginOrigin.bundled;
    }

    // 扫描已安装插件
    await manager.init();
    final installed = await manager.scanInstalled();
    for (final entry in installed) {
      _allEntries[entry.relativeId] = entry;
      _allMetadata[entry.metadata.id] = entry.metadata;
      _pluginOrigins[entry.relativeId] = PluginOrigin.installed;
    }

    _scanned = true;
    debugPrint(
      '[PluginRegistry] 扫描完成: ${bundled.length} 个捆版插件, '
      '${installed.length} 个已安装插件',
    );
  }

  /// 向后兼容：只扫描捆版插件
  Future<void> scanBundled() async {
    if (_scanned) return;

    try {
      final indexJson = await rootBundle.loadString(
        'assets/plugins/plugins_index.json',
      );
      final ids = (jsonDecode(indexJson) as List<dynamic>)
          .map((e) => e as String)
          .toList();

      for (final id in ids) {
        try {
          final meta = await _loadPluginJson(id);
          _allMetadata[id] = meta;
          _pluginOrigins[id] = PluginOrigin.bundled;
          debugPrint('[PluginRegistry] discovered plugin: ${meta.name} ($id)');
        } catch (e) {
          debugPrint('[PluginRegistry] failed to load plugin "$id": $e');
        }
      }

      _scanned = true;
    } catch (e) {
      debugPrint('[PluginRegistry] no bundled plugins found: $e');
      _scanned = true;
    }
  }

  /// 扫描过程中遇到错误仍继续，返回所有成功加载的元数据。
  Future<List<PluginMetadata>> scanBundledSafe() async {
    await scanBundled();
    return _allMetadata.values.toList();
  }

  /// 加载单个插件的 `plugin.json`
  Future<PluginMetadata> _loadPluginJson(String pluginId) async {
    final jsonStr = await rootBundle.loadString(
      'assets/plugins/$pluginId/plugin.json',
    );
    final map = jsonDecode(jsonStr) as Map<String, dynamic>;
    return PluginMetadata.fromJson(map);
  }

  // ---------------------------------------------------------------------------
  // 启用 / 禁用
  // ---------------------------------------------------------------------------

  /// 启用一个插件：创建 Lua 宿主，加载入口脚本。
  Future<bool> enable(String pluginId) async {
    if (_activeHosts.containsKey(pluginId)) {
      debugPrint('[PluginRegistry] plugin "$pluginId" already active');
      return true;
    }

    final meta = _allMetadata[pluginId];
    if (meta == null) {
      debugPrint('[PluginRegistry] plugin "$pluginId" not found');
      return false;
    }

    try {
      final host = LuaPluginHost.create(pluginId);
      host.metadata = meta;

      // 查找插件来源，加载 Lua 入口
      final pluginRelId = _findRelativeId(pluginId);
      final origin = _pluginOrigins[pluginRelId] ?? PluginOrigin.bundled;

      String script;
      if (origin == PluginOrigin.installed) {
        // 从文件系统加载
        final entry = _allEntries[pluginRelId];
        if (entry == null) {
          throw Exception('插件 "$pluginRelId" 无路径信息');
        }
        final entryPath = '${entry.directoryPath}/${meta.entryPoint}';
        script = await File(entryPath).readAsString();
      } else {
        // 从 assets 加载
        script = await rootBundle.loadString(
          'assets/plugins/$pluginRelId/${meta.entryPoint}',
        );
      }

      await host.loadString(script);

      // 记录工具所有者
      for (final tool in host.toolDefinitions) {
        _toolOwners[tool.name] = pluginId;
      }

      _activeHosts[pluginId] = host;
      debugPrint('[PluginRegistry] enabled plugin: ${meta.name}');
      return true;
    } catch (e) {
      debugPrint('[PluginRegistry] failed to enable plugin "$pluginId": $e');
      return false;
    }
  }

  /// 查找插件的相对 id
  String _findRelativeId(String pluginId) {
    for (final entry in _allEntries.entries) {
      if (entry.value.metadata.id == pluginId) return entry.key;
    }
    return pluginId; // fallback
  }

  /// 禁用一个插件
  Future<void> disable(String pluginId) async {
    final host = _activeHosts.remove(pluginId);
    if (host == null) return;

    _toolOwners.removeWhere((_, owner) => owner == pluginId);
    host.dispose();
    debugPrint('[PluginRegistry] disabled plugin: $pluginId');
  }

  /// 启用所有已发现的插件。
  Future<void> enableAll() async {
    await scanAll();
    for (final id in _allMetadata.keys) {
      await enable(id);
    }
  }

  // ---------------------------------------------------------------------------
  // 安装 / 卸载
  // ---------------------------------------------------------------------------

  // ---------------------------------------------------------------------------
  // ZIP 安装
  // ---------------------------------------------------------------------------

  /// 预览插件 ZIP 包：提取到临时目录并读取元数据。
  Future<(PluginMetadata, String)> previewZip(String zipFilePath) async {
    final manager = PluginManager();
    await manager.init();
    return manager.previewZip(zipFilePath);
  }

  /// 安装已预览的临时插件目录到最终位置并自动启用。
  Future<PluginEntry> installFromTemp(
    String tempDirPath,
    PluginMetadata meta,
  ) async {
    final manager = PluginManager();
    await manager.init();
    final entry = await manager.installFromTemp(tempDirPath, meta);

    // 更新内部状态
    _allEntries[entry.relativeId] = entry;
    _allMetadata[entry.metadata.id] = entry.metadata;
    _pluginOrigins[entry.relativeId] = PluginOrigin.installed;

    // 自动启用
    await enable(entry.metadata.id);

    return entry;
  }

  /// 安装插件（从目录）
  Future<PluginEntry> installFromDirectory(String sourceDirPath) async {
    final manager = PluginManager();
    await manager.init();
    final entry = await manager.installFromDirectory(sourceDirPath);

    // 添加到内部状态
    _allEntries[entry.relativeId] = entry;
    _allMetadata[entry.metadata.id] = entry.metadata;
    _pluginOrigins[entry.relativeId] = PluginOrigin.installed;

    return entry;
  }

  /// 从 assets 安装捆版插件到 documents/plugins/
  Future<PluginEntry> installFromAssets(String assetPluginId) async {
    final manager = PluginManager();
    await manager.init();
    final entry = await manager.installFromAssets(assetPluginId);

    // 添加到内部状态
    _allEntries[entry.relativeId] = entry;
    _allMetadata[entry.metadata.id] = entry.metadata;
    _pluginOrigins[entry.relativeId] = PluginOrigin.installed;

    return entry;
  }

  /// 卸载插件
  Future<void> uninstallPlugin(String pluginRelativeId) async {
    // 如果插件已启用，先禁用
    final entry = _allEntries[pluginRelativeId];
    if (entry != null) {
      await disable(entry.metadata.id);
    }

    final manager = PluginManager();
    await manager.init();
    await manager.uninstall(pluginRelativeId);

    // 从内部状态移除
    final removedEntry = _allEntries.remove(pluginRelativeId);
    if (removedEntry != null) {
      _allMetadata.remove(removedEntry.metadata.id);
      _pluginOrigins.remove(pluginRelativeId);
    }
  }

  // ---------------------------------------------------------------------------
  // 集成：ToolRegistry
  // ---------------------------------------------------------------------------

  /// 将当前所有启用插件的工具注册到 [ToolRegistry]。
  void registerTo(ToolRegistry registry, {bool clearFirst = false}) {
    if (clearFirst) {
      for (final name in _toolOwners.keys.toList()) {
        registry.unregister(name);
      }
    }

    for (final host in _activeHosts.values) {
      for (final toolDef in host.toolDefinitions) {
        final toolName = toolDef.name;
        registry.register(
          toolDef,
          (call) => host.callTool(call),
        );
        _toolOwners[toolName] = host.pluginId;
      }
    }
  }

  /// 从 [ToolRegistry] 中移除所有插件注册的工具。
  void unregisterFrom(ToolRegistry registry) {
    for (final name in _toolOwners.keys.toList()) {
      registry.unregister(name);
    }
    _toolOwners.clear();
  }

  // ---------------------------------------------------------------------------
  // 集成：System Prompt / SKILL 块
  // ---------------------------------------------------------------------------

  /// 构建所有启用插件注册的技能文本块。
  String buildSkillBlocks() {
    final buf = StringBuffer();
    for (final host in _activeHosts.values) {
      final block = host.renderSkillsBlock();
      if (block.isNotEmpty) {
        buf.writeln(block);
      }
    }
    return buf.toString();
  }

  /// 获取所有启用插件的技能列表
  List<PluginSkill> get allSkills {
    final list = <PluginSkill>[];
    for (final host in _activeHosts.values) {
      list.addAll(host.skills);
    }
    return list;
  }

  // ---------------------------------------------------------------------------
  // 查询
  // ---------------------------------------------------------------------------

  /// 所有已发现的插件元数据
  List<PluginMetadata> get allPlugins => _allMetadata.values.toList();

  /// 所有插件条目
  List<PluginEntry> get allEntries => _allEntries.values.toList();

  /// 所有已启用的插件 ID
  List<String> get activePluginIds => _activeHosts.keys.toList();

  /// 所有已启用插件注册的工具定义（用于合并进 LLM 的 tools 参数）
  List<ToolDefinition> get allEnabledToolDefinitions =>
      _activeHosts.values.expand((h) => h.toolDefinitions).toList();

  /// 当前状态快照
  PluginRegistryState get state => PluginRegistryState(
        allPlugins: allPlugins,
        activePluginIds: activePluginIds,
      );

  /// 获取某个插件的宿主（仅当启用时存在）
  LuaPluginHost? getHost(String pluginId) => _activeHosts[pluginId];

  /// 检查插件是否已启用
  bool isEnabled(String pluginId) => _activeHosts.containsKey(pluginId);

  /// 检查插件是否已发现
  bool isDiscovered(String pluginId) => _allMetadata.containsKey(pluginId);

  /// 获取插件来源
  PluginOrigin? getOrigin(String pluginId) {
    final relId = _findRelativeId(pluginId);
    return _pluginOrigins[relId];
  }

  /// 检查插件是否已安装到 documents/plugins/
  bool isInstalledToDocuments(String pluginId) {
    final relId = _findRelativeId(pluginId);
    return _pluginOrigins[relId] == PluginOrigin.installed;
  }

  // ---------------------------------------------------------------------------
  // 重置
  // ---------------------------------------------------------------------------

  /// 清空所有状态（用于测试或重新扫描）
  void reset() {
    for (final host in _activeHosts.values) {
      host.dispose();
    }
    _activeHosts.clear();
    _allMetadata.clear();
    _allEntries.clear();
    _toolOwners.clear();
    _pluginOrigins.clear();
    _scanned = false;
  }
}
