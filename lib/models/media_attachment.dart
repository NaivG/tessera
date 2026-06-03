/// 媒体类型枚举
enum MediaType {
  /// 图片
  image,

  /// 视频
  video,

  /// 音频
  audio,

  /// 普通文件
  file,
}

/// 媒体附件 — 表示用户上传或 LLM 生成的多模态内容
///
/// 内部所有文件信息使用 [libraryId] 映射到 [MediaLibrary]，
/// 对外展示使用 [libraryId] 查找实际文件路径。
class MediaAttachment {
  /// 资料库中的唯一 ID（在 MediaLibrary 中注册时生成）
  final String libraryId;

  /// 媒体类型
  final MediaType type;

  /// 原始文件名（展示用）
  final String fileName;

  /// 文件大小（字节）
  final int? fileSize;

  /// MIME 类型，如 "image/png"
  final String? mimeType;

  /// 缩略图路径（资料库中缓存的缩略图，可选）
  final String? thumbnailId;

  /// 附加元数据
  final Map<String, dynamic> metadata;

  const MediaAttachment({
    required this.libraryId,
    required this.type,
    required this.fileName,
    this.fileSize,
    this.mimeType,
    this.thumbnailId,
    this.metadata = const {},
  });

  /// 是否为图片
  bool get isImage => type == MediaType.image;

  /// 是否为视频
  bool get isVideo => type == MediaType.video;

  /// 是否为音频
  bool get isAudio => type == MediaType.audio;

  /// 是否为普通文件
  bool get isFile => type == MediaType.file;

  /// 文件大小显示文本（人类可读）
  String? get fileSizeLabel {
    if (fileSize == null) return null;
    if (fileSize! < 1024) return '${fileSize!} B';
    if (fileSize! < 1024 * 1024) {
      return '${(fileSize! / 1024).toStringAsFixed(1)} KB';
    }
    return '${(fileSize! / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// 从 JSON 反序列化
  factory MediaAttachment.fromJson(Map<String, dynamic> json) {
    return MediaAttachment(
      libraryId: json['library_id'] as String,
      type: MediaType.values.firstWhere((t) => t.name == json['type']),
      fileName: json['file_name'] as String,
      fileSize: json['file_size'] as int?,
      mimeType: json['mime_type'] as String?,
      thumbnailId: json['thumbnail_id'] as String?,
      metadata: (json['metadata'] as Map<String, dynamic>?) ?? {},
    );
  }

  /// 序列化为 JSON
  Map<String, dynamic> toJson() {
    return {
      'library_id': libraryId,
      'type': type.name,
      'file_name': fileName,
      if (fileSize != null) 'file_size': fileSize,
      if (mimeType != null) 'mime_type': mimeType,
      if (thumbnailId != null) 'thumbnail_id': thumbnailId,
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }

  /// 复制并修改部分字段
  MediaAttachment copyWith({
    String? libraryId,
    MediaType? type,
    String? fileName,
    int? fileSize,
    String? mimeType,
    String? thumbnailId,
    Map<String, dynamic>? metadata,
  }) {
    return MediaAttachment(
      libraryId: libraryId ?? this.libraryId,
      type: type ?? this.type,
      fileName: fileName ?? this.fileName,
      fileSize: fileSize ?? this.fileSize,
      mimeType: mimeType ?? this.mimeType,
      thumbnailId: thumbnailId ?? this.thumbnailId,
      metadata: metadata ?? this.metadata,
    );
  }
}
