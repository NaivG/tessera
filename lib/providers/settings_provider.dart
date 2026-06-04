import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/llm_config.dart';
import '../models/llm_provider_config.dart';
import '../models/model_info.dart';
import '../models/model_selection_config.dart';
import '../services/settings_service.dart';
import 'settings_service_provider.dart';

// =============================================================================
// 不可变数据类 — SettingsData
// =============================================================================

/// 设置状态数据（不可变）
class SettingsData {
  final List<LlmProviderConfig> providerConfigs;
  final ModelSelectionConfig modelSelectionConfig;
  final String themeMode;
  final bool ttsEnabled;
  final bool sttEnabled;
  final bool streamEnabled;
  final bool deepThinkingEnabled;
  final String userCustomPrompt;
  final bool lightweightSystemPrompt;
  final String locale;
  final String userDisplayName;
  final String userAlias;
  final String userRole;
  final String userPreferences;
  final String userFacts;
  final bool loaded;

  SettingsData({
    this.loaded = false,
    this.providerConfigs = const [],
    ModelSelectionConfig? modelSelectionConfig,
    this.themeMode = 'system',
    this.ttsEnabled = false,
    this.sttEnabled = false,
    this.streamEnabled = true,
    this.deepThinkingEnabled = false,
    this.userCustomPrompt = '',
    this.lightweightSystemPrompt = false,
    this.locale = 'system',
    this.userDisplayName = '',
    this.userAlias = '',
    this.userRole = '',
    this.userPreferences = '',
    this.userFacts = '',
  }) : modelSelectionConfig = modelSelectionConfig ?? ModelSelectionConfig.empty();

  SettingsData copyWith({
    bool? loaded,
    List<LlmProviderConfig>? providerConfigs,
    ModelSelectionConfig? modelSelectionConfig,
    String? themeMode,
    bool? ttsEnabled,
    bool? sttEnabled,
    bool? streamEnabled,
    bool? deepThinkingEnabled,
    String? userCustomPrompt,
    bool? lightweightSystemPrompt,
    String? locale,
    String? userDisplayName,
    String? userAlias,
    String? userRole,
    String? userPreferences,
    String? userFacts,
  }) {
    return SettingsData(
      loaded: loaded ?? this.loaded,
      providerConfigs: providerConfigs ?? this.providerConfigs,
      modelSelectionConfig: modelSelectionConfig ?? this.modelSelectionConfig,
      themeMode: themeMode ?? this.themeMode,
      ttsEnabled: ttsEnabled ?? this.ttsEnabled,
      sttEnabled: sttEnabled ?? this.sttEnabled,
      streamEnabled: streamEnabled ?? this.streamEnabled,
      deepThinkingEnabled: deepThinkingEnabled ?? this.deepThinkingEnabled,
      userCustomPrompt: userCustomPrompt ?? this.userCustomPrompt,
      lightweightSystemPrompt:
          lightweightSystemPrompt ?? this.lightweightSystemPrompt,
      locale: locale ?? this.locale,
      userDisplayName: userDisplayName ?? this.userDisplayName,
      userAlias: userAlias ?? this.userAlias,
      userRole: userRole ?? this.userRole,
      userPreferences: userPreferences ?? this.userPreferences,
      userFacts: userFacts ?? this.userFacts,
    );
  }
}

// =============================================================================
// SettingsNotifier — 替代 SettingsState (ChangeNotifier)
// =============================================================================

/// 设置状态 Notifier — 管理全局用户偏好和 LLM 提供商配置列表
class SettingsNotifier extends Notifier<SettingsData> {
  static const _uuid = Uuid();

  late final SettingsService _service;

  @override
  SettingsData build() {
    _service = ref.read(settingsServiceProvider);
    return SettingsData();
  }

  // ---------------------------------------------------------------------------
  // 初始化
  // ---------------------------------------------------------------------------

  /// 从持久化存储加载所有设置
  Future<void> load() async {
    final providerConfigs = await _service.loadProviderConfigs();
    _ensureModelUids(providerConfigs);
    final themeMode = await _service.getThemeMode();
    final ttsEnabled = await _service.isTtsEnabled();
    final sttEnabled = await _service.isSttEnabled();
    final streamEnabled = await _service.isStreamEnabled();
    final deepThinkingEnabled = await _service.isDeepThinkingEnabled();
    final userCustomPrompt = await _service.getUserCustomPrompt();
    final lightweightSystemPrompt = await _service.isLightweightSystemPrompt();
    final locale = await _service.getLocale();
    final userDisplayName = await _service.getUserDisplayName();
    final userAlias = await _service.getUserAlias();
    final userRole = await _service.getUserRole();
    final userPreferences = await _service.getUserPreferences();
    final userFacts = await _service.getUserFacts();
    var modelSelectionConfig = await _service.loadModelSelectionConfig();
    modelSelectionConfig = _migrateModelSlots(providerConfigs, modelSelectionConfig);

    state = SettingsData(
      loaded: true,
      providerConfigs: providerConfigs,
      modelSelectionConfig: modelSelectionConfig,
      themeMode: themeMode,
      ttsEnabled: ttsEnabled,
      sttEnabled: sttEnabled,
      streamEnabled: streamEnabled,
      deepThinkingEnabled: deepThinkingEnabled,
      userCustomPrompt: userCustomPrompt,
      lightweightSystemPrompt: lightweightSystemPrompt,
      locale: locale,
      userDisplayName: userDisplayName,
      userAlias: userAlias,
      userRole: userRole,
      userPreferences: userPreferences,
      userFacts: userFacts,
    );
  }

  /// 确保所有 ModelInfo 都有 uid（向后兼容旧数据）
  void _ensureModelUids(List<LlmProviderConfig> configs) {
    bool changed = false;
    for (final config in configs) {
      for (int i = 0; i < config.models.length; i++) {
        if (config.models[i].uid.isEmpty) {
          config.models[i] = config.models[i].copyWith(uid: _uuid.v4());
          changed = true;
        }
      }
    }
    if (changed) {
      _persistConfigs(configs);
    }
  }

  /// 迁移旧版 ModelSlot（整数索引 → UUID 引用）
  ModelSelectionConfig _migrateModelSlots(
    List<LlmProviderConfig> configs,
    ModelSelectionConfig cfg,
  ) {
    ModelSlot migrateSlot(ModelSlot slot) {
      final oldPi = int.tryParse(slot.providerConfigId);
      final oldMi = int.tryParse(slot.modelUid);
      if (oldPi == null || oldMi == null) return slot;
      if (oldPi < 0 || oldPi >= configs.length) return slot;
      if (oldMi < 0 || oldMi >= configs[oldPi].models.length) return slot;
      final provider = configs[oldPi];
      final model = provider.models[oldMi];
      return ModelSlot(providerConfigId: provider.id, modelUid: model.uid);
    }

    bool changed = false;

    final newMain = migrateSlot(cfg.mainModel);
    if (newMain != cfg.mainModel) {
      cfg = cfg.copyWith(mainModel: newMain);
      changed = true;
    }

    final newInput = <ModelTag, ModelSlot?>{};
    for (final e in cfg.inputModalities.entries) {
      newInput[e.key] = e.value != null ? migrateSlot(e.value!) : null;
      if (newInput[e.key] != e.value) changed = true;
    }
    if (changed) cfg = cfg.copyWith(inputModalities: newInput);

    final newOutput = <ModelType, ModelSlot?>{};
    for (final e in cfg.outputModalities.entries) {
      newOutput[e.key] = e.value != null ? migrateSlot(e.value!) : null;
      if (newOutput[e.key] != e.value) changed = true;
    }
    if (changed) cfg = cfg.copyWith(outputModalities: newOutput);

    final newOther = <String, ModelSlot?>{};
    for (final e in cfg.otherModels.entries) {
      newOther[e.key] = e.value != null ? migrateSlot(e.value!) : null;
      if (newOther[e.key] != e.value) changed = true;
    }
    if (changed) cfg = cfg.copyWith(otherModels: newOther);

    if (changed) {
      _service.saveModelSelectionConfig(cfg);
    }
    return cfg;
  }

  // ---------------------------------------------------------------------------
  // 提供商配置管理
  // ---------------------------------------------------------------------------

  int _findProviderIndex(String providerId) {
    return state.providerConfigs.indexWhere((c) => c.id == providerId);
  }

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
    final newList = [...state.providerConfigs, config];
    state = state.copyWith(providerConfigs: newList);
    await _persistConfigs(newList);
    return config;
  }

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
    final newList = [...state.providerConfigs];
    newList[index] = newList[index].copyWith(
      name: name,
      apiKey: apiKey,
      baseUrl: baseUrl,
      clearName: clearName,
      clearApiKey: clearApiKey,
      clearBaseUrl: clearBaseUrl,
    );
    state = state.copyWith(providerConfigs: newList);
    await _persistConfigs(newList);
  }

  Future<void> removeProviderConfig(String providerId) async {
    final index = _findProviderIndex(providerId);
    if (index < 0) return;
    final newList = [...state.providerConfigs]..removeAt(index);
    state = state.copyWith(providerConfigs: newList);
    await _persistConfigs(newList);
  }

  // ---------------------------------------------------------------------------
  // 模型管理
  // ---------------------------------------------------------------------------

  Future<void> addModel(String providerId, ModelInfo modelInfo) async {
    final index = _findProviderIndex(providerId);
    if (index < 0) return;
    if (modelInfo.id.trim().isEmpty) return;

    final newList = [...state.providerConfigs];
    final config = newList[index];
    final exists = config.models.any((m) => m.id == modelInfo.id);
    if (!exists) {
      final newModel = ModelInfo(
        uid: _uuid.v4(),
        id: modelInfo.id,
        type: modelInfo.type,
        tags: List<ModelTag>.from(modelInfo.tags),
      );
      config.models.add(newModel);
      state = state.copyWith(providerConfigs: newList);
      await _persistConfigs(newList);
    }
  }

  Future<void> removeModel(String providerId, String modelUid) async {
    final index = _findProviderIndex(providerId);
    if (index < 0) return;
    final newList = [...state.providerConfigs];
    newList[index].models.removeWhere((m) => m.uid == modelUid);
    state = state.copyWith(providerConfigs: newList);
    await _persistConfigs(newList);
  }

  // ---------------------------------------------------------------------------
  // 主题
  // ---------------------------------------------------------------------------

  Future<void> setThemeMode(String mode) async {
    state = state.copyWith(themeMode: mode);
    await _service.setThemeMode(mode);
  }

  // ---------------------------------------------------------------------------
  // 语音
  // ---------------------------------------------------------------------------

  Future<void> setTtsEnabled(bool enabled) async {
    state = state.copyWith(ttsEnabled: enabled);
    await _service.setTtsEnabled(enabled);
  }

  Future<void> setSttEnabled(bool enabled) async {
    state = state.copyWith(sttEnabled: enabled);
    await _service.setSttEnabled(enabled);
  }

  // ---------------------------------------------------------------------------
  // 流式传输
  // ---------------------------------------------------------------------------

  Future<void> setStreamEnabled(bool enabled) async {
    state = state.copyWith(streamEnabled: enabled);
    await _service.setStreamEnabled(enabled);
  }

  // ---------------------------------------------------------------------------
  // 深度思考
  // ---------------------------------------------------------------------------

  Future<void> setDeepThinkingEnabled(bool enabled) async {
    state = state.copyWith(deepThinkingEnabled: enabled);
    await _service.setDeepThinkingEnabled(enabled);
  }

  // ---------------------------------------------------------------------------
  // 用户自定义提示词
  // ---------------------------------------------------------------------------

  Future<void> setUserCustomPrompt(String prompt) async {
    state = state.copyWith(userCustomPrompt: prompt);
    await _service.setUserCustomPrompt(prompt);
  }

  // ---------------------------------------------------------------------------
  // 轻量模式
  // ---------------------------------------------------------------------------

  Future<void> setLightweightSystemPrompt(bool v) async {
    state = state.copyWith(lightweightSystemPrompt: v);
    await _service.setLightweightSystemPrompt(v);
  }

  // ---------------------------------------------------------------------------
  // 语言
  // ---------------------------------------------------------------------------

  Future<void> setLocale(String locale) async {
    state = state.copyWith(locale: locale);
    await _service.setLocale(locale);
  }

  // ---------------------------------------------------------------------------
  // 用户档案
  // ---------------------------------------------------------------------------

  Future<void> setUserDisplayName(String v) async {
    state = state.copyWith(userDisplayName: v);
    await _service.setUserDisplayName(v);
  }

  Future<void> setUserAlias(String v) async {
    state = state.copyWith(userAlias: v);
    await _service.setUserAlias(v);
  }

  Future<void> setUserRole(String v) async {
    state = state.copyWith(userRole: v);
    await _service.setUserRole(v);
  }

  Future<void> setUserPreferences(String v) async {
    state = state.copyWith(userPreferences: v);
    await _service.setUserPreferences(v);
  }

  Future<void> setUserFacts(String v) async {
    state = state.copyWith(userFacts: v);
    await _service.setUserFacts(v);
  }

  Future<void> setUserProfile({
    required String displayName,
    required String alias,
    required String role,
    required String preferences,
    required String facts,
  }) async {
    state = state.copyWith(
      userDisplayName: displayName,
      userAlias: alias,
      userRole: role,
      userPreferences: preferences,
      userFacts: facts,
    );
    await _service.setUserDisplayName(displayName);
    await _service.setUserAlias(alias);
    await _service.setUserRole(role);
    await _service.setUserPreferences(preferences);
    await _service.setUserFacts(facts);
  }

  // ---------------------------------------------------------------------------
  // 模型选择配置
  // ---------------------------------------------------------------------------

  /// 构建主模型 LlmConfig
  LlmConfig? buildMainLlmConfig() {
    final slot = state.modelSelectionConfig.mainModel;
    return slot.buildConfig(state);
  }

  LlmConfig? buildLlmConfig(ModelSlot? slot) {
    return slot?.buildConfig(state);
  }

  Future<void> setMainModel(ModelSlot slot) async {
    final newCfg = state.modelSelectionConfig.copyWith(mainModel: slot);
    state = state.copyWith(modelSelectionConfig: newCfg);
    await _service.saveModelSelectionConfig(newCfg);
  }

  Future<void> setInputModality(ModelTag tag, ModelSlot? slot) async {
    final newMap =
        Map<ModelTag, ModelSlot?>.from(state.modelSelectionConfig.inputModalities);
    newMap[tag] = slot;
    final newCfg = state.modelSelectionConfig.copyWith(inputModalities: newMap);
    state = state.copyWith(modelSelectionConfig: newCfg);
    await _service.saveModelSelectionConfig(newCfg);
  }

  Future<void> setOutputModality(ModelType type, ModelSlot? slot) async {
    final newMap =
        Map<ModelType, ModelSlot?>.from(state.modelSelectionConfig.outputModalities);
    newMap[type] = slot;
    final newCfg = state.modelSelectionConfig.copyWith(outputModalities: newMap);
    state = state.copyWith(modelSelectionConfig: newCfg);
    await _service.saveModelSelectionConfig(newCfg);
  }

  Future<void> setOtherModel(String key, ModelSlot? slot) async {
    final newMap =
        Map<String, ModelSlot?>.from(state.modelSelectionConfig.otherModels);
    newMap[key] = slot;
    final newCfg = state.modelSelectionConfig.copyWith(otherModels: newMap);
    state = state.copyWith(modelSelectionConfig: newCfg);
    await _service.saveModelSelectionConfig(newCfg);
  }

  Future<void> setModelSelectionConfig(ModelSelectionConfig config) async {
    state = state.copyWith(modelSelectionConfig: config);
    await _service.saveModelSelectionConfig(config);
  }

  // ---------------------------------------------------------------------------
  // 内部
  // ---------------------------------------------------------------------------

  Future<void> _persistConfigs(List<LlmProviderConfig> configs) async {
    await _service.saveProviderConfigs(configs);
  }
}

// =============================================================================
// Provider 定义
// =============================================================================

/// 设置状态 Provider — 持有 [SettingsData] 状态
final settingsProvider =
    NotifierProvider<SettingsNotifier, SettingsData>(SettingsNotifier.new);
