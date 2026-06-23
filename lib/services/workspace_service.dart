import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../models/workspace.dart';
import '../utils/path_traversal.dart';

// =============================================================================
// WorkspaceService — 工作空间文件系统服务
//
// 职责：
// 1. 在 <appDocs>/workspaces/ 下维护 JSON 索引
// 2. 管理若干 Workspace 注册项
// 3. 提供安全的文件读写 / 列表 / 搜索 / 编辑操作
//
// 所有文件操作都先经过 resolveSafePath() 校验，
// 路径逃逸时抛出 PathTraversalException。
// =============================================================================

class WorkspaceNotFoundException implements Exception {
  final String workspaceId;
  WorkspaceNotFoundException(this.workspaceId);

  @override
  String toString() =>
      'WorkspaceNotFoundException: workspace "$workspaceId" not found.';
}

class WorkspaceFileException implements Exception {
  final String message;
  WorkspaceFileException(this.message);

  @override
  String toString() => 'WorkspaceFileException: $message';
}

class WorkspaceService {
  static WorkspaceService? _instance;
  static WorkspaceService get instance => _instance ??= WorkspaceService._();

  WorkspaceService._();

  String? _workspacesDir;
  bool _initialized = false;
  WorkspaceIndex _index = WorkspaceIndex.empty;

  /// 索引文件路径
  String get _indexPath => p.join(_workspacesDir ?? '', 'index.json');

  bool get isInitialized => _initialized;
  WorkspaceIndex get index => _index;
  List<Workspace> get workspaces => _index.workspaces;
  Workspace? get active => _index.active;
  Workspace? byId(String id) => _index.byId(id);

  // ---------------------------------------------------------------------------
  // 初始化
  // ---------------------------------------------------------------------------

  /// 初始化工作空间目录。Web 平台跳过（无 dart:io 文件系统）。
  Future<void> init(String appDir) async {
    if (_initialized) return;
    if (kIsWeb) {
      debugPrint('[WorkspaceService] Web 平台跳过初始化');
      _initialized = true;
      return;
    }
    try {
      _workspacesDir = p.join(appDir, 'workspaces');
      final dir = Directory(_workspacesDir!);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
        debugPrint('[WorkspaceService] 创建工作空间目录: $_workspacesDir');
      }
      await _loadFromDisk();
      _initialized = true;
      debugPrint(
        '[WorkspaceService] 工作空间目录就绪: $_workspacesDir (${_index.workspaces.length} 个)',
      );
    } catch (e) {
      debugPrint('[WorkspaceService] 初始化失败: $e');
      _initialized = true; // 标记为已初始化以避免重试风暴
    }
  }

  void _ensureInitialized() {
    if (!_initialized) {
      throw StateError(
        'WorkspaceService is not initialized. Please call init() first.',
      );
    }
    if (kIsWeb) {
      throw WorkspaceFileException(
        'Workspace operations are not supported on Web.',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // 工作空间管理
  // ---------------------------------------------------------------------------

  /// 添加一个工作空间。路径必须已存在的目录。
  Future<Workspace> addWorkspace({
    required String name,
    required String path,
  }) async {
    _ensureInitialized();
    if (name.trim().isEmpty) {
      throw ArgumentError('Workspace name must not be empty.');
    }
    if (path.trim().isEmpty) {
      throw ArgumentError('Workspace path must not be empty.');
    }
    if (!Directory(path).existsSync()) {
      throw WorkspaceFileException('Directory does not exist: $path');
    }
    final ws = Workspace.create(name: name.trim(), rootPath: path);
    final list = [..._index.workspaces, ws];
    _index = WorkspaceIndex(
      workspaces: list,
      activeWorkspaceId: _index.activeWorkspaceId ?? ws.id,
    );
    await _saveToDisk();
    return ws;
  }

  Future<void> removeWorkspace(String id) async {
    _ensureInitialized();
    final list = _index.workspaces.where((w) => w.id != id).toList();
    var active = _index.activeWorkspaceId;
    if (active == id) active = null;
    _index = WorkspaceIndex(workspaces: list, activeWorkspaceId: active);
    await _saveToDisk();
  }

  Future<void> renameWorkspace(String id, String name) async {
    _ensureInitialized();
    if (name.trim().isEmpty) {
      throw ArgumentError('Workspace name must not be empty.');
    }
    final list = _index.workspaces.map((w) {
      if (w.id != id) return w;
      return w.copyWith(name: name.trim(), updatedAt: DateTime.now());
    }).toList();
    _index = WorkspaceIndex(
      workspaces: list,
      activeWorkspaceId: _index.activeWorkspaceId,
    );
    await _saveToDisk();
  }

  Future<void> setActive(String? id) async {
    _ensureInitialized();
    if (id != null && _index.byId(id) == null) {
      throw WorkspaceNotFoundException(id);
    }
    _index = WorkspaceIndex(
      workspaces: _index.workspaces,
      activeWorkspaceId: id,
    );
    await _saveToDisk();
  }

  // ---------------------------------------------------------------------------
  // 文件操作
  // ---------------------------------------------------------------------------

  /// 列出目录条目。
  ///
  /// [relativePath] 为空或 "/" 表示根目录。
  Future<List<WorkspaceEntry>> listDirectory(
    String workspaceId,
    String relativePath,
  ) async {
    _ensureInitialized();
    final ws = _require(workspaceId);
    final abs = resolveSafePath(
      workspaceRootPath: ws.rootPath,
      relativePath: relativePath,
    );
    final dir = Directory(abs);
    if (!await dir.exists()) {
      throw WorkspaceFileException('Directory not found: $relativePath');
    }
    final entries = await dir.list().toList();
    final result = <WorkspaceEntry>[];
    for (final entity in entries) {
      try {
        final stat = await entity.stat();
        final name = p.basename(entity.path);
        // 跳过隐藏文件 & 系统文件 —— 这些通常是元数据
        if (name.startsWith('.')) continue;
        final kind = entity is Directory
            ? WorkspaceEntryKind.directory
            : WorkspaceEntryKind.file;
        result.add(
          WorkspaceEntry(
            name: name,
            relativePath: _toRelative(ws.rootPath, entity.path),
            kind: kind,
            size: stat.size,
            modified: stat.modified,
          ),
        );
      } catch (_) {
        // 跳过无法 stat 的条目（权限问题等）
      }
    }
    // 目录优先，名称排序
    result.sort((a, b) {
      if (a.kind != b.kind) {
        return a.kind == WorkspaceEntryKind.directory ? -1 : 1;
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return result;
  }

  /// 读取文本文件内容。
  Future<String> readFile(String workspaceId, String relativePath) async {
    _ensureInitialized();
    final ws = _require(workspaceId);
    final abs = resolveSafePath(
      workspaceRootPath: ws.rootPath,
      relativePath: relativePath,
    );
    final file = File(abs);
    if (!await file.exists()) {
      throw WorkspaceFileException('File not found: $relativePath');
    }
    return file.readAsString();
  }

  /// 写入文本内容到文件。
  ///
  /// 若文件不存在则创建（包括父目录）。
  Future<void> writeFile(
    String workspaceId,
    String relativePath,
    String content,
  ) async {
    _ensureInitialized();
    final ws = _require(workspaceId);
    final abs = resolveSafePath(
      workspaceRootPath: ws.rootPath,
      relativePath: relativePath,
    );
    final file = File(abs);
    // 确保父目录存在
    await file.parent.create(recursive: true);
    await file.writeAsString(content, flush: true);
  }

  /// 创建目录（默认递归）。
  Future<void> mkdir(
    String workspaceId,
    String relativePath, {
    bool recursive = true,
  }) async {
    _ensureInitialized();
    final ws = _require(workspaceId);
    final abs = resolveSafePath(
      workspaceRootPath: ws.rootPath,
      relativePath: relativePath,
    );
    await Directory(abs).create(recursive: recursive);
  }

  /// 删除文件或目录。
  ///
  /// [recursive] 用于目录。文件删除时该参数被忽略。
  Future<void> deleteFile(
    String workspaceId,
    String relativePath, {
    bool recursive = false,
  }) async {
    _ensureInitialized();
    final ws = _require(workspaceId);
    final abs = resolveSafePath(
      workspaceRootPath: ws.rootPath,
      relativePath: relativePath,
    );
    final type = FileSystemEntity.typeSync(abs, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      throw WorkspaceFileException('Path not found: $relativePath');
    }
    if (type == FileSystemEntityType.directory) {
      await Directory(abs).delete(recursive: recursive);
    } else {
      await File(abs).delete();
    }
  }

  /// 在工作空间中搜索。
  ///
  /// - 当 [relativePath] 为空时，从根目录递归搜索。
  /// - 当 [contentOnly] 为 true 时，仅在文件内容中匹配 [query]。
  /// - 否则先匹配文件名（包含），再在内容中匹配。
  Future<List<WorkspaceEntry>> search(
    String workspaceId,
    String query, {
    String? relativePath,
    bool contentOnly = false,
  }) async {
    _ensureInitialized();
    if (query.isEmpty) return [];
    final ws = _require(workspaceId);
    final startAbs = relativePath == null || relativePath.isEmpty
        ? ws.rootPath
        : resolveSafePath(
            workspaceRootPath: ws.rootPath,
            relativePath: relativePath,
          );
    final start = Directory(startAbs);
    if (!await start.exists()) return [];
    final results = <WorkspaceEntry>[];
    final lowerQuery = query.toLowerCase();
    final maxResults = 200; // 防止搜索风暴

    await for (final entity in start.list(recursive: true)) {
      if (results.length >= maxResults) break;
      try {
        final name = p.basename(entity.path);
        if (name.startsWith('.')) continue;
        if (entity is! File) {
          // 仅在文件名匹配时记录目录
          if (!contentOnly && name.toLowerCase().contains(lowerQuery)) {
            final stat = await entity.stat();
            results.add(
              WorkspaceEntry(
                name: name,
                relativePath: _toRelative(ws.rootPath, entity.path),
                kind: WorkspaceEntryKind.directory,
                size: 0,
                modified: stat.modified,
              ),
            );
          }
          continue;
        }
        bool matched = false;
        if (!contentOnly && name.toLowerCase().contains(lowerQuery)) {
          matched = true;
        }
        if (!matched) {
          try {
            final content = await entity.readAsString();
            if (content.toLowerCase().contains(lowerQuery)) {
              matched = true;
            }
          } catch (_) {
            // 二进制文件无法读取，跳过
          }
        }
        if (matched) {
          final stat = await entity.stat();
          results.add(
            WorkspaceEntry(
              name: name,
              relativePath: _toRelative(ws.rootPath, entity.path),
              kind: WorkspaceEntryKind.file,
              size: stat.size,
              modified: stat.modified,
            ),
          );
        }
      } catch (_) {
        // 跳过无法访问的条目
      }
    }
    return results;
  }

  /// 编辑文件 —— 应用一组 EditOperation。
  ///
  /// - 当 find 缺失或非唯一匹配且 replaceAll == false 时抛出。
  /// - 返回修改后文件的字符数与应用的编辑数。
  Future<({int length, int appliedEdits})> editFile(
    String workspaceId,
    String relativePath,
    List<EditOperation> edits,
  ) async {
    _ensureInitialized();
    if (edits.isEmpty) {
      throw ArgumentError('edits must not be empty.');
    }
    final ws = _require(workspaceId);
    final abs = resolveSafePath(
      workspaceRootPath: ws.rootPath,
      relativePath: relativePath,
    );
    final file = File(abs);
    if (!await file.exists()) {
      throw WorkspaceFileException('File not found: $relativePath');
    }
    var content = await file.readAsString();
    int applied = 0;
    for (final edit in edits) {
      if (edit.find.isEmpty) {
        throw WorkspaceFileException('Edit.find must not be empty.');
      }
      final occurrences = edit.find.allMatches(content).length;
      if (edit.replaceAll) {
        if (occurrences == 0) {
          throw WorkspaceFileException(
            'find string not found in file: "${edit.find}"',
          );
        }
        content = content.replaceAll(edit.find, edit.replace);
        applied += occurrences;
      } else {
        if (occurrences == 0) {
          throw WorkspaceFileException(
            'find string not found in file: "${edit.find}"',
          );
        }
        if (occurrences > 1) {
          throw WorkspaceFileException(
            'find string "${edit.find}" matches $occurrences times; '
            'set replace_all=true to replace all occurrences.',
          );
        }
        content = content.replaceFirst(edit.find, edit.replace);
        applied += 1;
      }
    }
    await file.writeAsString(content, flush: true);
    return (length: content.length, appliedEdits: applied);
  }

  // ---------------------------------------------------------------------------
  // 内部
  // ---------------------------------------------------------------------------

  Workspace _require(String id) {
    final ws = _index.byId(id);
    if (ws == null) throw WorkspaceNotFoundException(id);
    return ws;
  }

  /// 将绝对路径转换为相对于 workspace 根的相对路径（使用 POSIX 分隔符）。
  String _toRelative(String rootPath, String absolute) {
    final root = Directory(rootPath).resolveSymbolicLinksSync();
    var resolved = absolute;
    try {
      resolved = File(absolute).resolveSymbolicLinksSync();
    } catch (_) {
      // 文件可能不存在 —— 退回到字符串前缀截取
    }
    if (resolved == root) return '.';
    final rootWithSep = root.endsWith(p.separator)
        ? root
        : '$root${p.separator}';
    if (resolved.startsWith(rootWithSep)) {
      return resolved
          .substring(rootWithSep.length)
          .replaceAll(p.separator, '/');
    }
    return resolved.replaceAll(p.separator, '/');
  }

  Future<void> _saveToDisk() async {
    if (!_initialized || _workspacesDir == null) return;
    try {
      await File(_indexPath).writeAsString(jsonEncode(_index.toJson()));
    } catch (e) {
      debugPrint('[WorkspaceService] 持久化失败: $e');
    }
  }

  Future<void> _loadFromDisk() async {
    if (_workspacesDir == null) return;
    try {
      final file = File(_indexPath);
      if (!await file.exists()) {
        _index = WorkspaceIndex.empty;
        return;
      }
      final raw = await file.readAsString();
      final map = jsonDecode(raw) as Map<String, dynamic>;
      _index = WorkspaceIndex.fromJson(map);
    } catch (e) {
      debugPrint('[WorkspaceService] 索引加载失败，从零开始: $e');
      _index = WorkspaceIndex.empty;
    }
  }
}
