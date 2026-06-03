import 'llm_config.dart';
import 'model_info.dart';

/// 模型槽位 — 引用某个提供商下的某个模型
///
/// 使用 [providerConfigId]（提供商 UUID）+ [modelUid]（模型实例 UUID）
/// 替代旧的整数索引方案，避免因删除操作导致列表索引偏移而引用失效。
/// 实际 [LlmConfig] 由 [buildConfig] 从 [dynamic] state 动态构建，
/// 避免在持久化数据中重复存储 API Key。
class ModelSlot {
  /// 提供商配置 ID（UUID）
  final String providerConfigId;

  /// 模型实例 ID（ModelInfo.uid，UUID）
  final String modelUid;

  const ModelSlot({required this.providerConfigId, required this.modelUid});

  /// 构建可执行的 [LlmConfig]
  ///
  /// [state] 为任意对象，只要提供 `providerConfigs`（List）和
  /// 每项 `models`（List）、`format`、`displayName`、`apiKey`、`baseUrl` 属性即可。
  /// 实际使用时传入 [SettingsState]。
  LlmConfig? buildConfig(dynamic state) {
    final configs = state.providerConfigs as List?;
    if (configs == null) return null;

    // 按 providerConfigId 查找
    dynamic provider;
    for (final c in configs) {
      if ((c.id as String?) == providerConfigId) {
        provider = c;
        break;
      }
    }
    if (provider == null) return null;

    // 按 modelUid 查找
    final models = provider.models as List?;
    if (models == null) return null;
    dynamic model;
    for (final m in models) {
      if ((m.uid as String?) == modelUid) {
        model = m;
        break;
      }
    }
    if (model == null) return null;

    return LlmConfig(
      providerId: provider.format as String,
      providerName: (provider.displayName as String?) ?? '',
      modelId: (model.id as String?) ?? '',
      apiKey: (provider.apiKey as String?)?.isNotEmpty == true
          ? provider.apiKey as String
          : null,
      baseUrl: (provider.baseUrl as String?)?.isNotEmpty == true
          ? provider.baseUrl as String
          : null,
    );
  }

  /// 获取模型 [ModelInfo]
  ModelInfo? getModelInfo(dynamic state) {
    final configs = state.providerConfigs as List?;
    if (configs == null) return null;

    for (final c in configs) {
      if ((c.id as String?) == providerConfigId) {
        final models = c.models as List?;
        if (models == null) return null;
        for (final m in models) {
          if ((m.uid as String?) == modelUid) {
            return m as ModelInfo?;
          }
        }
      }
    }
    return null;
  }

  /// 有效性检查
  bool isValid(dynamic state) {
    return buildConfig(state) != null;
  }

  /// 显示标签：提供商名/模型ID
  String displayLabel(dynamic state) {
    final cfg = buildConfig(state);
    if (cfg == null) return '(无效)';
    return cfg.chatLabel;
  }

  // --- 序列化 ---

  /// 从 JSON 反序列化，同时向后兼容旧格式（整数索引 `pi`/`mi`）。
  factory ModelSlot.fromJson(Map<String, dynamic> json) {
    // 新格式：字符串 ID
    if (json.containsKey('pc') && json.containsKey('mu')) {
      return ModelSlot(
        providerConfigId: json['pc'] as String,
        modelUid: json['mu'] as String,
      );
    }
    // 旧格式（整数索引），转为空 ID 占位，将在加载时通过兼容逻辑处理
    return ModelSlot(
      providerConfigId: json['pi'].toString(),
      modelUid: json['mi'].toString(),
    );
  }

  Map<String, dynamic> toJson() => {'pc': providerConfigId, 'mu': modelUid};

  @override
  bool operator ==(Object other) =>
      other is ModelSlot &&
      other.providerConfigId == providerConfigId &&
      other.modelUid == modelUid;

  @override
  int get hashCode => Object.hash(providerConfigId, modelUid);

  @override
  String toString() => 'ModelSlot(pc: $providerConfigId, mu: $modelUid)';
}

/// 模型选择配置
///
/// 定义各能力方向应使用哪个模型：
/// - [mainModel]：主文本 LLM
/// - [inputModalities]：输入模态 → 模型映射（null = 使用主模型）
/// - [outputModalities]：输出类型 → 模型映射
/// - [otherModels]：嵌入/排序等 → 模型映射
class ModelSelectionConfig {
  /// 主文本 LLM
  final ModelSlot mainModel;

  /// 输入模态模型映射。key 为 [ModelTag]（不含 text），
  /// value 为 null 时表示"若主模型支持则使用主模型"
  final Map<ModelTag, ModelSlot?> inputModalities;

  /// 输出类型模型映射。key 为 [ModelType]（不含 text）
  final Map<ModelType, ModelSlot?> outputModalities;

  /// 其他模型：嵌入、排序等
  final Map<String, ModelSlot?> otherModels;

  const ModelSelectionConfig({
    required this.mainModel,
    this.inputModalities = const {},
    this.outputModalities = const {},
    this.otherModels = const {},
  });

  /// 空配置（实际使用前需设置 mainModel）
  factory ModelSelectionConfig.empty() {
    return const ModelSelectionConfig(
      mainModel: ModelSlot(providerConfigId: '', modelUid: ''),
    );
  }

  // --- 解析 ---

  /// 解析输入模态应使用哪个模型
  ///
  /// - slot 非 null → 使用 slot 指定模型
  /// - slot 为 null 且主模型支持该 tag → 使用主模型
  /// - 否则 → 返回 null（不支持）
  ModelSlot? resolveInput(ModelTag tag, dynamic state) {
    final slot = inputModalities[tag];
    if (slot != null) return slot;

    // null → 尝试主模型
    final mainInfo = mainModel.getModelInfo(state);
    if (mainInfo != null && mainInfo.tags.contains(tag)) {
      return mainModel;
    }
    return null;
  }

  /// 解析输出类型应使用哪个模型
  ModelSlot? resolveOutput(ModelType type, dynamic state) {
    return outputModalities[type];
  }

  /// 解析其他模型
  ModelSlot? resolveOther(String key, dynamic state) {
    return otherModels[key];
  }

  // --- 有效性 ---

  /// 主模型是否有效
  bool get isMainModelValid => true; // 由调用方检查

  /// 所有选中的模型槽位是否仍然有效
  List<String> validateAll(dynamic state) {
    final errors = <String>[];
    if (!mainModel.isValid(state)) {
      errors.add('Main model is invalid');
    }
    for (final entry in inputModalities.entries) {
      if (entry.value != null && !entry.value!.isValid(state)) {
        errors.add('${entry.key.displayName} input model is invalid');
      }
    }
    for (final entry in outputModalities.entries) {
      if (entry.value != null && !entry.value!.isValid(state)) {
        errors.add('${entry.key.displayName} output model is invalid');
      }
    }
    for (final entry in otherModels.entries) {
      if (entry.value != null && !entry.value!.isValid(state)) {
        errors.add('${entry.key} model is invalid');
      }
    }
    return errors;
  }

  // --- 序列化 ---

  factory ModelSelectionConfig.fromJson(Map<String, dynamic> json) {
    return ModelSelectionConfig(
      mainModel: ModelSlot.fromJson(json['main'] as Map<String, dynamic>),
      inputModalities: _deserializeMap(
        json['input_m'] as Map<String, dynamic>?,
        (k) => ModelTag.values.firstWhere((t) => t.name == k),
      ),
      outputModalities: _deserializeMap(
        json['output_m'] as Map<String, dynamic>?,
        (k) => ModelType.values.firstWhere((t) => t.name == k),
      ),
      otherModels: _deserializeMap(
        json['other_m'] as Map<String, dynamic>?,
        (k) => k,
      ),
    );
  }

  static Map<K, ModelSlot?> _deserializeMap<K>(
    Map<String, dynamic>? raw,
    K Function(String) keyParser,
  ) {
    if (raw == null) return {};
    final result = <K, ModelSlot?>{};
    for (final entry in raw.entries) {
      final key = keyParser(entry.key);
      result[key] = entry.value != null
          ? ModelSlot.fromJson(entry.value as Map<String, dynamic>)
          : null;
    }
    return result;
  }

  Map<String, dynamic> toJson() {
    return {
      'main': mainModel.toJson(),
      'input_m': _serializeMap(inputModalities, (k) => k.name),
      'output_m': _serializeMap(outputModalities, (k) => k.name),
      'other_m': _serializeMap(otherModels, (k) => k),
    };
  }

  static Map<String, dynamic> _serializeMap<K>(
    Map<K, ModelSlot?> map,
    String Function(K) keySerializer,
  ) {
    final result = <String, dynamic>{};
    for (final entry in map.entries) {
      result[keySerializer(entry.key)] = entry.value?.toJson();
    }
    return result;
  }

  // --- 复制 ---

  ModelSelectionConfig copyWith({
    ModelSlot? mainModel,
    Map<ModelTag, ModelSlot?>? inputModalities,
    Map<ModelType, ModelSlot?>? outputModalities,
    Map<String, ModelSlot?>? otherModels,
  }) {
    return ModelSelectionConfig(
      mainModel: mainModel ?? this.mainModel,
      inputModalities: inputModalities ?? Map.from(this.inputModalities),
      outputModalities: outputModalities ?? Map.from(this.outputModalities),
      otherModels: otherModels ?? Map.from(this.otherModels),
    );
  }
}
