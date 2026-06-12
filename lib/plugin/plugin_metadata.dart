/// 插件元数据 — 描述一个 Lua 插件的身份与入口
class PluginMetadata {
  /// 插件唯一标识（反向域名风格，如 "com.tessera.example"）
  final String id;

  /// 展示名称
  final String name;

  /// 版本号（semver）
  final String version;

  /// 作者
  final String author;

  /// 功能描述
  final String description;

  /// Lua 入口文件路径（相对于插件目录）
  final String entryPoint;

  /// 可选的项目首页
  final String? homepage;

  /// 是否已启用
  final bool enabled;

  const PluginMetadata({
    required this.id,
    required this.name,
    required this.version,
    required this.author,
    required this.description,
    this.entryPoint = 'main.lua',
    this.homepage,
    this.enabled = true,
  });

  // ---------------------------------------------------------------------------
  // JSON 序列化 — 与 plugin.json 文件对应
  // ---------------------------------------------------------------------------

  factory PluginMetadata.fromJson(
    Map<String, dynamic> json, {
    bool enabled = true,
  }) {
    return PluginMetadata(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      version: json['version'] as String? ?? '0.0.0',
      author: json['author'] as String? ?? '',
      description: json['description'] as String? ?? '',
      entryPoint: json['entryPoint'] as String? ?? 'main.lua',
      homepage: json['homepage'] as String?,
      enabled: enabled,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'version': version,
        'author': author,
        'description': description,
        'entryPoint': entryPoint,
        if (homepage != null) 'homepage': homepage,
      };

  // ---------------------------------------------------------------------------
  // 副本
  // ---------------------------------------------------------------------------

  PluginMetadata copyWith({bool? enabled}) => PluginMetadata(
        id: id,
        name: name,
        version: version,
        author: author,
        description: description,
        entryPoint: entryPoint,
        homepage: homepage,
        enabled: enabled ?? this.enabled,
      );

  @override
  String toString() => 'Plugin($id $version "$name")';
}
