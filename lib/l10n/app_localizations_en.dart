// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get localeDescription => 'English';

  @override
  String get createdBy => 'Localized by NaivG';

  @override
  String get appTitle => 'Tessera';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonDelete => 'Delete';

  @override
  String get commonSave => 'Save';

  @override
  String get commonConfirm => 'OK';

  @override
  String get commonClear => 'Clear';

  @override
  String get chatNewConversation => 'New Chat';

  @override
  String get chatNewLabel => 'New Conversation';

  @override
  String get chatNoConversations => 'No conversations';

  @override
  String get chatSend => 'Send';

  @override
  String get chatModifyMessage => 'Modify Message';

  @override
  String get chatNewContentHint => 'Enter new content';

  @override
  String get chatConfigureProviderFirst =>
      'Please configure an LLM provider and select a model in Settings first';

  @override
  String get chatGoToSettings => 'Settings';

  @override
  String get chatWelcomeTitle => 'Tessera AI';

  @override
  String get chatWelcomeSubtitle =>
      'Start a new conversation by sending a message';

  @override
  String get bubbleThinking => 'Thinking...';

  @override
  String get bubbleThought => 'Thought';

  @override
  String get bubbleToolCall => 'Calling tool...';

  @override
  String get bubbleNoArgs => '(no arguments)';

  @override
  String get bubbleCopy => 'Copy';

  @override
  String get bubbleCopyMarkdown => 'Markdown';

  @override
  String get bubbleCopyPlainText => 'Plain Text';

  @override
  String get bubbleModify => 'Modify';

  @override
  String get bubbleRegenerate => 'Regenerate';

  @override
  String get bubbleShare => 'Share';

  @override
  String get sidebarTitle => 'Tessera AI';

  @override
  String get sidebarCollapseTooltip => 'Collapse sidebar';

  @override
  String get sidebarCloseTooltip => 'Close';

  @override
  String get sidebarConversationsLabel => 'Conversations';

  @override
  String get sidebarRename => 'Rename';

  @override
  String get sidebarRenameDialogTitle => 'Rename Conversation';

  @override
  String get sidebarRenameHint => 'Enter a new name';

  @override
  String get sidebarDeleteDialogTitle => 'Delete Conversation';

  @override
  String sidebarDeleteConfirm(Object title) {
    return 'Are you sure you want to delete \"$title\"?';
  }

  @override
  String get sidebarDefaultUserName => 'User';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsSectionUser => 'User';

  @override
  String get settingsUserProfile => 'User Profile';

  @override
  String get settingsUserProfileSubtitle =>
      'Set personal info to help AI understand you better';

  @override
  String get settingsSectionLlmProviders => 'LLM Providers';

  @override
  String get settingsEmptyProviders => 'No LLM providers configured yet';

  @override
  String get settingsEmptyProvidersSub => 'Click the button below to add one';

  @override
  String get settingsAddProvider => 'Add Provider';

  @override
  String get settingsSectionModelSelection => 'Model Selection';

  @override
  String get settingsModelAssignment => 'Model Assignment';

  @override
  String get settingsModelAssignmentSubtitle =>
      'Assign models for each capability (text, vision, speech, embedding, etc.)';

  @override
  String get settingsSectionRequest => 'Request';

  @override
  String get settingsStreamEnabled => 'Enable streaming';

  @override
  String get settingsStreamEnabledSubtitle =>
      'Display AI responses in real-time. Disable to wait for the full response.';

  @override
  String get settingsDeepThinking => 'Enable deep thinking';

  @override
  String get settingsDeepThinkingSubtitle =>
      'Show the model\'s reasoning process (enabled by default on some models)';

  @override
  String get settingsSectionSpeech => 'Speech';

  @override
  String get settingsTtsEnabled => 'Enable Text-to-Speech (TTS)';

  @override
  String get settingsTtsEnabledSubtitle =>
      'Read AI responses aloud automatically';

  @override
  String get settingsSttEnabled => 'Enable Speech-to-Text (STT)';

  @override
  String get settingsSttEnabledSubtitle => 'Input messages via voice';

  @override
  String get settingsSectionPrompt => 'Prompts';

  @override
  String get settingsLightweightMode => 'Lightweight Mode';

  @override
  String get settingsLightweightModeSubtitle =>
      'Greatly reduces system prompts — only keeps core constraints, skips memory loading.';

  @override
  String get settingsCustomPrompt => 'Custom Prompt';

  @override
  String get settingsEdit => 'Edit';

  @override
  String settingsEditProvider(Object name) {
    return 'Edit $name';
  }

  @override
  String settingsModelCount(Object count) {
    return 'Models ($count):';
  }

  @override
  String get settingsEditModel => 'Edit Models';

  @override
  String get settingsAddProviderDialogTitle => 'Add LLM Provider';

  @override
  String get settingsProviderFormat => 'Provider Format';

  @override
  String get settingsProviderNameLabel =>
      'Provider Name (leave empty to use format name)';

  @override
  String get settingsProviderNameHint => 'e.g. DeepSeek, Custom Proxy...';

  @override
  String get settingsBaseUrl => 'Base URL';

  @override
  String get settingsApiKey => 'API Key';

  @override
  String get settingsApiKeyOptional => 'API Key (not needed)';

  @override
  String get settingsApiKeyHint => 'Enter API Key...';

  @override
  String get settingsApiKeyNotNeeded => '(Ollama does not need an API Key)';

  @override
  String get settingsApiKeyEditHint => 'Leave empty to keep current...';

  @override
  String get settingsProviderAdd => 'Add';

  @override
  String get settingsDeleteConfirmTitle => 'Confirm Deletion';

  @override
  String settingsDeleteConfirm(Object name) {
    return 'Are you sure you want to delete \"$name\"? This action cannot be undone.';
  }

  @override
  String get messageInputImage => 'Image';

  @override
  String get messageInputImageSubtitle => 'Pick from gallery';

  @override
  String get messageInputCamera => 'Camera';

  @override
  String get messageInputCameraSubtitle => 'Take a photo';

  @override
  String get messageInputFile => 'File';

  @override
  String get messageInputFileSubtitle => 'Select any file';

  @override
  String get memoryAppBarTitle => 'Memory';

  @override
  String get memoryEmpty => 'No memories yet';

  @override
  String get memoryEmptySubtitle =>
      'Memories extracted from conversations will appear here';

  @override
  String get memoryTypeUser => 'User';

  @override
  String get memoryTypeKnowledge => 'Knowledge';

  @override
  String get memoryTypeEvent => 'Event';

  @override
  String get memoryTypeConversational => 'Conversational';

  @override
  String get memoryTypeLongTerm => 'Long-term';

  @override
  String get libraryAppBarTitle => 'Library';

  @override
  String get libraryClearTooltip => 'Clear library';

  @override
  String get libraryEmpty => 'Library is empty';

  @override
  String get libraryEmptySubtitle =>
      'Images, files, etc. uploaded in conversations are saved here automatically';

  @override
  String get libraryDeleteDialogTitle => 'Delete File';

  @override
  String libraryDeleteConfirm(Object name) {
    return 'Are you sure you want to delete \"$name\"?';
  }

  @override
  String get libraryClearDialogTitle => 'Clear Library';

  @override
  String get libraryClearConfirm =>
      'Are you sure you want to delete all files in the library? This action cannot be undone.';

  @override
  String get profileAppBarTitle => 'User Profile';

  @override
  String get profileSaving => 'Saving…';

  @override
  String get profileSave => 'Save';

  @override
  String get profileInfoCard =>
      'The information you provide will be injected into the system prompt to help AI understand your preferences and background, delivering more personalized responses. Empty fields will be ignored.';

  @override
  String get profileSectionBasic => 'Basic Info';

  @override
  String get profileDisplayName => 'Display Name';

  @override
  String get profileDisplayNameHint => 'e.g. John Doe';

  @override
  String get profileAlias => 'Preferred Name / Alias';

  @override
  String get profileAliasHint => 'e.g. John, JD';

  @override
  String get profileRole => 'Role / Relationship with AI';

  @override
  String get profileRoleHint => 'e.g. Software Engineer, Student';

  @override
  String get profileSectionPersonalization => 'Personalization';

  @override
  String get profilePreferences => 'Preferences & Style';

  @override
  String get profilePreferencesHint =>
      'e.g. prefers concise answers, enjoys technical depth';

  @override
  String get profileFacts => 'Relevant Facts';

  @override
  String get profileFactsHint =>
      'e.g. lives in New York, uses Flutter, learning Rust';

  @override
  String get profileSaveButton => 'Save Profile';

  @override
  String get profileClearButton => 'Clear All Profile Info';

  @override
  String get profileUnsavedDialogTitle => 'Unsaved Changes';

  @override
  String get profileUnsavedDialogContent =>
      'You have unsaved changes. Are you sure you want to leave?';

  @override
  String get profileLeave => 'Leave';

  @override
  String get profileSavedSnackbar => 'Profile saved';

  @override
  String get profileClearDialogTitle => 'Clear Profile';

  @override
  String get profileClearDialogContent =>
      'Are you sure you want to clear all profile info? This action cannot be undone.';

  @override
  String get errorTitle => 'Oops! An unexpected error occurred.';

  @override
  String get errorSubtitle =>
      'An unhandled exception occurred. Please report the following information to the developer.';

  @override
  String get errorType => 'Error Type';

  @override
  String get errorMessage => 'Error Message';

  @override
  String get errorStackTrace => 'Stack Trace';

  @override
  String get errorCopyInfo => 'Copy Info';

  @override
  String get errorRestart => 'Restart App';

  @override
  String get errorCopied => 'Error info copied to clipboard';

  @override
  String errorRestartFailed(Object error) {
    return 'Restart failed: $error';
  }

  @override
  String get shortcutLibrary => 'Library';

  @override
  String get shortcutMemory => 'Memory';

  @override
  String modelEditAppBarTitle(Object name) {
    return 'Edit Models - $name';
  }

  @override
  String modelEditAddModelDialogTitle(Object modelId) {
    return 'Add Model: $modelId';
  }

  @override
  String get modelEditModelIdLabel => 'Model ID';

  @override
  String get modelEditModelTypeLabel => 'Model Type';

  @override
  String get modelEditModalTagsLabel => 'Modality Tags';

  @override
  String modelEditSelectedTags(Object tags) {
    return 'Selected Tags: $tags';
  }

  @override
  String get modelEditApiInfoFetched =>
      'Model info fetched from API, please confirm';

  @override
  String get modelEditTitle => 'Edit Models';

  @override
  String get modelEditDeleteTitle => 'Delete Model';

  @override
  String modelEditDeleteConfirm(Object model) {
    return 'Are you sure you want to delete model \"$model\"?';
  }

  @override
  String get modelEditAddModel => 'Add Model';

  @override
  String modelEditAddedModels(Object count) {
    return 'Added Models ($count)';
  }

  @override
  String get modelEditFetching => 'Fetching model list…';

  @override
  String get modelEditSearchHint => 'Search or enter model ID…';

  @override
  String get modelEditAddTooltip => 'Add model';

  @override
  String get modelEditNoModels => 'No models added yet';

  @override
  String get modelEditAddPrompt => 'Search or enter a model ID above to add it';

  @override
  String get modelEditDeleteTooltip => 'Delete model';

  @override
  String get modelSelectionAppBarTitle => 'Model Selection';

  @override
  String get modelSelectionSectionMain => 'Main Model (Text LLM)';

  @override
  String get modelSelectionMainSubtitle =>
      'Which model handles basic text chat tasks';

  @override
  String get modelSelectionSectionInput => 'Multimodal Input';

  @override
  String get modelSelectionInputSubtitle =>
      'Which model processes user images, audio, and video.';

  @override
  String get modelSelectionInputHint =>
      'If the main model supports this modality, you can select \"Use Main Model\".';

  @override
  String get modelSelectionSectionOutput => 'Multimodal Output';

  @override
  String get modelSelectionSectionOther => 'Other Models';

  @override
  String get modelSelectionSectionEmbedding => 'Embedding Model';

  @override
  String get modelSelectionMainLabel => 'Main Model';

  @override
  String get modelSelectionUseMainModel => 'Use Main Model';

  @override
  String get modelSelectionNotConfigured => 'Not configured';

  @override
  String get modelSelectionClearSelection => 'Clear selection';

  @override
  String get modelSelectionSectionLlm => 'LLM Assist Features';

  @override
  String get modelSelectionOutputSubtitle =>
      'Which model generates non-text outputs (images, video, speech, etc.)';

  @override
  String get modelSelectionLlmSubtitle =>
      'Auxiliary tasks like topic detection, memory organization, and content summarization. Leave empty to use the main model by default.';

  @override
  String get modelSelectionOtherSubtitle =>
      'Specialized models for Embedding, Ranking, etc. Select LLM assist features (topic detection / memory / summarization) above.';

  @override
  String get modelSelectionTopicDetection => 'Topic Detection';

  @override
  String get modelSelectionTopicDetectionHint =>
      'Detect conversation topics and intent classification';

  @override
  String get modelSelectionMemoryOrganization => 'Memory Organization';

  @override
  String get modelSelectionMemoryOrganizationHint =>
      'Organize long-term memory and extract knowledge';

  @override
  String get modelSelectionContentSummarization => 'Content Summarization';

  @override
  String get modelSelectionContentSummarizationHint =>
      'Generate conversation/document summaries';

  @override
  String get modelSelectionEmbeddingHint => 'Generate text embedding vectors';

  @override
  String get modelSelectionRankingModel => 'Ranking Model';

  @override
  String get modelSelectionRankingHint => 'Re-rank search results';

  @override
  String get modelSelectionNoModelsFound =>
      'No available models found. Please add the corresponding model in Settings first.';

  @override
  String get modelSelectionPickTitle => 'Select Model';

  @override
  String get systemPrompt => 'System Prompt';

  @override
  String get customPromptEditTitle => 'Edit Custom Prompt';

  @override
  String customPromptLength(Object length) {
    return '$length chars';
  }

  @override
  String get notSetting => 'not set';

  @override
  String get customPromptHint =>
      'Content entered here will be injected into the \"User Custom Instruction\" block of the system prompt. Leave empty to skip.';

  @override
  String get customPromptHintTemplate =>
      'For example: prefer concise answers, favor English, emphasize code quality, etc.';

  @override
  String get memoryFormatJustNow => 'Just now';

  @override
  String memoryFormatMinutesAgo(Object minutes) {
    return '$minutes min ago';
  }

  @override
  String memoryFormatHoursAgo(Object hours) {
    return '${hours}h ago';
  }

  @override
  String memoryFormatDaysAgo(Object days) {
    return '${days}d ago';
  }

  @override
  String get mediaTypeImage => 'Image';

  @override
  String get mediaTypeVideo => 'Video';

  @override
  String get mediaTypeAudio => 'Audio';

  @override
  String get mediaTypeFile => 'File';

  @override
  String get settingsSectionAbout => 'About';

  @override
  String get settingsSectionLanguage => 'Language';

  @override
  String get settingsLanguageSystem => 'Follow System';

  @override
  String get settingsLanguageZh => '简体中文';

  @override
  String get settingsLanguageEn => 'English';

  @override
  String get modelTypeText => 'Text Generation';

  @override
  String get modelTypeImage => 'Text-to-Image';

  @override
  String get modelTypeVideo => 'Text-to-Video';

  @override
  String get modelTypeSpeech => 'Text-to-Speech';

  @override
  String get modelTypeEmbedding => 'Embedding';

  @override
  String get modelTypeRanking => 'Ranking';

  @override
  String get modelTagText => 'Text';

  @override
  String get modelTagVision => 'Vision';

  @override
  String get modelTagAudible => 'Audio';

  @override
  String get modelTagVideo => 'Video';

  @override
  String get modelTagsOmni => 'Omni-modal';

  @override
  String get modelTagsTextOnly => 'Text-only';

  @override
  String get toolboxLabel => 'Library';

  @override
  String get pluginAppBarTitle => 'Plugins';

  @override
  String get pluginEmpty => 'No plugins found';

  @override
  String get pluginLoadError => 'Failed to load plugins';

  @override
  String get pluginRetry => 'Retry';

  @override
  String get pluginInstall => 'Install';

  @override
  String get pluginUninstall => 'Uninstall';

  @override
  String get pluginInstalled => 'Installed';

  @override
  String get pluginBundled => 'Bundled';

  @override
  String pluginInstallSuccess(String name) =>
      'Plugin "$name" installed successfully';

  @override
  String pluginInstallFailed(String error) => 'Install failed: $error';

  @override
  String pluginUninstallSuccess(String name) =>
      'Plugin "$name" uninstalled';

  @override
  String pluginUninstallFailed(String error) => 'Uninstall failed: $error';

  @override
  String pluginUninstallConfirm(String name) =>
      'Are you sure you want to uninstall "$name"?\nThis will delete the plugin files.';

  @override
  String get pluginUninstallDialogTitle => 'Uninstall Plugin';

  @override
  String pluginEnableFailed(String name) =>
      'Failed to enable plugin "$name"';

  @override
  String pluginByAuthor(String author) => 'by $author';

  @override
  String get pluginShortcut => 'Plugins';

  @override
  String get pluginSectionInstalled => 'Installed';

  @override
  String get pluginSectionBundled => 'Bundled Sources';

  @override
  String get pluginSectionInstallFromFile => 'Install from File';

  @override
  String get pluginInstallFromFileAction => 'Select .plugin File';

  @override
  String get pluginInstallFromZip => 'Install from ZIP';

  @override
  String get pluginInstallConfirmTitle => 'Install Plugin';

  @override
  String pluginInvalidZip(String error) => 'Invalid plugin package: $error';

  @override
  String get statsAppBarTitle => 'Usage Statistics';

  @override
  String get statsOverall => 'Overall';

  @override
  String get statsTotalTokens => 'Total Tokens';

  @override
  String get statsPromptTokens => 'Prompt';

  @override
  String get statsCompletionTokens => 'Completion';

  @override
  String get statsCacheHitRate => 'Cache Hit Rate';

  @override
  String get statsRequests => 'Requests';

  @override
  String get statsReset => 'Reset';

  @override
  String get statsResetConfirmTitle => 'Confirm Reset';

  @override
  String get statsResetConfirm =>
      'Are you sure you want to reset all usage statistics? This action cannot be undone.';

  @override
  String get statsEmpty => 'No usage data yet';

  @override
  String get statsEmptySubtitle =>
      'Usage data will appear here after you start chatting with AI models';

  @override
  String get statsShortcut => 'Stats';
}
