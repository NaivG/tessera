import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/llm_provider_config.dart';
import '../models/model_selection_config.dart';

/// 设置服务 — 基于 shared_preferences 的用户偏好管理
class SettingsService {
  SharedPreferences? _prefs;

  // 键名常量
  static const _keyProviderConfigs = 'provider_configs';
  static const _keyThemeMode = 'theme_mode';
  static const _keyTtsEnabled = 'tts_enabled';
  static const _keySttEnabled = 'stt_enabled';
  static const _keyStreamEnabled = 'stream_enabled';
  static const _keyDeepThinkingEnabled = 'deep_thinking_enabled';
  static const _keyModelSelectionConfig = 'model_selection_config';
  static const _keyUserCustomPrompt = 'user_custom_prompt';
  static const _keyLightweightSystemPrompt = 'lightweight_system_prompt';
  static const _keyLocale = 'locale';

  Future<SharedPreferences> get _store async {
    if (_prefs != null) return _prefs!;
    _prefs = await SharedPreferences.getInstance();
    return _prefs!;
  }

  // --- 提供商配置列表 ---

  /// 加载所有提供商配置
  Future<List<LlmProviderConfig>> loadProviderConfigs() async {
    final raw = (await _store).getString(_keyProviderConfigs);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => LlmProviderConfig.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// 保存所有提供商配置
  Future<void> saveProviderConfigs(List<LlmProviderConfig> configs) async {
    final raw = jsonEncode(configs.map((e) => e.toJson()).toList());
    await (await _store).setString(_keyProviderConfigs, raw);
  }

  // --- 主题 ---

  Future<String> getThemeMode() async =>
      (await _store).getString(_keyThemeMode) ?? 'system';

  Future<void> setThemeMode(String mode) async =>
      (await _store).setString(_keyThemeMode, mode);

  // --- 语音 ---

  Future<bool> isTtsEnabled() async =>
      (await _store).getBool(_keyTtsEnabled) ?? false;

  Future<void> setTtsEnabled(bool enabled) async =>
      (await _store).setBool(_keyTtsEnabled, enabled);

  Future<bool> isSttEnabled() async =>
      (await _store).getBool(_keySttEnabled) ?? false;

  Future<void> setSttEnabled(bool enabled) async =>
      (await _store).setBool(_keySttEnabled, enabled);

  // --- 流式传输 ---

  Future<bool> isStreamEnabled() async =>
      (await _store).getBool(_keyStreamEnabled) ?? true;

  Future<void> setStreamEnabled(bool enabled) async =>
      (await _store).setBool(_keyStreamEnabled, enabled);

  // --- 深度思考 ---

  Future<bool> isDeepThinkingEnabled() async =>
      (await _store).getBool(_keyDeepThinkingEnabled) ?? false;

  Future<void> setDeepThinkingEnabled(bool enabled) async =>
      (await _store).setBool(_keyDeepThinkingEnabled, enabled);

  // --- 模型选择配置 ---

  /// 加载模型选择配置，无保存数据时返回空配置
  Future<ModelSelectionConfig> loadModelSelectionConfig() async {
    final raw = (await _store).getString(_keyModelSelectionConfig);
    if (raw == null || raw.isEmpty) return ModelSelectionConfig.empty();
    try {
      return ModelSelectionConfig.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return ModelSelectionConfig.empty();
    }
  }

  /// 保存模型选择配置
  Future<void> saveModelSelectionConfig(ModelSelectionConfig config) async {
    final raw = jsonEncode(config.toJson());
    await (await _store).setString(_keyModelSelectionConfig, raw);
  }

  // --- 轻量模式 ---

  Future<bool> isLightweightSystemPrompt() async =>
      (await _store).getBool(_keyLightweightSystemPrompt) ?? false;

  Future<void> setLightweightSystemPrompt(bool v) async =>
      (await _store).setBool(_keyLightweightSystemPrompt, v);

  // --- 用户自定义 Prompt ---

  /// 读取用户自定义系统提示词
  Future<String> getUserCustomPrompt() async =>
      (await _store).getString(_keyUserCustomPrompt) ?? '';

  /// 保存用户自定义系统提示词
  Future<void> setUserCustomPrompt(String prompt) async =>
      (await _store).setString(_keyUserCustomPrompt, prompt);

  // --- 用户档案 ---

  static const _keyUserDisplayName = 'user_display_name';
  static const _keyUserAlias = 'user_alias';
  static const _keyUserRole = 'user_role';
  static const _keyUserPreferences = 'user_preferences';
  static const _keyUserFacts = 'user_facts';

  Future<String> getUserDisplayName() async =>
      (await _store).getString(_keyUserDisplayName) ?? '';

  Future<void> setUserDisplayName(String v) async =>
      (await _store).setString(_keyUserDisplayName, v);

  Future<String> getUserAlias() async =>
      (await _store).getString(_keyUserAlias) ?? '';

  Future<void> setUserAlias(String v) async =>
      (await _store).setString(_keyUserAlias, v);

  Future<String> getUserRole() async =>
      (await _store).getString(_keyUserRole) ?? '';

  Future<void> setUserRole(String v) async =>
      (await _store).setString(_keyUserRole, v);

  Future<String> getUserPreferences() async =>
      (await _store).getString(_keyUserPreferences) ?? '';

  Future<void> setUserPreferences(String v) async =>
      (await _store).setString(_keyUserPreferences, v);

  Future<String> getUserFacts() async =>
      (await _store).getString(_keyUserFacts) ?? '';

  Future<void> setUserFacts(String v) async =>
      (await _store).setString(_keyUserFacts, v);

  // --- 语言 ---

  Future<String> getLocale() async =>
      (await _store).getString(_keyLocale) ?? 'system';

  Future<void> setLocale(String locale) async =>
      (await _store).setString(_keyLocale, locale);

  // --- 清除 ---

  Future<void> clearAll() async => (await _store).clear();
}
