import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:archive/archive.dart';
import 'plugin_metadata.dart';

// =============================================================================
// PluginManager — 管理 plugins 目录下的插件生命周期
//
// 职责：
// 1. 初始化 getApplicationDocumentsDirectory()/plugins/ 目录
// 2. 列出所有已安装插件（从文件系统读取 plugin.json）
// 3. 安装插件（从 assets 复制、从目录安装）
// 4. 卸载插件（删除目录）
// 5. 区分「捆版插件」（assets/plugins/）和「已安装插件」（documents/plugins/）
// =============================================================================

/// 插件来源
enum PluginOrigin {
  /// 随应用捆版在 assets/plugins/ 中（只读）
  bundled,

  /// 用户安装在 documents/plugins/ 中（可读写）
  installed,
}

/// 插件在系统中的完整描述，包含来源信息
class PluginEntry {
  final PluginMetadata metadata;
  final PluginOrigin origin;

  /// 插件在文件系统中的绝对路径（目录）
  final String directoryPath;

  /// 插件路径（相对于对应根目录，如 "example_hello"）
  final String relativeId;

  const PluginEntry({
    required this.metadata,
    required this.origin,
    required this.directoryPath,
    required this.relativeId,
  });
}

/// 插件管理器 — 单例
class PluginManager {
  // ---------------------------------------------------------------------------
  // 单例
  // ---------------------------------------------------------------------------

  PluginManager._internal();
  static final PluginManager _instance = PluginManager._internal();
  factory PluginManager() => _instance;

  // ---------------------------------------------------------------------------
  // 状态
  // ---------------------------------------------------------------------------

  String? _pluginsDirPath;
  bool _initialized = false;

  /// 插件根目录路径（getApplicationDocumentsDirectory()/plugins/）
  String? get pluginsDirPath => _pluginsDirPath;

  /// 是否已初始化
  bool get isInitialized => _initialized;

  // ---------------------------------------------------------------------------
  // 初始化
  // ---------------------------------------------------------------------------

  /// 初始化插件目录。
  ///
  /// Web 端不需要插件系统，返回 false。
  Future<bool> init() async {
    if (_initialized) return true;
    if (kIsWeb) {
      debugPrint('[PluginManager] Web 平台跳过插件目录初始化');
      _initialized = true;
      return false;
    }

    try {
      final appDir = await getApplicationDocumentsDirectory();
      _pluginsDirPath = p.join(appDir.path, 'plugins');
      final dir = Directory(_pluginsDirPath!);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
        debugPrint('[PluginManager] 创建插件目录: $_pluginsDirPath');
      }
      _initialized = true;
      debugPrint('[PluginManager] 插件目录就绪: $_pluginsDirPath');
      return true;
    } catch (e) {
      debugPrint('[PluginManager] 初始化失败: $e');
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // 扫描已安装插件（从 documents/plugins/）
  // ---------------------------------------------------------------------------

  /// 扫描 documents/plugins/ 下所有已安装的插件。
  ///
  /// 返回安装成功（能解析 plugin.json）的插件列表。
  Future<List<PluginEntry>> scanInstalled() async {
    if (!_initialized || _pluginsDirPath == null) return [];

    final dir = Directory(_pluginsDirPath!);
    if (!await dir.exists()) return [];

    final entries = <PluginEntry>[];
    try {
      await for (final entity in dir.list()) {
        if (entity is Directory) {
          final pluginId = p.basename(entity.path);
          try {
            final meta = await _loadPluginJsonFromDir(entity.path);
            if (meta.id.isEmpty) {
              debugPrint('[PluginManager] 跳过无效插件目录: $pluginId');
              continue;
            }
            entries.add(PluginEntry(
              metadata: meta,
              origin: PluginOrigin.installed,
              directoryPath: entity.path,
              relativeId: pluginId,
            ));
          } catch (e) {
            debugPrint('[PluginManager] 加载已安装插件 "$pluginId" 失败: $e');
          }
        }
      }
    } catch (e) {
      debugPrint('[PluginManager] 扫描已安装插件失败: $e');
    }
    return entries;
  }

  /// 从插件目录中加载 plugin.json
  Future<PluginMetadata> _loadPluginJsonFromDir(String dirPath) async {
    final jsonPath = p.join(dirPath, 'plugin.json');
    final file = File(jsonPath);
    if (!await file.exists()) {
      return PluginMetadata(
        id: p.basename(dirPath),
        name: p.basename(dirPath),
        version: '0.0.0',
        author: '',
        description: 'Missing plugin.json',
      );
    }
    final content = await file.readAsString();
    final map = jsonDecode(content) as Map<String, dynamic>;
    return PluginMetadata.fromJson(map);
  }

  // ---------------------------------------------------------------------------
  // 扫描捆版插件（从 assets/plugins/）
  // ---------------------------------------------------------------------------

  /// 扫描 assets/plugins/ 下所有捆版插件。
  Future<List<PluginEntry>> scanBundled() async {
    final entries = <PluginEntry>[];
    try {
      // 读取索引文件
      final indexJson = await rootBundle.loadString(
        'assets/plugins/plugins_index.json',
      );
      final ids = (jsonDecode(indexJson) as List<dynamic>)
          .map((e) => e as String)
          .toList();

      for (final id in ids) {
        try {
          final jsonStr = await rootBundle.loadString(
            'assets/plugins/$id/plugin.json',
          );
          final map = jsonDecode(jsonStr) as Map<String, dynamic>;
          final meta = PluginMetadata.fromJson(map);
          entries.add(PluginEntry(
            metadata: meta,
            origin: PluginOrigin.bundled,
            directoryPath: 'assets/plugins/$id',
            relativeId: id,
          ));
        } catch (e) {
          debugPrint('[PluginManager] 加载捆版插件 "$id" 失败: $e');
        }
      }
    } catch (e) {
      debugPrint('[PluginManager] 扫描捆版插件失败: $e');
    }
    return entries;
  }

  // ---------------------------------------------------------------------------
  // 安装 / 卸载
  // ---------------------------------------------------------------------------

  /// 安装一个插件：将源路径（目录或 zip）安装到 documents/plugins/ 下。
  ///
  /// 当前实现支持从 [sourceDirPath]（一个包含 plugin.json 的目录）安装。
  /// 返回安装后的 PluginEntry，失败抛出异常。
  Future<PluginEntry> installFromDirectory(String sourceDirPath) async {
    if (!_initialized || _pluginsDirPath == null) {
      throw Exception('PluginManager 未初始化');
    }

    // 1. 读取源插件元数据
    final meta = await _loadPluginJsonFromDir(sourceDirPath);
    if (meta.id.isEmpty) {
      throw Exception('源目录缺少有效的 plugin.json');
    }

    // 2. 构造目标路径（使用 plugin.json 中的 id 作为目录名）
    //    但如果 id 包含反域名如 "com.tessera.example"，用短名作为目录
    final targetDirName = _sanitizeDirName(meta.id);
    final targetPath = p.join(_pluginsDirPath!, targetDirName);

    // 3. 检查是否已存在
    if (await Directory(targetPath).exists()) {
      throw Exception('插件 "${meta.name}" 已安装');
    }

    // 4. 复制目录
    await _copyDirectory(Directory(sourceDirPath), Directory(targetPath));

    // 5. 重新加载元数据
    final installedMeta = await _loadPluginJsonFromDir(targetPath);

    debugPrint('[PluginManager] 插件已安装: ${installedMeta.name} ($targetPath)');
    return PluginEntry(
      metadata: installedMeta,
      origin: PluginOrigin.installed,
      directoryPath: targetPath,
      relativeId: targetDirName,
    );
  }

  /// 从 assets 复制捆版插件到 documents/plugins/ 下。
  ///
  /// 由于 assets 文件无法用 File API 直接复制，此方法通过读取 asset 内容
  /// 再写入目标文件实现「安装」。
  Future<PluginEntry> installFromAssets(String assetPluginId) async {
    if (!_initialized || _pluginsDirPath == null) {
      throw Exception('PluginManager 未初始化');
    }

    // 1. 读取 plugin.json 确认插件存在
    final jsonStr = await rootBundle.loadString(
      'assets/plugins/$assetPluginId/plugin.json',
    );
    final map = jsonDecode(jsonStr) as Map<String, dynamic>;
    final meta = PluginMetadata.fromJson(map);

    // 2. 目标路径
    final targetDirName = _sanitizeDirName(meta.id);
    final targetPath = p.join(_pluginsDirPath!, targetDirName);

    if (await Directory(targetPath).exists()) {
      throw Exception('插件 "${meta.name}" 已安装');
    }

    // 3. 创建目标目录
    await Directory(targetPath).create(recursive: true);

    try {
      // 4. 读取 assets 中的文件列表并复制
      //    由于 Flutter assets 不支持枚举目录文件，我们已知结构：
      //    plugin.json + entryPoint
      final entryPoint = meta.entryPoint;
      await _copyAssetToFile(
        'assets/plugins/$assetPluginId/plugin.json',
        p.join(targetPath, 'plugin.json'),
      );
      if (entryPoint.isNotEmpty) {
        await _copyAssetToFile(
          'assets/plugins/$assetPluginId/$entryPoint',
          p.join(targetPath, entryPoint),
        );
      }
      // 尝试复制可能的额外文件
      for (final extra in ['icon.png', 'README.md', 'config.json']) {
        try {
          await _copyAssetToFile(
            'assets/plugins/$assetPluginId/$extra',
            p.join(targetPath, extra),
          );
        } catch (_) {
          // 可选文件，忽略
        }
      }
    } catch (e) {
      // 清理
      await Directory(targetPath).delete(recursive: true);
      rethrow;
    }

    final installedMeta = await _loadPluginJsonFromDir(targetPath);
    debugPrint('[PluginManager] 插件已从 assets 安装: ${installedMeta.name}');
    return PluginEntry(
      metadata: installedMeta,
      origin: PluginOrigin.installed,
      directoryPath: targetPath,
      relativeId: targetDirName,
    );
  }

  // ---------------------------------------------------------------------------
  // ZIP 安装
  // ---------------------------------------------------------------------------

  /// 将插件 ZIP 包提取到临时目录，返回元数据和临时目录路径。
  ///
  /// 支持两种 ZIP 结构：
  /// - 文件在 ZIP 根目录（plugin.json / main.lua 等）
  /// - 文件在 ZIP 内的子目录中（plugin_name/plugin.json / main.lua 等）
  Future<(PluginMetadata, String)> previewZip(String zipFilePath) async {
    if (!_initialized || _pluginsDirPath == null) {
      throw Exception('PluginManager 未初始化');
    }

    final bytes = File(zipFilePath).readAsBytesSync();
    final archive = ZipDecoder().decodeBytes(bytes);
    final tempDir = await Directory.systemTemp.createTemp('tessera_plugin_');

    try {
      // 解压所有文件到临时目录
      for (final entry in archive) {
        if (entry.isFile) {
          final outputPath = p.join(tempDir.path, entry.name);
          final parentDir = Directory(p.dirname(outputPath));
          if (!await parentDir.exists()) {
            await parentDir.create(recursive: true);
          }
          await File(outputPath).writeAsBytes(entry.content as List<int>);
        }
      }

      // 定位 plugin.json
      final pluginJsonPath = await _findPluginJson(tempDir.path);
      if (pluginJsonPath == null) {
        throw Exception('Missing plugin.json');
      }

      // 解析元数据
      final content = await File(pluginJsonPath).readAsString();
      final map = jsonDecode(content) as Map<String, dynamic>;
      final meta = PluginMetadata.fromJson(map);

      if (meta.id.isEmpty) {
        throw Exception('plugin.json 中缺少 id 字段');
      }

      return (meta, tempDir.path);
    } catch (e) {
      await tempDir.delete(recursive: true);
      rethrow;
    }
  }

  /// 将已提取到临时目录的插件安装到最终的 plugins 目录。
  ///
  /// [tempDirPath] 由 [previewZip] 创建并返回，此方法将其移动到
  /// `documents/plugins/<sanitized_id>`。
  Future<PluginEntry> installFromTemp(
    String tempDirPath,
    PluginMetadata meta,
  ) async {
    if (!_initialized || _pluginsDirPath == null) {
      throw Exception('PluginManager 未初始化');
    }

    final targetDirName = _sanitizeDirName(meta.id);
    final targetPath = p.join(_pluginsDirPath!, targetDirName);

    if (await Directory(targetPath).exists()) {
      throw Exception('插件 "${meta.name}" 已安装');
    }

    // 移动临时目录到最终位置
    await Directory(tempDirPath).rename(targetPath);

    // 重新加载元数据
    final installedMeta = await _loadPluginJsonFromDir(targetPath);

    debugPrint(
      '[PluginManager] 插件已从 ZIP 安装: ${installedMeta.name} ($targetPath)',
    );
    return PluginEntry(
      metadata: installedMeta,
      origin: PluginOrigin.installed,
      directoryPath: targetPath,
      relativeId: targetDirName,
    );
  }

  /// 在解压后的目录中查找 plugin.json。
  ///
  /// 先检查根目录，再检查第一级子目录。
  Future<String?> _findPluginJson(String dirPath) async {
    // Case 1: plugin.json 在根目录
    final rootPath = p.join(dirPath, 'plugin.json');
    if (await File(rootPath).exists()) {
      return rootPath;
    }

    // Case 2: plugin.json 在一级子目录中
    final dir = Directory(dirPath);
    await for (final entity in dir.list()) {
      if (entity is Directory) {
        final subPath = p.join(entity.path, 'plugin.json');
        if (await File(subPath).exists()) {
          return subPath;
        }
      }
    }

    return null;
  }

  /// 卸载 plugin_id 对应的插件目录。
  Future<void> uninstall(String pluginRelativeId) async {
    if (!_initialized || _pluginsDirPath == null) {
      throw Exception('PluginManager 未初始化');
    }

    final targetPath = p.join(_pluginsDirPath!, pluginRelativeId);
    final dir = Directory(targetPath);
    if (!await dir.exists()) {
      debugPrint('[PluginManager] 插件 "$pluginRelativeId" 不存在，无法卸载');
      return;
    }

    await dir.delete(recursive: true);
    debugPrint('[PluginManager] 插件已卸载: $pluginRelativeId');
  }

  /// 检查插件是否已安装到 documents/plugins/ 下。
  Future<bool> isInstalled(String pluginRelativeId) async {
    if (!_initialized || _pluginsDirPath == null) return false;
    return Directory(p.join(_pluginsDirPath!, pluginRelativeId)).exists();
  }

  /// 获取已安装插件的路径
  Future<String?> getInstalledPath(String pluginRelativeId) async {
    if (!_initialized || _pluginsDirPath == null) return null;
    final path = p.join(_pluginsDirPath!, pluginRelativeId);
    if (await Directory(path).exists()) return path;
    return null;
  }

  // ---------------------------------------------------------------------------
  // 工具方法
  // ---------------------------------------------------------------------------

  /// 将插件 ID 转为安全的目录名
  String _sanitizeDirName(String id) {
    // 反向域名风格：com.tessera.example → com_tessera_example
    // 也可以保留原始 id 的目录名
    return id.replaceAll('.', '_').replaceAll('-', '_');
  }

  /// 复制目录（递归）
  Future<void> _copyDirectory(Directory source, Directory target) async {
    await target.create(recursive: true);
    await for (final entity in source.list()) {
      final targetPath = p.join(target.path, p.basename(entity.path));
      if (entity is Directory) {
        await _copyDirectory(entity, Directory(targetPath));
      } else if (entity is File) {
        await entity.copy(targetPath);
      }
    }
  }

  /// 从 assets 读取并写入文件
  Future<void> _copyAssetToFile(String assetPath, String filePath) async {
    final data = await rootBundle.load(assetPath);
    final file = File(filePath);
    await file.writeAsBytes(data.buffer.asUint8List());
  }
}
