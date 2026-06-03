import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models/model_info.dart';
import '../models/llm_config.dart';
import '../models/llm_provider_config.dart';
import '../models/model_selection_config.dart';
import '../services/settings_service.dart';

/// 设置状态 — 管理全局用户偏好和 LLM 提供商配置列表
class SettingsState extends ChangeNotifier {
  final SettingsService _service = SettingsService();
  static const _uuid = Uuid();

  /// 所有提供商配置列表
  List<LlmProviderConfig> _providerConfigs = [];

  ModelSelectionConfig _modelSelectionConfig = ModelSelectionConfig.empty();

  String _themeMode = 'system';
  bool _ttsEnabled = false;
  bool _sttEnabled = false;
  bool _streamEnabled = true;
  bool _deepThinkingEnabled = false;
  String _userCustomPrompt = '';
  bool _lightweightSystemPrompt = false;

  // 用户档案字段
  String _userDisplayName = '';
  String _userAlias = '';
  String _userRole = '';
  String _userPreferences = '';
  String _userFacts = '';

  // --- Getters ---

  List<LlmProviderConfig> get providerConfigs => _providerConfigs;
  ModelSelectionConfig get modelSelectionConfig => _modelSelectionConfig;
  String get themeMode => _themeMode;
  bool get ttsEnabled => _ttsEnabled;
  bool get sttEnabled => _sttEnabled;
  bool get streamEnabled => _streamEnabled;
  bool get deepThinkingEnabled => _deepThinkingEnabled;
  String get userCustomPrompt => _userCustomPrompt;
  bool get lightweightSystemPrompt => _lightweightSystemPrompt;
  String get userDisplayName => _userDisplayName;
  String get userAlias => _userAlias;
  String get userRole => _userRole;
  String get userPreferences => _userPreferences;
  String get userFacts => _userFacts;

  // --- 初始化 ---

  Future<void> load() async {
    _providerConfigs = await _service.loadProviderConfigs();
    // 向后兼容：为所有没有 uid 的 ModelInfo 分配 UUID
    _ensureModelUids();
    _themeMode = await _service.getThemeMode();
    _ttsEnabled = await _service.isTtsEnabled();
    _sttEnabled = await _service.isSttEnabled();
    _streamEnabled = await _service.isStreamEnabled();
    _deepThinkingEnabled = await _service.isDeepThinkingEnabled();
    _userCustomPrompt = await _service.getUserCustomPrompt();
    _lightweightSystemPrompt = await _service.isLightweightSystemPrompt();
    _userDisplayName = await _service.getUserDisplayName();
    _userAlias = await _service.getUserAlias();
    _userRole = await _service.getUserRole();
    _userPreferences = await _service.getUserPreferences();
    _userFacts = await _service.getUserFacts();
    _modelSelectionConfig = await _service.loadModelSelectionConfig();
    // 向后兼容迁移：将旧版整数索引 ModelSlot 转换为新版 UUID 引用
    _migrateModelSlots();

    notifyListeners();
  }

  /// 确保所有 [ModelInfo] 实例都有 uid（向后兼容旧数据）
  void _ensureModelUids() {
    bool changed = false;
    for (final config in _providerConfigs) {
      for (int i = 0; i < config.models.length; i++) {
        if (config.models[i].uid.isEmpty) {
          config.models[i] = config.models[i].copyWith(
            uid: _uuid.v4(),
          );
          changed = true;
        }
      }
    }
    if (changed) {
      _persistConfigs();
    }
  }

  /// 迁移旧版 [ModelSlot]（整数索引）到新版（UUID 引用）
  ///
  /// 旧数据使用 list index（pi/mi）引用提供商和模型，删除操作后索引偏移。
  /// 新版使用 [LlmProviderConfig.id] 和 [ModelInfo.uid] 做稳定引用。
  /// 此方法扫描所有 ModelSlot，将整数索引转换为对应的 UUID。
  void _migrateModelSlots() {
    ModelSlot migrateSlot(ModelSlot slot) {
      final oldPi = int.tryParse(slot.providerConfigId);
      final oldMi = int.tryParse(slot.modelUid);
      // 如果解析为整数，说明是旧格式
      if (oldPi == null || oldMi == null) return slot;
      if (oldPi < 0 || oldPi >= _providerConfigs.length) return slot;
      if (oldMi < 0 || oldMi >= _providerConfigs[oldPi].models.length) {
        return slot;
      }
      final provider = _providerConfigs[oldPi];
      final model = provider.models[oldMi];
      return ModelSlot(
        providerConfigId: provider.id,
        modelUid: model.uid,
      );
    }

    bool changed = false;
    var cfg = _modelSelectionConfig;

    // 迁移 mainModel
    final newMain = migrateSlot(cfg.mainModel);
    if (newMain != cfg.mainModel) {
      cfg = cfg.copyWith(mainModel: newMain);
      changed = true;
    }

    // 迁移 inputModalities
    final newInput = <ModelTag, ModelSlot?>{};
    for (final e in cfg.inputModalities.entries) {
      if (e.value == null) {
        newInput[e.key] = null;
      } else {
        newInput[e.key] = migrateSlot(e.value!);
        if (newInput[e.key] != e.value) changed = true;
      }
    }
    if (changed) cfg = cfg.copyWith(inputModalities: newInput);

    // 迁移 outputModalities
    final newOutput = <ModelType, ModelSlot?>{};
    for (final e in cfg.outputModalities.entries) {
      if (e.value == null) {
        newOutput[e.key] = null;
      } else {
        newOutput[e.key] = migrateSlot(e.value!);
        if (newOutput[e.key] != e.value) changed = true;
      }
    }
    if (changed) cfg = cfg.copyWith(outputModalities: newOutput);

    // 迁移 otherModels
    final newOther = <String, ModelSlot?>{};
    for (final e in cfg.otherModels.entries) {
      if (e.value == null) {
        newOther[e.key] = null;
      } else {
        newOther[e.key] = migrateSlot(e.value!);
        if (newOther[e.key] != e.value) changed = true;
      }
    }
    if (changed) cfg = cfg.copyWith(otherModels: newOther);

    if (changed) {
      _modelSelectionConfig = cfg;
      _service.saveModelSelectionConfig(_modelSelectionConfig);
    }
  }

  // --- 提供商配置管理 ---

  /// 按 providerId 查找配置索引，返回 -1 表示未找到
  int _findProviderIndex(String providerId) {
    return _providerConfigs.indexWhere((c) => c.id == providerId);
  }

  /// 添加新的提供商配置
  Future<LlmProviderConfig> addProviderConfig({
    required String format,
    String name = '',
    String apiKey = '',
    String baseUrl = '',
  }) async {
    final config = LlmProviderConfig(
      id: _uuid.v4(),
      name: name,
      format: format,
      apiKey: apiKey,
      baseUrl: baseUrl.isNotEmpty
          ? baseUrl
          : LlmProviderConfig.defaultBaseUrlFor(format),
    );
    _providerConfigs.add(config);

    await _persistConfigs();
    notifyListeners();
    return config;
  }

  /// 更新指定配置（通过 providerId）
  Future<void> updateProviderConfig(
    String providerId, {
    String? name,
    String? apiKey,
    String? baseUrl,
    bool clearName = false,
    bool clearApiKey = false,
    bool clearBaseUrl = false,
  }) async {
    final index = _findProviderIndex(providerId);
    if (index < 0) return;

    _providerConfigs[index] = _providerConfigs[index].copyWith(
      name: name,
      apiKey: apiKey,
      baseUrl: baseUrl,
      clearName: clearName,
      clearApiKey: clearApiKey,
      clearBaseUrl: clearBaseUrl,
    );

    await _persistConfigs();
    notifyListeners();
  }

  /// 删除指定配置（通过 providerId）
  Future<void> removeProviderConfig(String providerId) async {
    final index = _findProviderIndex(providerId);
    if (index < 0) return;

    _providerConfigs.removeAt(index);

    await _persistConfigs();
    notifyListeners();
  }

  // --- 模型管理（属于某个配置） ---

  /// 为指定配置添加模型（自动分配 model uid）
  Future<void> addModel(String providerId, ModelInfo modelInfo) async {
    final index = _findProviderIndex(providerId);
    if (index < 0) return;
    if (modelInfo.id.trim().isEmpty) return;

    final config = _providerConfigs[index];
    final exists = config.models.any((m) => m.id == modelInfo.id);
    if (!exists) {
      // 为新模型分配唯一 uid
      final newModel = ModelInfo(
        uid: _uuid.v4(),
        id: modelInfo.id,
        type: modelInfo.type,
        tags: List<ModelTag>.from(modelInfo.tags),
      );
      config.models.add(newModel);
      await _persistConfigs();
      notifyListeners();
    }
  }

  /// 从指定配置中移除模型（通过 modelUid）
  Future<void> removeModel(String providerId, String modelUid) async {
    final index = _findProviderIndex(providerId);
    if (index < 0) return;

    final config = _providerConfigs[index];
    config.models.removeWhere((m) => m.uid == modelUid);

    await _persistConfigs();
    notifyListeners();
  }

  // --- 主题 ---

  Future<void> setThemeMode(String mode) async {
    _themeMode = mode;
    await _service.setThemeMode(mode);
    notifyListeners();
  }

  // --- 语音 ---

  Future<void> setTtsEnabled(bool enabled) async {
    _ttsEnabled = enabled;
    await _service.setTtsEnabled(enabled);
    notifyListeners();
  }

  Future<void> setSttEnabled(bool enabled) async {
    _sttEnabled = enabled;
    await _service.setSttEnabled(enabled);
    notifyListeners();
  }

  // --- 流式传输 ---

  Future<void> setStreamEnabled(bool enabled) async {
    _streamEnabled = enabled;
    await _service.setStreamEnabled(enabled);
    notifyListeners();
  }

  // --- 深度思考 ---

  Future<void> setDeepThinkingEnabled(bool enabled) async {
    _deepThinkingEnabled = enabled;
    await _service.setDeepThinkingEnabled(enabled);
    notifyListeners();
  }

  // --- 用户自定义提示词 ---

  Future<void> setUserCustomPrompt(String prompt) async {
    _userCustomPrompt = prompt;
    await _service.setUserCustomPrompt(prompt);
    notifyListeners();
  }

  // --- 轻量模式 ---

  Future<void> setLightweightSystemPrompt(bool v) async {
    _lightweightSystemPrompt = v;
    await _service.setLightweightSystemPrompt(v);
    notifyListeners();
  }

  // --- 用户档案 ---

  Future<void> setUserDisplayName(String v) async {
    _userDisplayName = v;
    await _service.setUserDisplayName(v);
    notifyListeners();
  }

  Future<void> setUserAlias(String v) async {
    _userAlias = v;
    await _service.setUserAlias(v);
    notifyListeners();
  }

  Future<void> setUserRole(String v) async {
    _userRole = v;
    await _service.setUserRole(v);
    notifyListeners();
  }

  Future<void> setUserPreferences(String v) async {
    _userPreferences = v;
    await _service.setUserPreferences(v);
    notifyListeners();
  }

  Future<void> setUserFacts(String v) async {
    _userFacts = v;
    await _service.setUserFacts(v);
    notifyListeners();
  }

  /// 批量设置所有用户档案字段
  Future<void> setUserProfile({
    required String displayName,
    required String alias,
    required String role,
    required String preferences,
    required String facts,
  }) async {
    _userDisplayName = displayName;
    _userAlias = alias;
    _userRole = role;
    _userPreferences = preferences;
    _userFacts = facts;
    await _service.setUserDisplayName(displayName);
    await _service.setUserAlias(alias);
    await _service.setUserRole(role);
    await _service.setUserPreferences(preferences);
    await _service.setUserFacts(facts);
    notifyListeners();
  }

  // --- 模型选择配置 ---

  /// 构建主模型 LlmConfig（使用模型选择配置中的主模型）
  LlmConfig? buildMainLlmConfig() {
    final slot = _modelSelectionConfig.mainModel;
    return slot.buildConfig(this);
  }

  /// 设置主模型
  Future<void> setMainModel(ModelSlot slot) async {
    _modelSelectionConfig = _modelSelectionConfig.copyWith(mainModel: slot);
    await _service.saveModelSelectionConfig(_modelSelectionConfig);
    notifyListeners();
  }

  /// 设置输入模态模型（null = 使用主模型）
  Future<void> setInputModality(ModelTag tag, ModelSlot? slot) async {
    final newMap = Map<ModelTag, ModelSlot?>.from(_modelSelectionConfig.inputModalities);
    newMap[tag] = slot;
    _modelSelectionConfig = _modelSelectionConfig.copyWith(inputModalities: newMap);
    await _service.saveModelSelectionConfig(_modelSelectionConfig);
    notifyListeners();
  }

  /// 设置输出类型模型
  Future<void> setOutputModality(ModelType type, ModelSlot? slot) async {
    final newMap = Map<ModelType, ModelSlot?>.from(_modelSelectionConfig.outputModalities);
    newMap[type] = slot;
    _modelSelectionConfig = _modelSelectionConfig.copyWith(outputModalities: newMap);
    await _service.saveModelSelectionConfig(_modelSelectionConfig);
    notifyListeners();
  }

  /// 设置其他模型
  Future<void> setOtherModel(String key, ModelSlot? slot) async {
    final newMap = Map<String, ModelSlot?>.from(_modelSelectionConfig.otherModels);
    newMap[key] = slot;
    _modelSelectionConfig = _modelSelectionConfig.copyWith(otherModels: newMap);
    await _service.saveModelSelectionConfig(_modelSelectionConfig);
    notifyListeners();
  }

  /// 一次性替换整个模型选择配置
  Future<void> setModelSelectionConfig(ModelSelectionConfig config) async {
    _modelSelectionConfig = config;
    await _service.saveModelSelectionConfig(_modelSelectionConfig);
    notifyListeners();
  }

  // --- 内部 ---

  Future<void> _persistConfigs() async {
    await _service.saveProviderConfigs(_providerConfigs);
  }
}