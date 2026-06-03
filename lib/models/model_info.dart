/// 模型能力类型
///
/// 标注模型的核心能力方向：
/// - [text]: 纯文本生成（LLM 对话/补全）
/// - [image]: 文生图（TTI, Text-to-Image）
/// - [video]: 文生视频（TTV, Text-to-Video）
/// - [speech]: 文生语音（TTS, Text-to-Speech）
/// - [embedding]: 嵌入向量模型
/// - [ranking]: 排序/重排序模型
enum ModelType {
  text,
  image,
  video,
  speech,
  embedding,
  ranking;

  /// 中文显示名称
  String get displayName {
    return switch (this) {
      ModelType.text => '文本生成',
      ModelType.image => '文生图',
      ModelType.video => '文生视频',
      ModelType.speech => '文生语音',
      ModelType.embedding => '嵌入',
      ModelType.ranking => '排序',
    };
  }

  /// 简短别名（用于紧凑展示）
  String get shortName {
    return switch (this) {
      ModelType.text => 'LLM',
      ModelType.image => 'TTI',
      ModelType.video => 'TTV',
      ModelType.speech => 'TTS',
      ModelType.embedding => 'EMB',
      ModelType.ranking => 'RNK',
    };
  }
}

/// 模型模态标签
///
/// 标注模型支持的输入/输出模态：
/// - [text]: 文本输入/输出
/// - [vision]: 图像输入（视觉理解）
/// - [audible]: 音频输入/输出
/// - [video]: 视频输入/输出
///
/// 标签可自由组合。当同时具备 [text]、[vision]、[audible]、[video] 时，
/// 即表示全模态（omni）模型。
enum ModelTag {
  text,
  vision,
  audible,
  video;

  /// 中文显示名称
  String get displayName {
    return switch (this) {
      ModelTag.text => '文本',
      ModelTag.vision => '视觉',
      ModelTag.audible => '音频',
      ModelTag.video => '视频',
    };
  }

  /// 图标字符（用于紧凑展示）
  String get icon {
    return switch (this) {
      ModelTag.text => 'T',
      ModelTag.vision => 'V',
      ModelTag.audible => 'A',
      ModelTag.video => 'V',
    };
  }
}

/// 单个模型的完整描述信息
///
/// 取代原先的纯字符串 [String] 模型 ID，增加了类型和标签元数据。
/// [uid] 是实例唯一标识（UUID），用于可靠地引用此模型实例；
/// [id] 是模型标识符（如 "gpt-4o"）。
/// JSON 序列化格式：
/// ```json
/// {
///   "uid": "a1b2c3d4-...",
///   "id": "gpt-4o",
///   "type": "text",
///   "tags": ["text", "vision"]
/// }
/// ```
class ModelInfo {
  /// 实例唯一标识（UUID），用于稳定引用
  final String uid;

  /// 模型标识符（如 "gpt-4o"）
  final String id;

  /// 模型能力类型
  final ModelType type;

  /// 模态标签集合（顺序无关，但序列化时按 [ModelTag] 枚举定义排序）
  final List<ModelTag> tags;

  const ModelInfo({
    this.uid = '',
    required this.id,
    this.type = ModelType.text,
    this.tags = const [ModelTag.text],
  });

  // --- 便捷查询 ---

  /// 是否支持视觉输入
  bool get supportsVision => tags.contains(ModelTag.vision);

  /// 是否支持音频
  bool get supportsAudible => tags.contains(ModelTag.audible);

  /// 是否支持视频输入
  bool get supportsVideoInput => tags.contains(ModelTag.video);

  /// 是否为全模态（omni）模型
  bool get isOmni =>
      tags.contains(ModelTag.text) &&
      tags.contains(ModelTag.vision) &&
      tags.contains(ModelTag.audible) &&
      tags.contains(ModelTag.video);

  /// 是否为多模态模型（至少支持文本+视觉）
  bool get isMultimodal =>
      tags.contains(ModelTag.vision) ||
      tags.contains(ModelTag.audible) ||
      tags.contains(ModelTag.video);

  /// 标签的简短描述字符串，如 "text+vision"
  String get tagsShortLabel => tags.map((t) => t.name).join('+');

  /// 标签的完整描述字符串
  String get tagsLabel {
    if (isOmni) return '全模态';
    if (tags.length == 1 && tags.first == ModelTag.text) return '纯文本';
    return tags.map((t) => t.displayName).join('+');
  }

  // --- 复制 ---

  /// 复制并修改部分字段
  ModelInfo copyWith({
    String? uid,
    String? id,
    ModelType? type,
    List<ModelTag>? tags,
  }) {
    return ModelInfo(
      uid: uid ?? this.uid,
      id: id ?? this.id,
      type: type ?? this.type,
      tags: tags ?? List<ModelTag>.from(this.tags),
    );
  }

  // --- 序列化 ---

  /// 从 JSON 反序列化
  ///
  /// 同时支持新格式（Map）和旧格式（纯字符串 ID）以保证向后兼容。
  /// 旧格式会被推断为 [ModelType.text] + [ModelTag.text]。
  /// 缺少 [uid] 的旧数据会自动生成一个新的 UUID。
  factory ModelInfo.fromJson(dynamic json) {
    if (json is String) {
      // 向后兼容旧格式：纯字符串模型 ID
      return ModelInfo(id: json);
    }
    if (json is Map<String, dynamic>) {
      return ModelInfo(
        uid: json['uid'] as String? ?? '',
        id: json['id'] as String,
        type: _parseModelType(json['type']),
        tags: _parseModelTags(json['tags']),
      );
    }
    throw ArgumentError('无法解析 ModelInfo: $json');
  }

  /// 序列化为 JSON
  Map<String, dynamic> toJson() {
    return {
      if (uid.isNotEmpty) 'uid': uid,
      'id': id,
      'type': type.name,
      'tags': tags.map((t) => t.name).toList(),
    };
  }

  // --- 辅助解析 ---

  static ModelType _parseModelType(dynamic value) {
    if (value == null) return ModelType.text;
    if (value is ModelType) return value;
    final name = value.toString();
    return ModelType.values.firstWhere(
      (t) => t.name == name,
      orElse: () => ModelType.text,
    );
  }

  static List<ModelTag> _parseModelTags(dynamic value) {
    if (value == null) return [ModelTag.text];
    if (value is List) {
      final tags = <ModelTag>[];
      for (final v in value) {
        if (v is ModelTag) {
          tags.add(v);
        } else {
          final name = v.toString();
          try {
            tags.add(ModelTag.values.firstWhere((t) => t.name == name));
          } catch (_) {
            // 未知标签名，跳过
          }
        }
      }
      // 始终保证至少有 text 标签
      if (tags.isEmpty) tags.add(ModelTag.text);
      return tags;
    }
    return [ModelTag.text];
  }

  // --- 值相等 ---

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ModelInfo &&
          id == other.id &&
          type == other.type &&
          _listEquals(tags, other.tags);

  @override
  int get hashCode => Object.hash(id, type, Object.hashAll(tags));

  static bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
