import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../models/media_attachment.dart';

/// 资料库条目 — 保存文件原始信息以及到媒体附件的映射
class LibraryEntry {
  /// 资料库内唯一 ID
  final String id;

  /// 物理文件路径（源文件或拷贝）
  final String filePath;

  /// 媒体附件元数据
  final MediaAttachment attachment;

  const LibraryEntry({
    required this.id,
    required this.filePath,
    required this.attachment,
  });

  /// 从 JSON 反序列化
  factory LibraryEntry.fromJson(Map<String, dynamic> json) {
    return LibraryEntry(
      id: json['id'] as String,
      filePath: json['file_path'] as String,
      attachment: MediaAttachment.fromJson(
        json['attachment'] as Map<String, dynamic>,
      ),
    );
  }

  /// 序列化为 JSON
  Map<String, dynamic> toJson() => {
    'id': id,
    'file_path': filePath,
    'attachment': attachment.toJson(),
  };
}

/// 资料库 — 缓存所有上传文件的信息，内部使用资料库 ID 映射，
/// 外部（LLM 工具）同样通过 ID 访问，不暴露真实路径。
///
/// 使用示例：
/// ```dart
/// final lib = MediaLibrary();
/// final att = await lib.importFile('/path/to/photo.jpg');
/// // att.libraryId 在所有上下文中使用
/// final file = lib.fileFor(att.libraryId);
/// ```
class MediaLibrary {
  static MediaLibrary? _instance;
  static MediaLibrary get instance => _instance ??= MediaLibrary._();

  MediaLibrary._();

  final Map<String, LibraryEntry> _entries = {};
  final Uuid _uuid = const Uuid();

  /// 资料库缓存目录
  late String _cacheDir;
  bool _initialized = false;

  /// 初始化缓存目录
  Future<void> init(String appDir) async {
    _cacheDir = p.join(appDir, 'media_library');
    await Directory(_cacheDir).create(recursive: true);
    _initialized = true;

    // 恢复已持久化的条目，并清理不在磁盘上的脏数据
    await _loadFromDisk();
  }

  /// 确保已初始化，否则抛出明确的错误
  void _ensureInitialized() {
    if (!_initialized) {
      throw StateError(
        'MediaLibrary is not initialized. Please call init() first.',
      );
    }
  }

  /// 获取所有条目
  Iterable<LibraryEntry> get entries => _entries.values;

  /// 通过 libraryId 获取条目
  LibraryEntry? entryFor(String libraryId) => _entries[libraryId];

  /// 通过 libraryId 获取文件路径
  String? filePathFor(String libraryId) => _entries[libraryId]?.filePath;

  /// 通过 libraryId 获取媒体附件
  MediaAttachment? attachmentFor(String libraryId) =>
      _entries[libraryId]?.attachment;

  /// 导入文件到资料库
  ///
  /// 将文件复制到资料库缓存目录，生成唯一的 libraryId，
  /// 并返回对应的 [MediaAttachment]。
  Future<MediaAttachment> importFile(
    String sourcePath, {
    MediaType? forceType,
  }) async {
    _ensureInitialized();
    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      throw Exception('文件不存在: $sourcePath');
    }

    final libraryId = _uuid.v4();
    final ext = p.extension(sourcePath).toLowerCase();
    final fileName = p.basename(sourcePath);

    // 复制到资料库
    final destName = '$libraryId$ext';
    final destPath = p.join(_cacheDir, destName);
    await sourceFile.copy(destPath);

    // 确定媒体类型
    final mediaType = forceType ?? _inferType(ext);

    // 获取文件大小
    final fileSize = await File(destPath).length();

    // 生成缩略图（仅图片）
    String? thumbnailId;
    if (mediaType == MediaType.image) {
      thumbnailId = await _generateThumbnail(destPath);
    }

    final attachment = MediaAttachment(
      libraryId: libraryId,
      type: mediaType,
      fileName: fileName,
      fileSize: fileSize,
      mimeType: _mimeForExt(ext),
      thumbnailId: thumbnailId,
    );

    _entries[libraryId] = LibraryEntry(
      id: libraryId,
      filePath: destPath,
      attachment: attachment,
    );

    await _saveToDisk();
    return attachment;
  }

  /// 从文件数据 buffer 导入（内存导入）
  Future<MediaAttachment> importBytes(
    List<int> bytes,
    String fileName, {
    MediaType? forceType,
  }) async {
    _ensureInitialized();
    final libraryId = _uuid.v4();
    final ext = p.extension(fileName).toLowerCase();

    final destName = '$libraryId$ext';
    final destPath = p.join(_cacheDir, destName);
    await File(destPath).writeAsBytes(bytes);

    final mediaType = forceType ?? _inferType(ext);
    final fileSize = bytes.length;

    String? thumbnailId;
    if (mediaType == MediaType.image) {
      thumbnailId = await _generateThumbnail(destPath);
    }

    final attachment = MediaAttachment(
      libraryId: libraryId,
      type: mediaType,
      fileName: fileName,
      fileSize: fileSize,
      mimeType: _mimeForExt(ext),
      thumbnailId: thumbnailId,
    );

    _entries[libraryId] = LibraryEntry(
      id: libraryId,
      filePath: destPath,
      attachment: attachment,
    );

    await _saveToDisk();
    return attachment;
  }

  /// 获取所有已导入文件的 media_attachment 列表
  List<MediaAttachment> get allAttachments =>
      _entries.values.map((e) => e.attachment).toList();

  /// 移除资料库条目
  Future<void> remove(String libraryId) async {
    _ensureInitialized();
    final entry = _entries.remove(libraryId);
    if (entry != null) {
      try {
        await File(entry.filePath).delete();
      } catch (_) {
        // 删除失败，忽略
      }
      if (entry.attachment.thumbnailId != null) {
        try {
          final thumbPath = p.join(
            _cacheDir,
            'thumbnails',
            entry.attachment.thumbnailId!,
          );
          await File(thumbPath).delete();
        } catch (_) {
          // 删除失败，忽略
        }
      }
    }
    await _saveToDisk();
  }

  /// 清空资料库
  Future<void> clear() async {
    _ensureInitialized();
    _entries.clear();
    if (_cacheDir.isNotEmpty) {
      final dir = Directory(_cacheDir);
      if (await dir.exists()) {
        try {
          await dir.delete(recursive: true);
        } catch (_) {
          // 删除失败，忽略
        }
        await dir.create(recursive: true);
      }
    }
    await _saveToDisk();
  }

  // ── 私有 ──

  MediaType _inferType(String ext) {
    const imageExts = {
      '.png',
      '.jpg',
      '.jpeg',
      '.gif',
      '.webp',
      '.bmp',
      '.svg',
      '.heic',
    };
    const videoExts = {'.mp4', '.mov', '.avi', '.mkv', '.webm', '.flv', '.wmv'};
    const audioExts = {'.mp3', '.wav', '.aac', '.ogg', '.flac', '.m4a', '.wma'};

    if (imageExts.contains(ext)) return MediaType.image;
    if (videoExts.contains(ext)) return MediaType.video;
    if (audioExts.contains(ext)) return MediaType.audio;
    return MediaType.file;
  }

  String? _mimeForExt(String ext) {
    return switch (ext) {
      '.png' => 'image/png',
      '.jpg' || '.jpeg' => 'image/jpeg',
      '.gif' => 'image/gif',
      '.webp' => 'image/webp',
      '.bmp' => 'image/bmp',
      '.svg' => 'image/svg+xml',
      '.mp4' => 'video/mp4',
      '.mov' => 'video/quicktime',
      '.avi' => 'video/x-msvideo',
      '.webm' => 'video/webm',
      '.mp3' => 'audio/mpeg',
      '.wav' => 'audio/wav',
      '.ogg' => 'audio/ogg',
      '.flac' => 'audio/flac',
      '.aac' => 'audio/aac',
      '.pdf' => 'application/pdf',
      _ => null,
    };
  }

  /// 为图片文件生成缩略图（最多 200x200）
  Future<String?> _generateThumbnail(String imagePath) async {
    try {
      final bytes = await File(imagePath).readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return null;

      final thumb = img.copyResize(decoded, width: 200, height: 200);
      final thumbBytes = img.encodePng(thumb);

      final thumbName = '${p.basenameWithoutExtension(imagePath)}.thumb.png';
      final thumbDir = p.join(_cacheDir, 'thumbnails');
      await Directory(thumbDir).create(recursive: true);
      final thumbPath = p.join(thumbDir, thumbName);
      await File(thumbPath).writeAsBytes(thumbBytes);

      return thumbName;
    } catch (_) {
      return null;
    }
  }

  /// 获取缩略图文件路径
  String? thumbnailPath(String imagePath) {
    if (!_initialized) return null;
    final thumbName = '${p.basenameWithoutExtension(imagePath)}.thumb.png';
    final thumbPath = p.join(_cacheDir, 'thumbnails', thumbName);
    return File(thumbPath).existsSync() ? thumbPath : null;
  }

  /// 索引文件路径
  String get _indexPath => p.join(_cacheDir, 'index.json');

  /// 将当前条目持久化到 JSON 索引文件
  Future<void> _saveToDisk() async {
    if (!_initialized) return;
    try {
      final list = _entries.values.map((e) => e.toJson()).toList();
      await File(_indexPath).writeAsString(jsonEncode(list));
    } catch (_) {
      // 持久化失败不阻塞 UI
    }
  }

  /// 从磁盘恢复条目，清理已有文件被删除的脏数据
  Future<void> _loadFromDisk() async {
    try {
      final file = File(_indexPath);
      if (!await file.exists()) return;

      final raw = await file.readAsString();
      final List<dynamic> list = jsonDecode(raw) as List<dynamic>;

      _entries.clear();
      for (final item in list) {
        try {
          final entry = LibraryEntry.fromJson(item as Map<String, dynamic>);
          // 清理：文件已不存在的条目不再恢复
          if (await File(entry.filePath).exists()) {
            _entries[entry.id] = entry;
          }
        } catch (_) {
          // 跳过损坏的条目
        }
      }

      // 如果条目有变化（清理了脏数据），回写索引
      if (_entries.length != list.length) {
        await _saveToDisk();
      }
    } catch (_) {
      // 索引文件损坏或不存在时从零开始
      _entries.clear();
    }
  }
}
