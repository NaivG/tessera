// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get localeDescription => '简体中文';

  @override
  String get createdBy => '汉化 NaivG';

  @override
  String get appTitle => 'Tessera';

  @override
  String get commonCancel => '取消';

  @override
  String get commonDelete => '删除';

  @override
  String get commonSave => '保存';

  @override
  String get commonConfirm => '确认';

  @override
  String get commonClear => '清除';

  @override
  String get chatNewConversation => '新对话';

  @override
  String get chatNewLabel => '新建对话';

  @override
  String get chatNoConversations => '暂无对话';

  @override
  String get chatSend => '发送';

  @override
  String get chatModifyMessage => '修改消息';

  @override
  String get chatNewContentHint => '输入新内容';

  @override
  String get chatConfigureProviderFirst => '请先在设置中 LLM 提供商并选择模型';

  @override
  String get chatGoToSettings => '去设置';

  @override
  String get chatWelcomeTitle => 'Tessera AI';

  @override
  String get chatWelcomeSubtitle => '开始新对话，发送消息即可';

  @override
  String get bubbleThinking => '思考中...';

  @override
  String get bubbleThought => '已思考';

  @override
  String get bubbleToolCall => '调用工具...';

  @override
  String get bubbleNoArgs => '(无参数)';

  @override
  String get bubbleCopy => '复制';

  @override
  String get bubbleCopyMarkdown => 'Markdown';

  @override
  String get bubbleCopyPlainText => '纯文本';

  @override
  String get bubbleModify => '修改';

  @override
  String get bubbleRegenerate => '重新生成';

  @override
  String get bubbleShare => '分享';

  @override
  String get sidebarTitle => 'Tessera AI';

  @override
  String get sidebarCollapseTooltip => '收回侧边栏';

  @override
  String get sidebarCloseTooltip => '关闭';

  @override
  String get sidebarConversationsLabel => '对话';

  @override
  String get sidebarRename => '重命名';

  @override
  String get sidebarRenameDialogTitle => '重命名对话';

  @override
  String get sidebarRenameHint => '输入新名称';

  @override
  String get sidebarDeleteDialogTitle => '删除对话';

  @override
  String sidebarDeleteConfirm(Object title) {
    return '确定要删除「$title」吗？';
  }

  @override
  String get sidebarDefaultUserName => '用户';

  @override
  String get settingsTitle => '设置';

  @override
  String get settingsSectionUser => '用户';

  @override
  String get settingsUserProfile => '用户档案';

  @override
  String get settingsUserProfileSubtitle => '设置个人信息以让 AI 更好地了解你';

  @override
  String get settingsSectionLlmProviders => 'LLM 提供商';

  @override
  String get settingsEmptyProviders => '尚未配置任何 LLM 提供商';

  @override
  String get settingsEmptyProvidersSub => '点击下方按钮添加';

  @override
  String get settingsAddProvider => '添加提供商';

  @override
  String get settingsSectionModelSelection => '模型选择';

  @override
  String get settingsModelAssignment => '模型分配';

  @override
  String get settingsModelAssignmentSubtitle => '为各能力方向（文本/视觉/语音/嵌入等）指定模型';

  @override
  String get settingsSectionRequest => '请求';

  @override
  String get settingsStreamEnabled => '启用流式请求';

  @override
  String get settingsStreamEnabledSubtitle => '实时显示 AI 回复，关闭后等待完整回复';

  @override
  String get settingsDeepThinking => '启用深度思考';

  @override
  String get settingsDeepThinkingSubtitle => '显示模型的推理思考过程（部分模型默认开启）';

  @override
  String get settingsSectionSpeech => '语音';

  @override
  String get settingsTtsEnabled => '启用文字转语音 (TTS)';

  @override
  String get settingsTtsEnabledSubtitle => 'AI 回复时自动朗读';

  @override
  String get settingsSttEnabled => '启用语音输入 (STT)';

  @override
  String get settingsSttEnabledSubtitle => '通过语音输入消息';

  @override
  String get settingsSectionPrompt => '提示词';

  @override
  String get settingsLightweightMode => '轻量模式';

  @override
  String get settingsLightweightModeSubtitle =>
      '大幅缩减系统提示词，仅保留核心约束并不再限制安全指令，开启后跳过记忆加载。';

  @override
  String get settingsCustomPrompt => '自定义提示词';

  @override
  String get settingsEdit => '编辑';

  @override
  String settingsEditProvider(Object name) {
    return '编辑 $name';
  }

  @override
  String settingsModelCount(Object count) {
    return '模型 ($count):';
  }

  @override
  String get settingsEditModel => '编辑模型';

  @override
  String get settingsAddProviderDialogTitle => '添加 LLM 提供商';

  @override
  String get settingsProviderFormat => '提供商格式';

  @override
  String get settingsProviderNameLabel => '提供商名称（留空使用格式名称）';

  @override
  String get settingsProviderNameHint => '如: DeepSeek、自定义代理...';

  @override
  String get settingsBaseUrl => 'Base URL';

  @override
  String get settingsApiKey => 'API Key';

  @override
  String get settingsApiKeyOptional => 'API Key（无需）';

  @override
  String get settingsApiKeyHint => '输入 API Key...';

  @override
  String get settingsApiKeyNotNeeded => '(Ollama 不需要 API Key)';

  @override
  String get settingsApiKeyEditHint => '留空不修改...';

  @override
  String get settingsProviderAdd => '添加';

  @override
  String get settingsDeleteConfirmTitle => '确认删除';

  @override
  String settingsDeleteConfirm(Object name) {
    return '确定要删除「$name」吗？此操作不可撤销。';
  }

  @override
  String get messageInputImage => '图片';

  @override
  String get messageInputImageSubtitle => '从相册选择图片';

  @override
  String get messageInputCamera => '相机';

  @override
  String get messageInputCameraSubtitle => '使用相机拍摄';

  @override
  String get messageInputFile => '文件';

  @override
  String get messageInputFileSubtitle => '选择任意文件';

  @override
  String get memoryAppBarTitle => '记忆';

  @override
  String get memoryEmpty => '暂无记忆';

  @override
  String get memoryEmptySubtitle => '对话中提取的记忆会显示在这里';

  @override
  String get memoryTypeUser => '用户';

  @override
  String get memoryTypeKnowledge => '知识';

  @override
  String get memoryTypeEvent => '事件';

  @override
  String get memoryTypeConversational => '对话';

  @override
  String get memoryTypeLongTerm => '长期';

  @override
  String get libraryAppBarTitle => '资料库';

  @override
  String get libraryClearTooltip => '清空资料库';

  @override
  String get libraryEmpty => '资料库为空';

  @override
  String get libraryEmptySubtitle => '在对话中上传的图片、文件等会自动保存在这里';

  @override
  String get libraryDeleteDialogTitle => '删除文件';

  @override
  String libraryDeleteConfirm(Object name) {
    return '确定要删除「$name」吗？';
  }

  @override
  String get libraryClearDialogTitle => '清空资料库';

  @override
  String get libraryClearConfirm => '确定要删除资料库中的所有文件吗？此操作不可撤销。';

  @override
  String get profileAppBarTitle => '用户档案';

  @override
  String get profileSaving => '保存中…';

  @override
  String get profileSave => '保存';

  @override
  String get profileInfoCard =>
      '你填写的信息将注入系统提示词，帮助 AI 了解你的偏好和背景，提供更加个性化的回复。空字段将被忽略。';

  @override
  String get profileSectionBasic => '基本信息';

  @override
  String get profileDisplayName => '显示名称';

  @override
  String get profileDisplayNameHint => '例如：张三';

  @override
  String get profileAlias => '偏好称呼 / 别名';

  @override
  String get profileAliasHint => '例如：小张、Alice';

  @override
  String get profileRole => '角色 / 与 AI 的关系';

  @override
  String get profileRoleHint => '例如：软件工程师、学生';

  @override
  String get profileSectionPersonalization => '个性化信息';

  @override
  String get profilePreferences => '偏好与风格';

  @override
  String get profilePreferencesHint => '例如：喜欢简洁的回答、偏好中文、注重代码质量';

  @override
  String get profileFacts => '相关事实';

  @override
  String get profileFactsHint => '例如：住在北京、使用 Flutter 开发、正在学习 Rust';

  @override
  String get profileSaveButton => '保存用户档案';

  @override
  String get profileClearButton => '清除所有档案信息';

  @override
  String get profileUnsavedDialogTitle => '未保存的更改';

  @override
  String get profileUnsavedDialogContent => '你有未保存的更改，确定要离开吗？';

  @override
  String get profileLeave => '离开';

  @override
  String get profileSavedSnackbar => '用户档案已保存';

  @override
  String get profileClearDialogTitle => '清除用户档案';

  @override
  String get profileClearDialogContent => '确定要清除所有档案信息吗？此操作不可撤销。';

  @override
  String get errorTitle => 'Oops! An unexpected error occurred.';

  @override
  String get errorSubtitle => '应用发生了未处理的异常, 请将以下信息反馈给开发者';

  @override
  String get errorType => '错误类型';

  @override
  String get errorMessage => '错误信息';

  @override
  String get errorStackTrace => '堆栈跟踪';

  @override
  String get errorCopyInfo => '复制信息';

  @override
  String get errorRestart => '重启应用';

  @override
  String get errorCopied => '错误信息已复制到剪贴板';

  @override
  String errorRestartFailed(Object error) {
    return '重启失败: $error';
  }

  @override
  String get shortcutLibrary => '资料库';

  @override
  String get shortcutMemory => '记忆';

  @override
  String modelEditAppBarTitle(Object name) {
    return '编辑模型 - $name';
  }

  @override
  String modelEditAddModelDialogTitle(Object modelId) {
    return '添加模型: $modelId';
  }

  @override
  String get modelEditModelIdLabel => '模型 ID';

  @override
  String get modelEditModelTypeLabel => '模型类型';

  @override
  String get modelEditModalTagsLabel => '模态标签';

  @override
  String modelEditSelectedTags(Object tags) {
    return '已选标签: $tags';
  }

  @override
  String get modelEditApiInfoFetched => '已从 API 获取到模型信息，请确认';

  @override
  String get modelEditTitle => '编辑模型';

  @override
  String get modelEditDeleteTitle => '删除模型';

  @override
  String modelEditDeleteConfirm(Object model) {
    return '确定要删除模型「$model」吗？';
  }

  @override
  String get modelEditAddModel => '添加模型';

  @override
  String modelEditAddedModels(Object count) {
    return '已添加模型 ($count)';
  }

  @override
  String get modelEditFetching => '正在获取模型列表…';

  @override
  String get modelEditSearchHint => '搜索或输入模型 ID…';

  @override
  String get modelEditAddTooltip => '添加模型';

  @override
  String get modelEditNoModels => '尚未添加任何模型';

  @override
  String get modelEditAddPrompt => '在上方输入框中搜索或输入模型 ID 进行添加';

  @override
  String get modelEditDeleteTooltip => '删除模型';

  @override
  String get modelSelectionAppBarTitle => '模型选择';

  @override
  String get modelSelectionSectionMain => '主模型（文本 LLM）';

  @override
  String get modelSelectionMainSubtitle => '最基础的文本对话任务交给哪个模型';

  @override
  String get modelSelectionSectionInput => '多模态输入处理';

  @override
  String get modelSelectionInputSubtitle => '处理用户输入的图片、音频、视频时使用哪个模型。';

  @override
  String get modelSelectionInputHint => '若主模型支持该模态，可选择\"使用主模型\"。';

  @override
  String get modelSelectionSectionOutput => '多模态输出生成';

  @override
  String get modelSelectionSectionOther => '其他模型';

  @override
  String get modelSelectionSectionEmbedding => '嵌入模型';

  @override
  String get modelSelectionMainLabel => '主模型';

  @override
  String get modelSelectionUseMainModel => '使用主模型';

  @override
  String get modelSelectionNotConfigured => '未配置';

  @override
  String get modelSelectionClearSelection => '清除选择';

  @override
  String get modelSelectionSectionLlm => 'LLM 辅助功能';

  @override
  String get modelSelectionOutputSubtitle => '生成图片、视频、语音等非文本输出时使用哪个模型。';

  @override
  String get modelSelectionLlmSubtitle => '话题检测、记忆整理、内容总结等辅助任务。留空默认使用主模型。';

  @override
  String get modelSelectionOtherSubtitle =>
      '嵌入（Embedding）、排序（Ranking）等专用模型。话题检测/记忆整理/内容总结等 LLM 辅助功能请在上方选择。';

  @override
  String get modelSelectionTopicDetection => '话题检测';

  @override
  String get modelSelectionTopicDetectionHint => '检测对话话题、意图分类';

  @override
  String get modelSelectionMemoryOrganization => '记忆整理';

  @override
  String get modelSelectionMemoryOrganizationHint => '整理长期记忆、知识提取';

  @override
  String get modelSelectionContentSummarization => '内容总结';

  @override
  String get modelSelectionContentSummarizationHint => '对话/文档摘要生成';

  @override
  String get modelSelectionEmbeddingHint => '用于文本嵌入向量生成';

  @override
  String get modelSelectionRankingModel => '排序模型';

  @override
  String get modelSelectionRankingHint => '用于搜索结果重排序';

  @override
  String get modelSelectionNoModelsFound => '未找到可用的模型，请先在设置中添加对应模型';

  @override
  String get modelSelectionPickTitle => '选择模型';

  @override
  String get systemPrompt => '系统提示词';

  @override
  String get customPromptEditTitle => '自定义提示词注入';

  @override
  String customPromptLength(Object length) {
    return '共 $length 个字符';
  }

  @override
  String get notSetting => '未设置';

  @override
  String get customPromptHint => '在此输入的内容将注入到系统提示的 \"用户自定义指令\" 块中。留空则不注入。';

  @override
  String get customPromptHintTemplate => '例如：喜欢简洁的回答、偏好中文、注重代码质量等...';

  @override
  String get memoryFormatJustNow => '刚刚';

  @override
  String memoryFormatMinutesAgo(Object minutes) {
    return '$minutes 分钟前';
  }

  @override
  String memoryFormatHoursAgo(Object hours) {
    return '$hours 小时前';
  }

  @override
  String memoryFormatDaysAgo(Object days) {
    return '$days 天前';
  }

  @override
  String get mediaTypeImage => '图片';

  @override
  String get mediaTypeVideo => '视频';

  @override
  String get mediaTypeAudio => '音频';

  @override
  String get mediaTypeFile => '文件';

  @override
  String get settingsSectionAbout => '关于';

  @override
  String get settingsSectionLanguage => '语言';

  @override
  String get settingsLanguageSystem => '跟随系统';

  @override
  String get settingsLanguageZh => '简体中文';

  @override
  String get settingsLanguageEn => 'English';

  @override
  String get modelTypeText => '文本生成';

  @override
  String get modelTypeImage => '文生图';

  @override
  String get modelTypeVideo => '文生视频';

  @override
  String get modelTypeSpeech => '文生语音';

  @override
  String get modelTypeEmbedding => '嵌入';

  @override
  String get modelTypeRanking => '排序';

  @override
  String get modelTagText => '文本';

  @override
  String get modelTagVision => '视觉';

  @override
  String get modelTagAudible => '音频';

  @override
  String get modelTagVideo => '视频';

  @override
  String get modelTagsOmni => '全模态';

  @override
  String get modelTagsTextOnly => '纯文本';

  @override
  String get toolboxLabel => '资料库';

  @override
  String get pluginAppBarTitle => '插件管理';

  @override
  String get pluginEmpty => '暂无插件';

  @override
  String get pluginLoadError => '加载插件失败';

  @override
  String get pluginRetry => '重试';

  @override
  String get pluginInstall => '安装';

  @override
  String get pluginUninstall => '卸载';

  @override
  String get pluginInstalled => '已安装';

  @override
  String get pluginBundled => '捆版';

  @override
  String pluginInstallSuccess(String name) =>
      '插件「$name」安装成功';

  @override
  String pluginInstallFailed(String error) => '安装失败: $error';

  @override
  String pluginUninstallSuccess(String name) =>
      '插件「$name」已卸载';

  @override
  String pluginUninstallFailed(String error) => '卸载失败: $error';

  @override
  String pluginUninstallConfirm(String name) =>
      '确定要卸载「$name」吗？\n此操作将删除插件文件。';

  @override
  String get pluginUninstallDialogTitle => '卸载插件';

  @override
  String pluginEnableFailed(String name) =>
      '启用插件「$name」失败';

  @override
  String pluginByAuthor(String author) => '来自 $author';

  @override
  String get pluginShortcut => '插件';

  @override
  String get pluginSectionInstalled => '已安装';

  @override
  String get pluginSectionBundled => '捆绑插件源';

  @override
  String get pluginSectionInstallFromFile => '从文件安装';

  @override
  String get pluginInstallFromFileAction => '选择 .plugin 文件';

  @override
  String get pluginInstallFromZip => '从 ZIP 安装';

  @override
  String get pluginInstallConfirmTitle => '安装插件';

  @override
  String pluginInvalidZip(String error) => '无效的插件包: $error';

  @override
  String get statsAppBarTitle => '使用统计';

  @override
  String get statsOverall => '总计';

  @override
  String get statsTotalTokens => '总 Token 数';

  @override
  String get statsPromptTokens => '提示';

  @override
  String get statsCompletionTokens => '补全';

  @override
  String get statsCacheHitRate => '缓存命中率';

  @override
  String get statsRequests => '请求次数';

  @override
  String get statsReset => '重置';

  @override
  String get statsResetConfirmTitle => '确认重置';

  @override
  String get statsResetConfirm => '确定要重置所有使用统计吗？此操作不可撤销。';

  @override
  String get statsEmpty => '暂无统计数据';

  @override
  String get statsEmptySubtitle => '开始与 AI 模型对话后，使用数据将显示在此处';

  @override
  String get statsShortcut => '统计';
}
