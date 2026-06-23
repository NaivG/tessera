import 'dart:io';

import 'package:path/path.dart' as p;

/// 路径遍历异常 — 当相对路径解析后逃出 workspace 根目录时抛出。
class PathTraversalException implements Exception {
  final String message;
  PathTraversalException(this.message);

  @override
  String toString() => 'PathTraversalException: $message';
}

/// 解析 workspace 内的相对路径，确保其不逃出根目录。
///
/// 算法：
/// 1. 解析 [workspaceRootPath] 为真实路径（解析符号链接）。
/// 2. 将 [relativePath] 与根拼接，再用 [p.normalize] 归一化。
/// 3. 解析拼接后的路径（解析可能存在的符号链接）。
/// 4. 校验最终路径在根目录之内。
///
/// 注意：
/// - 不存在的文件使用父目录来解析（处理创建新文件的场景）。
/// - 绝对路径会被视为相对于根目录的字符串（截取前导 `/`）。
/// - `..` 通过 [p.normalize] + 解析后的范围检查拦截。
String resolveSafePath({
  required String workspaceRootPath,
  required String relativePath,
}) {
  if (workspaceRootPath.isEmpty) {
    throw PathTraversalException('Workspace root path is empty.');
  }

  // 1. 解析根目录的 realpath（不存在则抛）
  final rootStat = FileSystemEntity.typeSync(workspaceRootPath);
  if (rootStat != FileSystemEntityType.directory) {
    throw PathTraversalException(
      'Workspace root "$workspaceRootPath" is not a directory.',
    );
  }
  final root = Directory(workspaceRootPath).resolveSymbolicLinksSync();

  // 2. 拼接 + 归一化
  var cleaned = relativePath.trim();
  // 拒绝绝对路径 —— 但允许在 Windows 上用前导 `\` 视作相对
  if (p.isAbsolute(cleaned)) {
    // 截取路径分隔符之后的部分，将其视作相对
    cleaned = cleaned.replaceFirst(RegExp(r'^[/\\]+'), '');
  }
  final joined = p.normalize(p.join(root, cleaned));

  // 3. 解析拼接路径的 realpath
  //    如果 joined 不存在，尝试解析其父目录 + 子路径。
  String resolved;
  final joinedType = FileSystemEntity.typeSync(joined, followLinks: false);
  if (joinedType == FileSystemEntityType.notFound) {
    // 文件尚不存在 —— 通过父目录解析符号链接
    final parent = p.dirname(joined);
    final parentResolved = Directory(parent).resolveSymbolicLinksSync();
    resolved = p.join(parentResolved, p.basename(joined));
  } else if (joinedType == FileSystemEntityType.directory) {
    resolved = Directory(joined).resolveSymbolicLinksSync();
  } else {
    resolved = File(joined).resolveSymbolicLinksSync();
  }

  // 4. 范围检查：resolved 必须在 root 之内（或等于 root 本身）
  final rootWithSep = root.endsWith(p.separator) ? root : root + p.separator;
  if (resolved != root && !resolved.startsWith(rootWithSep)) {
    throw PathTraversalException(
      'Path "$relativePath" escapes workspace root "$workspaceRootPath".',
    );
  }

  return resolved;
}
