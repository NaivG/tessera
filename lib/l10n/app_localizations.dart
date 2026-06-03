import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// No description provided for @localeDescription.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get localeDescription;

  /// No description provided for @createdBy.
  ///
  /// In en, this message translates to:
  /// **'Localized by NaivG'**
  String get createdBy;

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Tessera'**
  String get appTitle;

  /// No description provided for @commonCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get commonCancel;

  /// No description provided for @commonDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get commonDelete;

  /// No description provided for @commonSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get commonSave;

  /// No description provided for @commonConfirm.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get commonConfirm;

  /// No description provided for @commonClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get commonClear;

  /// No description provided for @chatNewConversation.
  ///
  /// In en, this message translates to:
  /// **'New Chat'**
  String get chatNewConversation;

  /// No description provided for @chatNewLabel.
  ///
  /// In en, this message translates to:
  /// **'New Conversation'**
  String get chatNewLabel;

  /// No description provided for @chatNoConversations.
  ///
  /// In en, this message translates to:
  /// **'No conversations'**
  String get chatNoConversations;

  /// No description provided for @chatSend.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get chatSend;

  /// No description provided for @chatModifyMessage.
  ///
  /// In en, this message translates to:
  /// **'Modify Message'**
  String get chatModifyMessage;

  /// No description provided for @chatNewContentHint.
  ///
  /// In en, this message translates to:
  /// **'Enter new content'**
  String get chatNewContentHint;

  /// No description provided for @chatConfigureProviderFirst.
  ///
  /// In en, this message translates to:
  /// **'Please configure an LLM provider and select a model in Settings first'**
  String get chatConfigureProviderFirst;

  /// No description provided for @chatGoToSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get chatGoToSettings;

  /// No description provided for @chatWelcomeTitle.
  ///
  /// In en, this message translates to:
  /// **'Tessera AI'**
  String get chatWelcomeTitle;

  /// No description provided for @chatWelcomeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Start a new conversation by sending a message'**
  String get chatWelcomeSubtitle;

  /// No description provided for @bubbleThinking.
  ///
  /// In en, this message translates to:
  /// **'Thinking...'**
  String get bubbleThinking;

  /// No description provided for @bubbleThought.
  ///
  /// In en, this message translates to:
  /// **'Thought'**
  String get bubbleThought;

  /// No description provided for @bubbleToolCall.
  ///
  /// In en, this message translates to:
  /// **'Calling tool...'**
  String get bubbleToolCall;

  /// No description provided for @bubbleNoArgs.
  ///
  /// In en, this message translates to:
  /// **'(no arguments)'**
  String get bubbleNoArgs;

  /// No description provided for @bubbleCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get bubbleCopy;

  /// No description provided for @bubbleCopyMarkdown.
  ///
  /// In en, this message translates to:
  /// **'Markdown'**
  String get bubbleCopyMarkdown;

  /// No description provided for @bubbleCopyPlainText.
  ///
  /// In en, this message translates to:
  /// **'Plain Text'**
  String get bubbleCopyPlainText;

  /// No description provided for @bubbleModify.
  ///
  /// In en, this message translates to:
  /// **'Modify'**
  String get bubbleModify;

  /// No description provided for @bubbleRegenerate.
  ///
  /// In en, this message translates to:
  /// **'Regenerate'**
  String get bubbleRegenerate;

  /// No description provided for @bubbleShare.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get bubbleShare;

  /// No description provided for @sidebarTitle.
  ///
  /// In en, this message translates to:
  /// **'Tessera AI'**
  String get sidebarTitle;

  /// No description provided for @sidebarCollapseTooltip.
  ///
  /// In en, this message translates to:
  /// **'Collapse sidebar'**
  String get sidebarCollapseTooltip;

  /// No description provided for @sidebarCloseTooltip.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get sidebarCloseTooltip;

  /// No description provided for @sidebarConversationsLabel.
  ///
  /// In en, this message translates to:
  /// **'Conversations'**
  String get sidebarConversationsLabel;

  /// No description provided for @sidebarRename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get sidebarRename;

  /// No description provided for @sidebarRenameDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Rename Conversation'**
  String get sidebarRenameDialogTitle;

  /// No description provided for @sidebarRenameHint.
  ///
  /// In en, this message translates to:
  /// **'Enter a new name'**
  String get sidebarRenameHint;

  /// No description provided for @sidebarDeleteDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete Conversation'**
  String get sidebarDeleteDialogTitle;

  /// No description provided for @sidebarDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete \"{title}\"?'**
  String sidebarDeleteConfirm(Object title);

  /// No description provided for @sidebarDefaultUserName.
  ///
  /// In en, this message translates to:
  /// **'User'**
  String get sidebarDefaultUserName;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @settingsSectionUser.
  ///
  /// In en, this message translates to:
  /// **'User'**
  String get settingsSectionUser;

  /// No description provided for @settingsUserProfile.
  ///
  /// In en, this message translates to:
  /// **'User Profile'**
  String get settingsUserProfile;

  /// No description provided for @settingsUserProfileSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Set personal info to help AI understand you better'**
  String get settingsUserProfileSubtitle;

  /// No description provided for @settingsSectionLlmProviders.
  ///
  /// In en, this message translates to:
  /// **'LLM Providers'**
  String get settingsSectionLlmProviders;

  /// No description provided for @settingsEmptyProviders.
  ///
  /// In en, this message translates to:
  /// **'No LLM providers configured yet'**
  String get settingsEmptyProviders;

  /// No description provided for @settingsEmptyProvidersSub.
  ///
  /// In en, this message translates to:
  /// **'Click the button below to add one'**
  String get settingsEmptyProvidersSub;

  /// No description provided for @settingsAddProvider.
  ///
  /// In en, this message translates to:
  /// **'Add Provider'**
  String get settingsAddProvider;

  /// No description provided for @settingsSectionModelSelection.
  ///
  /// In en, this message translates to:
  /// **'Model Selection'**
  String get settingsSectionModelSelection;

  /// No description provided for @settingsModelAssignment.
  ///
  /// In en, this message translates to:
  /// **'Model Assignment'**
  String get settingsModelAssignment;

  /// No description provided for @settingsModelAssignmentSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Assign models for each capability (text, vision, speech, embedding, etc.)'**
  String get settingsModelAssignmentSubtitle;

  /// No description provided for @settingsSectionRequest.
  ///
  /// In en, this message translates to:
  /// **'Request'**
  String get settingsSectionRequest;

  /// No description provided for @settingsStreamEnabled.
  ///
  /// In en, this message translates to:
  /// **'Enable streaming'**
  String get settingsStreamEnabled;

  /// No description provided for @settingsStreamEnabledSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Display AI responses in real-time. Disable to wait for the full response.'**
  String get settingsStreamEnabledSubtitle;

  /// No description provided for @settingsDeepThinking.
  ///
  /// In en, this message translates to:
  /// **'Enable deep thinking'**
  String get settingsDeepThinking;

  /// No description provided for @settingsDeepThinkingSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Show the model\'s reasoning process (enabled by default on some models)'**
  String get settingsDeepThinkingSubtitle;

  /// No description provided for @settingsSectionSpeech.
  ///
  /// In en, this message translates to:
  /// **'Speech'**
  String get settingsSectionSpeech;

  /// No description provided for @settingsTtsEnabled.
  ///
  /// In en, this message translates to:
  /// **'Enable Text-to-Speech (TTS)'**
  String get settingsTtsEnabled;

  /// No description provided for @settingsTtsEnabledSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Read AI responses aloud automatically'**
  String get settingsTtsEnabledSubtitle;

  /// No description provided for @settingsSttEnabled.
  ///
  /// In en, this message translates to:
  /// **'Enable Speech-to-Text (STT)'**
  String get settingsSttEnabled;

  /// No description provided for @settingsSttEnabledSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Input messages via voice'**
  String get settingsSttEnabledSubtitle;

  /// No description provided for @settingsSectionPrompt.
  ///
  /// In en, this message translates to:
  /// **'Prompts'**
  String get settingsSectionPrompt;

  /// No description provided for @settingsLightweightMode.
  ///
  /// In en, this message translates to:
  /// **'Lightweight Mode'**
  String get settingsLightweightMode;

  /// No description provided for @settingsLightweightModeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Greatly reduces system prompts — only keeps core constraints, skips memory loading.'**
  String get settingsLightweightModeSubtitle;

  /// No description provided for @settingsCustomPrompt.
  ///
  /// In en, this message translates to:
  /// **'Custom Prompt'**
  String get settingsCustomPrompt;

  /// No description provided for @settingsEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get settingsEdit;

  /// No description provided for @settingsEditProvider.
  ///
  /// In en, this message translates to:
  /// **'Edit {name}'**
  String settingsEditProvider(Object name);

  /// No description provided for @settingsModelCount.
  ///
  /// In en, this message translates to:
  /// **'Models ({count}):'**
  String settingsModelCount(Object count);

  /// No description provided for @settingsEditModel.
  ///
  /// In en, this message translates to:
  /// **'Edit Models'**
  String get settingsEditModel;

  /// No description provided for @settingsAddProviderDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Add LLM Provider'**
  String get settingsAddProviderDialogTitle;

  /// No description provided for @settingsProviderFormat.
  ///
  /// In en, this message translates to:
  /// **'Provider Format'**
  String get settingsProviderFormat;

  /// No description provided for @settingsProviderNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Provider Name (leave empty to use format name)'**
  String get settingsProviderNameLabel;

  /// No description provided for @settingsProviderNameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. DeepSeek, Custom Proxy...'**
  String get settingsProviderNameHint;

  /// No description provided for @settingsBaseUrl.
  ///
  /// In en, this message translates to:
  /// **'Base URL'**
  String get settingsBaseUrl;

  /// No description provided for @settingsApiKey.
  ///
  /// In en, this message translates to:
  /// **'API Key'**
  String get settingsApiKey;

  /// No description provided for @settingsApiKeyOptional.
  ///
  /// In en, this message translates to:
  /// **'API Key (not needed)'**
  String get settingsApiKeyOptional;

  /// No description provided for @settingsApiKeyHint.
  ///
  /// In en, this message translates to:
  /// **'Enter API Key...'**
  String get settingsApiKeyHint;

  /// No description provided for @settingsApiKeyNotNeeded.
  ///
  /// In en, this message translates to:
  /// **'(Ollama does not need an API Key)'**
  String get settingsApiKeyNotNeeded;

  /// No description provided for @settingsApiKeyEditHint.
  ///
  /// In en, this message translates to:
  /// **'Leave empty to keep current...'**
  String get settingsApiKeyEditHint;

  /// No description provided for @settingsProviderAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get settingsProviderAdd;

  /// No description provided for @settingsDeleteConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Confirm Deletion'**
  String get settingsDeleteConfirmTitle;

  /// No description provided for @settingsDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete \"{name}\"? This action cannot be undone.'**
  String settingsDeleteConfirm(Object name);

  /// No description provided for @messageInputImage.
  ///
  /// In en, this message translates to:
  /// **'Image'**
  String get messageInputImage;

  /// No description provided for @messageInputImageSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Pick from gallery'**
  String get messageInputImageSubtitle;

  /// No description provided for @messageInputCamera.
  ///
  /// In en, this message translates to:
  /// **'Camera'**
  String get messageInputCamera;

  /// No description provided for @messageInputCameraSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Take a photo'**
  String get messageInputCameraSubtitle;

  /// No description provided for @messageInputFile.
  ///
  /// In en, this message translates to:
  /// **'File'**
  String get messageInputFile;

  /// No description provided for @messageInputFileSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Select any file'**
  String get messageInputFileSubtitle;

  /// No description provided for @memoryAppBarTitle.
  ///
  /// In en, this message translates to:
  /// **'Memory'**
  String get memoryAppBarTitle;

  /// No description provided for @memoryEmpty.
  ///
  /// In en, this message translates to:
  /// **'No memories yet'**
  String get memoryEmpty;

  /// No description provided for @memoryEmptySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Memories extracted from conversations will appear here'**
  String get memoryEmptySubtitle;

  /// No description provided for @memoryTypeUser.
  ///
  /// In en, this message translates to:
  /// **'User'**
  String get memoryTypeUser;

  /// No description provided for @memoryTypeKnowledge.
  ///
  /// In en, this message translates to:
  /// **'Knowledge'**
  String get memoryTypeKnowledge;

  /// No description provided for @memoryTypeEvent.
  ///
  /// In en, this message translates to:
  /// **'Event'**
  String get memoryTypeEvent;

  /// No description provided for @memoryTypeConversational.
  ///
  /// In en, this message translates to:
  /// **'Conversational'**
  String get memoryTypeConversational;

  /// No description provided for @memoryTypeLongTerm.
  ///
  /// In en, this message translates to:
  /// **'Long-term'**
  String get memoryTypeLongTerm;

  /// No description provided for @libraryAppBarTitle.
  ///
  /// In en, this message translates to:
  /// **'Library'**
  String get libraryAppBarTitle;

  /// No description provided for @libraryClearTooltip.
  ///
  /// In en, this message translates to:
  /// **'Clear library'**
  String get libraryClearTooltip;

  /// No description provided for @libraryEmpty.
  ///
  /// In en, this message translates to:
  /// **'Library is empty'**
  String get libraryEmpty;

  /// No description provided for @libraryEmptySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Images, files, etc. uploaded in conversations are saved here automatically'**
  String get libraryEmptySubtitle;

  /// No description provided for @libraryDeleteDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete File'**
  String get libraryDeleteDialogTitle;

  /// No description provided for @libraryDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete \"{name}\"?'**
  String libraryDeleteConfirm(Object name);

  /// No description provided for @libraryClearDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Clear Library'**
  String get libraryClearDialogTitle;

  /// No description provided for @libraryClearConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete all files in the library? This action cannot be undone.'**
  String get libraryClearConfirm;

  /// No description provided for @profileAppBarTitle.
  ///
  /// In en, this message translates to:
  /// **'User Profile'**
  String get profileAppBarTitle;

  /// No description provided for @profileSaving.
  ///
  /// In en, this message translates to:
  /// **'Saving…'**
  String get profileSaving;

  /// No description provided for @profileSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get profileSave;

  /// No description provided for @profileInfoCard.
  ///
  /// In en, this message translates to:
  /// **'The information you provide will be injected into the system prompt to help AI understand your preferences and background, delivering more personalized responses. Empty fields will be ignored.'**
  String get profileInfoCard;

  /// No description provided for @profileSectionBasic.
  ///
  /// In en, this message translates to:
  /// **'Basic Info'**
  String get profileSectionBasic;

  /// No description provided for @profileDisplayName.
  ///
  /// In en, this message translates to:
  /// **'Display Name'**
  String get profileDisplayName;

  /// No description provided for @profileDisplayNameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. John Doe'**
  String get profileDisplayNameHint;

  /// No description provided for @profileAlias.
  ///
  /// In en, this message translates to:
  /// **'Preferred Name / Alias'**
  String get profileAlias;

  /// No description provided for @profileAliasHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. John, JD'**
  String get profileAliasHint;

  /// No description provided for @profileRole.
  ///
  /// In en, this message translates to:
  /// **'Role / Relationship with AI'**
  String get profileRole;

  /// No description provided for @profileRoleHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Software Engineer, Student'**
  String get profileRoleHint;

  /// No description provided for @profileSectionPersonalization.
  ///
  /// In en, this message translates to:
  /// **'Personalization'**
  String get profileSectionPersonalization;

  /// No description provided for @profilePreferences.
  ///
  /// In en, this message translates to:
  /// **'Preferences & Style'**
  String get profilePreferences;

  /// No description provided for @profilePreferencesHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. prefers concise answers, enjoys technical depth'**
  String get profilePreferencesHint;

  /// No description provided for @profileFacts.
  ///
  /// In en, this message translates to:
  /// **'Relevant Facts'**
  String get profileFacts;

  /// No description provided for @profileFactsHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. lives in New York, uses Flutter, learning Rust'**
  String get profileFactsHint;

  /// No description provided for @profileSaveButton.
  ///
  /// In en, this message translates to:
  /// **'Save Profile'**
  String get profileSaveButton;

  /// No description provided for @profileClearButton.
  ///
  /// In en, this message translates to:
  /// **'Clear All Profile Info'**
  String get profileClearButton;

  /// No description provided for @profileUnsavedDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Unsaved Changes'**
  String get profileUnsavedDialogTitle;

  /// No description provided for @profileUnsavedDialogContent.
  ///
  /// In en, this message translates to:
  /// **'You have unsaved changes. Are you sure you want to leave?'**
  String get profileUnsavedDialogContent;

  /// No description provided for @profileLeave.
  ///
  /// In en, this message translates to:
  /// **'Leave'**
  String get profileLeave;

  /// No description provided for @profileSavedSnackbar.
  ///
  /// In en, this message translates to:
  /// **'Profile saved'**
  String get profileSavedSnackbar;

  /// No description provided for @profileClearDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Clear Profile'**
  String get profileClearDialogTitle;

  /// No description provided for @profileClearDialogContent.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to clear all profile info? This action cannot be undone.'**
  String get profileClearDialogContent;

  /// No description provided for @errorTitle.
  ///
  /// In en, this message translates to:
  /// **'Oops! An unexpected error occurred.'**
  String get errorTitle;

  /// No description provided for @errorSubtitle.
  ///
  /// In en, this message translates to:
  /// **'An unhandled exception occurred. Please report the following information to the developer.'**
  String get errorSubtitle;

  /// No description provided for @errorType.
  ///
  /// In en, this message translates to:
  /// **'Error Type'**
  String get errorType;

  /// No description provided for @errorMessage.
  ///
  /// In en, this message translates to:
  /// **'Error Message'**
  String get errorMessage;

  /// No description provided for @errorStackTrace.
  ///
  /// In en, this message translates to:
  /// **'Stack Trace'**
  String get errorStackTrace;

  /// No description provided for @errorCopyInfo.
  ///
  /// In en, this message translates to:
  /// **'Copy Info'**
  String get errorCopyInfo;

  /// No description provided for @errorRestart.
  ///
  /// In en, this message translates to:
  /// **'Restart App'**
  String get errorRestart;

  /// No description provided for @errorCopied.
  ///
  /// In en, this message translates to:
  /// **'Error info copied to clipboard'**
  String get errorCopied;

  /// No description provided for @errorRestartFailed.
  ///
  /// In en, this message translates to:
  /// **'Restart failed: {error}'**
  String errorRestartFailed(Object error);

  /// No description provided for @shortcutLibrary.
  ///
  /// In en, this message translates to:
  /// **'Library'**
  String get shortcutLibrary;

  /// No description provided for @shortcutMemory.
  ///
  /// In en, this message translates to:
  /// **'Memory'**
  String get shortcutMemory;

  /// No description provided for @modelEditAppBarTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit Models - {name}'**
  String modelEditAppBarTitle(Object name);

  /// No description provided for @modelEditAddModelDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Add Model: {modelId}'**
  String modelEditAddModelDialogTitle(Object modelId);

  /// No description provided for @modelEditModelIdLabel.
  ///
  /// In en, this message translates to:
  /// **'Model ID'**
  String get modelEditModelIdLabel;

  /// No description provided for @modelEditModelTypeLabel.
  ///
  /// In en, this message translates to:
  /// **'Model Type'**
  String get modelEditModelTypeLabel;

  /// No description provided for @modelEditModalTagsLabel.
  ///
  /// In en, this message translates to:
  /// **'Modality Tags'**
  String get modelEditModalTagsLabel;

  /// No description provided for @modelEditSelectedTags.
  ///
  /// In en, this message translates to:
  /// **'Selected Tags: {tags}'**
  String modelEditSelectedTags(Object tags);

  /// No description provided for @modelEditApiInfoFetched.
  ///
  /// In en, this message translates to:
  /// **'Model info fetched from API, please confirm'**
  String get modelEditApiInfoFetched;

  /// No description provided for @modelEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit Models'**
  String get modelEditTitle;

  /// No description provided for @modelEditDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete Model'**
  String get modelEditDeleteTitle;

  /// No description provided for @modelEditDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete model \"{model}\"?'**
  String modelEditDeleteConfirm(Object model);

  /// No description provided for @modelEditAddModel.
  ///
  /// In en, this message translates to:
  /// **'Add Model'**
  String get modelEditAddModel;

  /// No description provided for @modelEditAddedModels.
  ///
  /// In en, this message translates to:
  /// **'Added Models ({count})'**
  String modelEditAddedModels(Object count);

  /// No description provided for @modelEditFetching.
  ///
  /// In en, this message translates to:
  /// **'Fetching model list…'**
  String get modelEditFetching;

  /// No description provided for @modelEditSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search or enter model ID…'**
  String get modelEditSearchHint;

  /// No description provided for @modelEditAddTooltip.
  ///
  /// In en, this message translates to:
  /// **'Add model'**
  String get modelEditAddTooltip;

  /// No description provided for @modelEditNoModels.
  ///
  /// In en, this message translates to:
  /// **'No models added yet'**
  String get modelEditNoModels;

  /// No description provided for @modelEditAddPrompt.
  ///
  /// In en, this message translates to:
  /// **'Search or enter a model ID above to add it'**
  String get modelEditAddPrompt;

  /// No description provided for @modelEditDeleteTooltip.
  ///
  /// In en, this message translates to:
  /// **'Delete model'**
  String get modelEditDeleteTooltip;

  /// No description provided for @modelSelectionAppBarTitle.
  ///
  /// In en, this message translates to:
  /// **'Model Selection'**
  String get modelSelectionAppBarTitle;

  /// No description provided for @modelSelectionSectionMain.
  ///
  /// In en, this message translates to:
  /// **'Main Model (Text LLM)'**
  String get modelSelectionSectionMain;

  /// No description provided for @modelSelectionMainSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Which model handles basic text chat tasks'**
  String get modelSelectionMainSubtitle;

  /// No description provided for @modelSelectionSectionInput.
  ///
  /// In en, this message translates to:
  /// **'Multimodal Input'**
  String get modelSelectionSectionInput;

  /// No description provided for @modelSelectionInputSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Which model processes user images, audio, and video.'**
  String get modelSelectionInputSubtitle;

  /// No description provided for @modelSelectionInputHint.
  ///
  /// In en, this message translates to:
  /// **'If the main model supports this modality, you can select \"Use Main Model\".'**
  String get modelSelectionInputHint;

  /// No description provided for @modelSelectionSectionOutput.
  ///
  /// In en, this message translates to:
  /// **'Multimodal Output'**
  String get modelSelectionSectionOutput;

  /// No description provided for @modelSelectionSectionOther.
  ///
  /// In en, this message translates to:
  /// **'Other Models'**
  String get modelSelectionSectionOther;

  /// No description provided for @modelSelectionSectionEmbedding.
  ///
  /// In en, this message translates to:
  /// **'Embedding Model'**
  String get modelSelectionSectionEmbedding;

  /// No description provided for @modelSelectionMainLabel.
  ///
  /// In en, this message translates to:
  /// **'Main Model'**
  String get modelSelectionMainLabel;

  /// No description provided for @modelSelectionUseMainModel.
  ///
  /// In en, this message translates to:
  /// **'Use Main Model'**
  String get modelSelectionUseMainModel;

  /// No description provided for @modelSelectionNotConfigured.
  ///
  /// In en, this message translates to:
  /// **'Not configured'**
  String get modelSelectionNotConfigured;

  /// No description provided for @modelSelectionClearSelection.
  ///
  /// In en, this message translates to:
  /// **'Clear selection'**
  String get modelSelectionClearSelection;

  /// No description provided for @modelSelectionSectionLlm.
  ///
  /// In en, this message translates to:
  /// **'LLM Assist Features'**
  String get modelSelectionSectionLlm;

  /// No description provided for @modelSelectionOutputSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Which model generates non-text outputs (images, video, speech, etc.)'**
  String get modelSelectionOutputSubtitle;

  /// No description provided for @modelSelectionLlmSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Auxiliary tasks like topic detection, memory organization, and content summarization. Leave empty to use the main model by default.'**
  String get modelSelectionLlmSubtitle;

  /// No description provided for @modelSelectionOtherSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Specialized models for Embedding, Ranking, etc. Select LLM assist features (topic detection / memory / summarization) above.'**
  String get modelSelectionOtherSubtitle;

  /// No description provided for @modelSelectionTopicDetection.
  ///
  /// In en, this message translates to:
  /// **'Topic Detection'**
  String get modelSelectionTopicDetection;

  /// No description provided for @modelSelectionTopicDetectionHint.
  ///
  /// In en, this message translates to:
  /// **'Detect conversation topics and intent classification'**
  String get modelSelectionTopicDetectionHint;

  /// No description provided for @modelSelectionMemoryOrganization.
  ///
  /// In en, this message translates to:
  /// **'Memory Organization'**
  String get modelSelectionMemoryOrganization;

  /// No description provided for @modelSelectionMemoryOrganizationHint.
  ///
  /// In en, this message translates to:
  /// **'Organize long-term memory and extract knowledge'**
  String get modelSelectionMemoryOrganizationHint;

  /// No description provided for @modelSelectionContentSummarization.
  ///
  /// In en, this message translates to:
  /// **'Content Summarization'**
  String get modelSelectionContentSummarization;

  /// No description provided for @modelSelectionContentSummarizationHint.
  ///
  /// In en, this message translates to:
  /// **'Generate conversation/document summaries'**
  String get modelSelectionContentSummarizationHint;

  /// No description provided for @modelSelectionEmbeddingHint.
  ///
  /// In en, this message translates to:
  /// **'Generate text embedding vectors'**
  String get modelSelectionEmbeddingHint;

  /// No description provided for @modelSelectionRankingModel.
  ///
  /// In en, this message translates to:
  /// **'Ranking Model'**
  String get modelSelectionRankingModel;

  /// No description provided for @modelSelectionRankingHint.
  ///
  /// In en, this message translates to:
  /// **'Re-rank search results'**
  String get modelSelectionRankingHint;

  /// No description provided for @modelSelectionNoModelsFound.
  ///
  /// In en, this message translates to:
  /// **'No available models found. Please add the corresponding model in Settings first.'**
  String get modelSelectionNoModelsFound;

  /// No description provided for @modelSelectionPickTitle.
  ///
  /// In en, this message translates to:
  /// **'Select Model'**
  String get modelSelectionPickTitle;

  /// No description provided for @systemPrompt.
  ///
  /// In en, this message translates to:
  /// **'System Prompt'**
  String get systemPrompt;

  /// No description provided for @customPromptEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit Custom Prompt'**
  String get customPromptEditTitle;

  /// No description provided for @customPromptLength.
  ///
  /// In en, this message translates to:
  /// **'{length} chars'**
  String customPromptLength(Object length);

  /// No description provided for @notSetting.
  ///
  /// In en, this message translates to:
  /// **'not set'**
  String get notSetting;

  /// No description provided for @customPromptHint.
  ///
  /// In en, this message translates to:
  /// **'Content entered here will be injected into the \"User Custom Instruction\" block of the system prompt. Leave empty to skip.'**
  String get customPromptHint;

  /// No description provided for @customPromptHintTemplate.
  ///
  /// In en, this message translates to:
  /// **'For example: prefer concise answers, favor English, emphasize code quality, etc.'**
  String get customPromptHintTemplate;

  /// No description provided for @memoryFormatJustNow.
  ///
  /// In en, this message translates to:
  /// **'Just now'**
  String get memoryFormatJustNow;

  /// No description provided for @memoryFormatMinutesAgo.
  ///
  /// In en, this message translates to:
  /// **'{minutes} min ago'**
  String memoryFormatMinutesAgo(Object minutes);

  /// No description provided for @memoryFormatHoursAgo.
  ///
  /// In en, this message translates to:
  /// **'{hours}h ago'**
  String memoryFormatHoursAgo(Object hours);

  /// No description provided for @memoryFormatDaysAgo.
  ///
  /// In en, this message translates to:
  /// **'{days}d ago'**
  String memoryFormatDaysAgo(Object days);

  /// No description provided for @mediaTypeImage.
  ///
  /// In en, this message translates to:
  /// **'Image'**
  String get mediaTypeImage;

  /// No description provided for @mediaTypeVideo.
  ///
  /// In en, this message translates to:
  /// **'Video'**
  String get mediaTypeVideo;

  /// No description provided for @mediaTypeAudio.
  ///
  /// In en, this message translates to:
  /// **'Audio'**
  String get mediaTypeAudio;

  /// No description provided for @mediaTypeFile.
  ///
  /// In en, this message translates to:
  /// **'File'**
  String get mediaTypeFile;

  /// No description provided for @settingsSectionAbout.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get settingsSectionAbout;

  /// No description provided for @settingsSectionLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsSectionLanguage;

  /// No description provided for @settingsLanguageSystem.
  ///
  /// In en, this message translates to:
  /// **'Follow System'**
  String get settingsLanguageSystem;

  /// No description provided for @settingsLanguageZh.
  ///
  /// In en, this message translates to:
  /// **'简体中文'**
  String get settingsLanguageZh;

  /// No description provided for @settingsLanguageEn.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get settingsLanguageEn;

  /// No description provided for @modelTypeText.
  ///
  /// In en, this message translates to:
  /// **'Text Generation'**
  String get modelTypeText;

  /// No description provided for @modelTypeImage.
  ///
  /// In en, this message translates to:
  /// **'Text-to-Image'**
  String get modelTypeImage;

  /// No description provided for @modelTypeVideo.
  ///
  /// In en, this message translates to:
  /// **'Text-to-Video'**
  String get modelTypeVideo;

  /// No description provided for @modelTypeSpeech.
  ///
  /// In en, this message translates to:
  /// **'Text-to-Speech'**
  String get modelTypeSpeech;

  /// No description provided for @modelTypeEmbedding.
  ///
  /// In en, this message translates to:
  /// **'Embedding'**
  String get modelTypeEmbedding;

  /// No description provided for @modelTypeRanking.
  ///
  /// In en, this message translates to:
  /// **'Ranking'**
  String get modelTypeRanking;

  /// No description provided for @modelTagText.
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get modelTagText;

  /// No description provided for @modelTagVision.
  ///
  /// In en, this message translates to:
  /// **'Vision'**
  String get modelTagVision;

  /// No description provided for @modelTagAudible.
  ///
  /// In en, this message translates to:
  /// **'Audio'**
  String get modelTagAudible;

  /// No description provided for @modelTagVideo.
  ///
  /// In en, this message translates to:
  /// **'Video'**
  String get modelTagVideo;

  /// No description provided for @modelTagsOmni.
  ///
  /// In en, this message translates to:
  /// **'Omni-modal'**
  String get modelTagsOmni;

  /// No description provided for @modelTagsTextOnly.
  ///
  /// In en, this message translates to:
  /// **'Text-only'**
  String get modelTagsTextOnly;

  /// No description provided for @toolboxLabel.
  ///
  /// In en, this message translates to:
  /// **'Library'**
  String get toolboxLabel;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
