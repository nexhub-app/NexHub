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
/// import 'generated/app_localizations.dart';
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

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
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
    Locale('zh')
  ];

  /// Application title
  ///
  /// In en, this message translates to:
  /// **'NexHub'**
  String get appTitle;

  /// No description provided for @navBrowse.
  ///
  /// In en, this message translates to:
  /// **'Browse'**
  String get navBrowse;

  /// No description provided for @navNovel.
  ///
  /// In en, this message translates to:
  /// **'Novel'**
  String get navNovel;

  /// No description provided for @navMedia.
  ///
  /// In en, this message translates to:
  /// **'Media'**
  String get navMedia;

  /// No description provided for @navComic.
  ///
  /// In en, this message translates to:
  /// **'Comic'**
  String get navComic;

  /// No description provided for @navSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

  /// No description provided for @homeTitle.
  ///
  /// In en, this message translates to:
  /// **'Browse'**
  String get homeTitle;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @settingsTagline.
  ///
  /// In en, this message translates to:
  /// **'Craft your personal media space'**
  String get settingsTagline;

  /// No description provided for @sourceManagementTitle.
  ///
  /// In en, this message translates to:
  /// **'Source Management'**
  String get sourceManagementTitle;

  /// No description provided for @sourceManagementDesc.
  ///
  /// In en, this message translates to:
  /// **'Import, enable and reorder content sources'**
  String get sourceManagementDesc;

  /// No description provided for @downloadSettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get downloadSettingsTitle;

  /// No description provided for @downloadManagementTitle.
  ///
  /// In en, this message translates to:
  /// **'Download Management'**
  String get downloadManagementTitle;

  /// No description provided for @aboutTitle.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get aboutTitle;

  /// No description provided for @themeTitle.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get themeTitle;

  /// No description provided for @tabLibrary.
  ///
  /// In en, this message translates to:
  /// **'Library'**
  String get tabLibrary;

  /// No description provided for @tabMediaLibrary.
  ///
  /// In en, this message translates to:
  /// **'Media Library'**
  String get tabMediaLibrary;

  /// No description provided for @tabOnline.
  ///
  /// In en, this message translates to:
  /// **'Online'**
  String get tabOnline;

  /// No description provided for @tabSubscribe.
  ///
  /// In en, this message translates to:
  /// **'Subscribe'**
  String get tabSubscribe;

  /// No description provided for @tabSources.
  ///
  /// In en, this message translates to:
  /// **'Sources'**
  String get tabSources;

  /// No description provided for @browseLocalFiles.
  ///
  /// In en, this message translates to:
  /// **'Local Files'**
  String get browseLocalFiles;

  /// No description provided for @browseLocalFilesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Browse local novels, videos and comics'**
  String get browseLocalFilesSubtitle;

  /// No description provided for @browseNetworkFiles.
  ///
  /// In en, this message translates to:
  /// **'Network Files'**
  String get browseNetworkFiles;

  /// No description provided for @browseNetworkFilesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Browse HTTP file servers'**
  String get browseNetworkFilesSubtitle;

  /// No description provided for @browseWebScrape.
  ///
  /// In en, this message translates to:
  /// **'Web Scrape'**
  String get browseWebScrape;

  /// No description provided for @browseWebScrapeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Extract novels, comics, videos or articles from the web'**
  String get browseWebScrapeSubtitle;

  /// No description provided for @browseRss.
  ///
  /// In en, this message translates to:
  /// **'RSS Subscriptions'**
  String get browseRss;

  /// No description provided for @browseRssSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Manage and browse RSS feeds'**
  String get browseRssSubtitle;

  /// No description provided for @browseSniff.
  ///
  /// In en, this message translates to:
  /// **'Sniffer'**
  String get browseSniff;

  /// No description provided for @browseSniffSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Sniff web videos and play them in-app'**
  String get browseSniffSubtitle;

  /// No description provided for @subTabLocal.
  ///
  /// In en, this message translates to:
  /// **'Local'**
  String get subTabLocal;

  /// No description provided for @subTabHistory.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get subTabHistory;

  /// No description provided for @subTabFavorite.
  ///
  /// In en, this message translates to:
  /// **'Favorites'**
  String get subTabFavorite;

  /// No description provided for @filter.
  ///
  /// In en, this message translates to:
  /// **'Filter'**
  String get filter;

  /// No description provided for @filterTitle.
  ///
  /// In en, this message translates to:
  /// **'Filter'**
  String get filterTitle;

  /// No description provided for @sortBy.
  ///
  /// In en, this message translates to:
  /// **'Sort by'**
  String get sortBy;

  /// No description provided for @sortRecent.
  ///
  /// In en, this message translates to:
  /// **'Recent'**
  String get sortRecent;

  /// No description provided for @sortTitle.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get sortTitle;

  /// No description provided for @sortAuthor.
  ///
  /// In en, this message translates to:
  /// **'Author'**
  String get sortAuthor;

  /// No description provided for @sortLatestChapter.
  ///
  /// In en, this message translates to:
  /// **'Latest chapter'**
  String get sortLatestChapter;

  /// No description provided for @sortTitleZh.
  ///
  /// In en, this message translates to:
  /// **'Chinese title'**
  String get sortTitleZh;

  /// No description provided for @sortManual.
  ///
  /// In en, this message translates to:
  /// **'Manual'**
  String get sortManual;

  /// No description provided for @sortDirector.
  ///
  /// In en, this message translates to:
  /// **'Director'**
  String get sortDirector;

  /// No description provided for @sortActors.
  ///
  /// In en, this message translates to:
  /// **'Cast'**
  String get sortActors;

  /// No description provided for @sortLatestUpdate.
  ///
  /// In en, this message translates to:
  /// **'Latest'**
  String get sortLatestUpdate;

  /// No description provided for @sortLatestMangaChapter.
  ///
  /// In en, this message translates to:
  /// **'Latest chapter'**
  String get sortLatestMangaChapter;

  /// No description provided for @filterByStatus.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get filterByStatus;

  /// No description provided for @filterByCategory.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get filterByCategory;

  /// No description provided for @filterByProgress.
  ///
  /// In en, this message translates to:
  /// **'Progress'**
  String get filterByProgress;

  /// No description provided for @allLabel.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get allLabel;

  /// No description provided for @progressReading.
  ///
  /// In en, this message translates to:
  /// **'Reading'**
  String get progressReading;

  /// No description provided for @progressNotStarted.
  ///
  /// In en, this message translates to:
  /// **'Not started'**
  String get progressNotStarted;

  /// No description provided for @filterReset.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get filterReset;

  /// No description provided for @filterApply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get filterApply;

  /// Prefix shown on a collapsed filter group header listing its currently selected option labels
  ///
  /// In en, this message translates to:
  /// **'Selected'**
  String get filterSelectedPrefix;

  /// No description provided for @play.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get play;

  /// No description provided for @readChapter.
  ///
  /// In en, this message translates to:
  /// **'Read'**
  String get readChapter;

  /// Episode list header with selected line
  ///
  /// In en, this message translates to:
  /// **'Episodes · {line}'**
  String episodesWithLine(Object line);

  /// No description provided for @recommendations.
  ///
  /// In en, this message translates to:
  /// **'You may also like'**
  String get recommendations;

  /// Episode number label
  ///
  /// In en, this message translates to:
  /// **'Episode {n}'**
  String episodeN(Object n);

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @confirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @import.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get import;

  /// No description provided for @export.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get export;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @ok.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ok;

  /// No description provided for @next.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get next;

  /// No description provided for @previous.
  ///
  /// In en, this message translates to:
  /// **'Previous'**
  String get previous;

  /// No description provided for @emptyLibrary.
  ///
  /// In en, this message translates to:
  /// **'Your library is empty'**
  String get emptyLibrary;

  /// No description provided for @emptySearch.
  ///
  /// In en, this message translates to:
  /// **'No results found'**
  String get emptySearch;

  /// No description provided for @emptyDownloads.
  ///
  /// In en, this message translates to:
  /// **'No downloads yet'**
  String get emptyDownloads;

  /// No description provided for @emptySources.
  ///
  /// In en, this message translates to:
  /// **'No sources added'**
  String get emptySources;

  /// No description provided for @emptyBrowse.
  ///
  /// In en, this message translates to:
  /// **'Nothing here'**
  String get emptyBrowse;

  /// No description provided for @emptyLocalNovel.
  ///
  /// In en, this message translates to:
  /// **'No local novels'**
  String get emptyLocalNovel;

  /// No description provided for @emptyLocalMedia.
  ///
  /// In en, this message translates to:
  /// **'No local media'**
  String get emptyLocalMedia;

  /// No description provided for @emptyLocalComic.
  ///
  /// In en, this message translates to:
  /// **'No local comics'**
  String get emptyLocalComic;

  /// No description provided for @emptyLocalNovelAction.
  ///
  /// In en, this message translates to:
  /// **'Import novel'**
  String get emptyLocalNovelAction;

  /// No description provided for @emptyLocalMediaAction.
  ///
  /// In en, this message translates to:
  /// **'Import media'**
  String get emptyLocalMediaAction;

  /// No description provided for @emptyLocalComicAction.
  ///
  /// In en, this message translates to:
  /// **'Import comic'**
  String get emptyLocalComicAction;

  /// No description provided for @loading.
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get loading;

  /// No description provided for @noResults.
  ///
  /// In en, this message translates to:
  /// **'No results'**
  String get noResults;

  /// No description provided for @loadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load'**
  String get loadFailed;

  /// No description provided for @chapterLoadPartial.
  ///
  /// In en, this message translates to:
  /// **'Table of contents incomplete — showing {count} chapters (network may be unstable)'**
  String chapterLoadPartial(Object count);

  /// No description provided for @noMoreResults.
  ///
  /// In en, this message translates to:
  /// **'No more results'**
  String get noMoreResults;

  /// No description provided for @authorColon.
  ///
  /// In en, this message translates to:
  /// **'Author: '**
  String get authorColon;

  /// No description provided for @tagColon.
  ///
  /// In en, this message translates to:
  /// **'Tag: '**
  String get tagColon;

  /// No description provided for @searchFailed.
  ///
  /// In en, this message translates to:
  /// **'Search failed, please retry'**
  String get searchFailed;

  /// No description provided for @searching.
  ///
  /// In en, this message translates to:
  /// **'Searching…'**
  String get searching;

  /// Last updated time label
  ///
  /// In en, this message translates to:
  /// **'Updated {time}'**
  String updatedAt(Object time);

  /// No description provided for @statusOngoing.
  ///
  /// In en, this message translates to:
  /// **'Ongoing'**
  String get statusOngoing;

  /// No description provided for @statusCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get statusCompleted;

  /// No description provided for @deprecated.
  ///
  /// In en, this message translates to:
  /// **'Deprecated'**
  String get deprecated;

  /// No description provided for @mirrorSettings.
  ///
  /// In en, this message translates to:
  /// **'Mirror & stealth settings'**
  String get mirrorSettings;

  /// No description provided for @stealthMode.
  ///
  /// In en, this message translates to:
  /// **'Stealth mode'**
  String get stealthMode;

  /// No description provided for @gridView.
  ///
  /// In en, this message translates to:
  /// **'Grid view'**
  String get gridView;

  /// No description provided for @listView.
  ///
  /// In en, this message translates to:
  /// **'List view'**
  String get listView;

  /// No description provided for @toggleLayout.
  ///
  /// In en, this message translates to:
  /// **'Toggle layout'**
  String get toggleLayout;

  /// No description provided for @all.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get all;

  /// No description provided for @emptyCategory.
  ///
  /// In en, this message translates to:
  /// **'No content in this category'**
  String get emptyCategory;

  /// No description provided for @emptyContent.
  ///
  /// In en, this message translates to:
  /// **'No content yet'**
  String get emptyContent;

  /// No description provided for @contentExpired.
  ///
  /// In en, this message translates to:
  /// **'Content expired, please search again'**
  String get contentExpired;

  /// No description provided for @sourceNotFound.
  ///
  /// In en, this message translates to:
  /// **'Source unavailable, please switch source or search again'**
  String get sourceNotFound;

  /// No description provided for @onlineBrowse.
  ///
  /// In en, this message translates to:
  /// **'Online Browse'**
  String get onlineBrowse;

  /// No description provided for @switchSource.
  ///
  /// In en, this message translates to:
  /// **'Switch source'**
  String get switchSource;

  /// No description provided for @searchSourceHint.
  ///
  /// In en, this message translates to:
  /// **'Search sources'**
  String get searchSourceHint;

  /// No description provided for @refreshList.
  ///
  /// In en, this message translates to:
  /// **'Refresh list'**
  String get refreshList;

  /// No description provided for @goToVerification.
  ///
  /// In en, this message translates to:
  /// **'Verify now'**
  String get goToVerification;

  /// No description provided for @openSourceWebsite.
  ///
  /// In en, this message translates to:
  /// **'Open source site'**
  String get openSourceWebsite;

  /// No description provided for @errorGeneric.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong'**
  String get errorGeneric;

  /// No description provided for @errorNetwork.
  ///
  /// In en, this message translates to:
  /// **'Network error, please try again'**
  String get errorNetwork;

  /// No description provided for @errorParse.
  ///
  /// In en, this message translates to:
  /// **'Failed to parse content'**
  String get errorParse;

  /// No description provided for @errorVerification.
  ///
  /// In en, this message translates to:
  /// **'Verification required, please complete the challenge'**
  String get errorVerification;

  /// No description provided for @verificationFailed.
  ///
  /// In en, this message translates to:
  /// **'Verification failed, please retry later'**
  String get verificationFailed;

  /// No description provided for @errorVideoExpired.
  ///
  /// In en, this message translates to:
  /// **'Video link expired, please retry'**
  String get errorVideoExpired;

  /// No description provided for @danmaku.
  ///
  /// In en, this message translates to:
  /// **'Danmaku'**
  String get danmaku;

  /// No description provided for @danmakuSend.
  ///
  /// In en, this message translates to:
  /// **'Send danmaku'**
  String get danmakuSend;

  /// No description provided for @danmakuSendHint.
  ///
  /// In en, this message translates to:
  /// **'Enter danmaku text'**
  String get danmakuSendHint;

  /// No description provided for @danmakuUploadSuccess.
  ///
  /// In en, this message translates to:
  /// **'Danmaku posted'**
  String get danmakuUploadSuccess;

  /// No description provided for @danmakuUploadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to post danmaku: {error}'**
  String danmakuUploadFailed(String error);

  /// No description provided for @danmakuSendNoEpisode.
  ///
  /// In en, this message translates to:
  /// **'No matched danmaku episode; shown locally only'**
  String get danmakuSendNoEpisode;

  /// No description provided for @danmakuSendTimeInvalid.
  ///
  /// In en, this message translates to:
  /// **'Position beyond video duration; shown locally only'**
  String get danmakuSendTimeInvalid;

  /// No description provided for @danmakuLoginTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign in to DanDanPlay'**
  String get danmakuLoginTitle;

  /// No description provided for @danmakuLoginRequiredHint.
  ///
  /// In en, this message translates to:
  /// **'Sign in to your DanDanPlay account to post danmaku'**
  String get danmakuLoginRequiredHint;

  /// No description provided for @danmakuUsername.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get danmakuUsername;

  /// No description provided for @danmakuPassword.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get danmakuPassword;

  /// No description provided for @danmakuLoginAction.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get danmakuLoginAction;

  /// No description provided for @danmakuLoginEmptyFields.
  ///
  /// In en, this message translates to:
  /// **'Please enter username and password'**
  String get danmakuLoginEmptyFields;

  /// No description provided for @danmakuAccountSection.
  ///
  /// In en, this message translates to:
  /// **'DanDanPlay Account'**
  String get danmakuAccountSection;

  /// No description provided for @danmakuAccountLoggedInAs.
  ///
  /// In en, this message translates to:
  /// **'Signed in as {name}'**
  String danmakuAccountLoggedInAs(String name);

  /// No description provided for @dandanplayLoggedOut.
  ///
  /// In en, this message translates to:
  /// **'Signed out of DanDanPlay'**
  String get dandanplayLoggedOut;

  /// No description provided for @dandanplayAppNotConfigured.
  ///
  /// In en, this message translates to:
  /// **'DanDanPlay app is not configured; login unavailable'**
  String get dandanplayAppNotConfigured;

  /// No description provided for @dandanplayLoginTab.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get dandanplayLoginTab;

  /// No description provided for @dandanplayRegisterTab.
  ///
  /// In en, this message translates to:
  /// **'Register'**
  String get dandanplayRegisterTab;

  /// No description provided for @dandanplayEmail.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get dandanplayEmail;

  /// No description provided for @dandanplayNickname.
  ///
  /// In en, this message translates to:
  /// **'Nickname'**
  String get dandanplayNickname;

  /// No description provided for @dandanplayRegisterAction.
  ///
  /// In en, this message translates to:
  /// **'Register & sign in'**
  String get dandanplayRegisterAction;

  /// No description provided for @dandanplayRegisterSuccess.
  ///
  /// In en, this message translates to:
  /// **'Registered and signed in'**
  String get dandanplayRegisterSuccess;

  /// No description provided for @dandanplayRegisterEmptyFields.
  ///
  /// In en, this message translates to:
  /// **'Please enter username, password and email'**
  String get dandanplayRegisterEmptyFields;

  /// No description provided for @dandanplayRegisterEmailInvalid.
  ///
  /// In en, this message translates to:
  /// **'Invalid email format'**
  String get dandanplayRegisterEmailInvalid;

  /// No description provided for @danmakuStyle.
  ///
  /// In en, this message translates to:
  /// **'Danmaku style'**
  String get danmakuStyle;

  /// No description provided for @danmakuStyleScroll.
  ///
  /// In en, this message translates to:
  /// **'Scroll'**
  String get danmakuStyleScroll;

  /// No description provided for @danmakuStyleTop.
  ///
  /// In en, this message translates to:
  /// **'Top'**
  String get danmakuStyleTop;

  /// No description provided for @danmakuStyleBottom.
  ///
  /// In en, this message translates to:
  /// **'Bottom'**
  String get danmakuStyleBottom;

  /// No description provided for @themeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// No description provided for @themeSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get themeSystem;

  /// No description provided for @useMonet.
  ///
  /// In en, this message translates to:
  /// **'Use dynamic color (Monet)'**
  String get useMonet;

  /// No description provided for @glassEffectTitle.
  ///
  /// In en, this message translates to:
  /// **'Frosted glass bars'**
  String get glassEffectTitle;

  /// No description provided for @glassEffectDesc.
  ///
  /// In en, this message translates to:
  /// **'Translucent blurred nav rail/bar with content scrolling behind; turn off on low-end devices'**
  String get glassEffectDesc;

  /// No description provided for @sourceDragSplitTitle.
  ///
  /// In en, this message translates to:
  /// **'Reorder split effect'**
  String get sourceDragSplitTitle;

  /// No description provided for @sourceDragSplitDesc.
  ///
  /// In en, this message translates to:
  /// **'Split the source card with live corner updates while reordering; off keeps the card intact (simpler effect)'**
  String get sourceDragSplitDesc;

  /// No description provided for @statusBarTapToTopTitle.
  ///
  /// In en, this message translates to:
  /// **'Tap status bar to top'**
  String get statusBarTapToTopTitle;

  /// No description provided for @statusBarTapToTopDesc.
  ///
  /// In en, this message translates to:
  /// **'On HarmonyOS, tap the system status bar to quickly scroll the current page back to the top'**
  String get statusBarTapToTopDesc;

  /// No description provided for @glassBlurStrength.
  ///
  /// In en, this message translates to:
  /// **'Blur strength'**
  String get glassBlurStrength;

  /// No description provided for @glassBarOpacity.
  ///
  /// In en, this message translates to:
  /// **'Bar opacity'**
  String get glassBarOpacity;

  /// No description provided for @customColor.
  ///
  /// In en, this message translates to:
  /// **'Custom Color'**
  String get customColor;

  /// No description provided for @presetColor.
  ///
  /// In en, this message translates to:
  /// **'Preset colors'**
  String get presetColor;

  /// No description provided for @paletteStyleTitle.
  ///
  /// In en, this message translates to:
  /// **'Palette style'**
  String get paletteStyleTitle;

  /// No description provided for @paletteStyleDesc.
  ///
  /// In en, this message translates to:
  /// **'Color algorithm variant for the current seed'**
  String get paletteStyleDesc;

  /// No description provided for @paletteStyleTonalSpot.
  ///
  /// In en, this message translates to:
  /// **'Tonal spot'**
  String get paletteStyleTonalSpot;

  /// No description provided for @paletteStyleFidelity.
  ///
  /// In en, this message translates to:
  /// **'Fidelity'**
  String get paletteStyleFidelity;

  /// No description provided for @paletteStyleContent.
  ///
  /// In en, this message translates to:
  /// **'Content'**
  String get paletteStyleContent;

  /// No description provided for @paletteStyleNeutral.
  ///
  /// In en, this message translates to:
  /// **'Neutral'**
  String get paletteStyleNeutral;

  /// No description provided for @paletteStyleMonochrome.
  ///
  /// In en, this message translates to:
  /// **'Monochrome'**
  String get paletteStyleMonochrome;

  /// No description provided for @paletteStyleVibrant.
  ///
  /// In en, this message translates to:
  /// **'Vibrant'**
  String get paletteStyleVibrant;

  /// No description provided for @paletteStyleExpressive.
  ///
  /// In en, this message translates to:
  /// **'Expressive'**
  String get paletteStyleExpressive;

  /// No description provided for @paletteStyleRainbow.
  ///
  /// In en, this message translates to:
  /// **'Rainbow'**
  String get paletteStyleRainbow;

  /// No description provided for @paletteStyleFruitSalad.
  ///
  /// In en, this message translates to:
  /// **'Fruit salad'**
  String get paletteStyleFruitSalad;

  /// No description provided for @appearanceThemeMode.
  ///
  /// In en, this message translates to:
  /// **'Theme mode'**
  String get appearanceThemeMode;

  /// No description provided for @appearanceThemeSection.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get appearanceThemeSection;

  /// No description provided for @appearanceColorsSection.
  ///
  /// In en, this message translates to:
  /// **'Colors'**
  String get appearanceColorsSection;

  /// No description provided for @appearanceFontSection.
  ///
  /// In en, this message translates to:
  /// **'Font'**
  String get appearanceFontSection;

  /// No description provided for @appearanceFont.
  ///
  /// In en, this message translates to:
  /// **'App font'**
  String get appearanceFont;

  /// No description provided for @appFontFollowSystem.
  ///
  /// In en, this message translates to:
  /// **'Follow system'**
  String get appFontFollowSystem;

  /// No description provided for @appFontFollowSystemDesc.
  ///
  /// In en, this message translates to:
  /// **'Use the system default font'**
  String get appFontFollowSystemDesc;

  /// No description provided for @appFontPreviewSample.
  ///
  /// In en, this message translates to:
  /// **'Preview: Aa Bb, 123'**
  String get appFontPreviewSample;

  /// No description provided for @appFontCustomDesc.
  ///
  /// In en, this message translates to:
  /// **'Custom font'**
  String get appFontCustomDesc;

  /// No description provided for @appFontCustomImport.
  ///
  /// In en, this message translates to:
  /// **'Import font file (.ttf / .otf)'**
  String get appFontCustomImport;

  /// No description provided for @appFontClearCustom.
  ///
  /// In en, this message translates to:
  /// **'Remove custom font'**
  String get appFontClearCustom;

  /// No description provided for @appFontLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load that font. Try another .ttf / .otf file'**
  String get appFontLoadFailed;

  /// No description provided for @appearanceStartupSection.
  ///
  /// In en, this message translates to:
  /// **'Launch & Display'**
  String get appearanceStartupSection;

  /// No description provided for @heroSettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Hero Images'**
  String get heroSettingsTitle;

  /// No description provided for @appearanceHeroSection.
  ///
  /// In en, this message translates to:
  /// **'Background'**
  String get appearanceHeroSection;

  /// No description provided for @heroEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Add a few images to cycle at the top of Settings'**
  String get heroEmptyHint;

  /// No description provided for @heroAddFromUrl.
  ///
  /// In en, this message translates to:
  /// **'Add from URL'**
  String get heroAddFromUrl;

  /// No description provided for @heroAddFromDevice.
  ///
  /// In en, this message translates to:
  /// **'Pick from device'**
  String get heroAddFromDevice;

  /// No description provided for @heroUrlDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Add image URL'**
  String get heroUrlDialogTitle;

  /// No description provided for @heroUrlFieldHint.
  ///
  /// In en, this message translates to:
  /// **'Image address (https://... or file://...)'**
  String get heroUrlFieldHint;

  /// No description provided for @heroRemoveTooltip.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get heroRemoveTooltip;

  /// No description provided for @deleteConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete confirmation'**
  String get deleteConfirmTitle;

  /// Delete confirmation dialog content
  ///
  /// In en, this message translates to:
  /// **'Delete \"{name}\"? This cannot be undone.'**
  String deleteConfirmContent(String name);

  /// No description provided for @deleteRecordOnly.
  ///
  /// In en, this message translates to:
  /// **'Delete record only'**
  String get deleteRecordOnly;

  /// No description provided for @deleteRecordAndFile.
  ///
  /// In en, this message translates to:
  /// **'Delete record and files'**
  String get deleteRecordAndFile;

  /// No description provided for @addSource.
  ///
  /// In en, this message translates to:
  /// **'Add source'**
  String get addSource;

  /// No description provided for @importSource.
  ///
  /// In en, this message translates to:
  /// **'Import source'**
  String get importSource;

  /// No description provided for @exportSource.
  ///
  /// In en, this message translates to:
  /// **'Export source'**
  String get exportSource;

  /// No description provided for @aboutDescription.
  ///
  /// In en, this message translates to:
  /// **'NexHub — a four-in-one media aggregator (anime / manga / novel / film).'**
  String get aboutDescription;

  /// No description provided for @videoSourceLine.
  ///
  /// In en, this message translates to:
  /// **'Line'**
  String get videoSourceLine;

  /// No description provided for @defaultLine.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get defaultLine;

  /// No description provided for @errorWebView.
  ///
  /// In en, this message translates to:
  /// **'WebView verification required'**
  String get errorWebView;

  /// No description provided for @verifying.
  ///
  /// In en, this message translates to:
  /// **'Verifying…'**
  String get verifying;

  /// No description provided for @mirrorTest.
  ///
  /// In en, this message translates to:
  /// **'Speed test'**
  String get mirrorTest;

  /// No description provided for @sourceHealthy.
  ///
  /// In en, this message translates to:
  /// **'Healthy'**
  String get sourceHealthy;

  /// No description provided for @resolveTimeout.
  ///
  /// In en, this message translates to:
  /// **'Resolve timeout'**
  String get resolveTimeout;

  /// Source resolve failure message
  ///
  /// In en, this message translates to:
  /// **'Resolve failed: {message}'**
  String resolveFailed(Object message);

  /// No description provided for @categories.
  ///
  /// In en, this message translates to:
  /// **'Categories'**
  String get categories;

  /// Chapter number label for manga
  ///
  /// In en, this message translates to:
  /// **'Ch. {n}'**
  String chapterN(Object n);

  /// Reader page indicator
  ///
  /// In en, this message translates to:
  /// **'Page {cur} / {total}'**
  String pageIndicator(Object cur, Object total);

  /// Reader double-page spread indicator
  ///
  /// In en, this message translates to:
  /// **'{first}-{last} / {total}'**
  String readerDoublePageIndicator(Object first, Object last, Object total);

  /// No description provided for @prevChapter.
  ///
  /// In en, this message translates to:
  /// **'Prev chapter'**
  String get prevChapter;

  /// No description provided for @nextChapter.
  ///
  /// In en, this message translates to:
  /// **'Next chapter'**
  String get nextChapter;

  /// No description provided for @readerLastChapterReached.
  ///
  /// In en, this message translates to:
  /// **'Already at the last chapter'**
  String get readerLastChapterReached;

  /// No description provided for @readerFirstChapterReached.
  ///
  /// In en, this message translates to:
  /// **'Already at the first chapter'**
  String get readerFirstChapterReached;

  /// Webtoon skip-transition banner title shown when jumping over read/filtered/duplicate chapters
  ///
  /// In en, this message translates to:
  /// **'Next chapter: {title}'**
  String readerNextChapterSkipped(Object title);

  /// Hint text on the webtoon skip-transition banner telling the user to tap to jump immediately
  ///
  /// In en, this message translates to:
  /// **'Tap to jump now'**
  String get readerNextChapterSkippedHint;

  /// No description provided for @readerSettings.
  ///
  /// In en, this message translates to:
  /// **'Reader settings'**
  String get readerSettings;

  /// No description provided for @readerMode.
  ///
  /// In en, this message translates to:
  /// **'Reading mode'**
  String get readerMode;

  /// No description provided for @readerBackground.
  ///
  /// In en, this message translates to:
  /// **'Background'**
  String get readerBackground;

  /// No description provided for @readerOrientation.
  ///
  /// In en, this message translates to:
  /// **'Orientation'**
  String get readerOrientation;

  /// No description provided for @readerTapZone.
  ///
  /// In en, this message translates to:
  /// **'Tap zones'**
  String get readerTapZone;

  /// No description provided for @readerZoom.
  ///
  /// In en, this message translates to:
  /// **'Double-tap zoom'**
  String get readerZoom;

  /// No description provided for @noImages.
  ///
  /// In en, this message translates to:
  /// **'No readable images in this chapter'**
  String get noImages;

  /// No description provided for @preloading.
  ///
  /// In en, this message translates to:
  /// **'Preloading next chapter…'**
  String get preloading;

  /// No description provided for @readerModeSingleLTR.
  ///
  /// In en, this message translates to:
  /// **'Single page (L→R)'**
  String get readerModeSingleLTR;

  /// No description provided for @readerModeSingleRTL.
  ///
  /// In en, this message translates to:
  /// **'Single page (R→L)'**
  String get readerModeSingleRTL;

  /// No description provided for @readerModeSingleVertical.
  ///
  /// In en, this message translates to:
  /// **'Single page (vertical)'**
  String get readerModeSingleVertical;

  /// No description provided for @readerModeWebtoon.
  ///
  /// In en, this message translates to:
  /// **'Webtoon'**
  String get readerModeWebtoon;

  /// No description provided for @readerModeWebtoonWithGap.
  ///
  /// In en, this message translates to:
  /// **'Webtoon (with gap)'**
  String get readerModeWebtoonWithGap;

  /// No description provided for @readerOrientationDefault.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get readerOrientationDefault;

  /// No description provided for @readerOrientationSystem.
  ///
  /// In en, this message translates to:
  /// **'Follow system'**
  String get readerOrientationSystem;

  /// No description provided for @readerOrientationPortrait.
  ///
  /// In en, this message translates to:
  /// **'Portrait'**
  String get readerOrientationPortrait;

  /// No description provided for @readerOrientationLandscape.
  ///
  /// In en, this message translates to:
  /// **'Landscape'**
  String get readerOrientationLandscape;

  /// No description provided for @readerOrientationLockPortrait.
  ///
  /// In en, this message translates to:
  /// **'Lock portrait'**
  String get readerOrientationLockPortrait;

  /// No description provided for @readerOrientationLockLandscape.
  ///
  /// In en, this message translates to:
  /// **'Lock landscape'**
  String get readerOrientationLockLandscape;

  /// No description provided for @readerOrientationReversePortrait.
  ///
  /// In en, this message translates to:
  /// **'Reverse portrait'**
  String get readerOrientationReversePortrait;

  /// No description provided for @readerBgBlack.
  ///
  /// In en, this message translates to:
  /// **'Black'**
  String get readerBgBlack;

  /// No description provided for @readerBgGray.
  ///
  /// In en, this message translates to:
  /// **'Gray'**
  String get readerBgGray;

  /// No description provided for @readerBgDarkGray.
  ///
  /// In en, this message translates to:
  /// **'Dark gray'**
  String get readerBgDarkGray;

  /// No description provided for @readerBgEyeCare.
  ///
  /// In en, this message translates to:
  /// **'Eye care'**
  String get readerBgEyeCare;

  /// No description provided for @readerBgParchment.
  ///
  /// In en, this message translates to:
  /// **'Parchment'**
  String get readerBgParchment;

  /// No description provided for @readerBgWarmLinen.
  ///
  /// In en, this message translates to:
  /// **'Warm linen'**
  String get readerBgWarmLinen;

  /// No description provided for @readerBgLightBrown.
  ///
  /// In en, this message translates to:
  /// **'Light brown'**
  String get readerBgLightBrown;

  /// No description provided for @readerBgBeanGreen.
  ///
  /// In en, this message translates to:
  /// **'Bean green'**
  String get readerBgBeanGreen;

  /// No description provided for @readerBgMint.
  ///
  /// In en, this message translates to:
  /// **'Mint'**
  String get readerBgMint;

  /// No description provided for @readerBgApricot.
  ///
  /// In en, this message translates to:
  /// **'Apricot'**
  String get readerBgApricot;

  /// No description provided for @readerBgGrayBlue.
  ///
  /// In en, this message translates to:
  /// **'Gray blue'**
  String get readerBgGrayBlue;

  /// No description provided for @readerBgEInk.
  ///
  /// In en, this message translates to:
  /// **'E-Ink paper'**
  String get readerBgEInk;

  /// No description provided for @readerBgWhite.
  ///
  /// In en, this message translates to:
  /// **'White'**
  String get readerBgWhite;

  /// No description provided for @readerBgAuto.
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get readerBgAuto;

  /// No description provided for @readerTapLeftRight.
  ///
  /// In en, this message translates to:
  /// **'Left/Right'**
  String get readerTapLeftRight;

  /// No description provided for @readerTapLShape.
  ///
  /// In en, this message translates to:
  /// **'L-shape'**
  String get readerTapLShape;

  /// No description provided for @readerTapKindle.
  ///
  /// In en, this message translates to:
  /// **'Kindle'**
  String get readerTapKindle;

  /// No description provided for @readerTapBothSides.
  ///
  /// In en, this message translates to:
  /// **'Both sides'**
  String get readerTapBothSides;

  /// No description provided for @readerTapOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get readerTapOff;

  /// No description provided for @readerTapInvert.
  ///
  /// In en, this message translates to:
  /// **'Tap flip'**
  String get readerTapInvert;

  /// No description provided for @readerTapInvertNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get readerTapInvertNone;

  /// No description provided for @readerTapInvertLeftRight.
  ///
  /// In en, this message translates to:
  /// **'Left/Right'**
  String get readerTapInvertLeftRight;

  /// No description provided for @readerTapInvertUpDown.
  ///
  /// In en, this message translates to:
  /// **'Up/Down'**
  String get readerTapInvertUpDown;

  /// No description provided for @readerTapInvertAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get readerTapInvertAll;

  /// No description provided for @readerSideMargin.
  ///
  /// In en, this message translates to:
  /// **'Side margin'**
  String get readerSideMargin;

  /// No description provided for @readerFlashEnabled.
  ///
  /// In en, this message translates to:
  /// **'Page-turn flash'**
  String get readerFlashEnabled;

  /// No description provided for @readerFlashTime.
  ///
  /// In en, this message translates to:
  /// **'Flash duration'**
  String get readerFlashTime;

  /// No description provided for @readerFlashInterval.
  ///
  /// In en, this message translates to:
  /// **'Flash delay'**
  String get readerFlashInterval;

  /// No description provided for @readerFlashColor.
  ///
  /// In en, this message translates to:
  /// **'Flash color'**
  String get readerFlashColor;

  /// No description provided for @readerFlashBlack.
  ///
  /// In en, this message translates to:
  /// **'Black'**
  String get readerFlashBlack;

  /// No description provided for @readerFlashWhite.
  ///
  /// In en, this message translates to:
  /// **'White'**
  String get readerFlashWhite;

  /// No description provided for @readerFlashBlackWhite.
  ///
  /// In en, this message translates to:
  /// **'Black→White'**
  String get readerFlashBlackWhite;

  /// No description provided for @readerTapPreviewHint.
  ///
  /// In en, this message translates to:
  /// **'Tap zone preview (live)'**
  String get readerTapPreviewHint;

  /// No description provided for @tapPreviewPrev.
  ///
  /// In en, this message translates to:
  /// **'Prev page'**
  String get tapPreviewPrev;

  /// No description provided for @tapPreviewNext.
  ///
  /// In en, this message translates to:
  /// **'Next page'**
  String get tapPreviewNext;

  /// No description provided for @tapPreviewToggle.
  ///
  /// In en, this message translates to:
  /// **'Toggle'**
  String get tapPreviewToggle;

  /// No description provided for @filterInverted.
  ///
  /// In en, this message translates to:
  /// **'Invert'**
  String get filterInverted;

  /// No description provided for @favorite.
  ///
  /// In en, this message translates to:
  /// **'Favorite'**
  String get favorite;

  /// No description provided for @moreActions.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get moreActions;

  /// No description provided for @demoNormal.
  ///
  /// In en, this message translates to:
  /// **'Default view'**
  String get demoNormal;

  /// No description provided for @demoEmpty.
  ///
  /// In en, this message translates to:
  /// **'Show empty state'**
  String get demoEmpty;

  /// No description provided for @demoError.
  ///
  /// In en, this message translates to:
  /// **'Show error state'**
  String get demoError;

  /// No description provided for @noContent.
  ///
  /// In en, this message translates to:
  /// **'No content in this chapter'**
  String get noContent;

  /// No description provided for @novelFontSize.
  ///
  /// In en, this message translates to:
  /// **'Font size'**
  String get novelFontSize;

  /// No description provided for @novelLineHeight.
  ///
  /// In en, this message translates to:
  /// **'Line height'**
  String get novelLineHeight;

  /// Novel paragraph spacing
  ///
  /// In en, this message translates to:
  /// **'Paragraph spacing'**
  String get novelParagraphSpacing;

  /// Novel margin
  ///
  /// In en, this message translates to:
  /// **'Margin'**
  String get novelMargin;

  /// Novel page turn animation
  ///
  /// In en, this message translates to:
  /// **'Page animation'**
  String get novelPageAnimation;

  /// No description provided for @novelTextShadow.
  ///
  /// In en, this message translates to:
  /// **'Text shadow'**
  String get novelTextShadow;

  /// No description provided for @novelAnimNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get novelAnimNone;

  /// No description provided for @novelAnimSlide.
  ///
  /// In en, this message translates to:
  /// **'Slide'**
  String get novelAnimSlide;

  /// No description provided for @novelAnimScroll.
  ///
  /// In en, this message translates to:
  /// **'Scroll'**
  String get novelAnimScroll;

  /// No description provided for @novelAnimFade.
  ///
  /// In en, this message translates to:
  /// **'Fade'**
  String get novelAnimFade;

  /// No description provided for @novelAnimCover.
  ///
  /// In en, this message translates to:
  /// **'Cover'**
  String get novelAnimCover;

  /// No description provided for @novelAnimSimulation.
  ///
  /// In en, this message translates to:
  /// **'Simulation'**
  String get novelAnimSimulation;

  /// No description provided for @novelHfNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get novelHfNone;

  /// No description provided for @novelHfTime.
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get novelHfTime;

  /// No description provided for @novelHfBattery.
  ///
  /// In en, this message translates to:
  /// **'Battery'**
  String get novelHfBattery;

  /// No description provided for @novelHfChapterTitle.
  ///
  /// In en, this message translates to:
  /// **'Chapter title'**
  String get novelHfChapterTitle;

  /// No description provided for @novelHfBookName.
  ///
  /// In en, this message translates to:
  /// **'Book name'**
  String get novelHfBookName;

  /// No description provided for @novelHfPageNumber.
  ///
  /// In en, this message translates to:
  /// **'Page number'**
  String get novelHfPageNumber;

  /// No description provided for @novelHfProgressPercent.
  ///
  /// In en, this message translates to:
  /// **'Progress %'**
  String get novelHfProgressPercent;

  /// Novel chapter number label
  ///
  /// In en, this message translates to:
  /// **'Chapter {n}'**
  String novelChapterN(Object n);

  /// No description provided for @download.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get download;

  /// No description provided for @downloads.
  ///
  /// In en, this message translates to:
  /// **'Downloads'**
  String get downloads;

  /// No description provided for @downloadListTitle.
  ///
  /// In en, this message translates to:
  /// **'Downloads'**
  String get downloadListTitle;

  /// No description provided for @downloadedContent.
  ///
  /// In en, this message translates to:
  /// **'Downloaded'**
  String get downloadedContent;

  /// No description provided for @downloadSettings.
  ///
  /// In en, this message translates to:
  /// **'Download Settings'**
  String get downloadSettings;

  /// No description provided for @emptyDownloadList.
  ///
  /// In en, this message translates to:
  /// **'No active downloads'**
  String get emptyDownloadList;

  /// No description provided for @emptyDownloaded.
  ///
  /// In en, this message translates to:
  /// **'No downloaded content'**
  String get emptyDownloaded;

  /// No description provided for @clearAll.
  ///
  /// In en, this message translates to:
  /// **'Clear All'**
  String get clearAll;

  /// No description provided for @clearAllConfirm.
  ///
  /// In en, this message translates to:
  /// **'This clears all active/paused/failed download records across all filters. Finished downloads are kept and remain readable. Continue?'**
  String get clearAllConfirm;

  /// No description provided for @clearHistory.
  ///
  /// In en, this message translates to:
  /// **'Clear History'**
  String get clearHistory;

  /// No description provided for @recentSearches.
  ///
  /// In en, this message translates to:
  /// **'Recent searches'**
  String get recentSearches;

  /// No description provided for @clearHistoryConfirm.
  ///
  /// In en, this message translates to:
  /// **'Clear all browsing history for this module? Reading progress will be kept and restored when you revisit.'**
  String get clearHistoryConfirm;

  /// No description provided for @historyCleared.
  ///
  /// In en, this message translates to:
  /// **'History cleared'**
  String get historyCleared;

  /// No description provided for @batchPause.
  ///
  /// In en, this message translates to:
  /// **'Batch Pause'**
  String get batchPause;

  /// No description provided for @batchResume.
  ///
  /// In en, this message translates to:
  /// **'Batch Resume'**
  String get batchResume;

  /// No description provided for @deleteSelected.
  ///
  /// In en, this message translates to:
  /// **'Delete Selected'**
  String get deleteSelected;

  /// No description provided for @deleteSelectedConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete the {count} selected download records?'**
  String deleteSelectedConfirm(Object count);

  /// No description provided for @pause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get pause;

  /// No description provided for @selectAll.
  ///
  /// In en, this message translates to:
  /// **'Select All'**
  String get selectAll;

  /// No description provided for @select.
  ///
  /// In en, this message translates to:
  /// **'Select'**
  String get select;

  /// No description provided for @deleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete selected downloads?'**
  String get deleteConfirm;

  /// No description provided for @statusPending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get statusPending;

  /// No description provided for @statusDownloading.
  ///
  /// In en, this message translates to:
  /// **'Downloading'**
  String get statusDownloading;

  /// No description provided for @statusPaused.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get statusPaused;

  /// No description provided for @statusFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get statusFailed;

  /// No description provided for @statusWaitingForWifi.
  ///
  /// In en, this message translates to:
  /// **'Waiting for Wi-Fi'**
  String get statusWaitingForWifi;

  /// No description provided for @statusCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get statusCancelled;

  /// No description provided for @downloadWifiOnly.
  ///
  /// In en, this message translates to:
  /// **'Wi-Fi only downloads'**
  String get downloadWifiOnly;

  /// No description provided for @downloadWifiOnlyHint.
  ///
  /// In en, this message translates to:
  /// **'Start downloads only when connected to Wi-Fi'**
  String get downloadWifiOnlyHint;

  /// No description provided for @comicDownloadFormat.
  ///
  /// In en, this message translates to:
  /// **'Comic Download Format'**
  String get comicDownloadFormat;

  /// No description provided for @novelDownloadFormat.
  ///
  /// In en, this message translates to:
  /// **'Novel Download Format'**
  String get novelDownloadFormat;

  /// No description provided for @formatCbz.
  ///
  /// In en, this message translates to:
  /// **'CBZ Archive'**
  String get formatCbz;

  /// No description provided for @formatCbzSubtitle.
  ///
  /// In en, this message translates to:
  /// **'All images packed into a single .cbz file'**
  String get formatCbzSubtitle;

  /// No description provided for @formatFolder.
  ///
  /// In en, this message translates to:
  /// **'Image Folder'**
  String get formatFolder;

  /// No description provided for @formatFolderSubtitle.
  ///
  /// In en, this message translates to:
  /// **'One folder per chapter with loose images'**
  String get formatFolderSubtitle;

  /// No description provided for @formatEpub.
  ///
  /// In en, this message translates to:
  /// **'EPUB eBook'**
  String get formatEpub;

  /// No description provided for @formatEpubSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Standard eBook format with table of contents'**
  String get formatEpubSubtitle;

  /// No description provided for @formatTxt.
  ///
  /// In en, this message translates to:
  /// **'TXT Plain Text'**
  String get formatTxt;

  /// No description provided for @formatTxtSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Plain text format, widest compatibility'**
  String get formatTxtSubtitle;

  /// No description provided for @emptyHistory.
  ///
  /// In en, this message translates to:
  /// **'No browsing history'**
  String get emptyHistory;

  /// No description provided for @emptyFavorites.
  ///
  /// In en, this message translates to:
  /// **'No favorites yet'**
  String get emptyFavorites;

  /// No description provided for @emptyRssFeeds.
  ///
  /// In en, this message translates to:
  /// **'No RSS feeds'**
  String get emptyRssFeeds;

  /// No description provided for @emptyRssItems.
  ///
  /// In en, this message translates to:
  /// **'No articles'**
  String get emptyRssItems;

  /// No description provided for @addRssFeed.
  ///
  /// In en, this message translates to:
  /// **'Add RSS Feed'**
  String get addRssFeed;

  /// No description provided for @rssFeedTitle.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get rssFeedTitle;

  /// No description provided for @rssFeedTitleHint.
  ///
  /// In en, this message translates to:
  /// **'Custom title (optional)'**
  String get rssFeedTitleHint;

  /// No description provided for @opening.
  ///
  /// In en, this message translates to:
  /// **'Opening'**
  String get opening;

  /// No description provided for @verificationRequired.
  ///
  /// In en, this message translates to:
  /// **'Verification Required'**
  String get verificationRequired;

  /// No description provided for @verificationHint.
  ///
  /// In en, this message translates to:
  /// **'This content requires web verification. Tap the button below to complete verification in your browser, then return and retry.'**
  String get verificationHint;

  /// No description provided for @openInBrowser.
  ///
  /// In en, this message translates to:
  /// **'Open externally'**
  String get openInBrowser;

  /// No description provided for @verificationDone.
  ///
  /// In en, this message translates to:
  /// **'Verification Done, Retry'**
  String get verificationDone;

  /// No description provided for @webViewNotAvailable.
  ///
  /// In en, this message translates to:
  /// **'In-app browser is not available on this platform. Please use an external browser to complete verification.'**
  String get webViewNotAvailable;

  /// Button: run jsExtractor inside the embedded WebView to extract the real URL
  ///
  /// In en, this message translates to:
  /// **'Extract from this page'**
  String get extractFromPage;

  /// Hint shown above the extract button in the embedded WebView verification screen
  ///
  /// In en, this message translates to:
  /// **'After completing verification on the page, tap \"Extract from this page\" to auto-extract the content URL. Falls back to manual browser verification on failure.'**
  String get extractHint;

  /// Loading text while jsExtractor is being evaluated inside the WebView
  ///
  /// In en, this message translates to:
  /// **'Extracting…'**
  String get extracting;

  /// Toast when jsExtractor returns a valid URL
  ///
  /// In en, this message translates to:
  /// **'Extraction succeeded'**
  String get extractSuccess;

  /// Error shown when jsExtractor returns nothing usable
  ///
  /// In en, this message translates to:
  /// **'Nothing extracted, please retry or verify manually'**
  String get extractNoResult;

  /// Error prefix when jsExtractor evaluation throws
  ///
  /// In en, this message translates to:
  /// **'Extraction failed'**
  String get extractFailed;

  /// Button: capture the JS-rendered HTML of the embedded WebView and parse it with the source selectors
  ///
  /// In en, this message translates to:
  /// **'Capture rendered page'**
  String get captureFromPage;

  /// Hint shown above the capture button in the render-after-extract WebView screen
  ///
  /// In en, this message translates to:
  /// **'Once the page finishes rendering, tap \"Capture rendered page\" to parse the list/detail with the existing selectors. No manual script needed.'**
  String get captureHint;

  /// Loading text while the rendered HTML is being captured from the WebView
  ///
  /// In en, this message translates to:
  /// **'Capturing…'**
  String get capturing;

  /// Title of the video sniffer screen
  ///
  /// In en, this message translates to:
  /// **'Video Sniffer'**
  String get snifferTitle;

  /// Placeholder of the address bar in the video sniffer
  ///
  /// In en, this message translates to:
  /// **'Open a video page to sniff'**
  String get snifferAddressHint;

  /// Hint shown in the video sniffer results area
  ///
  /// In en, this message translates to:
  /// **'Open a video page; dynamically loaded m3u8/mp4 streams are auto-detected below.'**
  String get snifferHint;

  /// Empty state of the video sniffer results list
  ///
  /// In en, this message translates to:
  /// **'No video stream detected yet'**
  String get snifferNoResult;

  /// Copy a sniffed video URL
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get snifferCopy;

  /// Play a sniffed video URL with the built-in player
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get snifferPlay;

  /// Status shown when a blob/MSE stream is played inside the WebView instead of an external player
  ///
  /// In en, this message translates to:
  /// **'Playing in page'**
  String get snifferInPagePlaying;

  /// Hint explaining why a blob/MSE stream can only be played inside the page
  ///
  /// In en, this message translates to:
  /// **'This stream is blob/MSE and cannot be opened in an external player; it is now playing inside the page.'**
  String get snifferInPageHint;

  /// Copy the current page URL (for blob/MSE streams that play only in-page)
  ///
  /// In en, this message translates to:
  /// **'Copy page link'**
  String get snifferCopyPageLink;

  /// Clear the sniffed video URL list
  ///
  /// In en, this message translates to:
  /// **'Clear list'**
  String get snifferClear;

  /// Submit button on the sniffer address bar
  ///
  /// In en, this message translates to:
  /// **'Go'**
  String get snifferGo;

  /// Toggle label for deep DOM scanning in the sniffer
  ///
  /// In en, this message translates to:
  /// **'Deep sniff'**
  String get snifferDeep;

  /// Save a sniffed media URL to the download directory
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get snifferSave;

  /// Filter chip: all sniffed media
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get snifferFilterAll;

  /// Filter chip: video only
  ///
  /// In en, this message translates to:
  /// **'Video'**
  String get snifferFilterVideo;

  /// Filter chip: audio only
  ///
  /// In en, this message translates to:
  /// **'Audio'**
  String get snifferFilterAudio;

  /// Filter chip: other media
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get snifferFilterOther;

  /// Placeholder when media size is unknown
  ///
  /// In en, this message translates to:
  /// **'Size unknown'**
  String get snifferSizeUnknown;

  /// Result count badge on the collapsed sniffer results panel handle
  ///
  /// In en, this message translates to:
  /// **'{count} results'**
  String snifferResultCount(int count);

  /// Semantic label of the draggable sniffer results panel handle
  ///
  /// In en, this message translates to:
  /// **'Sniffer results panel; drag up or down to resize, tap to collapse or expand'**
  String get snifferPanelHandle;

  /// Title of the in-parse sniffer fallback screen
  ///
  /// In en, this message translates to:
  /// **'Sniff Resolve'**
  String get snifferResolveTitle;

  /// Status shown while the in-parse sniffer fallback is capturing a stream
  ///
  /// In en, this message translates to:
  /// **'Sniffing the video address…'**
  String get snifferResolving;

  /// Status shown when the in-parse sniffer fallback times out without a direct link
  ///
  /// In en, this message translates to:
  /// **'No direct link captured yet. Keep waiting or cancel.'**
  String get snifferResolveTimeout;

  /// Generic failure suffix
  ///
  /// In en, this message translates to:
  /// **'failed'**
  String get failed;

  /// No description provided for @share.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get share;

  /// No description provided for @shareCopied.
  ///
  /// In en, this message translates to:
  /// **'Copied to clipboard'**
  String get shareCopied;

  /// No description provided for @browserTitle.
  ///
  /// In en, this message translates to:
  /// **'Browser'**
  String get browserTitle;

  /// No description provided for @browserAddressHint.
  ///
  /// In en, this message translates to:
  /// **'Enter URL or search'**
  String get browserAddressHint;

  /// No description provided for @browserBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get browserBack;

  /// No description provided for @browserForward.
  ///
  /// In en, this message translates to:
  /// **'Forward'**
  String get browserForward;

  /// No description provided for @browserRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get browserRefresh;

  /// No description provided for @browserCopyLink.
  ///
  /// In en, this message translates to:
  /// **'Copy link'**
  String get browserCopyLink;

  /// No description provided for @browserShare.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get browserShare;

  /// No description provided for @browserLinkCopied.
  ///
  /// In en, this message translates to:
  /// **'Link copied'**
  String get browserLinkCopied;

  /// Menu item: sync current page cookies to HttpFetcher as verification fallback
  ///
  /// In en, this message translates to:
  /// **'Use this page for verification'**
  String get browserUseAsVerification;

  /// Menu item: open the video sniffer to intercept dynamically loaded streams
  ///
  /// In en, this message translates to:
  /// **'Video sniffer mode'**
  String get browserOpenSniffer;

  /// Snackbar shown after cookies are synced from the built-in browser
  ///
  /// In en, this message translates to:
  /// **'Verification completed using this page\'s cookies'**
  String get browserUseAsVerificationDone;

  /// Shown when InAppWebView is unavailable (e.g. on Web)
  ///
  /// In en, this message translates to:
  /// **'The built-in browser is not available on this platform. Please use an external browser.'**
  String get browserNotAvailable;

  /// Button: open the in-app HttpBrowserScreen for verification
  ///
  /// In en, this message translates to:
  /// **'Open built-in browser'**
  String get openInternalBrowser;

  /// No description provided for @downloadStarted.
  ///
  /// In en, this message translates to:
  /// **'Download started'**
  String get downloadStarted;

  /// No description provided for @downloadEpisodes.
  ///
  /// In en, this message translates to:
  /// **'Download Episodes'**
  String get downloadEpisodes;

  /// No description provided for @episodeRange.
  ///
  /// In en, this message translates to:
  /// **'Episode Range'**
  String get episodeRange;

  /// No description provided for @addToDownload.
  ///
  /// In en, this message translates to:
  /// **'Add to Download'**
  String get addToDownload;

  /// No description provided for @deselectAll.
  ///
  /// In en, this message translates to:
  /// **'Deselect All'**
  String get deselectAll;

  /// Selected episode count
  ///
  /// In en, this message translates to:
  /// **'Selected {selected}/{total}'**
  String selectedCount(Object selected, Object total);

  /// No description provided for @rangeStart.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get rangeStart;

  /// No description provided for @rangeEnd.
  ///
  /// In en, this message translates to:
  /// **'End'**
  String get rangeEnd;

  /// No description provided for @applyRange.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get applyRange;

  /// No description provided for @alreadyDownloaded.
  ///
  /// In en, this message translates to:
  /// **'Already downloaded'**
  String get alreadyDownloaded;

  /// No description provided for @favoriteAdded.
  ///
  /// In en, this message translates to:
  /// **'Added to favorites'**
  String get favoriteAdded;

  /// No description provided for @favoriteRemoved.
  ///
  /// In en, this message translates to:
  /// **'Removed from favorites'**
  String get favoriteRemoved;

  /// No description provided for @aboutApp.
  ///
  /// In en, this message translates to:
  /// **'About App'**
  String get aboutApp;

  /// No description provided for @appVersion.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get appVersion;

  /// No description provided for @privacySettings.
  ///
  /// In en, this message translates to:
  /// **'Privacy Settings'**
  String get privacySettings;

  /// No description provided for @stealthSettings.
  ///
  /// In en, this message translates to:
  /// **'Stealth Settings'**
  String get stealthSettings;

  /// No description provided for @browseLocalTitle.
  ///
  /// In en, this message translates to:
  /// **'Local Files'**
  String get browseLocalTitle;

  /// No description provided for @browseLocalEmpty.
  ///
  /// In en, this message translates to:
  /// **'No readable local files found'**
  String get browseLocalEmpty;

  /// No description provided for @browseLocalScan.
  ///
  /// In en, this message translates to:
  /// **'Scan Files'**
  String get browseLocalScan;

  /// No description provided for @browseLocalFileTypeAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get browseLocalFileTypeAll;

  /// No description provided for @browseLocalFileTypeNovel.
  ///
  /// In en, this message translates to:
  /// **'Novel'**
  String get browseLocalFileTypeNovel;

  /// No description provided for @browseLocalFileTypeComic.
  ///
  /// In en, this message translates to:
  /// **'Comic'**
  String get browseLocalFileTypeComic;

  /// No description provided for @browseLocalFileTypeVideo.
  ///
  /// In en, this message translates to:
  /// **'Video'**
  String get browseLocalFileTypeVideo;

  /// No description provided for @browseLocalSelectFolder.
  ///
  /// In en, this message translates to:
  /// **'Select Folder'**
  String get browseLocalSelectFolder;

  /// No description provided for @browseNetworkTitle.
  ///
  /// In en, this message translates to:
  /// **'Network Files'**
  String get browseNetworkTitle;

  /// No description provided for @browseNetworkUrlHint.
  ///
  /// In en, this message translates to:
  /// **'Enter HTTP file server address'**
  String get browseNetworkUrlHint;

  /// No description provided for @browseNetworkConnect.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get browseNetworkConnect;

  /// No description provided for @browseNetworkEmpty.
  ///
  /// In en, this message translates to:
  /// **'No files found'**
  String get browseNetworkEmpty;

  /// No description provided for @browseNetworkHistory.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get browseNetworkHistory;

  /// No description provided for @browseNetworkParentDir.
  ///
  /// In en, this message translates to:
  /// **'Parent directory'**
  String get browseNetworkParentDir;

  /// No description provided for @browseNetworkFileSize.
  ///
  /// In en, this message translates to:
  /// **'Size'**
  String get browseNetworkFileSize;

  /// No description provided for @scrapeModeGeneral.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get scrapeModeGeneral;

  /// No description provided for @scrapeModeNovel.
  ///
  /// In en, this message translates to:
  /// **'Novel'**
  String get scrapeModeNovel;

  /// No description provided for @scrapeModeComic.
  ///
  /// In en, this message translates to:
  /// **'Comic'**
  String get scrapeModeComic;

  /// No description provided for @scrapeModeVideo.
  ///
  /// In en, this message translates to:
  /// **'Video'**
  String get scrapeModeVideo;

  /// No description provided for @scrapeModeArticle.
  ///
  /// In en, this message translates to:
  /// **'Article'**
  String get scrapeModeArticle;

  /// No description provided for @scrapeUrlHint.
  ///
  /// In en, this message translates to:
  /// **'Enter URL to scrape'**
  String get scrapeUrlHint;

  /// No description provided for @scrapeStart.
  ///
  /// In en, this message translates to:
  /// **'Start Scraping'**
  String get scrapeStart;

  /// No description provided for @scrapeResultTitle.
  ///
  /// In en, this message translates to:
  /// **'Page Title'**
  String get scrapeResultTitle;

  /// No description provided for @scrapeResultLinks.
  ///
  /// In en, this message translates to:
  /// **'All Links'**
  String get scrapeResultLinks;

  /// No description provided for @scrapeResultText.
  ///
  /// In en, this message translates to:
  /// **'Body Text'**
  String get scrapeResultText;

  /// No description provided for @scrapeResultImages.
  ///
  /// In en, this message translates to:
  /// **'Images'**
  String get scrapeResultImages;

  /// No description provided for @scrapeResultVideos.
  ///
  /// In en, this message translates to:
  /// **'Videos'**
  String get scrapeResultVideos;

  /// No description provided for @scrapeOpenInReader.
  ///
  /// In en, this message translates to:
  /// **'Open in Reader'**
  String get scrapeOpenInReader;

  /// No description provided for @scrapeOpenInPlayer.
  ///
  /// In en, this message translates to:
  /// **'Open in Player'**
  String get scrapeOpenInPlayer;

  /// No description provided for @scrapeNoResults.
  ///
  /// In en, this message translates to:
  /// **'No content extracted'**
  String get scrapeNoResults;

  /// No description provided for @scrapeSelectorHint.
  ///
  /// In en, this message translates to:
  /// **'CSS selector (optional)'**
  String get scrapeSelectorHint;

  /// No description provided for @scrapeAdvanced.
  ///
  /// In en, this message translates to:
  /// **'Advanced'**
  String get scrapeAdvanced;

  /// No description provided for @rssFeedUrl.
  ///
  /// In en, this message translates to:
  /// **'Feed URL'**
  String get rssFeedUrl;

  /// No description provided for @rssFeedUrlHint.
  ///
  /// In en, this message translates to:
  /// **'https://example.com/feed.xml'**
  String get rssFeedUrlHint;

  /// No description provided for @rssFeedDescription.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get rssFeedDescription;

  /// No description provided for @rssFeedModule.
  ///
  /// In en, this message translates to:
  /// **'Module'**
  String get rssFeedModule;

  /// No description provided for @rssFeedModuleNone.
  ///
  /// In en, this message translates to:
  /// **'Global (Browse)'**
  String get rssFeedModuleNone;

  /// No description provided for @rssFeedTestConnection.
  ///
  /// In en, this message translates to:
  /// **'Test Connection'**
  String get rssFeedTestConnection;

  /// No description provided for @rssFeedTesting.
  ///
  /// In en, this message translates to:
  /// **'Testing…'**
  String get rssFeedTesting;

  /// No description provided for @rssFeedTestSuccess.
  ///
  /// In en, this message translates to:
  /// **'Connection successful'**
  String get rssFeedTestSuccess;

  /// No description provided for @rssFeedTestFailed.
  ///
  /// In en, this message translates to:
  /// **'Connection failed'**
  String get rssFeedTestFailed;

  /// No description provided for @rssFeedPreview.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get rssFeedPreview;

  /// No description provided for @rssFeedSaved.
  ///
  /// In en, this message translates to:
  /// **'Feed saved'**
  String get rssFeedSaved;

  /// No description provided for @articleDetailAuthor.
  ///
  /// In en, this message translates to:
  /// **'Author'**
  String get articleDetailAuthor;

  /// No description provided for @articleDetailPublishedAt.
  ///
  /// In en, this message translates to:
  /// **'Published'**
  String get articleDetailPublishedAt;

  /// No description provided for @articleDetailReadFull.
  ///
  /// In en, this message translates to:
  /// **'Read Full Article'**
  String get articleDetailReadFull;

  /// No description provided for @articleDetailSource.
  ///
  /// In en, this message translates to:
  /// **'Source'**
  String get articleDetailSource;

  /// No description provided for @articleDetailEmpty.
  ///
  /// In en, this message translates to:
  /// **'Article has no content'**
  String get articleDetailEmpty;

  /// No description provided for @articleReadingSettings.
  ///
  /// In en, this message translates to:
  /// **'Reading Settings'**
  String get articleReadingSettings;

  /// No description provided for @articleFontSize.
  ///
  /// In en, this message translates to:
  /// **'Font Size'**
  String get articleFontSize;

  /// No description provided for @articleLineHeight.
  ///
  /// In en, this message translates to:
  /// **'Line Height'**
  String get articleLineHeight;

  /// No description provided for @articleNightMode.
  ///
  /// In en, this message translates to:
  /// **'Night Mode'**
  String get articleNightMode;

  /// No description provided for @articleContentWidth.
  ///
  /// In en, this message translates to:
  /// **'Content width'**
  String get articleContentWidth;

  /// No description provided for @articleJustify.
  ///
  /// In en, this message translates to:
  /// **'Justify text'**
  String get articleJustify;

  /// No description provided for @articleParagraphSpacing.
  ///
  /// In en, this message translates to:
  /// **'Paragraph spacing'**
  String get articleParagraphSpacing;

  /// No description provided for @articleWidthNarrow.
  ///
  /// In en, this message translates to:
  /// **'Narrow'**
  String get articleWidthNarrow;

  /// No description provided for @articleWidthNormal.
  ///
  /// In en, this message translates to:
  /// **'Normal'**
  String get articleWidthNormal;

  /// No description provided for @articleWidthWide.
  ///
  /// In en, this message translates to:
  /// **'Wide'**
  String get articleWidthWide;

  /// No description provided for @articleFontFamily.
  ///
  /// In en, this message translates to:
  /// **'Font Family'**
  String get articleFontFamily;

  /// No description provided for @fontSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get fontSystem;

  /// No description provided for @fontSerif.
  ///
  /// In en, this message translates to:
  /// **'Serif'**
  String get fontSerif;

  /// No description provided for @fontMono.
  ///
  /// In en, this message translates to:
  /// **'Mono'**
  String get fontMono;

  /// No description provided for @articleLetterSpacing.
  ///
  /// In en, this message translates to:
  /// **'Letter Spacing'**
  String get articleLetterSpacing;

  /// No description provided for @mirrorListTitle.
  ///
  /// In en, this message translates to:
  /// **'Mirror List'**
  String get mirrorListTitle;

  /// No description provided for @mirrorTesting.
  ///
  /// In en, this message translates to:
  /// **'Testing…'**
  String get mirrorTesting;

  /// Mirror speed test result (ms)
  ///
  /// In en, this message translates to:
  /// **'{ms} ms'**
  String mirrorTestResultMs(Object ms);

  /// No description provided for @mirrorTestFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get mirrorTestFailed;

  /// No description provided for @mirrorCurrent.
  ///
  /// In en, this message translates to:
  /// **'Current'**
  String get mirrorCurrent;

  /// No description provided for @mirrorSwitched.
  ///
  /// In en, this message translates to:
  /// **'Mirror switched'**
  String get mirrorSwitched;

  /// No description provided for @mirrorStealthLocked.
  ///
  /// In en, this message translates to:
  /// **'Stealth mode is locked on'**
  String get mirrorStealthLocked;

  /// No description provided for @mirrorNoMirrors.
  ///
  /// In en, this message translates to:
  /// **'No mirrors configured'**
  String get mirrorNoMirrors;

  /// No description provided for @collectApiImportTitle.
  ///
  /// In en, this message translates to:
  /// **'Collect API Import'**
  String get collectApiImportTitle;

  /// No description provided for @collectApiUrlHint.
  ///
  /// In en, this message translates to:
  /// **'https://example.com/api.php/provide/vod/'**
  String get collectApiUrlHint;

  /// No description provided for @collectApiDetect.
  ///
  /// In en, this message translates to:
  /// **'Detect'**
  String get collectApiDetect;

  /// No description provided for @collectApiDetecting.
  ///
  /// In en, this message translates to:
  /// **'Detecting…'**
  String get collectApiDetecting;

  /// No description provided for @collectApiDetectSuccess.
  ///
  /// In en, this message translates to:
  /// **'Detection successful'**
  String get collectApiDetectSuccess;

  /// No description provided for @collectApiDetectFailed.
  ///
  /// In en, this message translates to:
  /// **'Detection failed'**
  String get collectApiDetectFailed;

  /// No description provided for @collectApiSiteName.
  ///
  /// In en, this message translates to:
  /// **'Site Name'**
  String get collectApiSiteName;

  /// No description provided for @collectApiCategories.
  ///
  /// In en, this message translates to:
  /// **'Categories'**
  String get collectApiCategories;

  /// No description provided for @collectApiPreview.
  ///
  /// In en, this message translates to:
  /// **'Content Preview'**
  String get collectApiPreview;

  /// No description provided for @collectApiSourceName.
  ///
  /// In en, this message translates to:
  /// **'Source Name'**
  String get collectApiSourceName;

  /// No description provided for @collectApiSourceId.
  ///
  /// In en, this message translates to:
  /// **'Source ID'**
  String get collectApiSourceId;

  /// No description provided for @collectApiSave.
  ///
  /// In en, this message translates to:
  /// **'Save Source'**
  String get collectApiSave;

  /// No description provided for @collectApiSaved.
  ///
  /// In en, this message translates to:
  /// **'Source saved'**
  String get collectApiSaved;

  /// No description provided for @collectApiInvalidUrl.
  ///
  /// In en, this message translates to:
  /// **'Invalid URL'**
  String get collectApiInvalidUrl;

  /// No description provided for @sourceImportFromUrl.
  ///
  /// In en, this message translates to:
  /// **'Import from URL'**
  String get sourceImportFromUrl;

  /// No description provided for @sourceImportFromFile.
  ///
  /// In en, this message translates to:
  /// **'Import from File'**
  String get sourceImportFromFile;

  /// No description provided for @sourceImportFromJson.
  ///
  /// In en, this message translates to:
  /// **'Enter JSON Manually'**
  String get sourceImportFromJson;

  /// No description provided for @sourceImportUrlHint.
  ///
  /// In en, this message translates to:
  /// **'URL of source JSON'**
  String get sourceImportUrlHint;

  /// No description provided for @sourceImportFilePicker.
  ///
  /// In en, this message translates to:
  /// **'Select JSON File'**
  String get sourceImportFilePicker;

  /// No description provided for @sourceImportJsonHint.
  ///
  /// In en, this message translates to:
  /// **'Paste source JSON config'**
  String get sourceImportJsonHint;

  /// No description provided for @sourceImportValidate.
  ///
  /// In en, this message translates to:
  /// **'Validate'**
  String get sourceImportValidate;

  /// No description provided for @sourceImportValid.
  ///
  /// In en, this message translates to:
  /// **'Validation passed'**
  String get sourceImportValid;

  /// No description provided for @sourceImportInvalid.
  ///
  /// In en, this message translates to:
  /// **'Validation failed'**
  String get sourceImportInvalid;

  /// No description provided for @sourceImportErrors.
  ///
  /// In en, this message translates to:
  /// **'Errors'**
  String get sourceImportErrors;

  /// No description provided for @sourceImportCollectApiDetected.
  ///
  /// In en, this message translates to:
  /// **'MacCMS Collect API detected'**
  String get sourceImportCollectApiDetected;

  /// No description provided for @sourceImportCollectApiRedirect.
  ///
  /// In en, this message translates to:
  /// **'Use Collect API Import'**
  String get sourceImportCollectApiRedirect;

  /// No description provided for @sourceImportSaved.
  ///
  /// In en, this message translates to:
  /// **'Source imported'**
  String get sourceImportSaved;

  /// No description provided for @contentImportTitle.
  ///
  /// In en, this message translates to:
  /// **'Import Content'**
  String get contentImportTitle;

  /// No description provided for @contentImportSelectFile.
  ///
  /// In en, this message translates to:
  /// **'Select File'**
  String get contentImportSelectFile;

  /// No description provided for @contentImportSupportedFormats.
  ///
  /// In en, this message translates to:
  /// **'Supported Formats'**
  String get contentImportSupportedFormats;

  /// No description provided for @contentImportHistory.
  ///
  /// In en, this message translates to:
  /// **'Import History'**
  String get contentImportHistory;

  /// No description provided for @contentImportEmpty.
  ///
  /// In en, this message translates to:
  /// **'No imports yet'**
  String get contentImportEmpty;

  /// No description provided for @contentImportOpened.
  ///
  /// In en, this message translates to:
  /// **'Opened'**
  String get contentImportOpened;

  /// No description provided for @comicDirImported.
  ///
  /// In en, this message translates to:
  /// **'Imported comic: {name}'**
  String comicDirImported(Object name);

  /// Novel folder import result toast
  ///
  /// In en, this message translates to:
  /// **'Imported novel: {name} ({count} chapters)'**
  String novelDirImported(String name, int count);

  /// No description provided for @contentImportNovelFormats.
  ///
  /// In en, this message translates to:
  /// **'.txt, .epub'**
  String get contentImportNovelFormats;

  /// No description provided for @contentImportComicFormats.
  ///
  /// In en, this message translates to:
  /// **'.cbz, image folder'**
  String get contentImportComicFormats;

  /// No description provided for @contentImportMediaFormats.
  ///
  /// In en, this message translates to:
  /// **'.mp4, .mkv, .avi'**
  String get contentImportMediaFormats;

  /// No description provided for @downloadedGroupChapters.
  ///
  /// In en, this message translates to:
  /// **'Chapters'**
  String get downloadedGroupChapters;

  /// No description provided for @downloadedGroupFormat.
  ///
  /// In en, this message translates to:
  /// **'Format'**
  String get downloadedGroupFormat;

  /// No description provided for @downloadedGroupOpen.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get downloadedGroupOpen;

  /// No description provided for @downloadedGroupFileMissing.
  ///
  /// In en, this message translates to:
  /// **'File not found'**
  String get downloadedGroupFileMissing;

  /// No description provided for @downloadedGroupDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete this download?'**
  String get downloadedGroupDeleteConfirm;

  /// No description provided for @downloadBatches.
  ///
  /// In en, this message translates to:
  /// **'{count} batches'**
  String downloadBatches(Object count);

  /// No description provided for @downloadBatchLabel.
  ///
  /// In en, this message translates to:
  /// **'Batch {index}'**
  String downloadBatchLabel(Object index);

  /// No description provided for @browsePageTitle.
  ///
  /// In en, this message translates to:
  /// **'Browse'**
  String get browsePageTitle;

  /// No description provided for @rssSubscribeTitle.
  ///
  /// In en, this message translates to:
  /// **'RSS Subscriptions'**
  String get rssSubscribeTitle;

  /// No description provided for @emptyRssSubscribe.
  ///
  /// In en, this message translates to:
  /// **'No RSS subscriptions yet'**
  String get emptyRssSubscribe;

  /// No description provided for @addSubscription.
  ///
  /// In en, this message translates to:
  /// **'Add Subscription'**
  String get addSubscription;

  /// No description provided for @subscribeAddressLabel.
  ///
  /// In en, this message translates to:
  /// **'Subscribe URL'**
  String get subscribeAddressLabel;

  /// No description provided for @rsshubRoutesTitle.
  ///
  /// In en, this message translates to:
  /// **'RSSHub Routes'**
  String get rsshubRoutesTitle;

  /// No description provided for @rsshubRouteRecommend.
  ///
  /// In en, this message translates to:
  /// **'RSSHub Route Recommendations'**
  String get rsshubRouteRecommend;

  /// No description provided for @rsshubRouteHint.
  ///
  /// In en, this message translates to:
  /// **'Tap a route to auto-fill with RSSHub instance URL'**
  String get rsshubRouteHint;

  /// No description provided for @novelLibraryName.
  ///
  /// In en, this message translates to:
  /// **'Novel Library'**
  String get novelLibraryName;

  /// No description provided for @mediaLibraryName.
  ///
  /// In en, this message translates to:
  /// **'Media Library'**
  String get mediaLibraryName;

  /// No description provided for @comicLibraryName.
  ///
  /// In en, this message translates to:
  /// **'Comic Library'**
  String get comicLibraryName;

  /// No description provided for @emptySubscribe.
  ///
  /// In en, this message translates to:
  /// **'No subscriptions'**
  String get emptySubscribe;

  /// No description provided for @sourceListTab.
  ///
  /// In en, this message translates to:
  /// **'Source List'**
  String get sourceListTab;

  /// No description provided for @networkImportTab.
  ///
  /// In en, this message translates to:
  /// **'Network Import'**
  String get networkImportTab;

  /// No description provided for @localImportTab.
  ///
  /// In en, this message translates to:
  /// **'Local Import'**
  String get localImportTab;

  /// No description provided for @sourceListEmpty.
  ///
  /// In en, this message translates to:
  /// **'No sources'**
  String get sourceListEmpty;

  /// No description provided for @networkImportHint.
  ///
  /// In en, this message translates to:
  /// **'Paste source URL (.json/.txt)'**
  String get networkImportHint;

  /// No description provided for @networkImportPasteHint.
  ///
  /// In en, this message translates to:
  /// **'Paste URL and tap to fetch'**
  String get networkImportPasteHint;

  /// No description provided for @localImportTitle.
  ///
  /// In en, this message translates to:
  /// **'Import from Local File'**
  String get localImportTitle;

  /// No description provided for @localImportFormats.
  ///
  /// In en, this message translates to:
  /// **'Supports .json, .txt, .xml'**
  String get localImportFormats;

  /// No description provided for @selectFile.
  ///
  /// In en, this message translates to:
  /// **'Select File'**
  String get selectFile;

  /// No description provided for @selectFolder.
  ///
  /// In en, this message translates to:
  /// **'Select Folder'**
  String get selectFolder;

  /// No description provided for @noLocalSource.
  ///
  /// In en, this message translates to:
  /// **'No source files found'**
  String get noLocalSource;

  /// No description provided for @localImportHint.
  ///
  /// In en, this message translates to:
  /// **'Pick a single file or a folder to scan for source files (.json/.txt/.xml)'**
  String get localImportHint;

  /// Import preview title showing number of scanned files
  ///
  /// In en, this message translates to:
  /// **'{count} files found'**
  String importPreviewTitle(Object count);

  /// Button to confirm importing selected sources
  ///
  /// In en, this message translates to:
  /// **'Confirm import'**
  String get confirmImport;

  /// Label showing count of selected items for import
  ///
  /// In en, this message translates to:
  /// **'{count} selected'**
  String importSelectedCount(Object count);

  /// Banner in local import preview when importing on a type-specific source page
  ///
  /// In en, this message translates to:
  /// **'Only {type} sources will be imported'**
  String importTypeOnly(Object type);

  /// Suffix in local import preview banner showing how many other-type sources were skipped
  ///
  /// In en, this message translates to:
  /// **'{count} other-type source(s) skipped'**
  String importTypeFiltered(int count);

  /// Snackbar when a type-specific import found no matching-type sources
  ///
  /// In en, this message translates to:
  /// **'No {type} sources found in the selection ({count} other-type source(s) skipped)'**
  String importNoMatchingType(Object type, int count);

  /// Snackbar after batch import showing success/total count
  ///
  /// In en, this message translates to:
  /// **'Imported {success}/{total} sources'**
  String sourceImportResult(int success, int total);

  /// Batch import preview hint
  ///
  /// In en, this message translates to:
  /// **'Recognized {count} sources. Select to batch import (includes novel / media / comic).'**
  String batchImportHint(int count);

  /// Shown when no valid source could be parsed
  ///
  /// In en, this message translates to:
  /// **'No valid source recognized (novel / media / comic).'**
  String get sourceUnrecognized;

  /// Cross-module import banner
  ///
  /// In en, this message translates to:
  /// **'Sources will be sorted into their modules automatically ({count} from other modules).'**
  String importDistributedHint(int count);

  /// No description provided for @settingsGroupDownload.
  ///
  /// In en, this message translates to:
  /// **'Download Management'**
  String get settingsGroupDownload;

  /// No description provided for @settingsGroupTools.
  ///
  /// In en, this message translates to:
  /// **'Tools'**
  String get settingsGroupTools;

  /// No description provided for @settingsGroupPlugins.
  ///
  /// In en, this message translates to:
  /// **'Plugins'**
  String get settingsGroupPlugins;

  /// No description provided for @settingsGroupData.
  ///
  /// In en, this message translates to:
  /// **'Data'**
  String get settingsGroupData;

  /// No description provided for @settingsGroupPlayback.
  ///
  /// In en, this message translates to:
  /// **'Playback & Reading'**
  String get settingsGroupPlayback;

  /// No description provided for @settingsGroupContentSources.
  ///
  /// In en, this message translates to:
  /// **'Content Sources'**
  String get settingsGroupContentSources;

  /// No description provided for @settingsGroupNetwork.
  ///
  /// In en, this message translates to:
  /// **'Network'**
  String get settingsGroupNetwork;

  /// No description provided for @settingsGroupSubscriptions.
  ///
  /// In en, this message translates to:
  /// **'Subscriptions & Notifications'**
  String get settingsGroupSubscriptions;

  /// No description provided for @settingsGroupDownloadsData.
  ///
  /// In en, this message translates to:
  /// **'Downloads & Data'**
  String get settingsGroupDownloadsData;

  /// No description provided for @webScrapeSetting.
  ///
  /// In en, this message translates to:
  /// **'Web Scraping'**
  String get webScrapeSetting;

  /// No description provided for @webScrapeSettingSameAsBrowse.
  ///
  /// In en, this message translates to:
  /// **'Same as browse page web scraping'**
  String get webScrapeSettingSameAsBrowse;

  /// No description provided for @subscriptionManagement.
  ///
  /// In en, this message translates to:
  /// **'Subscription Management'**
  String get subscriptionManagement;

  /// No description provided for @subscriptionManagementDesc.
  ///
  /// In en, this message translates to:
  /// **'Unified management by type, manage RSS subscriptions'**
  String get subscriptionManagementDesc;

  /// No description provided for @rsshubInstance.
  ///
  /// In en, this message translates to:
  /// **'RSSHub Instance'**
  String get rsshubInstance;

  /// No description provided for @rsshubInstanceDesc.
  ///
  /// In en, this message translates to:
  /// **'Self-hosted RSSHub address'**
  String get rsshubInstanceDesc;

  /// No description provided for @rsshubSettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'RSSHub Settings'**
  String get rsshubSettingsTitle;

  /// No description provided for @rsshubSettingsDesc.
  ///
  /// In en, this message translates to:
  /// **'Choose a preset or self-hosted instance'**
  String get rsshubSettingsDesc;

  /// No description provided for @rssNotifications.
  ///
  /// In en, this message translates to:
  /// **'RSS update notifications'**
  String get rssNotifications;

  /// No description provided for @rssNotificationsDesc.
  ///
  /// In en, this message translates to:
  /// **'Detect new items in subscriptions'**
  String get rssNotificationsDesc;

  /// No description provided for @rssNotificationsTitle.
  ///
  /// In en, this message translates to:
  /// **'RSS Update Notifications'**
  String get rssNotificationsTitle;

  /// No description provided for @rssNotificationEnabled.
  ///
  /// In en, this message translates to:
  /// **'Enable update detection'**
  String get rssNotificationEnabled;

  /// No description provided for @rssNotificationEnabledSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Poll subscriptions periodically while in foreground'**
  String get rssNotificationEnabledSubtitle;

  /// No description provided for @rssUpdateInterval.
  ///
  /// In en, this message translates to:
  /// **'Check interval'**
  String get rssUpdateInterval;

  /// No description provided for @interval15m.
  ///
  /// In en, this message translates to:
  /// **'15 minutes'**
  String get interval15m;

  /// No description provided for @interval30m.
  ///
  /// In en, this message translates to:
  /// **'30 minutes'**
  String get interval30m;

  /// No description provided for @interval1h.
  ///
  /// In en, this message translates to:
  /// **'1 hour'**
  String get interval1h;

  /// No description provided for @interval2h.
  ///
  /// In en, this message translates to:
  /// **'2 hours'**
  String get interval2h;

  /// No description provided for @interval4h.
  ///
  /// In en, this message translates to:
  /// **'4 hours'**
  String get interval4h;

  /// No description provided for @rssCheckNow.
  ///
  /// In en, this message translates to:
  /// **'Check now'**
  String get rssCheckNow;

  /// No description provided for @rssTotalNewCount.
  ///
  /// In en, this message translates to:
  /// **'Unread: {count}'**
  String rssTotalNewCount(int count);

  /// No description provided for @rssCheckDone.
  ///
  /// In en, this message translates to:
  /// **'Check complete'**
  String get rssCheckDone;

  /// No description provided for @rssNotificationHint.
  ///
  /// In en, this message translates to:
  /// **'Polls only while the app is in foreground; new items show an unread count badge on the feed card.'**
  String get rssNotificationHint;

  /// No description provided for @currentInstance.
  ///
  /// In en, this message translates to:
  /// **'Current Instance'**
  String get currentInstance;

  /// No description provided for @presetInstances.
  ///
  /// In en, this message translates to:
  /// **'Preset Instances'**
  String get presetInstances;

  /// No description provided for @presetInstanceOfficial.
  ///
  /// In en, this message translates to:
  /// **'Official'**
  String get presetInstanceOfficial;

  /// No description provided for @customInstance.
  ///
  /// In en, this message translates to:
  /// **'Custom Instance'**
  String get customInstance;

  /// No description provided for @restoreDefault.
  ///
  /// In en, this message translates to:
  /// **'Restore Default'**
  String get restoreDefault;

  /// No description provided for @rsshubTestAll.
  ///
  /// In en, this message translates to:
  /// **'Test all'**
  String get rsshubTestAll;

  /// No description provided for @rsshubTestingAll.
  ///
  /// In en, this message translates to:
  /// **'Testing all instances…'**
  String get rsshubTestingAll;

  /// No description provided for @rsshubTestAllDone.
  ///
  /// In en, this message translates to:
  /// **'Tested {count} instances'**
  String rsshubTestAllDone(Object count);

  /// No description provided for @saveCustomInstance.
  ///
  /// In en, this message translates to:
  /// **'Save Custom'**
  String get saveCustomInstance;

  /// No description provided for @instanceTestFail.
  ///
  /// In en, this message translates to:
  /// **'Test failed'**
  String get instanceTestFail;

  /// No description provided for @instanceTestSuccess.
  ///
  /// In en, this message translates to:
  /// **'Connection successful'**
  String get instanceTestSuccess;

  /// No description provided for @rsshubTroubleshoot.
  ///
  /// In en, this message translates to:
  /// **'Troubleshooting'**
  String get rsshubTroubleshoot;

  /// No description provided for @rsshubTroubleshootHint.
  ///
  /// In en, this message translates to:
  /// **'If you encounter issues:\n• Ensure the address is accessible and not blocked by firewall\n• Try switching to a different preset instance\n• Self-hosted users please check if service is running normally'**
  String get rsshubTroubleshootHint;

  /// No description provided for @danmakuSettings.
  ///
  /// In en, this message translates to:
  /// **'DanDanPlay Danmaku'**
  String get danmakuSettings;

  /// No description provided for @danmakuSettingsDesc.
  ///
  /// In en, this message translates to:
  /// **'Danmaku configuration'**
  String get danmakuSettingsDesc;

  /// No description provided for @danmakuConfigTitle.
  ///
  /// In en, this message translates to:
  /// **'DanDanPlay Danmaku Config'**
  String get danmakuConfigTitle;

  /// No description provided for @unconfigured.
  ///
  /// In en, this message translates to:
  /// **'Unconfigured'**
  String get unconfigured;

  /// No description provided for @configured.
  ///
  /// In en, this message translates to:
  /// **'Configured'**
  String get configured;

  /// No description provided for @appIdLabel.
  ///
  /// In en, this message translates to:
  /// **'AppId'**
  String get appIdLabel;

  /// No description provided for @appIdHint.
  ///
  /// In en, this message translates to:
  /// **'Enter AppId'**
  String get appIdHint;

  /// No description provided for @appSecretLabel.
  ///
  /// In en, this message translates to:
  /// **'AppSecret'**
  String get appSecretLabel;

  /// No description provided for @appSecretHint.
  ///
  /// In en, this message translates to:
  /// **'Enter AppSecret'**
  String get appSecretHint;

  /// No description provided for @saveDanmaku.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get saveDanmaku;

  /// No description provided for @danmakuDesc.
  ///
  /// In en, this message translates to:
  /// **'Get your AppId and AppSecret from https://daplay.danmaku.net. After configuration, danmaku will appear in the player.'**
  String get danmakuDesc;

  /// No description provided for @pluginManagement.
  ///
  /// In en, this message translates to:
  /// **'Manage Plugins'**
  String get pluginManagement;

  /// No description provided for @dataImportExport.
  ///
  /// In en, this message translates to:
  /// **'Import/Export'**
  String get dataImportExport;

  /// No description provided for @dataImportExportTitle.
  ///
  /// In en, this message translates to:
  /// **'Import/Export'**
  String get dataImportExportTitle;

  /// No description provided for @importData.
  ///
  /// In en, this message translates to:
  /// **'Import Data'**
  String get importData;

  /// No description provided for @importDataDesc.
  ///
  /// In en, this message translates to:
  /// **'Import subscriptions, plugins and progress'**
  String get importDataDesc;

  /// No description provided for @exportData.
  ///
  /// In en, this message translates to:
  /// **'Export Data'**
  String get exportData;

  /// No description provided for @exportDataDesc.
  ///
  /// In en, this message translates to:
  /// **'Export all data to file'**
  String get exportDataDesc;

  /// No description provided for @exportSubscription.
  ///
  /// In en, this message translates to:
  /// **'Export Subscriptions'**
  String get exportSubscription;

  /// No description provided for @exportSubscriptionDesc.
  ///
  /// In en, this message translates to:
  /// **'Export only RSS subscriptions'**
  String get exportSubscriptionDesc;

  /// No description provided for @exportPlugins.
  ///
  /// In en, this message translates to:
  /// **'Export Plugins'**
  String get exportPlugins;

  /// No description provided for @exportPluginsDesc.
  ///
  /// In en, this message translates to:
  /// **'Export plugin configurations'**
  String get exportPluginsDesc;

  /// No description provided for @selectExportFolder.
  ///
  /// In en, this message translates to:
  /// **'Select Export Folder'**
  String get selectExportFolder;

  /// No description provided for @exportFolderCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom export folder supported'**
  String get exportFolderCustom;

  /// No description provided for @downloadListTab.
  ///
  /// In en, this message translates to:
  /// **'Download List'**
  String get downloadListTab;

  /// No description provided for @downloadedListTab.
  ///
  /// In en, this message translates to:
  /// **'Downloaded'**
  String get downloadedListTab;

  /// No description provided for @maxConcurrentDownloads.
  ///
  /// In en, this message translates to:
  /// **'Max Concurrent Downloads'**
  String get maxConcurrentDownloads;

  /// No description provided for @maxConcurrentDownloadsDesc.
  ///
  /// In en, this message translates to:
  /// **'Number of simultaneous downloads'**
  String get maxConcurrentDownloadsDesc;

  /// No description provided for @downloadPath.
  ///
  /// In en, this message translates to:
  /// **'Download Path'**
  String get downloadPath;

  /// No description provided for @folderImportOhosUnsupported.
  ///
  /// In en, this message translates to:
  /// **'Folder import isn\'t supported on HarmonyOS yet. Use file import instead.'**
  String get folderImportOhosUnsupported;

  /// No description provided for @folderImportCopyProgress.
  ///
  /// In en, this message translates to:
  /// **'Importing folder'**
  String get folderImportCopyProgress;

  /// No description provided for @folderImportCopyProgressHint.
  ///
  /// In en, this message translates to:
  /// **'Copying into app storage. Keep the app open.'**
  String get folderImportCopyProgressHint;

  /// No description provided for @folderImportCopyFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t copy the folder. Please try again.'**
  String get folderImportCopyFailed;

  /// No description provided for @downloadPathSet.
  ///
  /// In en, this message translates to:
  /// **'Download path updated'**
  String get downloadPathSet;

  /// No description provided for @contentImportActions.
  ///
  /// In en, this message translates to:
  /// **'Actions'**
  String get contentImportActions;

  /// No description provided for @downloaderType.
  ///
  /// In en, this message translates to:
  /// **'Downloader'**
  String get downloaderType;

  /// No description provided for @downloaderInternal.
  ///
  /// In en, this message translates to:
  /// **'Built-in Downloader'**
  String get downloaderInternal;

  /// No description provided for @downloaderExternal.
  ///
  /// In en, this message translates to:
  /// **'External Downloader'**
  String get downloaderExternal;

  /// No description provided for @threadCount.
  ///
  /// In en, this message translates to:
  /// **'Thread Count'**
  String get threadCount;

  /// No description provided for @threadCountDesc.
  ///
  /// In en, this message translates to:
  /// **'Number of download threads'**
  String get threadCountDesc;

  /// No description provided for @comicFormatSetting.
  ///
  /// In en, this message translates to:
  /// **'Comic Format'**
  String get comicFormatSetting;

  /// No description provided for @novelFormatSetting.
  ///
  /// In en, this message translates to:
  /// **'Novel Format'**
  String get novelFormatSetting;

  /// No description provided for @downloadTabsAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get downloadTabsAll;

  /// No description provided for @downloadTabsNovel.
  ///
  /// In en, this message translates to:
  /// **'Novel'**
  String get downloadTabsNovel;

  /// No description provided for @downloadTabsMedia.
  ///
  /// In en, this message translates to:
  /// **'Media'**
  String get downloadTabsMedia;

  /// No description provided for @downloadTabsComic.
  ///
  /// In en, this message translates to:
  /// **'Comic'**
  String get downloadTabsComic;

  /// No description provided for @downloadedTabsAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get downloadedTabsAll;

  /// No description provided for @downloadedTabsNovel.
  ///
  /// In en, this message translates to:
  /// **'Novel'**
  String get downloadedTabsNovel;

  /// No description provided for @downloadedTabsMedia.
  ///
  /// In en, this message translates to:
  /// **'Media'**
  String get downloadedTabsMedia;

  /// No description provided for @downloadedTabsComic.
  ///
  /// In en, this message translates to:
  /// **'Comic'**
  String get downloadedTabsComic;

  /// No description provided for @downloadedTabsArchived.
  ///
  /// In en, this message translates to:
  /// **'Archived'**
  String get downloadedTabsArchived;

  /// No description provided for @noDownloads.
  ///
  /// In en, this message translates to:
  /// **'No downloads'**
  String get noDownloads;

  /// No description provided for @downloadPause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get downloadPause;

  /// No description provided for @downloadResume.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get downloadResume;

  /// No description provided for @sourceCategoryNovel.
  ///
  /// In en, this message translates to:
  /// **'Novel'**
  String get sourceCategoryNovel;

  /// No description provided for @sourceCategoryMedia.
  ///
  /// In en, this message translates to:
  /// **'Media'**
  String get sourceCategoryMedia;

  /// No description provided for @sourceCategoryComic.
  ///
  /// In en, this message translates to:
  /// **'Comic'**
  String get sourceCategoryComic;

  /// Empty state message for a source category tab
  ///
  /// In en, this message translates to:
  /// **'No {category} sources'**
  String sourceCategoryEmpty(Object category);

  /// RSSHub instance latency in milliseconds
  ///
  /// In en, this message translates to:
  /// **'{ms}ms'**
  String rsshubLatencyMs(Object ms);

  /// No description provided for @rsshubLatencyFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get rsshubLatencyFailed;

  /// No description provided for @downloaderSelectTitle.
  ///
  /// In en, this message translates to:
  /// **'Downloader Selection'**
  String get downloaderSelectTitle;

  /// No description provided for @comicFormatSelectTitle.
  ///
  /// In en, this message translates to:
  /// **'Comic Format'**
  String get comicFormatSelectTitle;

  /// No description provided for @comicFormatJpg.
  ///
  /// In en, this message translates to:
  /// **'Single Page JPG'**
  String get comicFormatJpg;

  /// No description provided for @comicFormatPng.
  ///
  /// In en, this message translates to:
  /// **'Single Page PNG'**
  String get comicFormatPng;

  /// No description provided for @comicFormatCbz.
  ///
  /// In en, this message translates to:
  /// **'CBZ Archive'**
  String get comicFormatCbz;

  /// No description provided for @novelFormatSelectTitle.
  ///
  /// In en, this message translates to:
  /// **'Novel Format'**
  String get novelFormatSelectTitle;

  /// No description provided for @novelFormatTxt.
  ///
  /// In en, this message translates to:
  /// **'TXT'**
  String get novelFormatTxt;

  /// No description provided for @novelFormatEpub.
  ///
  /// In en, this message translates to:
  /// **'EPUB'**
  String get novelFormatEpub;

  /// No description provided for @rsshubRouteBilibiliBangumi.
  ///
  /// In en, this message translates to:
  /// **'Bilibili Bangumi'**
  String get rsshubRouteBilibiliBangumi;

  /// No description provided for @rsshubRouteBilibiliBangumiPath.
  ///
  /// In en, this message translates to:
  /// **'/bilibili/bangumi/media/:mediaid'**
  String get rsshubRouteBilibiliBangumiPath;

  /// No description provided for @rsshubRouteBilibiliMangaUpdate.
  ///
  /// In en, this message translates to:
  /// **'Bilibili Manga Update'**
  String get rsshubRouteBilibiliMangaUpdate;

  /// No description provided for @rsshubRouteBilibiliMangaUpdatePath.
  ///
  /// In en, this message translates to:
  /// **'/bilibili/manga/update/:comicid'**
  String get rsshubRouteBilibiliMangaUpdatePath;

  /// No description provided for @rsshubRouteBilibiliUserVideo.
  ///
  /// In en, this message translates to:
  /// **'Bilibili User Videos'**
  String get rsshubRouteBilibiliUserVideo;

  /// No description provided for @rsshubRouteBilibiliUserVideoPath.
  ///
  /// In en, this message translates to:
  /// **'/bilibili/user/video/:uid'**
  String get rsshubRouteBilibiliUserVideoPath;

  /// No description provided for @rsshubRouteBilibiliRanking.
  ///
  /// In en, this message translates to:
  /// **'Bilibili Ranking'**
  String get rsshubRouteBilibiliRanking;

  /// No description provided for @rsshubRouteBilibiliRankingPath.
  ///
  /// In en, this message translates to:
  /// **'/bilibili/partion/ranking/:tid/:days?'**
  String get rsshubRouteBilibiliRankingPath;

  /// No description provided for @rsshubRouteYoutubeChannel.
  ///
  /// In en, this message translates to:
  /// **'YouTube Channel'**
  String get rsshubRouteYoutubeChannel;

  /// No description provided for @rsshubRouteYoutubeChannelPath.
  ///
  /// In en, this message translates to:
  /// **'/youtube/channel/:id'**
  String get rsshubRouteYoutubeChannelPath;

  /// No description provided for @rsshubRouteTwitterUser.
  ///
  /// In en, this message translates to:
  /// **'Twitter User'**
  String get rsshubRouteTwitterUser;

  /// No description provided for @rsshubRouteLinovelib.
  ///
  /// In en, this message translates to:
  /// **'Linovelib'**
  String get rsshubRouteLinovelib;

  /// No description provided for @rsshubRouteSfacg.
  ///
  /// In en, this message translates to:
  /// **'SFACG'**
  String get rsshubRouteSfacg;

  /// No description provided for @importMediaTitle.
  ///
  /// In en, this message translates to:
  /// **'Import Media'**
  String get importMediaTitle;

  /// No description provided for @importMediaFormatsHint.
  ///
  /// In en, this message translates to:
  /// **'Supports mp4, mkv, avi, mov and common video formats'**
  String get importMediaFormatsHint;

  /// No description provided for @importMediaPickFile.
  ///
  /// In en, this message translates to:
  /// **'Select Video File'**
  String get importMediaPickFile;

  /// No description provided for @importMediaPickFolder.
  ///
  /// In en, this message translates to:
  /// **'Select Video Folder'**
  String get importMediaPickFolder;

  /// No description provided for @importNovelTitle.
  ///
  /// In en, this message translates to:
  /// **'Import Novel'**
  String get importNovelTitle;

  /// No description provided for @importNovelFormatsHint.
  ///
  /// In en, this message translates to:
  /// **'Supports .txt / .epub files and archives (.zip / .cbz / .rar / .7z) containing them'**
  String get importNovelFormatsHint;

  /// No description provided for @novelArchiveImported.
  ///
  /// In en, this message translates to:
  /// **'archive(s) unpacked'**
  String get novelArchiveImported;

  /// No description provided for @importNovelPickFile.
  ///
  /// In en, this message translates to:
  /// **'Select File'**
  String get importNovelPickFile;

  /// No description provided for @importNovelPickFolder.
  ///
  /// In en, this message translates to:
  /// **'Select Folder'**
  String get importNovelPickFolder;

  /// No description provided for @importComicTitle.
  ///
  /// In en, this message translates to:
  /// **'Import Comic'**
  String get importComicTitle;

  /// No description provided for @importComicFormatsHint.
  ///
  /// In en, this message translates to:
  /// **'Supports cbz, cbr, cbt and common comic archive formats'**
  String get importComicFormatsHint;

  /// No description provided for @importComicPickFile.
  ///
  /// In en, this message translates to:
  /// **'Select Comic File'**
  String get importComicPickFile;

  /// No description provided for @importComicPickFolder.
  ///
  /// In en, this message translates to:
  /// **'Select Comic Folder'**
  String get importComicPickFolder;

  /// No description provided for @novelBrightness.
  ///
  /// In en, this message translates to:
  /// **'Brightness'**
  String get novelBrightness;

  /// No description provided for @playerLock.
  ///
  /// In en, this message translates to:
  /// **'Lock'**
  String get playerLock;

  /// No description provided for @playerUnlock.
  ///
  /// In en, this message translates to:
  /// **'Unlock'**
  String get playerUnlock;

  /// No description provided for @playerAutoPlayNext.
  ///
  /// In en, this message translates to:
  /// **'Auto-play next'**
  String get playerAutoPlayNext;

  /// No description provided for @playerAddToQueue.
  ///
  /// In en, this message translates to:
  /// **'Add to queue'**
  String get playerAddToQueue;

  /// No description provided for @playerPlayNext.
  ///
  /// In en, this message translates to:
  /// **'Play next'**
  String get playerPlayNext;

  /// No description provided for @playerQueue.
  ///
  /// In en, this message translates to:
  /// **'Play queue'**
  String get playerQueue;

  /// No description provided for @playerQueueEmpty.
  ///
  /// In en, this message translates to:
  /// **'Queue is empty'**
  String get playerQueueEmpty;

  /// No description provided for @playerQueueAdded.
  ///
  /// In en, this message translates to:
  /// **'Added to queue'**
  String get playerQueueAdded;

  /// No description provided for @playerQueuePlayNextAdded.
  ///
  /// In en, this message translates to:
  /// **'Set as next'**
  String get playerQueuePlayNextAdded;

  /// No description provided for @playerQueueCleared.
  ///
  /// In en, this message translates to:
  /// **'Queue cleared'**
  String get playerQueueCleared;

  /// No description provided for @playerQueueRemoved.
  ///
  /// In en, this message translates to:
  /// **'Removed from queue'**
  String get playerQueueRemoved;

  /// No description provided for @playerQueueNoEpisodes.
  ///
  /// In en, this message translates to:
  /// **'No episodes available'**
  String get playerQueueNoEpisodes;

  /// No description provided for @playerQueueLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load next work, auto-play stopped'**
  String get playerQueueLoadFailed;

  /// Shown while fetching the next queued work's episode list
  ///
  /// In en, this message translates to:
  /// **'Loading: {title}'**
  String playerQueueLoading(String title);

  /// Resume banner for the last played work
  ///
  /// In en, this message translates to:
  /// **'Resume: {title}'**
  String playerQueueResumeLast(String title);

  /// Countdown hint before cross-work auto-play
  ///
  /// In en, this message translates to:
  /// **'Up next: {title}'**
  String playerAutoNextWork(String title);

  /// No description provided for @playerQueueMoveUp.
  ///
  /// In en, this message translates to:
  /// **'Move up'**
  String get playerQueueMoveUp;

  /// No description provided for @playerQueueMoveDown.
  ///
  /// In en, this message translates to:
  /// **'Move down'**
  String get playerQueueMoveDown;

  /// No description provided for @playerQueueRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get playerQueueRemove;

  /// No description provided for @playerDecodeMode.
  ///
  /// In en, this message translates to:
  /// **'Decode mode'**
  String get playerDecodeMode;

  /// No description provided for @playerDecodeAuto.
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get playerDecodeAuto;

  /// No description provided for @playerDecodeSw.
  ///
  /// In en, this message translates to:
  /// **'Software'**
  String get playerDecodeSw;

  /// No description provided for @playerDecodeHw.
  ///
  /// In en, this message translates to:
  /// **'Hardware'**
  String get playerDecodeHw;

  /// No description provided for @playerDecodeHwPlus.
  ///
  /// In en, this message translates to:
  /// **'Hardware+'**
  String get playerDecodeHwPlus;

  /// No description provided for @playerDecodeHwPlusHint.
  ///
  /// In en, this message translates to:
  /// **'Recommended for screen artifacts'**
  String get playerDecodeHwPlusHint;

  /// No description provided for @playerUpscaleShader.
  ///
  /// In en, this message translates to:
  /// **'Super resolution'**
  String get playerUpscaleShader;

  /// No description provided for @playerUpscaleShaderOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get playerUpscaleShaderOff;

  /// No description provided for @playerUpscaleShaderPerformance.
  ///
  /// In en, this message translates to:
  /// **'Fast'**
  String get playerUpscaleShaderPerformance;

  /// No description provided for @playerUpscaleShaderQuality.
  ///
  /// In en, this message translates to:
  /// **'Quality'**
  String get playerUpscaleShaderQuality;

  /// No description provided for @playerUpscaleShaderHint.
  ///
  /// In en, this message translates to:
  /// **'Real-time upscale for low-res sources; use Fast or Off if frames drop'**
  String get playerUpscaleShaderHint;

  /// SnackBar shown when decode mode is auto-downgraded after a hardware decoding failure
  ///
  /// In en, this message translates to:
  /// **'Decoding issue detected, switched to {mode}'**
  String playerDecodeFallback(String mode);

  /// Player more menu item to show playback statistics panel
  ///
  /// In en, this message translates to:
  /// **'Playback stats'**
  String get playerStats;

  /// No description provided for @playerStatsDecoder.
  ///
  /// In en, this message translates to:
  /// **'Decoder'**
  String get playerStatsDecoder;

  /// No description provided for @playerStatsHardware.
  ///
  /// In en, this message translates to:
  /// **'Hardware decoding'**
  String get playerStatsHardware;

  /// No description provided for @playerStatsSoftware.
  ///
  /// In en, this message translates to:
  /// **'Software decoding'**
  String get playerStatsSoftware;

  /// No description provided for @playerStatsVideoCodec.
  ///
  /// In en, this message translates to:
  /// **'Video codec'**
  String get playerStatsVideoCodec;

  /// No description provided for @playerStatsPixelFormat.
  ///
  /// In en, this message translates to:
  /// **'Pixel format'**
  String get playerStatsPixelFormat;

  /// No description provided for @playerStatsResolution.
  ///
  /// In en, this message translates to:
  /// **'Resolution'**
  String get playerStatsResolution;

  /// No description provided for @playerStatsDroppedFrames.
  ///
  /// In en, this message translates to:
  /// **'Dropped frames (render / decode)'**
  String get playerStatsDroppedFrames;

  /// No description provided for @playerStatsBitrate.
  ///
  /// In en, this message translates to:
  /// **'Video bitrate'**
  String get playerStatsBitrate;

  /// No description provided for @playerStatsBuffering.
  ///
  /// In en, this message translates to:
  /// **'Cache buffering'**
  String get playerStatsBuffering;

  /// No description provided for @playerStatsUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Playback stats unavailable'**
  String get playerStatsUnavailable;

  /// No description provided for @playerAudioChannel.
  ///
  /// In en, this message translates to:
  /// **'Audio channel'**
  String get playerAudioChannel;

  /// No description provided for @playerAudioStereo.
  ///
  /// In en, this message translates to:
  /// **'Stereo'**
  String get playerAudioStereo;

  /// No description provided for @playerAudioMono.
  ///
  /// In en, this message translates to:
  /// **'Mono'**
  String get playerAudioMono;

  /// No description provided for @playerAudioAutoProtect.
  ///
  /// In en, this message translates to:
  /// **'Auto-protect'**
  String get playerAudioAutoProtect;

  /// No description provided for @playerAudioReverseStereo.
  ///
  /// In en, this message translates to:
  /// **'Reverse stereo'**
  String get playerAudioReverseStereo;

  /// No description provided for @playerAspectRatio.
  ///
  /// In en, this message translates to:
  /// **'Aspect ratio'**
  String get playerAspectRatio;

  /// No description provided for @playerAspectDefault.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get playerAspectDefault;

  /// No description provided for @playerAspectFill.
  ///
  /// In en, this message translates to:
  /// **'Fill'**
  String get playerAspectFill;

  /// No description provided for @playerAspect43.
  ///
  /// In en, this message translates to:
  /// **'4:3'**
  String get playerAspect43;

  /// No description provided for @playerAspect169.
  ///
  /// In en, this message translates to:
  /// **'16:9'**
  String get playerAspect169;

  /// No description provided for @playerPlaybackSpeed.
  ///
  /// In en, this message translates to:
  /// **'Playback speed'**
  String get playerPlaybackSpeed;

  /// No description provided for @playerLongPressSpeed.
  ///
  /// In en, this message translates to:
  /// **'Long Press Speed'**
  String get playerLongPressSpeed;

  /// No description provided for @playerSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Subtitle'**
  String get playerSubtitle;

  /// No description provided for @playerSubtitleSettings.
  ///
  /// In en, this message translates to:
  /// **'Subtitle settings'**
  String get playerSubtitleSettings;

  /// No description provided for @playerSubtitleDelay.
  ///
  /// In en, this message translates to:
  /// **'Subtitle delay (ms)'**
  String get playerSubtitleDelay;

  /// No description provided for @playerFontSize.
  ///
  /// In en, this message translates to:
  /// **'Font size'**
  String get playerFontSize;

  /// No description provided for @playerSubtitleOutline.
  ///
  /// In en, this message translates to:
  /// **'Subtitle outline'**
  String get playerSubtitleOutline;

  /// No description provided for @playerTimer.
  ///
  /// In en, this message translates to:
  /// **'Sleep timer'**
  String get playerTimer;

  /// No description provided for @playerPlayInfo.
  ///
  /// In en, this message translates to:
  /// **'Play info'**
  String get playerPlayInfo;

  /// No description provided for @playerExternalPlay.
  ///
  /// In en, this message translates to:
  /// **'External play'**
  String get playerExternalPlay;

  /// No description provided for @playerVideoExpired.
  ///
  /// In en, this message translates to:
  /// **'Video link expired, please retry'**
  String get playerVideoExpired;

  /// No description provided for @playerOhosUnsupported.
  ///
  /// In en, this message translates to:
  /// **'Video playback isn\'t supported on HarmonyOS yet. This feature is being adapted.'**
  String get playerOhosUnsupported;

  /// No description provided for @playerEpisodeSwitchFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to switch episode, please retry'**
  String get playerEpisodeSwitchFailed;

  /// No description provided for @playerStallDetected.
  ///
  /// In en, this message translates to:
  /// **'Playback stalled, reconnecting…'**
  String get playerStallDetected;

  /// No description provided for @playerRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get playerRetry;

  /// No description provided for @playerNextEpisode.
  ///
  /// In en, this message translates to:
  /// **'Next episode'**
  String get playerNextEpisode;

  /// No description provided for @playerPreviousEpisode.
  ///
  /// In en, this message translates to:
  /// **'Previous episode'**
  String get playerPreviousEpisode;

  /// No description provided for @playerNextFrame.
  ///
  /// In en, this message translates to:
  /// **'Next frame'**
  String get playerNextFrame;

  /// No description provided for @playerPreviousFrame.
  ///
  /// In en, this message translates to:
  /// **'Previous frame'**
  String get playerPreviousFrame;

  /// No description provided for @playerShare.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get playerShare;

  /// No description provided for @danmakuFilterKeywords.
  ///
  /// In en, this message translates to:
  /// **'Filter keywords'**
  String get danmakuFilterKeywords;

  /// No description provided for @danmakuTimeOffset.
  ///
  /// In en, this message translates to:
  /// **'Time offset (s)'**
  String get danmakuTimeOffset;

  /// No description provided for @danmakuArea.
  ///
  /// In en, this message translates to:
  /// **'Display area'**
  String get danmakuArea;

  /// No description provided for @danmakuDuration.
  ///
  /// In en, this message translates to:
  /// **'Duration (s)'**
  String get danmakuDuration;

  /// No description provided for @danmakuLineHeight.
  ///
  /// In en, this message translates to:
  /// **'Line height'**
  String get danmakuLineHeight;

  /// No description provided for @danmakuHideTop.
  ///
  /// In en, this message translates to:
  /// **'Hide top'**
  String get danmakuHideTop;

  /// No description provided for @danmakuHideBottom.
  ///
  /// In en, this message translates to:
  /// **'Hide bottom'**
  String get danmakuHideBottom;

  /// No description provided for @danmakuHideScroll.
  ///
  /// In en, this message translates to:
  /// **'Hide scroll'**
  String get danmakuHideScroll;

  /// No description provided for @danmakuFollowSpeed.
  ///
  /// In en, this message translates to:
  /// **'Follow playback speed'**
  String get danmakuFollowSpeed;

  /// No description provided for @danmakuAddKeyword.
  ///
  /// In en, this message translates to:
  /// **'Add keyword'**
  String get danmakuAddKeyword;

  /// No description provided for @danmakuKeywordHint.
  ///
  /// In en, this message translates to:
  /// **'Enter keyword or regex'**
  String get danmakuKeywordHint;

  /// No description provided for @danmakuSearch.
  ///
  /// In en, this message translates to:
  /// **'Search danmaku'**
  String get danmakuSearch;

  /// No description provided for @danmakuSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Enter anime name to search'**
  String get danmakuSearchHint;

  /// No description provided for @danmakuMatchEpisode.
  ///
  /// In en, this message translates to:
  /// **'Match episode'**
  String get danmakuMatchEpisode;

  /// No description provided for @danmakuNoResult.
  ///
  /// In en, this message translates to:
  /// **'No results'**
  String get danmakuNoResult;

  /// No description provided for @danmakuLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load danmaku'**
  String get danmakuLoadFailed;

  /// No description provided for @danmakuLoaded.
  ///
  /// In en, this message translates to:
  /// **'Danmaku loaded'**
  String get danmakuLoaded;

  /// No description provided for @danmakuCacheHit.
  ///
  /// In en, this message translates to:
  /// **'Danmaku cached'**
  String get danmakuCacheHit;

  /// Danmaku source selection sheet title
  ///
  /// In en, this message translates to:
  /// **'Danmaku Source'**
  String get danmakuSourceTitle;

  /// Subtitle hint on the danmaku source sheet
  ///
  /// In en, this message translates to:
  /// **'Choose danmaku source'**
  String get danmakuSourceHint;

  /// dandanplay danmaku source option
  ///
  /// In en, this message translates to:
  /// **'dandanplay'**
  String get danmakuSourceDandanplay;

  /// bilibili danmaku source option
  ///
  /// In en, this message translates to:
  /// **'bilibili'**
  String get danmakuSourceBilibili;

  /// Disable danmaku source option
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get danmakuSourceOff;

  /// dandanplay source description
  ///
  /// In en, this message translates to:
  /// **'Auto-match by anime title'**
  String get danmakuSourceDandanplayDesc;

  /// bilibili source description
  ///
  /// In en, this message translates to:
  /// **'Match by video av/BV id'**
  String get danmakuSourceBilibiliDesc;

  /// Disabled danmaku source description
  ///
  /// In en, this message translates to:
  /// **'No danmaku'**
  String get danmakuSourceOffDesc;

  /// Danmaku display settings entry title
  ///
  /// In en, this message translates to:
  /// **'Danmaku Display Settings'**
  String get danmakuDisplaySettingsTitle;

  /// Danmaku display settings entry description
  ///
  /// In en, this message translates to:
  /// **'Font size, opacity, time offset, etc.'**
  String get danmakuDisplaySettingsDesc;

  /// Danmaku font size
  ///
  /// In en, this message translates to:
  /// **'Font Size'**
  String get danmakuFontSize;

  /// Danmaku opacity
  ///
  /// In en, this message translates to:
  /// **'Opacity'**
  String get danmakuOpacity;

  /// Player settings title
  ///
  /// In en, this message translates to:
  /// **'Player Settings'**
  String get playerSettingsTitle;

  /// Player settings description
  ///
  /// In en, this message translates to:
  /// **'Decode mode, aspect ratio, playback speed, etc.'**
  String get playerSettingsDesc;

  /// Default decode mode
  ///
  /// In en, this message translates to:
  /// **'Default Decode Mode'**
  String get playerDefaultDecodeMode;

  /// Default audio channel
  ///
  /// In en, this message translates to:
  /// **'Default Audio Channel'**
  String get playerDefaultAudioChannel;

  /// Default aspect ratio
  ///
  /// In en, this message translates to:
  /// **'Default Aspect Ratio'**
  String get playerDefaultAspectRatio;

  /// Default playback speed
  ///
  /// In en, this message translates to:
  /// **'Default Playback Speed'**
  String get playerDefaultSpeed;

  /// Default auto-play next
  ///
  /// In en, this message translates to:
  /// **'Default Auto-play Next'**
  String get playerDefaultAutoPlay;

  /// Subtitle font size
  ///
  /// In en, this message translates to:
  /// **'Subtitle Font Size'**
  String get playerSubtitleFontSize;

  /// Subtitle panel title
  ///
  /// In en, this message translates to:
  /// **'Subtitles'**
  String get subtitleTitle;

  /// Subtitle offset slider label
  ///
  /// In en, this message translates to:
  /// **'Offset'**
  String get subtitleOffset;

  /// No description provided for @subtitlePosTop.
  ///
  /// In en, this message translates to:
  /// **'Top'**
  String get subtitlePosTop;

  /// No description provided for @subtitlePosCenter.
  ///
  /// In en, this message translates to:
  /// **'Center'**
  String get subtitlePosCenter;

  /// No description provided for @subtitlePosBottom.
  ///
  /// In en, this message translates to:
  /// **'Bottom'**
  String get subtitlePosBottom;

  /// No description provided for @subtitleAssYes.
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get subtitleAssYes;

  /// No description provided for @subtitleAssNo.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get subtitleAssNo;

  /// No description provided for @subtitleAssStrip.
  ///
  /// In en, this message translates to:
  /// **'Strip'**
  String get subtitleAssStrip;

  /// No description provided for @subtitleAssForce.
  ///
  /// In en, this message translates to:
  /// **'Force'**
  String get subtitleAssForce;

  /// Subtitle visibility switch label
  ///
  /// In en, this message translates to:
  /// **'Show subtitles'**
  String get subtitleShow;

  /// Option to disable subtitles
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get subtitleNone;

  /// Shown when no subtitle tracks are available
  ///
  /// In en, this message translates to:
  /// **'No subtitle tracks available'**
  String get subtitleNoTracks;

  /// No description provided for @subtitleStyleTitle.
  ///
  /// In en, this message translates to:
  /// **'Subtitle Style'**
  String get subtitleStyleTitle;

  /// No description provided for @subtitleFontSize.
  ///
  /// In en, this message translates to:
  /// **'Font Size'**
  String get subtitleFontSize;

  /// No description provided for @subtitleScale.
  ///
  /// In en, this message translates to:
  /// **'Scale'**
  String get subtitleScale;

  /// No description provided for @subtitleBorderSize.
  ///
  /// In en, this message translates to:
  /// **'Border Width'**
  String get subtitleBorderSize;

  /// No description provided for @subtitleShadowOffset.
  ///
  /// In en, this message translates to:
  /// **'Shadow Offset'**
  String get subtitleShadowOffset;

  /// No description provided for @subtitleTextColor.
  ///
  /// In en, this message translates to:
  /// **'Text Color'**
  String get subtitleTextColor;

  /// No description provided for @subtitleBorderColorLabel.
  ///
  /// In en, this message translates to:
  /// **'Border Color'**
  String get subtitleBorderColorLabel;

  /// No description provided for @subtitleShadowColorLabel.
  ///
  /// In en, this message translates to:
  /// **'Shadow Color'**
  String get subtitleShadowColorLabel;

  /// No description provided for @subtitlePosition.
  ///
  /// In en, this message translates to:
  /// **'Position'**
  String get subtitlePosition;

  /// No description provided for @subtitleAssOverride.
  ///
  /// In en, this message translates to:
  /// **'Override ASS/SSA Style'**
  String get subtitleAssOverride;

  /// Fallback subtitle track label using its id
  ///
  /// In en, this message translates to:
  /// **'Track {n}'**
  String subtitleTrackN(Object n);

  /// Reader settings title
  ///
  /// In en, this message translates to:
  /// **'Reader Settings'**
  String get readerSettingsTitle;

  /// Reader settings description
  ///
  /// In en, this message translates to:
  /// **'Reading mode, background, orientation, etc.'**
  String get readerSettingsDesc;

  /// Reader settings: general reading preferences
  ///
  /// In en, this message translates to:
  /// **'General Reading Preferences'**
  String get readerGeneralGroup;

  /// Novel reader default settings title
  ///
  /// In en, this message translates to:
  /// **'Novel Reader Settings'**
  String get novelReaderSettingsTitle;

  /// Novel reader default settings description
  ///
  /// In en, this message translates to:
  /// **'Global novel reader defaults'**
  String get novelReaderSettingsDesc;

  /// Comic reader default settings title
  ///
  /// In en, this message translates to:
  /// **'Comic Reader Settings'**
  String get comicReaderSettingsTitle;

  /// Comic reader default settings description
  ///
  /// In en, this message translates to:
  /// **'Direction, tap zone, filter, zoom & gesture'**
  String get comicReaderSettingsDesc;

  /// Novel default: typography
  ///
  /// In en, this message translates to:
  /// **'Novel Typography'**
  String get novelTypographyGroup;

  /// Novel text shadow
  ///
  /// In en, this message translates to:
  /// **'Shadow toggle'**
  String get novelShadow;

  /// Novel background preset
  ///
  /// In en, this message translates to:
  /// **'Background preset'**
  String get novelBackgroundPreset;

  /// Novel tap zone invert
  ///
  /// In en, this message translates to:
  /// **'Tap zone invert'**
  String get novelTapZoneInvert;

  /// Comic default: image filter
  ///
  /// In en, this message translates to:
  /// **'Image Filter'**
  String get comicFilterGroup;

  /// Comic filter brightness
  ///
  /// In en, this message translates to:
  /// **'Brightness'**
  String get comicFilterBrightness;

  /// Comic filter contrast
  ///
  /// In en, this message translates to:
  /// **'Contrast'**
  String get comicFilterContrast;

  /// Comic filter color temperature
  ///
  /// In en, this message translates to:
  /// **'Color Temperature'**
  String get comicFilterColorTemp;

  /// Comic image invert filter
  ///
  /// In en, this message translates to:
  /// **'Invert Filter'**
  String get comicFilterInverted;

  /// Comic tap zone invert
  ///
  /// In en, this message translates to:
  /// **'Tap Zone Invert'**
  String get comicTapZoneInvert;

  /// Novel defaults: zoom and typography
  ///
  /// In en, this message translates to:
  /// **'Zoom & Typography'**
  String get novelZoomGroup;

  /// Comic defaults: zoom and gesture
  ///
  /// In en, this message translates to:
  /// **'Zoom & Gesture'**
  String get comicZoomGroup;

  /// Default reading mode
  ///
  /// In en, this message translates to:
  /// **'Default Reading Mode'**
  String get readerDefaultMode;

  /// Default reader background
  ///
  /// In en, this message translates to:
  /// **'Default Background'**
  String get readerDefaultBackground;

  /// White background
  ///
  /// In en, this message translates to:
  /// **'White'**
  String get readerBackgroundWhite;

  /// Beige background
  ///
  /// In en, this message translates to:
  /// **'Beige'**
  String get readerBackgroundBeige;

  /// Dark background
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get readerBackgroundDark;

  /// Default reader orientation
  ///
  /// In en, this message translates to:
  /// **'Default Orientation'**
  String get readerDefaultOrientation;

  /// Horizontal orientation
  ///
  /// In en, this message translates to:
  /// **'Horizontal'**
  String get readerOrientationHorizontal;

  /// Vertical orientation
  ///
  /// In en, this message translates to:
  /// **'Vertical'**
  String get readerOrientationVertical;

  /// Double tap zoom
  ///
  /// In en, this message translates to:
  /// **'Double Tap Zoom'**
  String get readerDoubleTapZoom;

  /// Orientation lock
  ///
  /// In en, this message translates to:
  /// **'Orientation Lock'**
  String get readerOrientationLock;

  /// Layout settings
  ///
  /// In en, this message translates to:
  /// **'Layout Settings'**
  String get layoutSettings;

  /// Layout settings description
  ///
  /// In en, this message translates to:
  /// **'Bookshelf grid/list, density'**
  String get layoutSettingsDesc;

  /// Bookshelf layout mode
  ///
  /// In en, this message translates to:
  /// **'Bookshelf Layout Mode'**
  String get bookshelfLayoutMode;

  /// Grid layout
  ///
  /// In en, this message translates to:
  /// **'Grid'**
  String get bookshelfLayoutGrid;

  /// List layout
  ///
  /// In en, this message translates to:
  /// **'List'**
  String get bookshelfLayoutList;

  /// Grid density
  ///
  /// In en, this message translates to:
  /// **'Grid Density'**
  String get bookshelfLayoutDensity;

  /// Compact density
  ///
  /// In en, this message translates to:
  /// **'Compact'**
  String get bookshelfDensityCompact;

  /// Standard density
  ///
  /// In en, this message translates to:
  /// **'Standard'**
  String get bookshelfDensityStandard;

  /// Comfortable density
  ///
  /// In en, this message translates to:
  /// **'Comfortable'**
  String get bookshelfDensityComfortable;

  /// Hide source
  ///
  /// In en, this message translates to:
  /// **'Hide'**
  String get sourceHide;

  /// Show hidden sources
  ///
  /// In en, this message translates to:
  /// **'Show Hidden Sources'**
  String get sourceShowHidden;

  /// No description provided for @sourceEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit Source'**
  String get sourceEdit;

  /// No description provided for @sourceDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete Source'**
  String get sourceDelete;

  /// No description provided for @sourceMigrate.
  ///
  /// In en, this message translates to:
  /// **'View migration note'**
  String get sourceMigrate;

  /// No description provided for @sourceEditBuiltinNotAllowed.
  ///
  /// In en, this message translates to:
  /// **'Built-in sources cannot be edited'**
  String get sourceEditBuiltinNotAllowed;

  /// No description provided for @sourceEditSaved.
  ///
  /// In en, this message translates to:
  /// **'Source updated'**
  String get sourceEditSaved;

  /// No description provided for @sourceEditFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to update source'**
  String get sourceEditFailed;

  /// No description provided for @sourceEditJsonHint.
  ///
  /// In en, this message translates to:
  /// **'Edit all fields of this source as JSON in collapsible modules. Tap a module title to expand or collapse; a module\'s content is only loaded when expanded. Clearing a module and saving deletes that field. The id is locked and cannot be changed.'**
  String get sourceEditJsonHint;

  /// No description provided for @sourceEditInvalidJson.
  ///
  /// In en, this message translates to:
  /// **'JSON format or field validation failed. Please fix and retry.'**
  String get sourceEditInvalidJson;

  /// Summary on a collapsed source-edit module header: how many entries the JSON object or array holds
  ///
  /// In en, this message translates to:
  /// **'{count} entries'**
  String sourceEditSectionItems(int count);

  /// Button on the source-edit screen: add a new top-level JSON field as its own collapsible module
  ///
  /// In en, this message translates to:
  /// **'Add field'**
  String get sourceEditAddField;

  /// Input label in the add-field dialog on the source-edit screen
  ///
  /// In en, this message translates to:
  /// **'Field name'**
  String get sourceEditFieldName;

  /// Error when adding a top-level field whose name already exists on the source-edit screen
  ///
  /// In en, this message translates to:
  /// **'This field already exists'**
  String get sourceEditFieldExists;

  /// Tooltip on the lock icon of the id module in the source-edit screen
  ///
  /// In en, this message translates to:
  /// **'id is locked and stays unchanged on save'**
  String get sourceEditIdLocked;

  /// Source-edit screen tab: identity fields such as id, name, type and toggles
  ///
  /// In en, this message translates to:
  /// **'Basic'**
  String get sourceEditTabBasic;

  /// Source-edit screen tab: site, parser, selectors and hotlink/webview configs
  ///
  /// In en, this message translates to:
  /// **'Site & Parsing'**
  String get sourceEditTabParse;

  /// Source-edit screen tab: the routes module
  ///
  /// In en, this message translates to:
  /// **'Routes'**
  String get sourceEditTabRoutes;

  /// Source-edit screen tab: category, home sections, filters and web favorite
  ///
  /// In en, this message translates to:
  /// **'Category & Filters'**
  String get sourceEditTabBrowse;

  /// Source-edit screen tab: network, comments, announcement and custom fields
  ///
  /// In en, this message translates to:
  /// **'Network & Other'**
  String get sourceEditTabAdvanced;

  /// No description provided for @sourceDeleteBuiltinNotAllowed.
  ///
  /// In en, this message translates to:
  /// **'Built-in sources cannot be deleted'**
  String get sourceDeleteBuiltinNotAllowed;

  /// No description provided for @sourceDeleted.
  ///
  /// In en, this message translates to:
  /// **'Source deleted'**
  String get sourceDeleted;

  /// No description provided for @sourceDeleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to delete source'**
  String get sourceDeleteFailed;

  /// No description provided for @sourceDeprecatedHint.
  ///
  /// In en, this message translates to:
  /// **'This source is deprecated. Please use an alternative.'**
  String get sourceDeprecatedHint;

  /// No description provided for @sourceNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Source Name'**
  String get sourceNameLabel;

  /// No description provided for @sourceUrlLabel.
  ///
  /// In en, this message translates to:
  /// **'Source URL'**
  String get sourceUrlLabel;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @sourceType.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get sourceType;

  /// No description provided for @sourceTypeAnime.
  ///
  /// In en, this message translates to:
  /// **'Anime'**
  String get sourceTypeAnime;

  /// No description provided for @sourceTypeManga.
  ///
  /// In en, this message translates to:
  /// **'Manga'**
  String get sourceTypeManga;

  /// No description provided for @sourceTypeNovel.
  ///
  /// In en, this message translates to:
  /// **'Novel'**
  String get sourceTypeNovel;

  /// No description provided for @playerTimerOff.
  ///
  /// In en, this message translates to:
  /// **'Turn off timer'**
  String get playerTimerOff;

  /// Sleep timer duration in minutes
  ///
  /// In en, this message translates to:
  /// **'{minutes} minutes'**
  String playerTimerMinutes(int minutes);

  /// No description provided for @playerTimerCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get playerTimerCustom;

  /// No description provided for @playerTimerCanceled.
  ///
  /// In en, this message translates to:
  /// **'Sleep timer canceled'**
  String get playerTimerCanceled;

  /// No description provided for @playerTimerFired.
  ///
  /// In en, this message translates to:
  /// **'Sleep timer fired, playback paused'**
  String get playerTimerFired;

  /// Sleep timer: pause after N episodes
  ///
  /// In en, this message translates to:
  /// **'Pause after {count} more episodes'**
  String playerTimerEpisodes(int count);

  /// No description provided for @playerTimerEpisodesFired.
  ///
  /// In en, this message translates to:
  /// **'Playback paused by episode sleep timer'**
  String get playerTimerEpisodesFired;

  /// No description provided for @noDescription.
  ///
  /// In en, this message translates to:
  /// **'No description available'**
  String get noDescription;

  /// No description provided for @aboutAppTitle.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get aboutAppTitle;

  /// No description provided for @openSourceLicenses.
  ///
  /// In en, this message translates to:
  /// **'Open source licenses'**
  String get openSourceLicenses;

  /// No description provided for @thirdPartyLibraries.
  ///
  /// In en, this message translates to:
  /// **'Third-party libraries'**
  String get thirdPartyLibraries;

  /// No description provided for @acknowledgements.
  ///
  /// In en, this message translates to:
  /// **'Acknowledgements'**
  String get acknowledgements;

  /// No description provided for @acknowledgementsLegado.
  ///
  /// In en, this message translates to:
  /// **'NexHub\'s novel paginator re-implements its ChapterProvider pagination algorithm as an independent Dart implementation (no source copied). The upstream repo ships no explicit open-source license; this credit is inspiration attribution only.'**
  String get acknowledgementsLegado;

  /// No description provided for @acknowledgementsMihon.
  ///
  /// In en, this message translates to:
  /// **'Its extension-source architecture and comic-reader interaction informed NexHub\'s manga parsing and reading experience. Licensed under Apache License 2.0 (© Mihon contributors).'**
  String get acknowledgementsMihon;

  /// No description provided for @acknowledgementsRssHub.
  ///
  /// In en, this message translates to:
  /// **'Powers the RSS aggregation behind NexHub\'s subscription feature. Licensed under AGPL-3.0 (© DIYgod); NexHub only calls it as a client and does not modify or redistribute its source.'**
  String get acknowledgementsRssHub;

  /// No description provided for @acknowledgementsWenyi.
  ///
  /// In en, this message translates to:
  /// **'Its novel AI-translation pipeline design (context enrichment, terminology loop, review and refined drafting) informed the deep optimization of NexHub\'s built-in novel translation. Licensed under the MIT License (© BigDawnGhost); NexHub copied no source code and implemented independently.'**
  String get acknowledgementsWenyi;

  /// No description provided for @acknowledgementsAnime4K.
  ///
  /// In en, this message translates to:
  /// **'The player\'s \"Super resolution\" ships its GLSL shader presets (Mode A Fast/Quality). Licensed under the MIT License (© 2019-2021 bloc97).'**
  String get acknowledgementsAnime4K;

  /// No description provided for @acknowledgementsViewProject.
  ///
  /// In en, this message translates to:
  /// **'View project'**
  String get acknowledgementsViewProject;

  /// No description provided for @acknowledgementsMoreLibs.
  ///
  /// In en, this message translates to:
  /// **'Other third-party libraries are listed under \"Open source licenses\".'**
  String get acknowledgementsMoreLibs;

  /// No description provided for @projectRepository.
  ///
  /// In en, this message translates to:
  /// **'Project repository'**
  String get projectRepository;

  /// No description provided for @aboutContactSection.
  ///
  /// In en, this message translates to:
  /// **'Contact us'**
  String get aboutContactSection;

  /// No description provided for @aboutGithubDesc.
  ///
  /// In en, this message translates to:
  /// **'Source code and issue tracker'**
  String get aboutGithubDesc;

  /// No description provided for @aboutQqGroup.
  ///
  /// In en, this message translates to:
  /// **'QQ group'**
  String get aboutQqGroup;

  /// Subtitle of the QQ group entry on the About page; placeholder is the group number
  ///
  /// In en, this message translates to:
  /// **'Dev group: {number}'**
  String aboutQqGroupDesc(String number);

  /// No description provided for @checkUpdate.
  ///
  /// In en, this message translates to:
  /// **'Check for updates'**
  String get checkUpdate;

  /// No description provided for @updateChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking for updates…'**
  String get updateChecking;

  /// No description provided for @updateLatest.
  ///
  /// In en, this message translates to:
  /// **'You are on the latest version'**
  String get updateLatest;

  /// No description provided for @updateAvailable.
  ///
  /// In en, this message translates to:
  /// **'New version {version} available'**
  String updateAvailable(Object version);

  /// No description provided for @updateAvailableHint.
  ///
  /// In en, this message translates to:
  /// **'Open the releases page to download?'**
  String get updateAvailableHint;

  /// No description provided for @updateGoToDownload.
  ///
  /// In en, this message translates to:
  /// **'Go to download'**
  String get updateGoToDownload;

  /// No description provided for @updateCheckFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to check for updates. Try again later.'**
  String get updateCheckFailed;

  /// No description provided for @updateMirrorSettings.
  ///
  /// In en, this message translates to:
  /// **'Update Mirror Settings'**
  String get updateMirrorSettings;

  /// No description provided for @updateMirror.
  ///
  /// In en, this message translates to:
  /// **'Mirror'**
  String get updateMirror;

  /// No description provided for @updateSilentDownload.
  ///
  /// In en, this message translates to:
  /// **'Silent download'**
  String get updateSilentDownload;

  /// No description provided for @updateDownloadAndInstall.
  ///
  /// In en, this message translates to:
  /// **'Download & Install'**
  String get updateDownloadAndInstall;

  /// No description provided for @updateDownloaded.
  ///
  /// In en, this message translates to:
  /// **'Download complete. Ready to install.'**
  String get updateDownloaded;

  /// No description provided for @updateInstallNow.
  ///
  /// In en, this message translates to:
  /// **'Install Now'**
  String get updateInstallNow;

  /// No description provided for @updateAutoSwitchMirror.
  ///
  /// In en, this message translates to:
  /// **'Auto-switch to fastest mirror'**
  String get updateAutoSwitchMirror;

  /// No description provided for @updateAutoSwitchMirrorDesc.
  ///
  /// In en, this message translates to:
  /// **'Test mirror latency during download and pick the fastest'**
  String get updateAutoSwitchMirrorDesc;

  /// No description provided for @updateMirrorSelection.
  ///
  /// In en, this message translates to:
  /// **'Mirror Selection'**
  String get updateMirrorSelection;

  /// No description provided for @updateCustomMirrors.
  ///
  /// In en, this message translates to:
  /// **'Custom Mirrors'**
  String get updateCustomMirrors;

  /// No description provided for @updateNoCustomMirrors.
  ///
  /// In en, this message translates to:
  /// **'No custom mirrors'**
  String get updateNoCustomMirrors;

  /// No description provided for @updateAddMirror.
  ///
  /// In en, this message translates to:
  /// **'Add Mirror'**
  String get updateAddMirror;

  /// No description provided for @updateMirrorName.
  ///
  /// In en, this message translates to:
  /// **'Mirror Name'**
  String get updateMirrorName;

  /// No description provided for @updateMirrorUrl.
  ///
  /// In en, this message translates to:
  /// **'Mirror URL'**
  String get updateMirrorUrl;

  /// No description provided for @updateMirrorUrlInvalid.
  ///
  /// In en, this message translates to:
  /// **'Invalid mirror URL: must be a full http/https URL'**
  String get updateMirrorUrlInvalid;

  /// No description provided for @updateTestMirrors.
  ///
  /// In en, this message translates to:
  /// **'Test All Mirrors'**
  String get updateTestMirrors;

  /// No description provided for @updateMirrorTimeout.
  ///
  /// In en, this message translates to:
  /// **'Timeout'**
  String get updateMirrorTimeout;

  /// No description provided for @updateSettings.
  ///
  /// In en, this message translates to:
  /// **'Update Settings'**
  String get updateSettings;

  /// No description provided for @updateSettingsDesc.
  ///
  /// In en, this message translates to:
  /// **'Check for updates, upgrade channel and download mode'**
  String get updateSettingsDesc;

  /// No description provided for @updateChannelSection.
  ///
  /// In en, this message translates to:
  /// **'Upgrade channel'**
  String get updateChannelSection;

  /// No description provided for @updateChannelStable.
  ///
  /// In en, this message translates to:
  /// **'Stable'**
  String get updateChannelStable;

  /// No description provided for @updateChannelStableDesc.
  ///
  /// In en, this message translates to:
  /// **'Receive stable releases only'**
  String get updateChannelStableDesc;

  /// No description provided for @updateChannelBeta.
  ///
  /// In en, this message translates to:
  /// **'Beta'**
  String get updateChannelBeta;

  /// No description provided for @updateChannelBetaDesc.
  ///
  /// In en, this message translates to:
  /// **'Early access to alpha/beta/rc releases (may be unstable)'**
  String get updateChannelBetaDesc;

  /// No description provided for @updateAutoCheck.
  ///
  /// In en, this message translates to:
  /// **'Check updates automatically'**
  String get updateAutoCheck;

  /// No description provided for @updateAutoCheckDesc.
  ///
  /// In en, this message translates to:
  /// **'Check for new versions in the background on startup'**
  String get updateAutoCheckDesc;

  /// No description provided for @updateAutoDownload.
  ///
  /// In en, this message translates to:
  /// **'Download updates automatically'**
  String get updateAutoDownload;

  /// No description provided for @updateAutoDownloadDesc.
  ///
  /// In en, this message translates to:
  /// **'Download the installer automatically when a new version is found'**
  String get updateAutoDownloadDesc;

  /// No description provided for @updateWifiOnlyAutoDownload.
  ///
  /// In en, this message translates to:
  /// **'Only auto-download on Wi-Fi'**
  String get updateWifiOnlyAutoDownload;

  /// No description provided for @updateWifiOnlyAutoDownloadDesc.
  ///
  /// In en, this message translates to:
  /// **'Wait for a Wi-Fi connection before auto-downloading'**
  String get updateWifiOnlyAutoDownloadDesc;

  /// No description provided for @updateInAppDownload.
  ///
  /// In en, this message translates to:
  /// **'In-app download'**
  String get updateInAppDownload;

  /// No description provided for @updateInAppDownloadDesc.
  ///
  /// In en, this message translates to:
  /// **'Download inside the app; open the browser otherwise'**
  String get updateInAppDownloadDesc;

  /// No description provided for @updateMirrorSection.
  ///
  /// In en, this message translates to:
  /// **'Download mirrors'**
  String get updateMirrorSection;

  /// No description provided for @updateMirrorCommunityThanks.
  ///
  /// In en, this message translates to:
  /// **'Mirrors are contributed by the community and stability is not guaranteed. Thanks to every generous contributor 🙏'**
  String get updateMirrorCommunityThanks;

  /// No description provided for @updateMirrorShowAll.
  ///
  /// In en, this message translates to:
  /// **'Show all ({count})'**
  String updateMirrorShowAll(Object count);

  /// No description provided for @updateMirrorCollapse.
  ///
  /// In en, this message translates to:
  /// **'Collapse'**
  String get updateMirrorCollapse;

  /// No description provided for @updateMirrorAllUnreachable.
  ///
  /// In en, this message translates to:
  /// **'All mirrors are unreachable under the current network. Downloads will use GitHub official directly. Retry later or add a custom mirror.'**
  String get updateMirrorAllUnreachable;

  /// No description provided for @updateOpenedBrowser.
  ///
  /// In en, this message translates to:
  /// **'Opened the browser for download'**
  String get updateOpenedBrowser;

  /// No description provided for @updateCannotOpenBrowser.
  ///
  /// In en, this message translates to:
  /// **'Unable to open the browser'**
  String get updateCannotOpenBrowser;

  /// No description provided for @settingsGroupLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsGroupLanguage;

  /// No description provided for @languageTitle.
  ///
  /// In en, this message translates to:
  /// **'Interface language'**
  String get languageTitle;

  /// No description provided for @languageFollowSystem.
  ///
  /// In en, this message translates to:
  /// **'Follow system'**
  String get languageFollowSystem;

  /// No description provided for @languageChinese.
  ///
  /// In en, this message translates to:
  /// **'简体中文'**
  String get languageChinese;

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @chapterList.
  ///
  /// In en, this message translates to:
  /// **'Chapter list'**
  String get chapterList;

  /// No description provided for @currentChapter.
  ///
  /// In en, this message translates to:
  /// **'Current chapter'**
  String get currentChapter;

  /// No description provided for @searchByAuthor.
  ///
  /// In en, this message translates to:
  /// **'Search by author'**
  String get searchByAuthor;

  /// No description provided for @noRecommendation.
  ///
  /// In en, this message translates to:
  /// **'No recommendations'**
  String get noRecommendation;

  /// No description provided for @restore.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get restore;

  /// No description provided for @archive.
  ///
  /// In en, this message translates to:
  /// **'Archive'**
  String get archive;

  /// No description provided for @archivedEmpty.
  ///
  /// In en, this message translates to:
  /// **'No archived content'**
  String get archivedEmpty;

  /// No description provided for @archivedHint.
  ///
  /// In en, this message translates to:
  /// **'Archived files are kept on disk and can be restored anytime'**
  String get archivedHint;

  /// No description provided for @deletePermanently.
  ///
  /// In en, this message translates to:
  /// **'Delete permanently'**
  String get deletePermanently;

  /// No description provided for @restoreSuccess.
  ///
  /// In en, this message translates to:
  /// **'Restored'**
  String get restoreSuccess;

  /// No description provided for @statusArchived.
  ///
  /// In en, this message translates to:
  /// **'Archived'**
  String get statusArchived;

  /// No description provided for @searchHistoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Search history'**
  String get searchHistoryTitle;

  /// No description provided for @clearSearchHistory.
  ///
  /// In en, this message translates to:
  /// **'Clear history'**
  String get clearSearchHistory;

  /// No description provided for @clearSearchHistoryConfirm.
  ///
  /// In en, this message translates to:
  /// **'Clear all search history?'**
  String get clearSearchHistoryConfirm;

  /// No description provided for @noSearchHistory.
  ///
  /// In en, this message translates to:
  /// **'No search history'**
  String get noSearchHistory;

  /// No description provided for @deleteSearchHistoryConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete this search history entry?'**
  String get deleteSearchHistoryConfirm;

  /// No description provided for @hotSearch.
  ///
  /// In en, this message translates to:
  /// **'Hot search'**
  String get hotSearch;

  /// No description provided for @noHotSearch.
  ///
  /// In en, this message translates to:
  /// **'No hot search'**
  String get noHotSearch;

  /// No description provided for @importDataParsing.
  ///
  /// In en, this message translates to:
  /// **'Parsing…'**
  String get importDataParsing;

  /// No description provided for @importDataSuccess.
  ///
  /// In en, this message translates to:
  /// **'Import successful'**
  String get importDataSuccess;

  /// No description provided for @importDataFailed.
  ///
  /// In en, this message translates to:
  /// **'Import failed'**
  String get importDataFailed;

  /// No description provided for @importDataInvalidFormat.
  ///
  /// In en, this message translates to:
  /// **'Invalid file format'**
  String get importDataInvalidFormat;

  /// No description provided for @importDataSummary.
  ///
  /// In en, this message translates to:
  /// **'Imported {plugins} plugins / {favorites} favorites / {history} history'**
  String importDataSummary(int plugins, int favorites, int history);

  /// No description provided for @exportFolderDefault.
  ///
  /// In en, this message translates to:
  /// **'Default path (Documents)'**
  String get exportFolderDefault;

  /// No description provided for @exportDataSuccess.
  ///
  /// In en, this message translates to:
  /// **'Export successful'**
  String get exportDataSuccess;

  /// No description provided for @exportDataFailed.
  ///
  /// In en, this message translates to:
  /// **'Export failed'**
  String get exportDataFailed;

  /// No description provided for @exportDataInProgress.
  ///
  /// In en, this message translates to:
  /// **'Exporting…'**
  String get exportDataInProgress;

  /// No description provided for @exportDataFileSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved to {path}'**
  String exportDataFileSaved(String path);

  /// No description provided for @exportNothingToExport.
  ///
  /// In en, this message translates to:
  /// **'Nothing to export'**
  String get exportNothingToExport;

  /// No description provided for @notImplemented.
  ///
  /// In en, this message translates to:
  /// **'Not implemented yet'**
  String get notImplemented;

  /// No description provided for @cast.
  ///
  /// In en, this message translates to:
  /// **'Cast'**
  String get cast;

  /// No description provided for @castNotSupportedYet.
  ///
  /// In en, this message translates to:
  /// **'Cast is not supported yet'**
  String get castNotSupportedYet;

  /// No description provided for @cloudSync.
  ///
  /// In en, this message translates to:
  /// **'Cloud sync'**
  String get cloudSync;

  /// No description provided for @cloudSyncNotSupportedYet.
  ///
  /// In en, this message translates to:
  /// **'Coming soon'**
  String get cloudSyncNotSupportedYet;

  /// No description provided for @cloudSyncNotConfigured.
  ///
  /// In en, this message translates to:
  /// **'Not configured, tap to set up'**
  String get cloudSyncNotConfigured;

  /// No description provided for @cloudSyncFeatureWebdav.
  ///
  /// In en, this message translates to:
  /// **'WebDAV backup'**
  String get cloudSyncFeatureWebdav;

  /// No description provided for @cloudSyncFeatureSync.
  ///
  /// In en, this message translates to:
  /// **'Sync favorites and progress across devices'**
  String get cloudSyncFeatureSync;

  /// No description provided for @enableRecommendedSources.
  ///
  /// In en, this message translates to:
  /// **'Enable Recommended Sources'**
  String get enableRecommendedSources;

  /// No description provided for @enableRecommendedSourcesHint.
  ///
  /// In en, this message translates to:
  /// **'Enable all available recommended sources at once'**
  String get enableRecommendedSourcesHint;

  /// Toast after enabling recommended sources
  ///
  /// In en, this message translates to:
  /// **'Enabled {count} recommended sources'**
  String recommendedSourcesEnabled(int count);

  /// No description provided for @castToDevice.
  ///
  /// In en, this message translates to:
  /// **'Cast to device'**
  String get castToDevice;

  /// Casting to a device name
  ///
  /// In en, this message translates to:
  /// **'Casting to {device}'**
  String castingTo(Object device);

  /// No description provided for @castNoDevices.
  ///
  /// In en, this message translates to:
  /// **'No cast devices found'**
  String get castNoDevices;

  /// No description provided for @castNotSupportedOnDevice.
  ///
  /// In en, this message translates to:
  /// **'Casting is not supported on this device'**
  String get castNotSupportedOnDevice;

  /// No description provided for @castDisconnect.
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get castDisconnect;

  /// No description provided for @castDisconnected.
  ///
  /// In en, this message translates to:
  /// **'Casting disconnected'**
  String get castDisconnected;

  /// No description provided for @pip.
  ///
  /// In en, this message translates to:
  /// **'Picture-in-Picture'**
  String get pip;

  /// No description provided for @pipNotSupportedOnDevice.
  ///
  /// In en, this message translates to:
  /// **'Picture-in-Picture is not supported on this device'**
  String get pipNotSupportedOnDevice;

  /// No description provided for @pipNotWhileCasting.
  ///
  /// In en, this message translates to:
  /// **'Cannot enter PiP while casting'**
  String get pipNotWhileCasting;

  /// No description provided for @pipNotReady.
  ///
  /// In en, this message translates to:
  /// **'PiP is unavailable until the media is ready'**
  String get pipNotReady;

  /// No description provided for @pipActionPlay.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get pipActionPlay;

  /// No description provided for @pipActionPause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get pipActionPause;

  /// No description provided for @pipActionDanmaku.
  ///
  /// In en, this message translates to:
  /// **'Danmaku'**
  String get pipActionDanmaku;

  /// No description provided for @pipActionRewind.
  ///
  /// In en, this message translates to:
  /// **'Rewind 10s'**
  String get pipActionRewind;

  /// No description provided for @pipActionForward.
  ///
  /// In en, this message translates to:
  /// **'Forward 30s'**
  String get pipActionForward;

  /// No description provided for @screenshot.
  ///
  /// In en, this message translates to:
  /// **'Screenshot'**
  String get screenshot;

  /// No description provided for @screenshotSaved.
  ///
  /// In en, this message translates to:
  /// **'Screenshot saved'**
  String get screenshotSaved;

  /// No description provided for @screenshotFailed.
  ///
  /// In en, this message translates to:
  /// **'Screenshot failed'**
  String get screenshotFailed;

  /// No description provided for @screenshotPathSetting.
  ///
  /// In en, this message translates to:
  /// **'Screenshot save path'**
  String get screenshotPathSetting;

  /// No description provided for @screenshotPathDefault.
  ///
  /// In en, this message translates to:
  /// **'Default (Documents/screenshots)'**
  String get screenshotPathDefault;

  /// No description provided for @imageLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Image load failed'**
  String get imageLoadFailed;

  /// Gallery screen title for favorited comic images
  ///
  /// In en, this message translates to:
  /// **'Image Favorites'**
  String get imageFavoriteGalleryTitle;

  /// Empty state shown when no images have been favorited
  ///
  /// In en, this message translates to:
  /// **'No favorited images yet'**
  String get imageFavoriteEmpty;

  /// Confirmation dialog before removing a favorited image
  ///
  /// In en, this message translates to:
  /// **'Delete this favorited image?'**
  String get imageFavoriteDeleteConfirm;

  /// Snackbar shown after a favorited image is removed
  ///
  /// In en, this message translates to:
  /// **'Removed from image favorites'**
  String get imageFavoriteDeleted;

  /// Series entry button label and series detail screen title
  ///
  /// In en, this message translates to:
  /// **'Series'**
  String get seriesTitle;

  /// Seasons section title
  ///
  /// In en, this message translates to:
  /// **'Seasons'**
  String get seasonsTitle;

  /// Episode count badge on season card
  ///
  /// In en, this message translates to:
  /// **'{count} episodes'**
  String episodeCount(int count);

  /// Season count label
  ///
  /// In en, this message translates to:
  /// **'{count} seasons'**
  String seasonCount(int count);

  /// No description provided for @imageFilter.
  ///
  /// In en, this message translates to:
  /// **'Image Filter'**
  String get imageFilter;

  /// No description provided for @brightness.
  ///
  /// In en, this message translates to:
  /// **'Brightness'**
  String get brightness;

  /// No description provided for @contrast.
  ///
  /// In en, this message translates to:
  /// **'Contrast'**
  String get contrast;

  /// No description provided for @colorTemperature.
  ///
  /// In en, this message translates to:
  /// **'Color Temperature'**
  String get colorTemperature;

  /// No description provided for @saturation.
  ///
  /// In en, this message translates to:
  /// **'Saturation'**
  String get saturation;

  /// No description provided for @hue.
  ///
  /// In en, this message translates to:
  /// **'Hue'**
  String get hue;

  /// No description provided for @resetFilter.
  ///
  /// In en, this message translates to:
  /// **'Reset Filter'**
  String get resetFilter;

  /// No description provided for @saveImage.
  ///
  /// In en, this message translates to:
  /// **'Save Image'**
  String get saveImage;

  /// No description provided for @shareImage.
  ///
  /// In en, this message translates to:
  /// **'Share Image'**
  String get shareImage;

  /// Toast after saving a reader image
  ///
  /// In en, this message translates to:
  /// **'Image saved to {path}'**
  String imageSavedTo(String path);

  /// No description provided for @imageSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to save image'**
  String get imageSaveFailed;

  /// No description provided for @imagePathCopied.
  ///
  /// In en, this message translates to:
  /// **'Image path copied to clipboard'**
  String get imagePathCopied;

  /// No description provided for @chineseConverter.
  ///
  /// In en, this message translates to:
  /// **'Chinese Conversion'**
  String get chineseConverter;

  /// No description provided for @noConvert.
  ///
  /// In en, this message translates to:
  /// **'No Conversion'**
  String get noConvert;

  /// No description provided for @traditionalToSimplified.
  ///
  /// In en, this message translates to:
  /// **'Traditional to Simplified'**
  String get traditionalToSimplified;

  /// No description provided for @simplifiedToTraditional.
  ///
  /// In en, this message translates to:
  /// **'Simplified to Traditional'**
  String get simplifiedToTraditional;

  /// No description provided for @autoPageInterval.
  ///
  /// In en, this message translates to:
  /// **'Auto Page Interval'**
  String get autoPageInterval;

  /// No description provided for @autoPageSmooth.
  ///
  /// In en, this message translates to:
  /// **'Smooth Auto-Page'**
  String get autoPageSmooth;

  /// No description provided for @autoPageOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get autoPageOff;

  /// No description provided for @pauseAutoPage.
  ///
  /// In en, this message translates to:
  /// **'Pause Auto Page'**
  String get pauseAutoPage;

  /// No description provided for @resumeAutoPage.
  ///
  /// In en, this message translates to:
  /// **'Resume Auto Page'**
  String get resumeAutoPage;

  /// No description provided for @customFont.
  ///
  /// In en, this message translates to:
  /// **'Custom Font'**
  String get customFont;

  /// No description provided for @fontMonospace.
  ///
  /// In en, this message translates to:
  /// **'Monospace'**
  String get fontMonospace;

  /// No description provided for @addBookmark.
  ///
  /// In en, this message translates to:
  /// **'Add Bookmark'**
  String get addBookmark;

  /// No description provided for @bookmarkList.
  ///
  /// In en, this message translates to:
  /// **'Bookmark List'**
  String get bookmarkList;

  /// No description provided for @bookmarkAdded.
  ///
  /// In en, this message translates to:
  /// **'Bookmark Added'**
  String get bookmarkAdded;

  /// No description provided for @novelSwipeKeepGoing.
  ///
  /// In en, this message translates to:
  /// **'Keep swiping down to add bookmark'**
  String get novelSwipeKeepGoing;

  /// No description provided for @novelSwipeRelease.
  ///
  /// In en, this message translates to:
  /// **'Release to add bookmark'**
  String get novelSwipeRelease;

  /// No description provided for @novelSwipeReleaseRemove.
  ///
  /// In en, this message translates to:
  /// **'Release to remove bookmark'**
  String get novelSwipeReleaseRemove;

  /// No description provided for @novelBookmarkRemoved.
  ///
  /// In en, this message translates to:
  /// **'Bookmark removed'**
  String get novelBookmarkRemoved;

  /// No description provided for @deleteBookmark.
  ///
  /// In en, this message translates to:
  /// **'Delete Bookmark'**
  String get deleteBookmark;

  /// No description provided for @bookmarkBadgeCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom Badge Image'**
  String get bookmarkBadgeCustom;

  /// No description provided for @bookmarkBadgeReset.
  ///
  /// In en, this message translates to:
  /// **'Reset Default Icon'**
  String get bookmarkBadgeReset;

  /// No description provided for @noBookmarks.
  ///
  /// In en, this message translates to:
  /// **'No Bookmarks'**
  String get noBookmarks;

  /// No description provided for @bookmarkNoteHint.
  ///
  /// In en, this message translates to:
  /// **'Note (optional)'**
  String get bookmarkNoteHint;

  /// No description provided for @novelChapterProgress.
  ///
  /// In en, this message translates to:
  /// **'Ch. {current} / {total}'**
  String novelChapterProgress(int current, int total);

  /// No description provided for @novelLetterSpacing.
  ///
  /// In en, this message translates to:
  /// **'Letter spacing'**
  String get novelLetterSpacing;

  /// No description provided for @novelFontStyle.
  ///
  /// In en, this message translates to:
  /// **'Font style'**
  String get novelFontStyle;

  /// No description provided for @fontBold.
  ///
  /// In en, this message translates to:
  /// **'Bold'**
  String get fontBold;

  /// No description provided for @fontItalic.
  ///
  /// In en, this message translates to:
  /// **'Italic'**
  String get fontItalic;

  /// No description provided for @fontUnderline.
  ///
  /// In en, this message translates to:
  /// **'Underline'**
  String get fontUnderline;

  /// No description provided for @novelTextColor.
  ///
  /// In en, this message translates to:
  /// **'Text color'**
  String get novelTextColor;

  /// No description provided for @novelTextColorFollowBg.
  ///
  /// In en, this message translates to:
  /// **'Auto (follow background)'**
  String get novelTextColorFollowBg;

  /// No description provided for @novelShadowColor.
  ///
  /// In en, this message translates to:
  /// **'Shadow color'**
  String get novelShadowColor;

  /// No description provided for @novelShadowColorAuto.
  ///
  /// In en, this message translates to:
  /// **'Auto (text color, translucent)'**
  String get novelShadowColorAuto;

  /// No description provided for @novelSectionText.
  ///
  /// In en, this message translates to:
  /// **'Reading basics'**
  String get novelSectionText;

  /// No description provided for @novelSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Chapter Title'**
  String get novelSectionTitle;

  /// No description provided for @novelSectionColor.
  ///
  /// In en, this message translates to:
  /// **'Color & Background'**
  String get novelSectionColor;

  /// No description provided for @novelSectionPage.
  ///
  /// In en, this message translates to:
  /// **'Page & Gesture'**
  String get novelSectionPage;

  /// No description provided for @novelWheelInverted.
  ///
  /// In en, this message translates to:
  /// **'Invert mouse wheel page direction'**
  String get novelWheelInverted;

  /// No description provided for @novelSectionMisc.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get novelSectionMisc;

  /// No description provided for @novelSectionPreDownload.
  ///
  /// In en, this message translates to:
  /// **'Pre-download'**
  String get novelSectionPreDownload;

  /// No description provided for @preDownloadEnabled.
  ///
  /// In en, this message translates to:
  /// **'Pre-download upcoming chapters while reading'**
  String get preDownloadEnabled;

  /// No description provided for @preDownloadThreshold.
  ///
  /// In en, this message translates to:
  /// **'Trigger threshold (current chapter progress)'**
  String get preDownloadThreshold;

  /// No description provided for @preDownloadCount.
  ///
  /// In en, this message translates to:
  /// **'Chapters to pre-download'**
  String get preDownloadCount;

  /// No description provided for @preDownloadStarted.
  ///
  /// In en, this message translates to:
  /// **'Pre-downloading next {count} chapters in background'**
  String preDownloadStarted(Object count);

  /// No description provided for @preDownloadDone.
  ///
  /// In en, this message translates to:
  /// **'Pre-downloaded {count} chapters'**
  String preDownloadDone(Object count);

  /// No description provided for @preDownloadFailedHint.
  ///
  /// In en, this message translates to:
  /// **'Pre-download failed (may need verification or network timed out)'**
  String get preDownloadFailedHint;

  /// No description provided for @localReadContinueOnline.
  ///
  /// In en, this message translates to:
  /// **'Local content finished, switching to online to continue…'**
  String get localReadContinueOnline;

  /// No description provided for @localContinueOnlineFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to continue online'**
  String get localContinueOnlineFailed;

  /// No description provided for @localContinueOnlineUpToDate.
  ///
  /// In en, this message translates to:
  /// **'You have read the latest content'**
  String get localContinueOnlineUpToDate;

  /// No description provided for @novelShowChapterTitle.
  ///
  /// In en, this message translates to:
  /// **'Show chapter title in body'**
  String get novelShowChapterTitle;

  /// No description provided for @novelTitleFontScale.
  ///
  /// In en, this message translates to:
  /// **'Title font scale'**
  String get novelTitleFontScale;

  /// No description provided for @novelTitleBold.
  ///
  /// In en, this message translates to:
  /// **'Title bold'**
  String get novelTitleBold;

  /// No description provided for @novelTitleColor.
  ///
  /// In en, this message translates to:
  /// **'Title color'**
  String get novelTitleColor;

  /// No description provided for @novelTitleColorAuto.
  ///
  /// In en, this message translates to:
  /// **'Follow accent color'**
  String get novelTitleColorAuto;

  /// No description provided for @importShuyuan.
  ///
  /// In en, this message translates to:
  /// **'Import Book Source'**
  String get importShuyuan;

  /// No description provided for @shuyuanImportTitle.
  ///
  /// In en, this message translates to:
  /// **'Import Book Source'**
  String get shuyuanImportTitle;

  /// No description provided for @shuyuanImportHint.
  ///
  /// In en, this message translates to:
  /// **'Supports book source rules (@css/@xpath/@json/@js + ## regex)'**
  String get shuyuanImportHint;

  /// No description provided for @shuyuanImportFromUrl.
  ///
  /// In en, this message translates to:
  /// **'URL'**
  String get shuyuanImportFromUrl;

  /// No description provided for @shuyuanImportFromFile.
  ///
  /// In en, this message translates to:
  /// **'File'**
  String get shuyuanImportFromFile;

  /// No description provided for @shuyuanImportFromJson.
  ///
  /// In en, this message translates to:
  /// **'JSON'**
  String get shuyuanImportFromJson;

  /// No description provided for @shuyuanImportUrlHint.
  ///
  /// In en, this message translates to:
  /// **'URL of book source JSON'**
  String get shuyuanImportUrlHint;

  /// No description provided for @shuyuanImportJsonHint.
  ///
  /// In en, this message translates to:
  /// **'Paste book source JSON config'**
  String get shuyuanImportJsonHint;

  /// No description provided for @shuyuanImportFilePicker.
  ///
  /// In en, this message translates to:
  /// **'Select Book Source File'**
  String get shuyuanImportFilePicker;

  /// No description provided for @shuyuanImportParse.
  ///
  /// In en, this message translates to:
  /// **'Parse'**
  String get shuyuanImportParse;

  /// No description provided for @shuyuanImportParsing.
  ///
  /// In en, this message translates to:
  /// **'Parsing…'**
  String get shuyuanImportParsing;

  /// No description provided for @shuyuanImportParseFailed.
  ///
  /// In en, this message translates to:
  /// **'Parse failed, no valid book sources detected'**
  String get shuyuanImportParseFailed;

  /// No description provided for @shuyuanImportPreview.
  ///
  /// In en, this message translates to:
  /// **'Preview ({count})'**
  String shuyuanImportPreview(int count);

  /// No description provided for @shuyuanImportSaveAll.
  ///
  /// In en, this message translates to:
  /// **'Import All'**
  String get shuyuanImportSaveAll;

  /// No description provided for @shuyuanImportEmpty.
  ///
  /// In en, this message translates to:
  /// **'No parsed results'**
  String get shuyuanImportEmpty;

  /// No description provided for @shuyuanImportValid.
  ///
  /// In en, this message translates to:
  /// **'Valid'**
  String get shuyuanImportValid;

  /// No description provided for @shuyuanImportInvalid.
  ///
  /// In en, this message translates to:
  /// **'Invalid'**
  String get shuyuanImportInvalid;

  /// No description provided for @shuyuanImportTypeUnsupported.
  ///
  /// In en, this message translates to:
  /// **'Unsupported type (text only)'**
  String get shuyuanImportTypeUnsupported;

  /// No description provided for @shuyuanImportSuccess.
  ///
  /// In en, this message translates to:
  /// **'Imported {count} book sources'**
  String shuyuanImportSuccess(int count);

  /// Bottom button label showing count of selected sources to import
  ///
  /// In en, this message translates to:
  /// **'Import {count} selected'**
  String shuyuanImportSelected(int count);

  /// No description provided for @shuyuanImportFailed.
  ///
  /// In en, this message translates to:
  /// **'Import failed'**
  String get shuyuanImportFailed;

  /// No description provided for @shareFailed.
  ///
  /// In en, this message translates to:
  /// **'Share failed'**
  String get shareFailed;

  /// No description provided for @openInBrowserFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to open browser'**
  String get openInBrowserFailed;

  /// No description provided for @updatedAtLabel.
  ///
  /// In en, this message translates to:
  /// **'Updated: '**
  String get updatedAtLabel;

  /// No description provided for @searchChapter.
  ///
  /// In en, this message translates to:
  /// **'Search chapters'**
  String get searchChapter;

  /// No description provided for @noChaptersFound.
  ///
  /// In en, this message translates to:
  /// **'No matching chapters found'**
  String get noChaptersFound;

  /// No description provided for @expandRemainingChapters.
  ///
  /// In en, this message translates to:
  /// **'Show remaining {count} chapters'**
  String expandRemainingChapters(int count);

  /// No description provided for @sortAscending.
  ///
  /// In en, this message translates to:
  /// **'Ascending'**
  String get sortAscending;

  /// No description provided for @sortDescending.
  ///
  /// In en, this message translates to:
  /// **'Descending'**
  String get sortDescending;

  /// No description provided for @downloadSingleChapter.
  ///
  /// In en, this message translates to:
  /// **'Download chapter'**
  String get downloadSingleChapter;

  /// No description provided for @chapterBookmark.
  ///
  /// In en, this message translates to:
  /// **'Chapter bookmark'**
  String get chapterBookmark;

  /// No description provided for @chapterRead.
  ///
  /// In en, this message translates to:
  /// **'Read mark'**
  String get chapterRead;

  /// No description provided for @chapterSortMode.
  ///
  /// In en, this message translates to:
  /// **'Chapter sort'**
  String get chapterSortMode;

  /// No description provided for @aggModeFileExpanded.
  ///
  /// In en, this message translates to:
  /// **'By file order (EPUB chapters expanded in place)'**
  String get aggModeFileExpanded;

  /// No description provided for @aggModeEpubLast.
  ///
  /// In en, this message translates to:
  /// **'EPUB chapters at the end'**
  String get aggModeEpubLast;

  /// No description provided for @aggModeCollapsed.
  ///
  /// In en, this message translates to:
  /// **'One chapter per file (EPUB not expanded)'**
  String get aggModeCollapsed;

  /// No description provided for @continueReading.
  ///
  /// In en, this message translates to:
  /// **'Continue reading'**
  String get continueReading;

  /// No description provided for @continueWatching.
  ///
  /// In en, this message translates to:
  /// **'Continue watching'**
  String get continueWatching;

  /// No description provided for @startFromBeginning.
  ///
  /// In en, this message translates to:
  /// **'Start from beginning'**
  String get startFromBeginning;

  /// No description provided for @openInAppBrowser.
  ///
  /// In en, this message translates to:
  /// **'Open in app'**
  String get openInAppBrowser;

  /// No description provided for @refreshMetadata.
  ///
  /// In en, this message translates to:
  /// **'Refresh metadata'**
  String get refreshMetadata;

  /// No description provided for @removeFromFavorites.
  ///
  /// In en, this message translates to:
  /// **'Remove from favorites'**
  String get removeFromFavorites;

  /// No description provided for @coverViewer.
  ///
  /// In en, this message translates to:
  /// **'Cover'**
  String get coverViewer;

  /// No description provided for @downloadPreset1.
  ///
  /// In en, this message translates to:
  /// **'Download latest 1'**
  String get downloadPreset1;

  /// No description provided for @downloadPreset5.
  ///
  /// In en, this message translates to:
  /// **'Download latest 5'**
  String get downloadPreset5;

  /// No description provided for @downloadPreset10.
  ///
  /// In en, this message translates to:
  /// **'Download latest 10'**
  String get downloadPreset10;

  /// No description provided for @downloadUnread.
  ///
  /// In en, this message translates to:
  /// **'Download unread'**
  String get downloadUnread;

  /// No description provided for @downloadFavorited.
  ///
  /// In en, this message translates to:
  /// **'Download favorited'**
  String get downloadFavorited;

  /// No description provided for @tagLabel.
  ///
  /// In en, this message translates to:
  /// **'Tags'**
  String get tagLabel;

  /// No description provided for @sourceLabel.
  ///
  /// In en, this message translates to:
  /// **'Source'**
  String get sourceLabel;

  /// No description provided for @reloadChapter.
  ///
  /// In en, this message translates to:
  /// **'Reload chapter'**
  String get reloadChapter;

  /// No description provided for @clearReadingProgress.
  ///
  /// In en, this message translates to:
  /// **'Clear reading progress'**
  String get clearReadingProgress;

  /// No description provided for @readingProgressCleared.
  ///
  /// In en, this message translates to:
  /// **'Reading progress cleared'**
  String get readingProgressCleared;

  /// No description provided for @novelMenuBookmarkList.
  ///
  /// In en, this message translates to:
  /// **'Bookmark list'**
  String get novelMenuBookmarkList;

  /// No description provided for @novelMenuConfigureToolbar.
  ///
  /// In en, this message translates to:
  /// **'Configure bottom toolbar'**
  String get novelMenuConfigureToolbar;

  /// No description provided for @novelTtsBackground.
  ///
  /// In en, this message translates to:
  /// **'Background playback'**
  String get novelTtsBackground;

  /// No description provided for @httpTtsEnable.
  ///
  /// In en, this message translates to:
  /// **'Online TTS engine'**
  String get httpTtsEnable;

  /// No description provided for @httpTtsEnableDesc.
  ///
  /// In en, this message translates to:
  /// **'Synthesize speech online (built-in Edge voices, or a self-hosted/third-party HTTP endpoint)'**
  String get httpTtsEnableDesc;

  /// No description provided for @httpTtsProvider.
  ///
  /// In en, this message translates to:
  /// **'Online voice source'**
  String get httpTtsProvider;

  /// No description provided for @httpTtsProviderEdge.
  ///
  /// In en, this message translates to:
  /// **'Edge voices'**
  String get httpTtsProviderEdge;

  /// No description provided for @httpTtsProviderCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom endpoint'**
  String get httpTtsProviderCustom;

  /// No description provided for @httpTtsEdgeHint.
  ///
  /// In en, this message translates to:
  /// **'Microsoft Edge read-aloud interface: free online synthesis, no service to configure; usually better than system TTS, requires network'**
  String get httpTtsEdgeHint;

  /// No description provided for @httpTtsUrlTemplate.
  ///
  /// In en, this message translates to:
  /// **'URL template'**
  String get httpTtsUrlTemplate;

  /// No description provided for @httpTtsDefaultVoice.
  ///
  /// In en, this message translates to:
  /// **'Default voice'**
  String get httpTtsDefaultVoice;

  /// No description provided for @httpTtsVoiceFollowDefault.
  ///
  /// In en, this message translates to:
  /// **'Follow default voice'**
  String get httpTtsVoiceFollowDefault;

  /// No description provided for @httpTtsVoicePreview.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get httpTtsVoicePreview;

  /// No description provided for @httpTtsVoicePreviewSample.
  ///
  /// In en, this message translates to:
  /// **'Hello, this is a voice preview.'**
  String get httpTtsVoicePreviewSample;

  /// No description provided for @httpTtsVoicePreviewFail.
  ///
  /// In en, this message translates to:
  /// **'Preview failed. Please check the network'**
  String get httpTtsVoicePreviewFail;

  /// No description provided for @highlightsSyncNow.
  ///
  /// In en, this message translates to:
  /// **'Sync highlights'**
  String get highlightsSyncNow;

  /// Manual highlight sync result
  ///
  /// In en, this message translates to:
  /// **'Uploaded {uploaded} books · merged {applied} from cloud'**
  String highlightsSyncResult(int uploaded, int applied);

  /// No description provided for @highlightsSyncedNone.
  ///
  /// In en, this message translates to:
  /// **'Highlights already up to date'**
  String get highlightsSyncedNone;

  /// No description provided for @highlightsSyncStatusTitle.
  ///
  /// In en, this message translates to:
  /// **'Highlight sync'**
  String get highlightsSyncStatusTitle;

  /// Local stats line of the highlight sync status card
  ///
  /// In en, this message translates to:
  /// **'{total} highlights · {books} books on this device'**
  String highlightsSyncLocal(int total, int books);

  /// No description provided for @highlightsSyncLastNone.
  ///
  /// In en, this message translates to:
  /// **'Not synced yet'**
  String get highlightsSyncLastNone;

  /// No description provided for @highlightsSyncFailed.
  ///
  /// In en, this message translates to:
  /// **'Highlight sync failed. Check network and WebDAV settings'**
  String get highlightsSyncFailed;

  /// No description provided for @aiAskSection.
  ///
  /// In en, this message translates to:
  /// **'Ask AI'**
  String get aiAskSection;

  /// No description provided for @aiAskDesc.
  ///
  /// In en, this message translates to:
  /// **'Endpoint for the reader\'s \"Ask AI\" action; falls back to the common endpoint when empty'**
  String get aiAskDesc;

  /// No description provided for @aiGroupGeneration.
  ///
  /// In en, this message translates to:
  /// **'Content generation'**
  String get aiGroupGeneration;

  /// No description provided for @aiGroupTranslation.
  ///
  /// In en, this message translates to:
  /// **'Translation'**
  String get aiGroupTranslation;

  /// No description provided for @httpTtsVoiceMap.
  ///
  /// In en, this message translates to:
  /// **'Role → voice (one \'role=voice\' per line)'**
  String get httpTtsVoiceMap;

  /// No description provided for @httpTtsConcurrency.
  ///
  /// In en, this message translates to:
  /// **'Preload concurrency (1-8)'**
  String get httpTtsConcurrency;

  /// No description provided for @httpTtsMaxFailures.
  ///
  /// In en, this message translates to:
  /// **'Consecutive failure stop threshold'**
  String get httpTtsMaxFailures;

  /// No description provided for @httpTtsSilentPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Silent placeholder on failure'**
  String get httpTtsSilentPlaceholder;

  /// No description provided for @httpTtsSilentPlaceholderDesc.
  ///
  /// In en, this message translates to:
  /// **'Skip failed sentences and keep reading; disable to stop immediately'**
  String get httpTtsSilentPlaceholderDesc;

  /// No description provided for @novelSectionFont.
  ///
  /// In en, this message translates to:
  /// **'Font style'**
  String get novelSectionFont;

  /// No description provided for @searchInBook.
  ///
  /// In en, this message translates to:
  /// **'Search in book'**
  String get searchInBook;

  /// No description provided for @wholeBook.
  ///
  /// In en, this message translates to:
  /// **'Whole book'**
  String get wholeBook;

  /// No description provided for @noSearchResults.
  ///
  /// In en, this message translates to:
  /// **'No results'**
  String get noSearchResults;

  /// No description provided for @searchProgress.
  ///
  /// In en, this message translates to:
  /// **'Searched {searched}/{total} chapters'**
  String searchProgress(int searched, int total);

  /// No description provided for @customBgColor.
  ///
  /// In en, this message translates to:
  /// **'Custom background'**
  String get customBgColor;

  /// No description provided for @tapZoneInvert.
  ///
  /// In en, this message translates to:
  /// **'Tap invert'**
  String get tapZoneInvert;

  /// No description provided for @tapInvertNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get tapInvertNone;

  /// No description provided for @tapInvertLeftRight.
  ///
  /// In en, this message translates to:
  /// **'Left/Right'**
  String get tapInvertLeftRight;

  /// No description provided for @tapInvertAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get tapInvertAll;

  /// No description provided for @tapZonePreview.
  ///
  /// In en, this message translates to:
  /// **'Preview tap zones'**
  String get tapZonePreview;

  /// No description provided for @tapZonePrev.
  ///
  /// In en, this message translates to:
  /// **'Prev page'**
  String get tapZonePrev;

  /// No description provided for @tapZoneNext.
  ///
  /// In en, this message translates to:
  /// **'Next page'**
  String get tapZoneNext;

  /// No description provided for @tapZoneToggle.
  ///
  /// In en, this message translates to:
  /// **'Toggle UI'**
  String get tapZoneToggle;

  /// No description provided for @startReading.
  ///
  /// In en, this message translates to:
  /// **'Start reading'**
  String get startReading;

  /// No description provided for @stopReading.
  ///
  /// In en, this message translates to:
  /// **'Stop reading'**
  String get stopReading;

  /// No description provided for @noteList.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get noteList;

  /// No description provided for @noNotes.
  ///
  /// In en, this message translates to:
  /// **'No notes yet'**
  String get noNotes;

  /// No description provided for @noteEditUnsupported.
  ///
  /// In en, this message translates to:
  /// **'Independent notes cannot be edited. Delete and recreate.'**
  String get noteEditUnsupported;

  /// No description provided for @add.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

  /// No description provided for @testConnection.
  ///
  /// In en, this message translates to:
  /// **'Test connection'**
  String get testConnection;

  /// No description provided for @noCustomInstances.
  ///
  /// In en, this message translates to:
  /// **'No custom instances'**
  String get noCustomInstances;

  /// No description provided for @searchByDirector.
  ///
  /// In en, this message translates to:
  /// **'Search by director'**
  String get searchByDirector;

  /// No description provided for @searchByActor.
  ///
  /// In en, this message translates to:
  /// **'Search by actor'**
  String get searchByActor;

  /// No description provided for @searchByTag.
  ///
  /// In en, this message translates to:
  /// **'Search by tag'**
  String get searchByTag;

  /// No description provided for @searchAggregate.
  ///
  /// In en, this message translates to:
  /// **'All sources'**
  String get searchAggregate;

  /// No description provided for @searchSingle.
  ///
  /// In en, this message translates to:
  /// **'Single source'**
  String get searchSingle;

  /// No description provided for @searchSelectSource.
  ///
  /// In en, this message translates to:
  /// **'Select a source'**
  String get searchSelectSource;

  /// No description provided for @searchByWork.
  ///
  /// In en, this message translates to:
  /// **'Search by title'**
  String get searchByWork;

  /// No description provided for @searchFieldAuthor.
  ///
  /// In en, this message translates to:
  /// **'Author'**
  String get searchFieldAuthor;

  /// No description provided for @searchFieldDirector.
  ///
  /// In en, this message translates to:
  /// **'Director'**
  String get searchFieldDirector;

  /// No description provided for @searchFieldActor.
  ///
  /// In en, this message translates to:
  /// **'Cast'**
  String get searchFieldActor;

  /// No description provided for @searchFieldWork.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get searchFieldWork;

  /// No description provided for @rsshubRouteQidian.
  ///
  /// In en, this message translates to:
  /// **'Qidian'**
  String get rsshubRouteQidian;

  /// No description provided for @rsshubRouteJjwxc.
  ///
  /// In en, this message translates to:
  /// **'JJWXC'**
  String get rsshubRouteJjwxc;

  /// No description provided for @rsshubRouteDoubanBooks.
  ///
  /// In en, this message translates to:
  /// **'Douban Books'**
  String get rsshubRouteDoubanBooks;

  /// No description provided for @rsshubRouteDmzj.
  ///
  /// In en, this message translates to:
  /// **'DMZJ'**
  String get rsshubRouteDmzj;

  /// No description provided for @rsshubRouteJmcomic.
  ///
  /// In en, this message translates to:
  /// **'JM Comic'**
  String get rsshubRouteJmcomic;

  /// AppBar title in multi-select mode showing selected count
  ///
  /// In en, this message translates to:
  /// **'Selected {count}'**
  String browseNetworkSelectedCount(int count);

  /// No description provided for @browseNetworkOpenSelected.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get browseNetworkOpenSelected;

  /// No description provided for @browseNetworkDownloadSelected.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get browseNetworkDownloadSelected;

  /// Snackbar shown when batch download starts
  ///
  /// In en, this message translates to:
  /// **'Started downloading {count} files'**
  String browseNetworkDownloadStarted(int count);

  /// Snackbar shown when batch download completes
  ///
  /// In en, this message translates to:
  /// **'Downloaded {count} items'**
  String browseNetworkDownloadDone(int count);

  /// No description provided for @browseNetworkDownloadFailed.
  ///
  /// In en, this message translates to:
  /// **'Download failed'**
  String get browseNetworkDownloadFailed;

  /// No description provided for @browseNetworkDownloadPathMissing.
  ///
  /// In en, this message translates to:
  /// **'Download path unavailable'**
  String get browseNetworkDownloadPathMissing;

  /// No description provided for @unknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get unknown;

  /// No description provided for @rssFeedListTitle.
  ///
  /// In en, this message translates to:
  /// **'RSS subscriptions'**
  String get rssFeedListTitle;

  /// No description provided for @rssTestAllSpeed.
  ///
  /// In en, this message translates to:
  /// **'Test all speeds'**
  String get rssTestAllSpeed;

  /// Single RSS feed speed test menu item
  ///
  /// In en, this message translates to:
  /// **'Test speed'**
  String get rssTestSpeed;

  /// No description provided for @rssSpeedFailed.
  ///
  /// In en, this message translates to:
  /// **'Speed test failed'**
  String get rssSpeedFailed;

  /// RSS feed speed test result in milliseconds
  ///
  /// In en, this message translates to:
  /// **'{ms}ms'**
  String rssSpeedMs(int ms);

  /// Snackbar shown when a picked file extension is not recognized
  ///
  /// In en, this message translates to:
  /// **'Unrecognized file: {fileName}'**
  String unrecognizedFile(String fileName);

  /// Snackbar shown when an import/pick operation throws
  ///
  /// In en, this message translates to:
  /// **'Import failed: {reason}'**
  String importFailed(String reason);

  /// Snackbar shown when recursive folder scan throws FileSystemException
  ///
  /// In en, this message translates to:
  /// **'Folder scan failed, please check permissions or path'**
  String get folderScanFailed;

  /// Snackbar shown when a picked folder has no recognizable files
  ///
  /// In en, this message translates to:
  /// **'Folder is empty or has no usable files'**
  String get emptyFolder;

  /// Snackbar shown when runtime storage/media permission is denied
  ///
  /// In en, this message translates to:
  /// **'Storage permission denied, cannot pick files'**
  String get storagePermissionDenied;

  /// Snackbar shown when a picked file has a null path (e.g. Android SAF edge case)
  ///
  /// In en, this message translates to:
  /// **'Could not get the path of the selected file (possibly a system limitation). Please try another file'**
  String get pickFileNoPath;

  /// Snackbar shown when folder picker returns an Android SAF content URI that dart:io cannot list
  ///
  /// In en, this message translates to:
  /// **'Folder selection is not supported on this system (Android SAF). Please use \"Select File\" to add files one by one'**
  String get folderPickUnsupportedSaf;

  /// Title of the folder-import choice dialog
  ///
  /// In en, this message translates to:
  /// **'Import folder \"{name}\"'**
  String folderImportChoiceTitle(Object name);

  /// Hint text explaining folder-import merge vs per-file
  ///
  /// In en, this message translates to:
  /// **'Multiple {type} files detected. Merge to treat the whole folder as one work (each file = a chapter/volume), or import each file separately.'**
  String folderImportChoiceHint(Object type);

  /// Button: merge folder files into one work
  ///
  /// In en, this message translates to:
  /// **'Merge into one work'**
  String get folderImportChoiceMerge;

  /// Button: import each file separately
  ///
  /// In en, this message translates to:
  /// **'Import files separately'**
  String get folderImportChoicePerFile;

  /// Title of the folder file multi-select sheet for comic import
  ///
  /// In en, this message translates to:
  /// **'Select comic files to import'**
  String get folderFileSelectTitle;

  /// Hint text explaining multi-select of folder comic files
  ///
  /// In en, this message translates to:
  /// **'Found {count} files in the folder (each is one chapter). Check the files you want to import.'**
  String folderFileSelectHint(Object count);

  /// Button to select all files in the multi-select sheet
  ///
  /// In en, this message translates to:
  /// **'Select all'**
  String get folderFileSelectAll;

  /// Button to deselect all files in the multi-select sheet
  ///
  /// In en, this message translates to:
  /// **'Select none'**
  String get folderFileSelectNone;

  /// Toggle: merge selected files into one comic, each file a chapter
  ///
  /// In en, this message translates to:
  /// **'Merge into one'**
  String get folderFileSelectMerge;

  /// Toggle: each selected file becomes a separate comic entry
  ///
  /// In en, this message translates to:
  /// **'Separate entries'**
  String get folderFileSelectSeparate;

  /// Confirm button showing selected count
  ///
  /// In en, this message translates to:
  /// **'Import selected ({count})'**
  String folderFileSelectConfirm(Object count);

  /// Popup menu item to set current comic cover as shelf cover
  ///
  /// In en, this message translates to:
  /// **'Set as shelf cover'**
  String get setAsShelfCover;

  /// Popup menu item to open download manager screen
  ///
  /// In en, this message translates to:
  /// **'Open download manager'**
  String get openDownloadManager;

  /// Popup menu item to show content details
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get details;

  /// Snackbar shown when shelf cover is successfully updated
  ///
  /// In en, this message translates to:
  /// **'Cover updated'**
  String get coverUpdated;

  /// Snackbar shown when shelf cover update fails (favorite entry not found)
  ///
  /// In en, this message translates to:
  /// **'Cover update failed: favorite entry not found'**
  String get coverUpdateFailed;

  /// Label for author field in details sheet
  ///
  /// In en, this message translates to:
  /// **'Author'**
  String get authorLabel;

  /// Label for status field in details sheet
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get statusLabel;

  /// Long-press menu item to set image as cover
  ///
  /// In en, this message translates to:
  /// **'Set as cover'**
  String get setAsCover;

  /// Player more menu item to show media info
  ///
  /// In en, this message translates to:
  /// **'Media info'**
  String get mediaInfo;

  /// Player more menu item to play in external player
  ///
  /// In en, this message translates to:
  /// **'Play external'**
  String get playExternal;

  /// Subtitle panel item to load external subtitle file
  ///
  /// In en, this message translates to:
  /// **'Load external subtitle'**
  String get loadExternalSubtitle;

  /// Snackbar shown when external subtitle loading fails
  ///
  /// In en, this message translates to:
  /// **'External subtitle loading failed'**
  String get loadExternalSubtitleFailed;

  /// Danmaku source sheet option for custom URL source
  ///
  /// In en, this message translates to:
  /// **'Custom URL'**
  String get danmakuCustomUrl;

  /// Hint text for custom danmaku URL input field
  ///
  /// In en, this message translates to:
  /// **'Enter danmaku source URL'**
  String get danmakuCustomUrlHint;

  /// Description for custom URL danmaku source option
  ///
  /// In en, this message translates to:
  /// **'Load danmaku from a custom URL'**
  String get danmakuCustomUrlDesc;

  /// Tab label for online content home tab
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get onlineTabHome;

  /// Tab label for weekly schedule tab
  ///
  /// In en, this message translates to:
  /// **'Schedule'**
  String get onlineTabSchedule;

  /// Tab label for ranking tab
  ///
  /// In en, this message translates to:
  /// **'Ranking'**
  String get onlineTabRanking;

  /// Filter sheet field label for year
  ///
  /// In en, this message translates to:
  /// **'Year'**
  String get filterYear;

  /// Filter sheet field label for region
  ///
  /// In en, this message translates to:
  /// **'Region'**
  String get filterRegion;

  /// Filter sheet field label for sort order
  ///
  /// In en, this message translates to:
  /// **'Sort'**
  String get filterSort;

  /// Dynamic filter group label for source categories
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get filterCategory;

  /// Dynamic filter group label for source tags
  ///
  /// In en, this message translates to:
  /// **'Tag'**
  String get filterTag;

  /// Sort option label for hottest items
  ///
  /// In en, this message translates to:
  /// **'Hottest'**
  String get sortHottest;

  /// Sort option label for highest rated items
  ///
  /// In en, this message translates to:
  /// **'Rating'**
  String get sortRating;

  /// Button label to view all items in a home section
  ///
  /// In en, this message translates to:
  /// **'View all'**
  String get viewAll;

  /// Home section title for latest updated items
  ///
  /// In en, this message translates to:
  /// **'Latest updates'**
  String get latestUpdates;

  /// Home section title for hot recommended items
  ///
  /// In en, this message translates to:
  /// **'Hot picks'**
  String get hotRecommendations;

  /// Weekday label Monday
  ///
  /// In en, this message translates to:
  /// **'Mon'**
  String get weekdayMon;

  /// Weekday label Tuesday
  ///
  /// In en, this message translates to:
  /// **'Tue'**
  String get weekdayTue;

  /// Weekday label Wednesday
  ///
  /// In en, this message translates to:
  /// **'Wed'**
  String get weekdayWed;

  /// Weekday label Thursday
  ///
  /// In en, this message translates to:
  /// **'Thu'**
  String get weekdayThu;

  /// Weekday label Friday
  ///
  /// In en, this message translates to:
  /// **'Fri'**
  String get weekdayFri;

  /// Weekday label Saturday
  ///
  /// In en, this message translates to:
  /// **'Sat'**
  String get weekdaySat;

  /// Weekday label Sunday
  ///
  /// In en, this message translates to:
  /// **'Sun'**
  String get weekdaySun;

  /// Region filter option: mainland China
  ///
  /// In en, this message translates to:
  /// **'China'**
  String get regionChina;

  /// Region filter option: Hong Kong, China
  ///
  /// In en, this message translates to:
  /// **'Hong Kong, China'**
  String get regionHongKong;

  /// Region filter option: Taiwan, China
  ///
  /// In en, this message translates to:
  /// **'Taiwan, China'**
  String get regionTaiwan;

  /// Region filter option: Japan
  ///
  /// In en, this message translates to:
  /// **'Japan'**
  String get regionJapan;

  /// Region filter option: Korea
  ///
  /// In en, this message translates to:
  /// **'Korea'**
  String get regionKorea;

  /// Region filter option: USA
  ///
  /// In en, this message translates to:
  /// **'USA'**
  String get regionUSA;

  /// Region filter option: other regions
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get regionOther;

  /// Shown when a .cbr/.rar comic archive cannot be extracted
  ///
  /// In en, this message translates to:
  /// **'RAR format comics are not supported'**
  String get unsupportedRarFormat;

  /// Shown when an .epub file is opened in the text viewer
  ///
  /// In en, this message translates to:
  /// **'EPUB format is not supported, please use a dedicated reader'**
  String get unsupportedEpubFormat;

  /// Generic unsupported format message for .umd/.mobi/.fb2/.azw3 etc.
  ///
  /// In en, this message translates to:
  /// **'This format is not supported'**
  String get unsupportedFormat;

  /// Label shown as chapter placeholder when reading a local file in specialized readers
  ///
  /// In en, this message translates to:
  /// **'Local file'**
  String get localFileLabel;

  /// Error message shown when a local file fails to load in specialized readers
  ///
  /// In en, this message translates to:
  /// **'Failed to read local file'**
  String get localFileLoadFailed;

  /// No description provided for @playerDefaultOrientation.
  ///
  /// In en, this message translates to:
  /// **'Lock Orientation'**
  String get playerDefaultOrientation;

  /// No description provided for @playerOrientationAuto.
  ///
  /// In en, this message translates to:
  /// **'Follow System'**
  String get playerOrientationAuto;

  /// No description provided for @playerOrientationPortrait.
  ///
  /// In en, this message translates to:
  /// **'Portrait'**
  String get playerOrientationPortrait;

  /// No description provided for @playerOrientationLandscape.
  ///
  /// In en, this message translates to:
  /// **'Landscape'**
  String get playerOrientationLandscape;

  /// No description provided for @playerGestureSeekMultiplier.
  ///
  /// In en, this message translates to:
  /// **'Drag Seek Multiplier'**
  String get playerGestureSeekMultiplier;

  /// No description provided for @playerSeekHalf.
  ///
  /// In en, this message translates to:
  /// **'0.5x'**
  String get playerSeekHalf;

  /// No description provided for @playerSeekNormal.
  ///
  /// In en, this message translates to:
  /// **'1x'**
  String get playerSeekNormal;

  /// No description provided for @playerSeekDouble.
  ///
  /// In en, this message translates to:
  /// **'2x'**
  String get playerSeekDouble;

  /// No description provided for @playerLongPressSpeedUp.
  ///
  /// In en, this message translates to:
  /// **'Long Press Speed Boost'**
  String get playerLongPressSpeedUp;

  /// No description provided for @playerBottomProgress.
  ///
  /// In en, this message translates to:
  /// **'Show bottom progress bar when controls hidden'**
  String get playerBottomProgress;

  /// No description provided for @playerAutoSelectLine.
  ///
  /// In en, this message translates to:
  /// **'Auto-select available line'**
  String get playerAutoSelectLine;

  /// No description provided for @playerCurrentPlayingLine.
  ///
  /// In en, this message translates to:
  /// **'Currently playing line'**
  String get playerCurrentPlayingLine;

  /// No description provided for @playerLineSwitched.
  ///
  /// In en, this message translates to:
  /// **'Switched to line {line}'**
  String playerLineSwitched(Object line);

  /// No description provided for @playerLineFailover.
  ///
  /// In en, this message translates to:
  /// **'Line {from} unavailable, switched to line {to}'**
  String playerLineFailover(Object from, Object to);

  /// No description provided for @playerDefaultVolume.
  ///
  /// In en, this message translates to:
  /// **'Default Volume'**
  String get playerDefaultVolume;

  /// No description provided for @playerResetEpisodeSettings.
  ///
  /// In en, this message translates to:
  /// **'Reset This Video Settings'**
  String get playerResetEpisodeSettings;

  /// No description provided for @playerResetEpisodeSettingsDone.
  ///
  /// In en, this message translates to:
  /// **'Restored this video to global defaults'**
  String get playerResetEpisodeSettingsDone;

  /// Player settings group: core playback
  ///
  /// In en, this message translates to:
  /// **'Playback Core'**
  String get playerCoreGroup;

  /// Player settings group: subtitle
  ///
  /// In en, this message translates to:
  /// **'Subtitle'**
  String get playerSubtitleGroup;

  /// Player settings group: gesture and control
  ///
  /// In en, this message translates to:
  /// **'Gesture & Control'**
  String get playerGestureGroup;

  /// Player settings group: screenshot
  ///
  /// In en, this message translates to:
  /// **'Screenshot'**
  String get playerScreenshotGroup;

  /// No description provided for @novelDefaultGroupTitle.
  ///
  /// In en, this message translates to:
  /// **'Novel Defaults'**
  String get novelDefaultGroupTitle;

  /// No description provided for @novelDefaultPageTurnAnimation.
  ///
  /// In en, this message translates to:
  /// **'Page Turn Animation'**
  String get novelDefaultPageTurnAnimation;

  /// No description provided for @novelDefaultFontSize.
  ///
  /// In en, this message translates to:
  /// **'Default font size'**
  String get novelDefaultFontSize;

  /// No description provided for @novelDefaultLineHeight.
  ///
  /// In en, this message translates to:
  /// **'Default line height'**
  String get novelDefaultLineHeight;

  /// No description provided for @novelDefaultBackground.
  ///
  /// In en, this message translates to:
  /// **'Background'**
  String get novelDefaultBackground;

  /// No description provided for @novelDefaultTtsRate.
  ///
  /// In en, this message translates to:
  /// **'TTS Rate'**
  String get novelDefaultTtsRate;

  /// No description provided for @novelDefaultChineseConversion.
  ///
  /// In en, this message translates to:
  /// **'Chinese Conversion'**
  String get novelDefaultChineseConversion;

  /// No description provided for @novelBgWhite.
  ///
  /// In en, this message translates to:
  /// **'White'**
  String get novelBgWhite;

  /// No description provided for @novelBgCream.
  ///
  /// In en, this message translates to:
  /// **'Cream'**
  String get novelBgCream;

  /// No description provided for @novelBgDarkGray.
  ///
  /// In en, this message translates to:
  /// **'Dark Gray'**
  String get novelBgDarkGray;

  /// No description provided for @novelBgBlack.
  ///
  /// In en, this message translates to:
  /// **'Black'**
  String get novelBgBlack;

  /// No description provided for @comicDefaultGroupTitle.
  ///
  /// In en, this message translates to:
  /// **'Comic Defaults'**
  String get comicDefaultGroupTitle;

  /// No description provided for @comicDefaultReadingDirection.
  ///
  /// In en, this message translates to:
  /// **'Reading Direction'**
  String get comicDefaultReadingDirection;

  /// No description provided for @comicDefaultTapZoneLayout.
  ///
  /// In en, this message translates to:
  /// **'Tap Zone Layout'**
  String get comicDefaultTapZoneLayout;

  /// No description provided for @comicDefaultInvertFilter.
  ///
  /// In en, this message translates to:
  /// **'Invert Filter'**
  String get comicDefaultInvertFilter;

  /// No description provided for @comicDefaultInitialZoom.
  ///
  /// In en, this message translates to:
  /// **'Initial Zoom'**
  String get comicDefaultInitialZoom;

  /// No description provided for @comicDefaultDoubleTapZoom.
  ///
  /// In en, this message translates to:
  /// **'Double Tap Zoom'**
  String get comicDefaultDoubleTapZoom;

  /// No description provided for @comicDefaultScrollWheel.
  ///
  /// In en, this message translates to:
  /// **'Scroll Wheel Direction'**
  String get comicDefaultScrollWheel;

  /// No description provided for @comicTapLayout1.
  ///
  /// In en, this message translates to:
  /// **'Layout 1'**
  String get comicTapLayout1;

  /// No description provided for @comicTapLayout2.
  ///
  /// In en, this message translates to:
  /// **'Layout 2'**
  String get comicTapLayout2;

  /// No description provided for @comicTapLayout3.
  ///
  /// In en, this message translates to:
  /// **'Layout 3'**
  String get comicTapLayout3;

  /// No description provided for @comicTapLayout4.
  ///
  /// In en, this message translates to:
  /// **'Layout 4'**
  String get comicTapLayout4;

  /// No description provided for @comicTapLayout5.
  ///
  /// In en, this message translates to:
  /// **'Layout 5'**
  String get comicTapLayout5;

  /// No description provided for @comicZoomFitWidth.
  ///
  /// In en, this message translates to:
  /// **'Fit Width'**
  String get comicZoomFitWidth;

  /// No description provided for @comicZoomFitHeight.
  ///
  /// In en, this message translates to:
  /// **'Fit Height'**
  String get comicZoomFitHeight;

  /// No description provided for @comicZoomOriginal.
  ///
  /// In en, this message translates to:
  /// **'Original'**
  String get comicZoomOriginal;

  /// No description provided for @comicZoom2x.
  ///
  /// In en, this message translates to:
  /// **'2x'**
  String get comicZoom2x;

  /// No description provided for @comicZoom3x.
  ///
  /// In en, this message translates to:
  /// **'3x'**
  String get comicZoom3x;

  /// No description provided for @comicWheelNatural.
  ///
  /// In en, this message translates to:
  /// **'Natural'**
  String get comicWheelNatural;

  /// No description provided for @comicWheelInverted.
  ///
  /// In en, this message translates to:
  /// **'Inverted'**
  String get comicWheelInverted;

  /// No description provided for @comicDirLtr.
  ///
  /// In en, this message translates to:
  /// **'LTR'**
  String get comicDirLtr;

  /// No description provided for @comicDirRtl.
  ///
  /// In en, this message translates to:
  /// **'RTL'**
  String get comicDirRtl;

  /// No description provided for @comicDirVertical.
  ///
  /// In en, this message translates to:
  /// **'Vertical'**
  String get comicDirVertical;

  /// No description provided for @comicDirWebtoon.
  ///
  /// In en, this message translates to:
  /// **'Webtoon'**
  String get comicDirWebtoon;

  /// No description provided for @comicDirWebtoonGap.
  ///
  /// In en, this message translates to:
  /// **'Webtoon (gap)'**
  String get comicDirWebtoonGap;

  /// No description provided for @danmakuDisplayFontSize.
  ///
  /// In en, this message translates to:
  /// **'Font Size'**
  String get danmakuDisplayFontSize;

  /// No description provided for @danmakuDisplayOpacity.
  ///
  /// In en, this message translates to:
  /// **'Opacity'**
  String get danmakuDisplayOpacity;

  /// No description provided for @danmakuDisplayScrollSpeed.
  ///
  /// In en, this message translates to:
  /// **'Scroll Speed'**
  String get danmakuDisplayScrollSpeed;

  /// No description provided for @danmakuDisplayArea.
  ///
  /// In en, this message translates to:
  /// **'Display Area'**
  String get danmakuDisplayArea;

  /// No description provided for @danmakuDisplayMaxOnScreen.
  ///
  /// In en, this message translates to:
  /// **'Max On Screen'**
  String get danmakuDisplayMaxOnScreen;

  /// No description provided for @danmakuSizeSmall.
  ///
  /// In en, this message translates to:
  /// **'Small'**
  String get danmakuSizeSmall;

  /// No description provided for @danmakuSizeMedium.
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get danmakuSizeMedium;

  /// No description provided for @danmakuSizeLarge.
  ///
  /// In en, this message translates to:
  /// **'Large'**
  String get danmakuSizeLarge;

  /// No description provided for @danmakuSpeedSlow.
  ///
  /// In en, this message translates to:
  /// **'Slow'**
  String get danmakuSpeedSlow;

  /// No description provided for @danmakuSpeedMedium.
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get danmakuSpeedMedium;

  /// No description provided for @danmakuSpeedFast.
  ///
  /// In en, this message translates to:
  /// **'Fast'**
  String get danmakuSpeedFast;

  /// No description provided for @danmakuAreaQuarter.
  ///
  /// In en, this message translates to:
  /// **'Quarter'**
  String get danmakuAreaQuarter;

  /// No description provided for @danmakuAreaHalf.
  ///
  /// In en, this message translates to:
  /// **'Half'**
  String get danmakuAreaHalf;

  /// No description provided for @danmakuAreaFull.
  ///
  /// In en, this message translates to:
  /// **'Full'**
  String get danmakuAreaFull;

  /// No description provided for @danmakuMaxTen.
  ///
  /// In en, this message translates to:
  /// **'10'**
  String get danmakuMaxTen;

  /// No description provided for @danmakuMaxTwenty.
  ///
  /// In en, this message translates to:
  /// **'20'**
  String get danmakuMaxTwenty;

  /// No description provided for @danmakuMaxFifty.
  ///
  /// In en, this message translates to:
  /// **'50'**
  String get danmakuMaxFifty;

  /// No description provided for @danmakuMaxHundred.
  ///
  /// In en, this message translates to:
  /// **'100'**
  String get danmakuMaxHundred;

  /// Danmaku display group: filter and block
  ///
  /// In en, this message translates to:
  /// **'Filter & Block'**
  String get danmakuDisplayGroupFilter;

  /// Danmaku display group: appearance
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get danmakuDisplayGroupAppearance;

  /// Danmaku display group: display
  ///
  /// In en, this message translates to:
  /// **'Display'**
  String get danmakuDisplayGroupDisplay;

  /// Danmaku display group: display range
  ///
  /// In en, this message translates to:
  /// **'Display Range'**
  String get danmakuDisplayGroupDisplayRange;

  /// Danmaku display group: speed
  ///
  /// In en, this message translates to:
  /// **'Speed'**
  String get danmakuDisplayGroupSpeed;

  /// No description provided for @layoutTypeLabel.
  ///
  /// In en, this message translates to:
  /// **'Layout Type'**
  String get layoutTypeLabel;

  /// No description provided for @layoutGridLarge.
  ///
  /// In en, this message translates to:
  /// **'Large Grid'**
  String get layoutGridLarge;

  /// No description provided for @layoutGridMedium.
  ///
  /// In en, this message translates to:
  /// **'Medium Grid'**
  String get layoutGridMedium;

  /// No description provided for @layoutGridSmall.
  ///
  /// In en, this message translates to:
  /// **'Small Grid'**
  String get layoutGridSmall;

  /// No description provided for @layoutListComfortable.
  ///
  /// In en, this message translates to:
  /// **'Comfortable List'**
  String get layoutListComfortable;

  /// No description provided for @layoutListCompact.
  ///
  /// In en, this message translates to:
  /// **'Compact List'**
  String get layoutListCompact;

  /// No description provided for @layoutGridColumns.
  ///
  /// In en, this message translates to:
  /// **'Grid Columns'**
  String get layoutGridColumns;

  /// No description provided for @layoutGridSpacing.
  ///
  /// In en, this message translates to:
  /// **'Grid Spacing'**
  String get layoutGridSpacing;

  /// No description provided for @layoutCoverRadius.
  ///
  /// In en, this message translates to:
  /// **'Cover Radius'**
  String get layoutCoverRadius;

  /// No description provided for @layoutTitleFontSize.
  ///
  /// In en, this message translates to:
  /// **'Title Font Size'**
  String get layoutTitleFontSize;

  /// No description provided for @layoutShowTitle.
  ///
  /// In en, this message translates to:
  /// **'Show Title'**
  String get layoutShowTitle;

  /// No description provided for @layoutTitleMaxLines.
  ///
  /// In en, this message translates to:
  /// **'Title Max Lines'**
  String get layoutTitleMaxLines;

  /// No description provided for @layoutShowAuthor.
  ///
  /// In en, this message translates to:
  /// **'Show Author'**
  String get layoutShowAuthor;

  /// No description provided for @layoutShowProgress.
  ///
  /// In en, this message translates to:
  /// **'Show Progress'**
  String get layoutShowProgress;

  /// No description provided for @layoutOpenSettings.
  ///
  /// In en, this message translates to:
  /// **'Open Layout Settings'**
  String get layoutOpenSettings;

  /// Layout settings group: bookshelf layout
  ///
  /// In en, this message translates to:
  /// **'Bookshelf Layout'**
  String get bookshelfLayoutGroup;

  /// Layout settings group: layout type
  ///
  /// In en, this message translates to:
  /// **'Global Layout Type'**
  String get layoutTypeGroup;

  /// Layout settings group: grid and cover
  ///
  /// In en, this message translates to:
  /// **'Grid & Cover'**
  String get layoutGridCoverGroup;

  /// Layout settings group: display options
  ///
  /// In en, this message translates to:
  /// **'Display Options'**
  String get layoutDisplayGroup;

  /// No description provided for @downloadStatusInProgress.
  ///
  /// In en, this message translates to:
  /// **'In Progress'**
  String get downloadStatusInProgress;

  /// No description provided for @cloudSyncWebdavUrl.
  ///
  /// In en, this message translates to:
  /// **'WebDAV URL'**
  String get cloudSyncWebdavUrl;

  /// No description provided for @cloudSyncWebdavUsername.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get cloudSyncWebdavUsername;

  /// No description provided for @cloudSyncWebdavPassword.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get cloudSyncWebdavPassword;

  /// No description provided for @cloudSyncTestConnection.
  ///
  /// In en, this message translates to:
  /// **'Test Connection'**
  String get cloudSyncTestConnection;

  /// No description provided for @cloudSyncConnectionSuccess.
  ///
  /// In en, this message translates to:
  /// **'Connected ({ms}ms)'**
  String cloudSyncConnectionSuccess(int ms);

  /// No description provided for @cloudSyncConnectionFailed.
  ///
  /// In en, this message translates to:
  /// **'Connection Failed'**
  String get cloudSyncConnectionFailed;

  /// No description provided for @cloudSyncAutoSync.
  ///
  /// In en, this message translates to:
  /// **'Auto Sync'**
  String get cloudSyncAutoSync;

  /// No description provided for @cloudSyncSyncFrequencyManual.
  ///
  /// In en, this message translates to:
  /// **'Manual'**
  String get cloudSyncSyncFrequencyManual;

  /// No description provided for @cloudSyncSyncFrequencyDaily.
  ///
  /// In en, this message translates to:
  /// **'Daily'**
  String get cloudSyncSyncFrequencyDaily;

  /// No description provided for @cloudSyncSyncFrequencyWeekly.
  ///
  /// In en, this message translates to:
  /// **'Weekly'**
  String get cloudSyncSyncFrequencyWeekly;

  /// No description provided for @cloudSyncSyncNow.
  ///
  /// In en, this message translates to:
  /// **'Sync Now'**
  String get cloudSyncSyncNow;

  /// No description provided for @novelProgressSyncNow.
  ///
  /// In en, this message translates to:
  /// **'Sync reading progress'**
  String get novelProgressSyncNow;

  /// No description provided for @novelProgressConflictTitle.
  ///
  /// In en, this message translates to:
  /// **'Reading progress conflict'**
  String get novelProgressConflictTitle;

  /// No description provided for @novelProgressConflictBody.
  ///
  /// In en, this message translates to:
  /// **'Cloud progress is ahead for {n} books. Use cloud progress?'**
  String novelProgressConflictBody(int n);

  /// No description provided for @novelProgressUseRemote.
  ///
  /// In en, this message translates to:
  /// **'Use cloud'**
  String get novelProgressUseRemote;

  /// No description provided for @novelProgressSyncedUploaded.
  ///
  /// In en, this message translates to:
  /// **'{n} uploaded'**
  String novelProgressSyncedUploaded(int n);

  /// No description provided for @novelProgressSyncedRestored.
  ///
  /// In en, this message translates to:
  /// **'{n} restored'**
  String novelProgressSyncedRestored(int n);

  /// No description provided for @novelProgressSyncedConflicted.
  ///
  /// In en, this message translates to:
  /// **'{n} need confirmation'**
  String novelProgressSyncedConflicted(int n);

  /// No description provided for @novelProgressSyncedNone.
  ///
  /// In en, this message translates to:
  /// **'No progress changes'**
  String get novelProgressSyncedNone;

  /// No description provided for @cloudSyncLastSyncTime.
  ///
  /// In en, this message translates to:
  /// **'Last sync: {time}'**
  String cloudSyncLastSyncTime(String time);

  /// No description provided for @cloudSyncNeverSynced.
  ///
  /// In en, this message translates to:
  /// **'Never synced'**
  String get cloudSyncNeverSynced;

  /// No description provided for @cloudSyncSyncSuccess.
  ///
  /// In en, this message translates to:
  /// **'Sync successful'**
  String get cloudSyncSyncSuccess;

  /// No description provided for @cloudSyncSyncFailed.
  ///
  /// In en, this message translates to:
  /// **'Sync failed'**
  String get cloudSyncSyncFailed;

  /// No description provided for @cloudSyncSaveConfig.
  ///
  /// In en, this message translates to:
  /// **'Save Config'**
  String get cloudSyncSaveConfig;

  /// No description provided for @readingProgress.
  ///
  /// In en, this message translates to:
  /// **'Reading progress'**
  String get readingProgress;

  /// No description provided for @watchingProgress.
  ///
  /// In en, this message translates to:
  /// **'Watching progress'**
  String get watchingProgress;

  /// No description provided for @totalChapters.
  ///
  /// In en, this message translates to:
  /// **'Total chapters'**
  String get totalChapters;

  /// No description provided for @totalEpisodes.
  ///
  /// In en, this message translates to:
  /// **'Total episodes'**
  String get totalEpisodes;

  /// No description provided for @chaptersRead.
  ///
  /// In en, this message translates to:
  /// **'Read'**
  String get chaptersRead;

  /// No description provided for @episodesWatched.
  ///
  /// In en, this message translates to:
  /// **'Watched'**
  String get episodesWatched;

  /// No description provided for @progressLabel.
  ///
  /// In en, this message translates to:
  /// **'Progress'**
  String get progressLabel;

  /// No description provided for @layoutModeLabel.
  ///
  /// In en, this message translates to:
  /// **'Layout mode'**
  String get layoutModeLabel;

  /// No description provided for @layoutListStyle.
  ///
  /// In en, this message translates to:
  /// **'List style'**
  String get layoutListStyle;

  /// No description provided for @lastReadAt.
  ///
  /// In en, this message translates to:
  /// **'Last read'**
  String get lastReadAt;

  /// No description provided for @lastWatchedAt.
  ///
  /// In en, this message translates to:
  /// **'Last watched'**
  String get lastWatchedAt;

  /// No description provided for @anime.
  ///
  /// In en, this message translates to:
  /// **'Anime'**
  String get anime;

  /// No description provided for @episodeList.
  ///
  /// In en, this message translates to:
  /// **'Episodes'**
  String get episodeList;

  /// No description provided for @chapterListWithCount.
  ///
  /// In en, this message translates to:
  /// **'Chapter list ({count})'**
  String chapterListWithCount(int count);

  /// No description provided for @episodeListWithCount.
  ///
  /// In en, this message translates to:
  /// **'Episodes ({count})'**
  String episodeListWithCount(int count);

  /// No description provided for @lastReadInfo.
  ///
  /// In en, this message translates to:
  /// **'Last read: {time} · {chapter}'**
  String lastReadInfo(String time, String chapter);

  /// No description provided for @lastWatchedInfo.
  ///
  /// In en, this message translates to:
  /// **'Last watched: {time} · {episode}'**
  String lastWatchedInfo(String time, String episode);

  /// No description provided for @notStartedYet.
  ///
  /// In en, this message translates to:
  /// **'Not started yet'**
  String get notStartedYet;

  /// No description provided for @timeJustNow.
  ///
  /// In en, this message translates to:
  /// **'Just now'**
  String get timeJustNow;

  /// No description provided for @timeMinutesAgo.
  ///
  /// In en, this message translates to:
  /// **'{n} minutes ago'**
  String timeMinutesAgo(int n);

  /// No description provided for @timeHoursAgo.
  ///
  /// In en, this message translates to:
  /// **'{n} hours ago'**
  String timeHoursAgo(int n);

  /// No description provided for @timeDaysAgo.
  ///
  /// In en, this message translates to:
  /// **'{n} days ago'**
  String timeDaysAgo(int n);

  /// No description provided for @expand.
  ///
  /// In en, this message translates to:
  /// **'Expand'**
  String get expand;

  /// No description provided for @collapse.
  ///
  /// In en, this message translates to:
  /// **'Collapse'**
  String get collapse;

  /// Button: expand to show the remaining N director/cast names
  ///
  /// In en, this message translates to:
  /// **'Show {count} more'**
  String expandCount(int count);

  /// No description provided for @sortSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Sort'**
  String get sortSectionTitle;

  /// No description provided for @displayTitle.
  ///
  /// In en, this message translates to:
  /// **'Display'**
  String get displayTitle;

  /// No description provided for @sortByIndex.
  ///
  /// In en, this message translates to:
  /// **'By {unitWord} index'**
  String sortByIndex(Object unitWord);

  /// No description provided for @sortByName.
  ///
  /// In en, this message translates to:
  /// **'By {unitWord} name'**
  String sortByName(Object unitWord);

  /// No description provided for @sortBySource.
  ///
  /// In en, this message translates to:
  /// **'By source'**
  String get sortBySource;

  /// No description provided for @sortByUploadDate.
  ///
  /// In en, this message translates to:
  /// **'By upload date'**
  String get sortByUploadDate;

  /// No description provided for @sortAscendingLabel.
  ///
  /// In en, this message translates to:
  /// **'Ascending'**
  String get sortAscendingLabel;

  /// No description provided for @sortDescendingLabel.
  ///
  /// In en, this message translates to:
  /// **'Descending'**
  String get sortDescendingLabel;

  /// No description provided for @filterUnread.
  ///
  /// In en, this message translates to:
  /// **'Unread'**
  String get filterUnread;

  /// No description provided for @filterDownloaded.
  ///
  /// In en, this message translates to:
  /// **'Downloaded'**
  String get filterDownloaded;

  /// No description provided for @filterBookmarked.
  ///
  /// In en, this message translates to:
  /// **'Bookmarked'**
  String get filterBookmarked;

  /// No description provided for @displaySourceTitle.
  ///
  /// In en, this message translates to:
  /// **'Source title'**
  String get displaySourceTitle;

  /// No description provided for @displayNumber.
  ///
  /// In en, this message translates to:
  /// **'{unitWord} number'**
  String displayNumber(Object unitWord);

  /// No description provided for @resetButton.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get resetButton;

  /// No description provided for @doneButton.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get doneButton;

  /// No description provided for @wordCount.
  ///
  /// In en, this message translates to:
  /// **'Word count'**
  String get wordCount;

  /// No description provided for @updatedTo.
  ///
  /// In en, this message translates to:
  /// **'Updated to {n}'**
  String updatedTo(Object n);

  /// No description provided for @unitWordChapter.
  ///
  /// In en, this message translates to:
  /// **'chapter'**
  String get unitWordChapter;

  /// No description provided for @unitWordComicChapter.
  ///
  /// In en, this message translates to:
  /// **'chapter'**
  String get unitWordComicChapter;

  /// No description provided for @unitWordEpisode.
  ///
  /// In en, this message translates to:
  /// **'episode'**
  String get unitWordEpisode;

  /// No description provided for @prevPage.
  ///
  /// In en, this message translates to:
  /// **'Previous page'**
  String get prevPage;

  /// No description provided for @nextPage.
  ///
  /// In en, this message translates to:
  /// **'Next page'**
  String get nextPage;

  /// No description provided for @nightMode.
  ///
  /// In en, this message translates to:
  /// **'Night mode'**
  String get nightMode;

  /// No description provided for @toolToc.
  ///
  /// In en, this message translates to:
  /// **'Contents'**
  String get toolToc;

  /// No description provided for @toolPrevChapter.
  ///
  /// In en, this message translates to:
  /// **'Previous chapter'**
  String get toolPrevChapter;

  /// No description provided for @toolNextChapter.
  ///
  /// In en, this message translates to:
  /// **'Next chapter'**
  String get toolNextChapter;

  /// No description provided for @toolNightMode.
  ///
  /// In en, this message translates to:
  /// **'Night mode'**
  String get toolNightMode;

  /// No description provided for @toolAutoPage.
  ///
  /// In en, this message translates to:
  /// **'Auto page'**
  String get toolAutoPage;

  /// No description provided for @toolSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get toolSettings;

  /// No description provided for @toolBookmark.
  ///
  /// In en, this message translates to:
  /// **'Bookmark'**
  String get toolBookmark;

  /// No description provided for @toolBookmarkList.
  ///
  /// In en, this message translates to:
  /// **'Bookmarks'**
  String get toolBookmarkList;

  /// No description provided for @toolSearch.
  ///
  /// In en, this message translates to:
  /// **'Search in book'**
  String get toolSearch;

  /// No description provided for @toolTts.
  ///
  /// In en, this message translates to:
  /// **'Read aloud'**
  String get toolTts;

  /// No description provided for @configureBottomToolbar.
  ///
  /// In en, this message translates to:
  /// **'Configure toolbar'**
  String get configureBottomToolbar;

  /// No description provided for @bottomToolbarConfigTitle.
  ///
  /// In en, this message translates to:
  /// **'Bottom toolbar'**
  String get bottomToolbarConfigTitle;

  /// No description provided for @slotsShown.
  ///
  /// In en, this message translates to:
  /// **'Shown'**
  String get slotsShown;

  /// No description provided for @slotsHidden.
  ///
  /// In en, this message translates to:
  /// **'Hidden (tap + to add)'**
  String get slotsHidden;

  /// No description provided for @novelCacheBook.
  ///
  /// In en, this message translates to:
  /// **'Cache'**
  String get novelCacheBook;

  /// No description provided for @novelResetBookPrefs.
  ///
  /// In en, this message translates to:
  /// **'Reset book to default'**
  String get novelResetBookPrefs;

  /// No description provided for @novelResetBookDone.
  ///
  /// In en, this message translates to:
  /// **'Book settings reset to default'**
  String get novelResetBookDone;

  /// No description provided for @readerCropEdge.
  ///
  /// In en, this message translates to:
  /// **'Crop edges'**
  String get readerCropEdge;

  /// No description provided for @readerRotatePage.
  ///
  /// In en, this message translates to:
  /// **'Rotate page'**
  String get readerRotatePage;

  /// No description provided for @readerKeepScreenOn.
  ///
  /// In en, this message translates to:
  /// **'Keep screen on'**
  String get readerKeepScreenOn;

  /// No description provided for @readerProgressBarOnRight.
  ///
  /// In en, this message translates to:
  /// **'Progress bar on right'**
  String get readerProgressBarOnRight;

  /// No description provided for @readerShowChapterSlider.
  ///
  /// In en, this message translates to:
  /// **'Chapter navigation slider'**
  String get readerShowChapterSlider;

  /// No description provided for @readerShowPageNumber.
  ///
  /// In en, this message translates to:
  /// **'Show page number'**
  String get readerShowPageNumber;

  /// No description provided for @readerSplitDoublePage.
  ///
  /// In en, this message translates to:
  /// **'Split double page'**
  String get readerSplitDoublePage;

  /// No description provided for @readerSplitDoublePageHint.
  ///
  /// In en, this message translates to:
  /// **'Double-page split enabled; switched to horizontal single-page mode'**
  String get readerSplitDoublePageHint;

  /// No description provided for @readerInitialZoom.
  ///
  /// In en, this message translates to:
  /// **'Initial zoom'**
  String get readerInitialZoom;

  /// No description provided for @readerZoomFitWidth.
  ///
  /// In en, this message translates to:
  /// **'Fit width'**
  String get readerZoomFitWidth;

  /// No description provided for @readerZoomFitHeight.
  ///
  /// In en, this message translates to:
  /// **'Fit height'**
  String get readerZoomFitHeight;

  /// No description provided for @readerZoomOriginal.
  ///
  /// In en, this message translates to:
  /// **'Original size'**
  String get readerZoomOriginal;

  /// No description provided for @readerFullscreen.
  ///
  /// In en, this message translates to:
  /// **'Fullscreen'**
  String get readerFullscreen;

  /// No description provided for @readerLongPressMenu.
  ///
  /// In en, this message translates to:
  /// **'Long-press menu'**
  String get readerLongPressMenu;

  /// No description provided for @readerGrayscale.
  ///
  /// In en, this message translates to:
  /// **'Grayscale'**
  String get readerGrayscale;

  /// No description provided for @readerPreventShrink.
  ///
  /// In en, this message translates to:
  /// **'Prevent shrink'**
  String get readerPreventShrink;

  /// No description provided for @readerChapterTransition.
  ///
  /// In en, this message translates to:
  /// **'Chapter transition'**
  String get readerChapterTransition;

  /// No description provided for @readerPreloadCount.
  ///
  /// In en, this message translates to:
  /// **'Preload count'**
  String get readerPreloadCount;

  /// No description provided for @readerPreloadCountDesc.
  ///
  /// In en, this message translates to:
  /// **'Pages from the chapter end/start to begin preloading adjacent chapters (higher = smoother, uses more data)'**
  String get readerPreloadCountDesc;

  /// No description provided for @readerSeamlessReading.
  ///
  /// In en, this message translates to:
  /// **'Seamless cross-chapter reading'**
  String get readerSeamlessReading;

  /// No description provided for @readerSeamlessReadingDesc.
  ///
  /// In en, this message translates to:
  /// **'Keep reading the adjacent chapter right at the chapter end/start using the preloaded cache, without reloading the chapter or flashing white'**
  String get readerSeamlessReadingDesc;

  /// No description provided for @readerChapterSeparator.
  ///
  /// In en, this message translates to:
  /// **'Chapter separator'**
  String get readerChapterSeparator;

  /// No description provided for @readerChapterSeparatorDesc.
  ///
  /// In en, this message translates to:
  /// **'Insert a chapter title card between chapters in webtoon continuous mode'**
  String get readerChapterSeparatorDesc;

  /// No description provided for @readerWebtoonDecodeLimit.
  ///
  /// In en, this message translates to:
  /// **'Limit webtoon decode size'**
  String get readerWebtoonDecodeLimit;

  /// No description provided for @readerScrollSpeed.
  ///
  /// In en, this message translates to:
  /// **'Scroll speed'**
  String get readerScrollSpeed;

  /// No description provided for @readerScrollSpeedDesc.
  ///
  /// In en, this message translates to:
  /// **'Multiplier applied to the webtoon scroll amount from the mouse wheel (0.5x–3x)'**
  String get readerScrollSpeedDesc;

  /// No description provided for @readerVolumeKeyPageTurn.
  ///
  /// In en, this message translates to:
  /// **'Volume key page turn'**
  String get readerVolumeKeyPageTurn;

  /// No description provided for @readerVolumeKeyPageTurnDesc.
  ///
  /// In en, this message translates to:
  /// **'Intercept volume up/down to turn pages on Android and HarmonyOS (paged: turn page; webtoon: scroll by distance)'**
  String get readerVolumeKeyPageTurnDesc;

  /// No description provided for @readerVolumeKeyDistance.
  ///
  /// In en, this message translates to:
  /// **'Volume key scroll distance'**
  String get readerVolumeKeyDistance;

  /// No description provided for @readerVolumeKeyDistanceDesc.
  ///
  /// In en, this message translates to:
  /// **'How far the volume key scrolls in webtoon mode (percent of viewport height)'**
  String get readerVolumeKeyDistanceDesc;

  /// No description provided for @readerLongPressZoom.
  ///
  /// In en, this message translates to:
  /// **'Long-press to zoom'**
  String get readerLongPressZoom;

  /// No description provided for @readerLongPressZoomDesc.
  ///
  /// In en, this message translates to:
  /// **'Long-press enters 1.75x zoom (long-press/release exits); when off, long-press shows the menu'**
  String get readerLongPressZoomDesc;

  /// No description provided for @readerLongPressAtPress.
  ///
  /// In en, this message translates to:
  /// **'At press point'**
  String get readerLongPressAtPress;

  /// No description provided for @readerLongPressAtCenter.
  ///
  /// In en, this message translates to:
  /// **'Screen center'**
  String get readerLongPressAtCenter;

  /// No description provided for @readerLongPressZoomPosition.
  ///
  /// In en, this message translates to:
  /// **'Long-press zoom anchor'**
  String get readerLongPressZoomPosition;

  /// No description provided for @readerZoomStart.
  ///
  /// In en, this message translates to:
  /// **'Zoom anchor'**
  String get readerZoomStart;

  /// No description provided for @readerZoomStartLeft.
  ///
  /// In en, this message translates to:
  /// **'Left'**
  String get readerZoomStartLeft;

  /// No description provided for @readerZoomStartCenter.
  ///
  /// In en, this message translates to:
  /// **'Center'**
  String get readerZoomStartCenter;

  /// No description provided for @readerZoomStartRight.
  ///
  /// In en, this message translates to:
  /// **'Right'**
  String get readerZoomStartRight;

  /// No description provided for @readerAutoPageTurning.
  ///
  /// In en, this message translates to:
  /// **'Auto page turning'**
  String get readerAutoPageTurning;

  /// No description provided for @readerAutoPageTurningDesc.
  ///
  /// In en, this message translates to:
  /// **'Automatically turn pages in paged mode at a fixed interval (0 = off)'**
  String get readerAutoPageTurningDesc;

  /// No description provided for @readerAutoPageInterval.
  ///
  /// In en, this message translates to:
  /// **'Auto page interval (s)'**
  String get readerAutoPageInterval;

  /// No description provided for @readerAutoScroll.
  ///
  /// In en, this message translates to:
  /// **'Auto scroll'**
  String get readerAutoScroll;

  /// No description provided for @readerAutoScrollDesc.
  ///
  /// In en, this message translates to:
  /// **'Smoothly auto-scroll in webtoon mode at the scroll speed above'**
  String get readerAutoScrollDesc;

  /// No description provided for @readerSleepTimer.
  ///
  /// In en, this message translates to:
  /// **'Sleep timer'**
  String get readerSleepTimer;

  /// No description provided for @readerSleepTimerDesc.
  ///
  /// In en, this message translates to:
  /// **'Pause reading after a set time or chapter count'**
  String get readerSleepTimerDesc;

  /// No description provided for @readerSleepTimerOff.
  ///
  /// In en, this message translates to:
  /// **'Turn off timer'**
  String get readerSleepTimerOff;

  /// No description provided for @readerSleepTimerChapters.
  ///
  /// In en, this message translates to:
  /// **'Pause after {count} more chapters'**
  String readerSleepTimerChapters(Object count);

  /// No description provided for @readerSleepTimerFired.
  ///
  /// In en, this message translates to:
  /// **'Sleep timer fired, reading paused'**
  String get readerSleepTimerFired;

  /// No description provided for @readerPageAnimation.
  ///
  /// In en, this message translates to:
  /// **'Page transition animation'**
  String get readerPageAnimation;

  /// No description provided for @readerPageAnimNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get readerPageAnimNone;

  /// No description provided for @readerPageAnimSlide.
  ///
  /// In en, this message translates to:
  /// **'Slide'**
  String get readerPageAnimSlide;

  /// No description provided for @readerPageAnimFade.
  ///
  /// In en, this message translates to:
  /// **'Fade'**
  String get readerPageAnimFade;

  /// No description provided for @motionEffectTitle.
  ///
  /// In en, this message translates to:
  /// **'Motion effects'**
  String get motionEffectTitle;

  /// No description provided for @motionEffectDesc.
  ///
  /// In en, this message translates to:
  /// **'Render static comic pages into layered motion (parallax / breathing / particles / light / manga action). Works in paged and webtoon modes'**
  String get motionEffectDesc;

  /// No description provided for @motionEffectEnabled.
  ///
  /// In en, this message translates to:
  /// **'Enable motion effects'**
  String get motionEffectEnabled;

  /// No description provided for @motionEffectEnabledDesc.
  ///
  /// In en, this message translates to:
  /// **'About a second after you stop on a page (page turn or scroll settle) it is rendered in the background; toggle and tune each effect below'**
  String get motionEffectEnabledDesc;

  /// No description provided for @motionInteractiveTitle.
  ///
  /// In en, this message translates to:
  /// **'Interactive reading'**
  String get motionInteractiveTitle;

  /// No description provided for @motionInteractiveDesc.
  ///
  /// In en, this message translates to:
  /// **'In single-page paged mode, tap the centre of the page to focus it and reveal the motion through a tear; tap again to dismiss. Zoomed, rotated, webtoon and double-page views keep the plain motion overlay'**
  String get motionInteractiveDesc;

  /// No description provided for @motionEffectStateOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get motionEffectStateOff;

  /// No description provided for @motionEffectStateOn.
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get motionEffectStateOn;

  /// No description provided for @motionPresets.
  ///
  /// In en, this message translates to:
  /// **'Quick presets'**
  String get motionPresets;

  /// No description provided for @motionPresetClassic.
  ///
  /// In en, this message translates to:
  /// **'Classic'**
  String get motionPresetClassic;

  /// No description provided for @motionPresetSakura.
  ///
  /// In en, this message translates to:
  /// **'Sakura'**
  String get motionPresetSakura;

  /// No description provided for @motionPresetNightRain.
  ///
  /// In en, this message translates to:
  /// **'Night rain'**
  String get motionPresetNightRain;

  /// No description provided for @motionPresetStarryNight.
  ///
  /// In en, this message translates to:
  /// **'Starry night'**
  String get motionPresetStarryNight;

  /// No description provided for @motionPresetBattle.
  ///
  /// In en, this message translates to:
  /// **'Battle'**
  String get motionPresetBattle;

  /// No description provided for @motionQuality.
  ///
  /// In en, this message translates to:
  /// **'Quality & smoothness'**
  String get motionQuality;

  /// No description provided for @motionFps.
  ///
  /// In en, this message translates to:
  /// **'Frame rate'**
  String get motionFps;

  /// No description provided for @motionDuration.
  ///
  /// In en, this message translates to:
  /// **'Loop duration'**
  String get motionDuration;

  /// No description provided for @motionResolution.
  ///
  /// In en, this message translates to:
  /// **'Render resolution cap'**
  String get motionResolution;

  /// No description provided for @motionQualityHint.
  ///
  /// In en, this message translates to:
  /// **'Higher values look sharper but render slower and produce larger GIFs. Pages are rendered in the background shortly after you stop on them; zooming in temporarily falls back to the static image'**
  String get motionQualityHint;

  /// No description provided for @motionWebtoonModeTitle.
  ///
  /// In en, this message translates to:
  /// **'Webtoon render timing'**
  String get motionWebtoonModeTitle;

  /// No description provided for @motionWebtoonModeDwell.
  ///
  /// In en, this message translates to:
  /// **'On settle (battery saver)'**
  String get motionWebtoonModeDwell;

  /// No description provided for @motionWebtoonModeFollow.
  ///
  /// In en, this message translates to:
  /// **'Realtime follow (more battery)'**
  String get motionWebtoonModeFollow;

  /// No description provided for @motionWebtoonModeHint.
  ///
  /// In en, this message translates to:
  /// **'On settle: visible pages are rendered only after scrolling stops for about a second. Realtime follow: the render target switches as your view moves — a fast preview (fewer frames / lower resolution) appears while scrolling and is automatically upgraded to full quality once you stop, at higher CPU / battery cost'**
  String get motionWebtoonModeHint;

  /// No description provided for @motionEffectCountHint.
  ///
  /// In en, this message translates to:
  /// **'Each effect can be toggled independently and expanded to tune its parameters. Turning all off equals a static page'**
  String get motionEffectCountHint;

  /// No description provided for @motionGroupAmbient.
  ///
  /// In en, this message translates to:
  /// **'Ambient basics'**
  String get motionGroupAmbient;

  /// No description provided for @motionGroupParticles.
  ///
  /// In en, this message translates to:
  /// **'Particles & weather'**
  String get motionGroupParticles;

  /// No description provided for @motionGroupLight.
  ///
  /// In en, this message translates to:
  /// **'Light & shadow'**
  String get motionGroupLight;

  /// No description provided for @motionGroupManga.
  ///
  /// In en, this message translates to:
  /// **'Manga action'**
  String get motionGroupManga;

  /// No description provided for @motionFxParallax.
  ///
  /// In en, this message translates to:
  /// **'Parallax'**
  String get motionFxParallax;

  /// No description provided for @motionFxBreathing.
  ///
  /// In en, this message translates to:
  /// **'Breathing'**
  String get motionFxBreathing;

  /// No description provided for @motionFxSlowPush.
  ///
  /// In en, this message translates to:
  /// **'Slow push-in'**
  String get motionFxSlowPush;

  /// No description provided for @motionFxHeartbeat.
  ///
  /// In en, this message translates to:
  /// **'Heartbeat'**
  String get motionFxHeartbeat;

  /// No description provided for @motionFxToneShift.
  ///
  /// In en, this message translates to:
  /// **'Tone shift'**
  String get motionFxToneShift;

  /// No description provided for @motionFxVignette.
  ///
  /// In en, this message translates to:
  /// **'Vignette'**
  String get motionFxVignette;

  /// No description provided for @motionFxAmbient.
  ///
  /// In en, this message translates to:
  /// **'Ambient particles'**
  String get motionFxAmbient;

  /// No description provided for @motionFxDust.
  ///
  /// In en, this message translates to:
  /// **'Dust'**
  String get motionFxDust;

  /// No description provided for @motionFxRain.
  ///
  /// In en, this message translates to:
  /// **'Rain'**
  String get motionFxRain;

  /// No description provided for @motionFxSnow.
  ///
  /// In en, this message translates to:
  /// **'Snow'**
  String get motionFxSnow;

  /// No description provided for @motionFxSakura.
  ///
  /// In en, this message translates to:
  /// **'Sakura petals'**
  String get motionFxSakura;

  /// No description provided for @motionFxLeaves.
  ///
  /// In en, this message translates to:
  /// **'Falling leaves'**
  String get motionFxLeaves;

  /// No description provided for @motionFxBubbles.
  ///
  /// In en, this message translates to:
  /// **'Bubbles'**
  String get motionFxBubbles;

  /// No description provided for @motionFxFireflies.
  ///
  /// In en, this message translates to:
  /// **'Fireflies'**
  String get motionFxFireflies;

  /// No description provided for @motionFxEmbers.
  ///
  /// In en, this message translates to:
  /// **'Embers'**
  String get motionFxEmbers;

  /// No description provided for @motionFxMeteors.
  ///
  /// In en, this message translates to:
  /// **'Meteors'**
  String get motionFxMeteors;

  /// No description provided for @motionFxFog.
  ///
  /// In en, this message translates to:
  /// **'Fog'**
  String get motionFxFog;

  /// No description provided for @motionFxSmoke.
  ///
  /// In en, this message translates to:
  /// **'Smoke'**
  String get motionFxSmoke;

  /// No description provided for @motionFxFlame.
  ///
  /// In en, this message translates to:
  /// **'Flame'**
  String get motionFxFlame;

  /// No description provided for @motionFxGodRays.
  ///
  /// In en, this message translates to:
  /// **'God rays'**
  String get motionFxGodRays;

  /// No description provided for @motionFxLightSweep.
  ///
  /// In en, this message translates to:
  /// **'Light sweep'**
  String get motionFxLightSweep;

  /// No description provided for @motionFxShimmer.
  ///
  /// In en, this message translates to:
  /// **'Shimmer'**
  String get motionFxShimmer;

  /// No description provided for @motionFxStarlight.
  ///
  /// In en, this message translates to:
  /// **'Starlight'**
  String get motionFxStarlight;

  /// No description provided for @motionFxLightning.
  ///
  /// In en, this message translates to:
  /// **'Lightning'**
  String get motionFxLightning;

  /// No description provided for @motionFxImpactFlash.
  ///
  /// In en, this message translates to:
  /// **'Impact flash'**
  String get motionFxImpactFlash;

  /// No description provided for @motionFxSpeedLines.
  ///
  /// In en, this message translates to:
  /// **'Speed lines'**
  String get motionFxSpeedLines;

  /// No description provided for @motionFxFocusLines.
  ///
  /// In en, this message translates to:
  /// **'Focus lines'**
  String get motionFxFocusLines;

  /// No description provided for @motionFxScreenTone.
  ///
  /// In en, this message translates to:
  /// **'Screen tone'**
  String get motionFxScreenTone;

  /// No description provided for @motionFxMangaShake.
  ///
  /// In en, this message translates to:
  /// **'Screen shake'**
  String get motionFxMangaShake;

  /// No description provided for @motionFxImpactRings.
  ///
  /// In en, this message translates to:
  /// **'Impact rings'**
  String get motionFxImpactRings;

  /// No description provided for @motionFxBrushStreak.
  ///
  /// In en, this message translates to:
  /// **'Brush streaks'**
  String get motionFxBrushStreak;

  /// No description provided for @motionFxMoodScript.
  ///
  /// In en, this message translates to:
  /// **'Mood modulation'**
  String get motionFxMoodScript;

  /// No description provided for @motionParamAmplitude.
  ///
  /// In en, this message translates to:
  /// **'Amplitude'**
  String get motionParamAmplitude;

  /// No description provided for @motionParamPeriod.
  ///
  /// In en, this message translates to:
  /// **'Period (s)'**
  String get motionParamPeriod;

  /// No description provided for @motionParamVerticalRatio.
  ///
  /// In en, this message translates to:
  /// **'Vertical ratio'**
  String get motionParamVerticalRatio;

  /// No description provided for @motionParamPushFrac.
  ///
  /// In en, this message translates to:
  /// **'Push amount'**
  String get motionParamPushFrac;

  /// No description provided for @motionParamBeats.
  ///
  /// In en, this message translates to:
  /// **'Beats'**
  String get motionParamBeats;

  /// No description provided for @motionParamIntensity.
  ///
  /// In en, this message translates to:
  /// **'Intensity'**
  String get motionParamIntensity;

  /// No description provided for @motionParamShift.
  ///
  /// In en, this message translates to:
  /// **'Shift'**
  String get motionParamShift;

  /// No description provided for @motionParamStrength.
  ///
  /// In en, this message translates to:
  /// **'Depth'**
  String get motionParamStrength;

  /// No description provided for @motionParamCount.
  ///
  /// In en, this message translates to:
  /// **'Count'**
  String get motionParamCount;

  /// No description provided for @motionParamSpeed.
  ///
  /// In en, this message translates to:
  /// **'Speed'**
  String get motionParamSpeed;

  /// No description provided for @motionParamOpacity.
  ///
  /// In en, this message translates to:
  /// **'Opacity'**
  String get motionParamOpacity;

  /// No description provided for @motionParamAngle.
  ///
  /// In en, this message translates to:
  /// **'Angle'**
  String get motionParamAngle;

  /// No description provided for @motionParamSize.
  ///
  /// In en, this message translates to:
  /// **'Size'**
  String get motionParamSize;

  /// No description provided for @motionParamSpin.
  ///
  /// In en, this message translates to:
  /// **'Spins'**
  String get motionParamSpin;

  /// No description provided for @motionParamGlow.
  ///
  /// In en, this message translates to:
  /// **'Glow'**
  String get motionParamGlow;

  /// No description provided for @motionParamLengthFrac.
  ///
  /// In en, this message translates to:
  /// **'Length'**
  String get motionParamLengthFrac;

  /// No description provided for @motionParamBlobs.
  ///
  /// In en, this message translates to:
  /// **'Blobs'**
  String get motionParamBlobs;

  /// No description provided for @motionParamPuffs.
  ///
  /// In en, this message translates to:
  /// **'Puffs'**
  String get motionParamPuffs;

  /// No description provided for @motionParamTongues.
  ///
  /// In en, this message translates to:
  /// **'Tongues'**
  String get motionParamTongues;

  /// No description provided for @motionParamRows.
  ///
  /// In en, this message translates to:
  /// **'Rows'**
  String get motionParamRows;

  /// No description provided for @motionParamStrikes.
  ///
  /// In en, this message translates to:
  /// **'Strikes'**
  String get motionParamStrikes;

  /// No description provided for @motionParamFlashes.
  ///
  /// In en, this message translates to:
  /// **'Flashes'**
  String get motionParamFlashes;

  /// No description provided for @motionParamPulses.
  ///
  /// In en, this message translates to:
  /// **'Pulses'**
  String get motionParamPulses;

  /// No description provided for @motionParamLines.
  ///
  /// In en, this message translates to:
  /// **'Lines'**
  String get motionParamLines;

  /// No description provided for @motionParamSpacing.
  ///
  /// In en, this message translates to:
  /// **'Spacing'**
  String get motionParamSpacing;

  /// No description provided for @motionParamDensity.
  ///
  /// In en, this message translates to:
  /// **'Density'**
  String get motionParamDensity;

  /// No description provided for @motionParamShakes.
  ///
  /// In en, this message translates to:
  /// **'Shakes'**
  String get motionParamShakes;

  /// No description provided for @motionParamRings.
  ///
  /// In en, this message translates to:
  /// **'Rings'**
  String get motionParamRings;

  /// No description provided for @motionParamStreaks.
  ///
  /// In en, this message translates to:
  /// **'Streaks'**
  String get motionParamStreaks;

  /// No description provided for @motionParamHeightFrac.
  ///
  /// In en, this message translates to:
  /// **'Height'**
  String get motionParamHeightFrac;

  /// No description provided for @readerDoubleTapAnimSpeed.
  ///
  /// In en, this message translates to:
  /// **'Double-tap zoom animation'**
  String get readerDoubleTapAnimSpeed;

  /// No description provided for @readerDoubleTapAnimSpeedDesc.
  ///
  /// In en, this message translates to:
  /// **'Duration of the double-tap zoom animation in milliseconds (scaled with system reduce-motion)'**
  String get readerDoubleTapAnimSpeedDesc;

  /// No description provided for @readerPageSpacing.
  ///
  /// In en, this message translates to:
  /// **'Page spacing'**
  String get readerPageSpacing;

  /// No description provided for @readerPageSpacingDesc.
  ///
  /// In en, this message translates to:
  /// **'Gap between webtoon pages (px)'**
  String get readerPageSpacingDesc;

  /// No description provided for @readerShowSingleImageOnFirstPage.
  ///
  /// In en, this message translates to:
  /// **'Single image on first page'**
  String get readerShowSingleImageOnFirstPage;

  /// No description provided for @readerShowSingleImageOnFirstPageDesc.
  ///
  /// In en, this message translates to:
  /// **'Show the first page alone in spread mode on chapter one, then resume spread'**
  String get readerShowSingleImageOnFirstPageDesc;

  /// No description provided for @readerClockBattery.
  ///
  /// In en, this message translates to:
  /// **'Clock / battery overlay'**
  String get readerClockBattery;

  /// No description provided for @readerClockBatteryDesc.
  ///
  /// In en, this message translates to:
  /// **'Show current time and battery in the reader, toggled with the controls'**
  String get readerClockBatteryDesc;

  /// No description provided for @readerClockPosition.
  ///
  /// In en, this message translates to:
  /// **'Overlay position'**
  String get readerClockPosition;

  /// No description provided for @readerClockPosTop.
  ///
  /// In en, this message translates to:
  /// **'Top'**
  String get readerClockPosTop;

  /// No description provided for @readerClockPosBottom.
  ///
  /// In en, this message translates to:
  /// **'Bottom'**
  String get readerClockPosBottom;

  /// No description provided for @readerClockMargin.
  ///
  /// In en, this message translates to:
  /// **'Margin'**
  String get readerClockMargin;

  /// No description provided for @readerClockOpacity.
  ///
  /// In en, this message translates to:
  /// **'Opacity'**
  String get readerClockOpacity;

  /// No description provided for @readerClockFontSize.
  ///
  /// In en, this message translates to:
  /// **'Font size'**
  String get readerClockFontSize;

  /// No description provided for @readerBrightness.
  ///
  /// In en, this message translates to:
  /// **'Reading brightness'**
  String get readerBrightness;

  /// No description provided for @readerBrightnessDesc.
  ///
  /// In en, this message translates to:
  /// **'Positive writes to system brightness; negative dims system brightness and overlays a black mask'**
  String get readerBrightnessDesc;

  /// No description provided for @readerNightLight.
  ///
  /// In en, this message translates to:
  /// **'Night light'**
  String get readerNightLight;

  /// No description provided for @readerNightLightDesc.
  ///
  /// In en, this message translates to:
  /// **'Overlay a warm tint to reduce blue light; independent of reading brightness'**
  String get readerNightLightDesc;

  /// No description provided for @readerNightLightOpacity.
  ///
  /// In en, this message translates to:
  /// **'Night light intensity'**
  String get readerNightLightOpacity;

  /// No description provided for @readerAutoDownload.
  ///
  /// In en, this message translates to:
  /// **'Auto-download later chapters'**
  String get readerAutoDownload;

  /// No description provided for @readerAutoDownloadDesc.
  ///
  /// In en, this message translates to:
  /// **'Queue later chapters for download after reading 25% of the current one (silent on failure)'**
  String get readerAutoDownloadDesc;

  /// No description provided for @readerSkipReadChapters.
  ///
  /// In en, this message translates to:
  /// **'Skip read chapters'**
  String get readerSkipReadChapters;

  /// No description provided for @readerSkipReadChaptersDesc.
  ///
  /// In en, this message translates to:
  /// **'Skip already-read chapters when going to the next/previous chapter'**
  String get readerSkipReadChaptersDesc;

  /// No description provided for @readerSkipFilteredChapters.
  ///
  /// In en, this message translates to:
  /// **'Skip filtered chapters'**
  String get readerSkipFilteredChapters;

  /// No description provided for @readerSkipFilteredChaptersDesc.
  ///
  /// In en, this message translates to:
  /// **'Skip filtered chapters when going to the next/previous chapter'**
  String get readerSkipFilteredChaptersDesc;

  /// No description provided for @readerSkipDuplicateChapters.
  ///
  /// In en, this message translates to:
  /// **'Skip duplicate chapters'**
  String get readerSkipDuplicateChapters;

  /// No description provided for @readerSkipDuplicateChaptersDesc.
  ///
  /// In en, this message translates to:
  /// **'Skip chapters with duplicate titles when going to the next/previous chapter'**
  String get readerSkipDuplicateChaptersDesc;

  /// No description provided for @readerColorProfile.
  ///
  /// In en, this message translates to:
  /// **'Color profile'**
  String get readerColorProfile;

  /// No description provided for @readerColorProfileNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get readerColorProfileNone;

  /// No description provided for @readerColorProfileSrgb.
  ///
  /// In en, this message translates to:
  /// **'sRGB'**
  String get readerColorProfileSrgb;

  /// No description provided for @readerColorProfileWarm.
  ///
  /// In en, this message translates to:
  /// **'Warm'**
  String get readerColorProfileWarm;

  /// No description provided for @readerColorProfileCool.
  ///
  /// In en, this message translates to:
  /// **'Cool'**
  String get readerColorProfileCool;

  /// No description provided for @readerColorProfileManga.
  ///
  /// In en, this message translates to:
  /// **'Manga'**
  String get readerColorProfileManga;

  /// No description provided for @readerColorProfilePaper.
  ///
  /// In en, this message translates to:
  /// **'Paper'**
  String get readerColorProfilePaper;

  /// No description provided for @readerEInkRefresh.
  ///
  /// In en, this message translates to:
  /// **'E-Ink refresh'**
  String get readerEInkRefresh;

  /// No description provided for @readerEInkRefreshDesc.
  ///
  /// In en, this message translates to:
  /// **'E-ink ghosting fix: auto full-screen flash by page-turn interval'**
  String get readerEInkRefreshDesc;

  /// No description provided for @readerEInkRefreshInterval.
  ///
  /// In en, this message translates to:
  /// **'Refresh interval (pages)'**
  String get readerEInkRefreshInterval;

  /// No description provided for @readerEInkRefreshDuration.
  ///
  /// In en, this message translates to:
  /// **'Refresh duration (ms)'**
  String get readerEInkRefreshDuration;

  /// No description provided for @readerEInkRefreshWhite.
  ///
  /// In en, this message translates to:
  /// **'White flash'**
  String get readerEInkRefreshWhite;

  /// No description provided for @readerEInkRefreshBlack.
  ///
  /// In en, this message translates to:
  /// **'Black flash'**
  String get readerEInkRefreshBlack;

  /// No description provided for @readerEInkRefreshStyle.
  ///
  /// In en, this message translates to:
  /// **'Refresh style'**
  String get readerEInkRefreshStyle;

  /// No description provided for @readerGroupEInk.
  ///
  /// In en, this message translates to:
  /// **'E-Ink refresh'**
  String get readerGroupEInk;

  /// No description provided for @readerGroupEInkDesc.
  ///
  /// In en, this message translates to:
  /// **'E-ink devices only: anti-ghosting full-screen refresh'**
  String get readerGroupEInkDesc;

  /// No description provided for @readerAutoFavorite.
  ///
  /// In en, this message translates to:
  /// **'Auto-favorite'**
  String get readerAutoFavorite;

  /// No description provided for @readerAutoFavoriteDesc.
  ///
  /// In en, this message translates to:
  /// **'Add to favorites when opening a comic (skips if already favorited)'**
  String get readerAutoFavoriteDesc;

  /// No description provided for @readerScreenPicNumberPortrait.
  ///
  /// In en, this message translates to:
  /// **'Images per screen (portrait)'**
  String get readerScreenPicNumberPortrait;

  /// No description provided for @readerScreenPicNumberLandscape.
  ///
  /// In en, this message translates to:
  /// **'Images per screen (landscape)'**
  String get readerScreenPicNumberLandscape;

  /// No description provided for @readerScreenPicNumberDesc.
  ///
  /// In en, this message translates to:
  /// **'Stack multiple images vertically per screen (1–5)'**
  String get readerScreenPicNumberDesc;

  /// No description provided for @readerChapterBookmark.
  ///
  /// In en, this message translates to:
  /// **'Bookmark this chapter'**
  String get readerChapterBookmark;

  /// No description provided for @readerChapterBookmarked.
  ///
  /// In en, this message translates to:
  /// **'Chapter bookmarked'**
  String get readerChapterBookmarked;

  /// No description provided for @readerChapterBookmarkRemoved.
  ///
  /// In en, this message translates to:
  /// **'Chapter bookmark removed'**
  String get readerChapterBookmarkRemoved;

  /// No description provided for @readerImageFavorite.
  ///
  /// In en, this message translates to:
  /// **'Image favorites'**
  String get readerImageFavorite;

  /// No description provided for @readerFavoriteImage.
  ///
  /// In en, this message translates to:
  /// **'Favorite this image'**
  String get readerFavoriteImage;

  /// No description provided for @imageFavoriteAdded.
  ///
  /// In en, this message translates to:
  /// **'Image favorited'**
  String get imageFavoriteAdded;

  /// No description provided for @imageFavoriteRemoved.
  ///
  /// In en, this message translates to:
  /// **'Image unfavorited'**
  String get imageFavoriteRemoved;

  /// No description provided for @imageFavoriteAdd.
  ///
  /// In en, this message translates to:
  /// **'Save to gallery'**
  String get imageFavoriteAdd;

  /// No description provided for @imageFavoriteSourceComic.
  ///
  /// In en, this message translates to:
  /// **'Comic'**
  String get imageFavoriteSourceComic;

  /// No description provided for @imageFavoriteSourcePlayer.
  ///
  /// In en, this message translates to:
  /// **'Media'**
  String get imageFavoriteSourcePlayer;

  /// No description provided for @imageFavoriteSourceNovel.
  ///
  /// In en, this message translates to:
  /// **'Novel'**
  String get imageFavoriteSourceNovel;

  /// No description provided for @imageFavoriteAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get imageFavoriteAll;

  /// No description provided for @imageFavoriteSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search title, work or link'**
  String get imageFavoriteSearchHint;

  /// No description provided for @imageFavoriteSortNewest.
  ///
  /// In en, this message translates to:
  /// **'Newest'**
  String get imageFavoriteSortNewest;

  /// No description provided for @imageFavoriteSortOldest.
  ///
  /// In en, this message translates to:
  /// **'Oldest'**
  String get imageFavoriteSortOldest;

  /// No description provided for @imageFavoriteSortTitle.
  ///
  /// In en, this message translates to:
  /// **'By title'**
  String get imageFavoriteSortTitle;

  /// No description provided for @imageFavoriteCount.
  ///
  /// In en, this message translates to:
  /// **'{count} images'**
  String imageFavoriteCount(Object count);

  /// No description provided for @imageFavoriteNoMatch.
  ///
  /// In en, this message translates to:
  /// **'No matching favorites'**
  String get imageFavoriteNoMatch;

  /// No description provided for @imageFavoriteFilter.
  ///
  /// In en, this message translates to:
  /// **'Filter by source'**
  String get imageFavoriteFilter;

  /// No description provided for @imageFavoriteTimeAll.
  ///
  /// In en, this message translates to:
  /// **'All time'**
  String get imageFavoriteTimeAll;

  /// No description provided for @imageFavoriteTimeToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get imageFavoriteTimeToday;

  /// No description provided for @imageFavoriteTimeWeek.
  ///
  /// In en, this message translates to:
  /// **'This week'**
  String get imageFavoriteTimeWeek;

  /// No description provided for @imageFavoriteTimeMonth.
  ///
  /// In en, this message translates to:
  /// **'This month'**
  String get imageFavoriteTimeMonth;

  /// No description provided for @imageFavoriteTimeYear.
  ///
  /// In en, this message translates to:
  /// **'This year'**
  String get imageFavoriteTimeYear;

  /// No description provided for @imageFavoriteTimeOlder.
  ///
  /// In en, this message translates to:
  /// **'Earlier'**
  String get imageFavoriteTimeOlder;

  /// No description provided for @imageFavoriteLayoutGrid.
  ///
  /// In en, this message translates to:
  /// **'Grid'**
  String get imageFavoriteLayoutGrid;

  /// No description provided for @imageFavoriteLayoutMasonry.
  ///
  /// In en, this message translates to:
  /// **'Masonry'**
  String get imageFavoriteLayoutMasonry;

  /// No description provided for @imageFavoriteGroupByWork.
  ///
  /// In en, this message translates to:
  /// **'By work'**
  String get imageFavoriteGroupByWork;

  /// No description provided for @imageFavoriteDisplayOptions.
  ///
  /// In en, this message translates to:
  /// **'Display & sort'**
  String get imageFavoriteDisplayOptions;

  /// No description provided for @imageFavoriteShowTitle.
  ///
  /// In en, this message translates to:
  /// **'Show title'**
  String get imageFavoriteShowTitle;

  /// No description provided for @imageFavoriteShowTime.
  ///
  /// In en, this message translates to:
  /// **'Show time'**
  String get imageFavoriteShowTime;

  /// No description provided for @imageFavoriteRename.
  ///
  /// In en, this message translates to:
  /// **'Rename title'**
  String get imageFavoriteRename;

  /// No description provided for @imageFavoriteRenamed.
  ///
  /// In en, this message translates to:
  /// **'Renamed'**
  String get imageFavoriteRenamed;

  /// No description provided for @imageFavoriteTitleHint.
  ///
  /// In en, this message translates to:
  /// **'New title'**
  String get imageFavoriteTitleHint;

  /// No description provided for @imageFavoriteAllFolders.
  ///
  /// In en, this message translates to:
  /// **'All folders'**
  String get imageFavoriteAllFolders;

  /// No description provided for @backToFolders.
  ///
  /// In en, this message translates to:
  /// **'Back to folders'**
  String get backToFolders;

  /// No description provided for @imageFavoriteFiltersToggle.
  ///
  /// In en, this message translates to:
  /// **'Collapse / expand filters'**
  String get imageFavoriteFiltersToggle;

  /// No description provided for @imageFavoriteUnfiled.
  ///
  /// In en, this message translates to:
  /// **'Unfiled'**
  String get imageFavoriteUnfiled;

  /// No description provided for @imageFavoriteNewFolder.
  ///
  /// In en, this message translates to:
  /// **'New folder'**
  String get imageFavoriteNewFolder;

  /// No description provided for @imageFavoriteFolderHint.
  ///
  /// In en, this message translates to:
  /// **'Folder name'**
  String get imageFavoriteFolderHint;

  /// No description provided for @imageFavoriteDeleteFolder.
  ///
  /// In en, this message translates to:
  /// **'Delete folder'**
  String get imageFavoriteDeleteFolder;

  /// No description provided for @imageFavoriteDeleteFolderConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete folder {folder}? Images inside will return to unfiled'**
  String imageFavoriteDeleteFolderConfirm(Object folder);

  /// No description provided for @imageFavoriteSelected.
  ///
  /// In en, this message translates to:
  /// **'{count} selected'**
  String imageFavoriteSelected(Object count);

  /// No description provided for @imageFavoriteSelectAll.
  ///
  /// In en, this message translates to:
  /// **'Select all'**
  String get imageFavoriteSelectAll;

  /// No description provided for @imageFavoriteMoveTo.
  ///
  /// In en, this message translates to:
  /// **'Move to folder'**
  String get imageFavoriteMoveTo;

  /// No description provided for @imageFavoriteMoved.
  ///
  /// In en, this message translates to:
  /// **'Moved'**
  String get imageFavoriteMoved;

  /// No description provided for @imageFavoriteDeleteMulti.
  ///
  /// In en, this message translates to:
  /// **'Delete {count} selected images?'**
  String imageFavoriteDeleteMulti(Object count);

  /// No description provided for @imageFavoriteRenameSingle.
  ///
  /// In en, this message translates to:
  /// **'Select exactly one image to rename'**
  String get imageFavoriteRenameSingle;

  /// No description provided for @imageFavoriteGalleryDesc.
  ///
  /// In en, this message translates to:
  /// **'Unified gallery of comic pages, player screenshots and novel images (folders / multi-select)'**
  String get imageFavoriteGalleryDesc;

  /// No description provided for @readingQueueTitle.
  ///
  /// In en, this message translates to:
  /// **'Reading queue'**
  String get readingQueueTitle;

  /// No description provided for @readingQueueAdd.
  ///
  /// In en, this message translates to:
  /// **'Add to reading queue'**
  String get readingQueueAdd;

  /// No description provided for @readingQueueAdded.
  ///
  /// In en, this message translates to:
  /// **'Added to reading queue'**
  String get readingQueueAdded;

  /// No description provided for @readingQueueOpen.
  ///
  /// In en, this message translates to:
  /// **'Reading queue'**
  String get readingQueueOpen;

  /// No description provided for @readingQueueEmpty.
  ///
  /// In en, this message translates to:
  /// **'Reading queue is empty\nAdd works from the work menu or bookshelf long-press'**
  String get readingQueueEmpty;

  /// No description provided for @readingQueueClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get readingQueueClear;

  /// No description provided for @readingQueueLoading.
  ///
  /// In en, this message translates to:
  /// **'Opening {title}…'**
  String readingQueueLoading(Object title);

  /// No description provided for @readingQueueLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to open queued work'**
  String get readingQueueLoadFailed;

  /// No description provided for @readingQueueTypeNovel.
  ///
  /// In en, this message translates to:
  /// **'Novel'**
  String get readingQueueTypeNovel;

  /// No description provided for @readingQueueTypeComic.
  ///
  /// In en, this message translates to:
  /// **'Comic'**
  String get readingQueueTypeComic;

  /// Battery percentage in clock/battery overlay
  ///
  /// In en, this message translates to:
  /// **'{percent}%'**
  String readerClockBatteryPercent(int percent);

  /// No description provided for @comicDefaultFullscreen.
  ///
  /// In en, this message translates to:
  /// **'Fullscreen'**
  String get comicDefaultFullscreen;

  /// No description provided for @comicDefaultLongPressMenu.
  ///
  /// In en, this message translates to:
  /// **'Long-press menu'**
  String get comicDefaultLongPressMenu;

  /// No description provided for @comicDefaultGrayscale.
  ///
  /// In en, this message translates to:
  /// **'Grayscale'**
  String get comicDefaultGrayscale;

  /// No description provided for @comicDefaultPreventShrink.
  ///
  /// In en, this message translates to:
  /// **'Prevent shrink'**
  String get comicDefaultPreventShrink;

  /// No description provided for @comicDefaultChapterTransition.
  ///
  /// In en, this message translates to:
  /// **'Chapter transition'**
  String get comicDefaultChapterTransition;

  /// No description provided for @copyImage.
  ///
  /// In en, this message translates to:
  /// **'Copy image'**
  String get copyImage;

  /// No description provided for @copyImageSuccess.
  ///
  /// In en, this message translates to:
  /// **'Image copied to clipboard'**
  String get copyImageSuccess;

  /// No description provided for @copyImageFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to copy image'**
  String get copyImageFailed;

  /// Chapter transition title card
  ///
  /// In en, this message translates to:
  /// **'Chapter: {title}'**
  String chapterTransitionCard(Object title);

  /// No description provided for @readerProgress.
  ///
  /// In en, this message translates to:
  /// **'Progress'**
  String get readerProgress;

  /// No description provided for @regexSearch.
  ///
  /// In en, this message translates to:
  /// **'Regex'**
  String get regexSearch;

  /// No description provided for @locateCurrent.
  ///
  /// In en, this message translates to:
  /// **'Locate current'**
  String get locateCurrent;

  /// No description provided for @scrollToTop.
  ///
  /// In en, this message translates to:
  /// **'Top'**
  String get scrollToTop;

  /// No description provided for @scrollToBottom.
  ///
  /// In en, this message translates to:
  /// **'Bottom'**
  String get scrollToBottom;

  /// No description provided for @bookmarkedHint.
  ///
  /// In en, this message translates to:
  /// **'Bookmarked'**
  String get bookmarkedHint;

  /// No description provided for @playerFullscreen.
  ///
  /// In en, this message translates to:
  /// **'Fullscreen'**
  String get playerFullscreen;

  /// No description provided for @playerExitFullscreen.
  ///
  /// In en, this message translates to:
  /// **'Exit fullscreen'**
  String get playerExitFullscreen;

  /// No description provided for @playerScreenshot.
  ///
  /// In en, this message translates to:
  /// **'Screenshot'**
  String get playerScreenshot;

  /// No description provided for @playerBrightness.
  ///
  /// In en, this message translates to:
  /// **'Brightness'**
  String get playerBrightness;

  /// No description provided for @playerVolume.
  ///
  /// In en, this message translates to:
  /// **'Volume'**
  String get playerVolume;

  /// No description provided for @playerSuperRes.
  ///
  /// In en, this message translates to:
  /// **'Super resolution'**
  String get playerSuperRes;

  /// No description provided for @playerLine.
  ///
  /// In en, this message translates to:
  /// **'Playback line'**
  String get playerLine;

  /// No description provided for @playerSelectLine.
  ///
  /// In en, this message translates to:
  /// **'Select line'**
  String get playerSelectLine;

  /// No description provided for @playerLineEmpty.
  ///
  /// In en, this message translates to:
  /// **'No playback lines (parse failed or source did not provide a video URL).'**
  String get playerLineEmpty;

  /// No description provided for @playerLineSingleHint.
  ///
  /// In en, this message translates to:
  /// **'This source returned only 1 line; no switch available.\nTo enable line switching, ask the source author to return a `urls` array in the video parser.'**
  String get playerLineSingleHint;

  /// Episode progress indicator inside the player line sheet header (filtered by current line)
  ///
  /// In en, this message translates to:
  /// **'Episode {current} / {total}'**
  String playerLineEpisodesProgress(int current, int total);

  /// No description provided for @playerEpisodes.
  ///
  /// In en, this message translates to:
  /// **'Episodes'**
  String get playerEpisodes;

  /// No description provided for @playerPip.
  ///
  /// In en, this message translates to:
  /// **'Picture in picture'**
  String get playerPip;

  /// No description provided for @playerCast.
  ///
  /// In en, this message translates to:
  /// **'Cast'**
  String get playerCast;

  /// No description provided for @playerMore.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get playerMore;

  /// No description provided for @seekForward10.
  ///
  /// In en, this message translates to:
  /// **'Forward 10s'**
  String get seekForward10;

  /// No description provided for @seekBackward10.
  ///
  /// In en, this message translates to:
  /// **'Backward 10s'**
  String get seekBackward10;

  /// No description provided for @playerSeekCancel.
  ///
  /// In en, this message translates to:
  /// **'Seek canceled'**
  String get playerSeekCancel;

  /// No description provided for @playerSkipOpEd.
  ///
  /// In en, this message translates to:
  /// **'Skip intro & outro'**
  String get playerSkipOpEd;

  /// No description provided for @playerSkipOp.
  ///
  /// In en, this message translates to:
  /// **'Skip intro'**
  String get playerSkipOp;

  /// No description provided for @playerSkipEd.
  ///
  /// In en, this message translates to:
  /// **'Skip outro'**
  String get playerSkipEd;

  /// No description provided for @playerSkipOpEndLabel.
  ///
  /// In en, this message translates to:
  /// **'Intro ends (m:ss)'**
  String get playerSkipOpEndLabel;

  /// No description provided for @playerSkipEdStartLabel.
  ///
  /// In en, this message translates to:
  /// **'Outro starts (m:ss)'**
  String get playerSkipEdStartLabel;

  /// No description provided for @playerSkipUseCurrent.
  ///
  /// In en, this message translates to:
  /// **'Use current'**
  String get playerSkipUseCurrent;

  /// No description provided for @playerSkipAuto.
  ///
  /// In en, this message translates to:
  /// **'Auto skip'**
  String get playerSkipAuto;

  /// No description provided for @playerSkipHint.
  ///
  /// In en, this message translates to:
  /// **'Leave empty to disable. Applies to all episodes of this series.'**
  String get playerSkipHint;

  /// No description provided for @novelReadingSummary.
  ///
  /// In en, this message translates to:
  /// **'Reading overview'**
  String get novelReadingSummary;

  /// No description provided for @novelParagraphTranslate.
  ///
  /// In en, this message translates to:
  /// **'Paragraph translation'**
  String get novelParagraphTranslate;

  /// No description provided for @novelTranslateAction.
  ///
  /// In en, this message translates to:
  /// **'Translate chapter'**
  String get novelTranslateAction;

  /// No description provided for @novelTranslateRetranslate.
  ///
  /// In en, this message translates to:
  /// **'Re-translate'**
  String get novelTranslateRetranslate;

  /// No description provided for @translationStaleNotice.
  ///
  /// In en, this message translates to:
  /// **'The source, glossary, or translation style has changed. The cached translation may be outdated.'**
  String get translationStaleNotice;

  /// No description provided for @translationRefinedMode.
  ///
  /// In en, this message translates to:
  /// **'Refined mode (3-draft synthesis, ≈4× tokens)'**
  String get translationRefinedMode;

  /// No description provided for @novelTranslateProgress.
  ///
  /// In en, this message translates to:
  /// **'{done} of {total} paragraphs'**
  String novelTranslateProgress(String done, String total);

  /// No description provided for @novelTranslateNoApi.
  ///
  /// In en, this message translates to:
  /// **'Translation failed — configure the cloud AI endpoint in Reading Overview'**
  String get novelTranslateNoApi;

  /// No description provided for @novelTranslating.
  ///
  /// In en, this message translates to:
  /// **'Translating…'**
  String get novelTranslating;

  /// No description provided for @novelTranslateHint.
  ///
  /// In en, this message translates to:
  /// **'Tap Translate chapter to render a bilingual view of this chapter'**
  String get novelTranslateHint;

  /// No description provided for @novelContentEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit chapter content'**
  String get novelContentEdit;

  /// No description provided for @novelContentEditHint.
  ///
  /// In en, this message translates to:
  /// **'One paragraph per block; lines starting with @@NEXHUB_IMG@@ are illustrations and @@NEXHUB_TITLE@@ marks headings'**
  String get novelContentEditHint;

  /// No description provided for @novelContentEditSaved.
  ///
  /// In en, this message translates to:
  /// **'Chapter content updated'**
  String get novelContentEditSaved;

  /// No description provided for @novelContentEditEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing to save: content is empty'**
  String get novelContentEditEmpty;

  /// No description provided for @novelContentEditBadge.
  ///
  /// In en, this message translates to:
  /// **'edited'**
  String get novelContentEditBadge;

  /// No description provided for @novelContentEditRestore.
  ///
  /// In en, this message translates to:
  /// **'Restore original'**
  String get novelContentEditRestore;

  /// No description provided for @novelContentEditRestoreConfirm.
  ///
  /// In en, this message translates to:
  /// **'Discard your edits and restore the chapter to its original content?'**
  String get novelContentEditRestoreConfirm;

  /// No description provided for @novelContentEditRestored.
  ///
  /// In en, this message translates to:
  /// **'Original content restored'**
  String get novelContentEditRestored;

  /// No description provided for @novelSummaryProgress.
  ///
  /// In en, this message translates to:
  /// **'Progress: chapter {read} of {total}'**
  String novelSummaryProgress(int read, int total);

  /// No description provided for @novelSummaryTotalRead.
  ///
  /// In en, this message translates to:
  /// **'Total reading time'**
  String get novelSummaryTotalRead;

  /// No description provided for @novelSummaryToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get novelSummaryToday;

  /// No description provided for @novelSummarySessionsValue.
  ///
  /// In en, this message translates to:
  /// **'{count} sessions'**
  String novelSummarySessionsValue(int count);

  /// No description provided for @novelSummaryRemaining.
  ///
  /// In en, this message translates to:
  /// **'Est. time to finish: {duration}'**
  String novelSummaryRemaining(String duration);

  /// No description provided for @novelSummaryCurrentChars.
  ///
  /// In en, this message translates to:
  /// **'{count} chars in this chapter'**
  String novelSummaryCurrentChars(int count);

  /// No description provided for @novelDurationHourMin.
  ///
  /// In en, this message translates to:
  /// **'{h}h {m}m'**
  String novelDurationHourMin(int h, int m);

  /// No description provided for @novelDurationHour.
  ///
  /// In en, this message translates to:
  /// **'{h}h'**
  String novelDurationHour(int h);

  /// No description provided for @novelDurationMin.
  ///
  /// In en, this message translates to:
  /// **'{m} min'**
  String novelDurationMin(int m);

  /// No description provided for @novelSummaryNoStats.
  ///
  /// In en, this message translates to:
  /// **'No reading stats yet'**
  String get novelSummaryNoStats;

  /// No description provided for @novelSummaryPosition.
  ///
  /// In en, this message translates to:
  /// **'Now: {chapter} · page {page}/{pages}'**
  String novelSummaryPosition(String chapter, int page, int pages);

  /// No description provided for @playerAutoPlayCountdown.
  ///
  /// In en, this message translates to:
  /// **'Auto-play next countdown'**
  String get playerAutoPlayCountdown;

  /// No description provided for @playerCountdownImmediate.
  ///
  /// In en, this message translates to:
  /// **'Immediate'**
  String get playerCountdownImmediate;

  /// No description provided for @playerAutoNextCountdown.
  ///
  /// In en, this message translates to:
  /// **'Next episode in {left}s'**
  String playerAutoNextCountdown(int left);

  /// No description provided for @novelTitleAlignLeft.
  ///
  /// In en, this message translates to:
  /// **'Left'**
  String get novelTitleAlignLeft;

  /// No description provided for @novelTitleAlignCenter.
  ///
  /// In en, this message translates to:
  /// **'Center'**
  String get novelTitleAlignCenter;

  /// No description provided for @novelTitleAlignRight.
  ///
  /// In en, this message translates to:
  /// **'Right'**
  String get novelTitleAlignRight;

  /// No description provided for @novelTitleAlignHidden.
  ///
  /// In en, this message translates to:
  /// **'Hidden'**
  String get novelTitleAlignHidden;

  /// No description provided for @novelSectionToolbar.
  ///
  /// In en, this message translates to:
  /// **'Bottom toolbar'**
  String get novelSectionToolbar;

  /// No description provided for @novelSectionTts.
  ///
  /// In en, this message translates to:
  /// **'TTS Settings'**
  String get novelSectionTts;

  /// No description provided for @ttsRate.
  ///
  /// In en, this message translates to:
  /// **'Speech rate'**
  String get ttsRate;

  /// No description provided for @ttsPlaybackFailed.
  ///
  /// In en, this message translates to:
  /// **'Reading failed. Check the system speech engine.'**
  String get ttsPlaybackFailed;

  /// No description provided for @ttsSleepTimer.
  ///
  /// In en, this message translates to:
  /// **'Sleep timer'**
  String get ttsSleepTimer;

  /// No description provided for @ttsSleepOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get ttsSleepOff;

  /// No description provided for @ttsSleepCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get ttsSleepCustom;

  /// No description provided for @ttsSleepCustomMinutes.
  ///
  /// In en, this message translates to:
  /// **'Custom minutes'**
  String get ttsSleepCustomMinutes;

  /// TTS sleep timer remaining time
  ///
  /// In en, this message translates to:
  /// **'Remaining {min} min {sec} sec'**
  String ttsSleepRemaining(int min, int sec);

  /// No description provided for @ttsPrevSentence.
  ///
  /// In en, this message translates to:
  /// **'Previous sentence'**
  String get ttsPrevSentence;

  /// No description provided for @ttsPauseOrResume.
  ///
  /// In en, this message translates to:
  /// **'Pause / Resume'**
  String get ttsPauseOrResume;

  /// No description provided for @ttsExit.
  ///
  /// In en, this message translates to:
  /// **'Exit reading'**
  String get ttsExit;

  /// No description provided for @ttsNextSentence.
  ///
  /// In en, this message translates to:
  /// **'Next sentence'**
  String get ttsNextSentence;

  /// Minute count suffix for sleep timer options
  ///
  /// In en, this message translates to:
  /// **'{minutes} min'**
  String minuteUnit(int minutes);

  /// No description provided for @novelFontFileGroup.
  ///
  /// In en, this message translates to:
  /// **'Font file & emphasis color'**
  String get novelFontFileGroup;

  /// No description provided for @novelChooseFontFile.
  ///
  /// In en, this message translates to:
  /// **'Body font file'**
  String get novelChooseFontFile;

  /// No description provided for @novelTitleFontFile.
  ///
  /// In en, this message translates to:
  /// **'Title font file'**
  String get novelTitleFontFile;

  /// No description provided for @novelResetConfirm.
  ///
  /// In en, this message translates to:
  /// **'Reset all novel reader settings to default? This cannot be undone.'**
  String get novelResetConfirm;

  /// No description provided for @novelSettingsSearch.
  ///
  /// In en, this message translates to:
  /// **'Search settings'**
  String get novelSettingsSearch;

  /// No description provided for @novelSettingsCommon.
  ///
  /// In en, this message translates to:
  /// **'Common'**
  String get novelSettingsCommon;

  /// No description provided for @novelSettingsNoResult.
  ///
  /// In en, this message translates to:
  /// **'No matching settings'**
  String get novelSettingsNoResult;

  /// Current custom font file name
  ///
  /// In en, this message translates to:
  /// **'Selected: {name}'**
  String novelFontFileCurrent(String name);

  /// No description provided for @novelClearFontFile.
  ///
  /// In en, this message translates to:
  /// **'Clear font file'**
  String get novelClearFontFile;

  /// No description provided for @novelEmphasisColor.
  ///
  /// In en, this message translates to:
  /// **'Emphasis color'**
  String get novelEmphasisColor;

  /// No description provided for @novelEmphasisColorAuto.
  ///
  /// In en, this message translates to:
  /// **'Auto (title color)'**
  String get novelEmphasisColorAuto;

  /// No description provided for @novelSectionShadowUnderline.
  ///
  /// In en, this message translates to:
  /// **'Shadow & underline'**
  String get novelSectionShadowUnderline;

  /// No description provided for @novelShadowBlur.
  ///
  /// In en, this message translates to:
  /// **'Shadow blur radius'**
  String get novelShadowBlur;

  /// No description provided for @novelShadowOffsetX.
  ///
  /// In en, this message translates to:
  /// **'Shadow horizontal offset'**
  String get novelShadowOffsetX;

  /// No description provided for @novelShadowOffsetY.
  ///
  /// In en, this message translates to:
  /// **'Shadow vertical offset'**
  String get novelShadowOffsetY;

  /// No description provided for @novelUnderlineColor.
  ///
  /// In en, this message translates to:
  /// **'Underline color'**
  String get novelUnderlineColor;

  /// No description provided for @novelUnderlineColorAuto.
  ///
  /// In en, this message translates to:
  /// **'Auto (body color)'**
  String get novelUnderlineColorAuto;

  /// No description provided for @novelUnderlineDashed.
  ///
  /// In en, this message translates to:
  /// **'Dashed underline'**
  String get novelUnderlineDashed;

  /// No description provided for @novelUnderlineStyle.
  ///
  /// In en, this message translates to:
  /// **'Underline style'**
  String get novelUnderlineStyle;

  /// No description provided for @novelUnderlineStyleSolid.
  ///
  /// In en, this message translates to:
  /// **'Solid'**
  String get novelUnderlineStyleSolid;

  /// No description provided for @novelUnderlineStyleDashed.
  ///
  /// In en, this message translates to:
  /// **'Dashed'**
  String get novelUnderlineStyleDashed;

  /// No description provided for @novelUnderlineStyleWavy.
  ///
  /// In en, this message translates to:
  /// **'Wavy'**
  String get novelUnderlineStyleWavy;

  /// No description provided for @novelUnderlineStyleDotted.
  ///
  /// In en, this message translates to:
  /// **'Dotted'**
  String get novelUnderlineStyleDotted;

  /// No description provided for @novelFontWeightFine.
  ///
  /// In en, this message translates to:
  /// **'Bold weight (100-900)'**
  String get novelFontWeightFine;

  /// No description provided for @novelTextAlignMode.
  ///
  /// In en, this message translates to:
  /// **'Text alignment'**
  String get novelTextAlignMode;

  /// No description provided for @novelTextAlignStart.
  ///
  /// In en, this message translates to:
  /// **'Natural (left)'**
  String get novelTextAlignStart;

  /// No description provided for @novelTextAlignJustify.
  ///
  /// In en, this message translates to:
  /// **'Justified'**
  String get novelTextAlignJustify;

  /// No description provided for @novelLineBreakMode.
  ///
  /// In en, this message translates to:
  /// **'CJK line breaking'**
  String get novelLineBreakMode;

  /// No description provided for @novelLineBreakStandard.
  ///
  /// In en, this message translates to:
  /// **'Native wrapping'**
  String get novelLineBreakStandard;

  /// No description provided for @novelLineBreakCjkStrict.
  ///
  /// In en, this message translates to:
  /// **'Char-wise + kinsoku'**
  String get novelLineBreakCjkStrict;

  /// No description provided for @novelScrollImageMode.
  ///
  /// In en, this message translates to:
  /// **'Scroll image style'**
  String get novelScrollImageMode;

  /// No description provided for @novelScrollImageModeBanner.
  ///
  /// In en, this message translates to:
  /// **'Full-width'**
  String get novelScrollImageModeBanner;

  /// No description provided for @novelScrollImageModeCard.
  ///
  /// In en, this message translates to:
  /// **'Card'**
  String get novelScrollImageModeCard;

  /// No description provided for @novelScrollImageAlign.
  ///
  /// In en, this message translates to:
  /// **'Image alignment'**
  String get novelScrollImageAlign;

  /// No description provided for @novelScrollImageAlignLeft.
  ///
  /// In en, this message translates to:
  /// **'Left'**
  String get novelScrollImageAlignLeft;

  /// No description provided for @novelScrollImageAlignCenter.
  ///
  /// In en, this message translates to:
  /// **'Center'**
  String get novelScrollImageAlignCenter;

  /// No description provided for @novelScrollImageAlignRight.
  ///
  /// In en, this message translates to:
  /// **'Right'**
  String get novelScrollImageAlignRight;

  /// No description provided for @novelUnderlineThickness.
  ///
  /// In en, this message translates to:
  /// **'Underline thickness'**
  String get novelUnderlineThickness;

  /// No description provided for @novelUnderlineDashLength.
  ///
  /// In en, this message translates to:
  /// **'Dash length'**
  String get novelUnderlineDashLength;

  /// No description provided for @novelUnderlineDashGap.
  ///
  /// In en, this message translates to:
  /// **'Dash gap'**
  String get novelUnderlineDashGap;

  /// No description provided for @novelTitlePosition.
  ///
  /// In en, this message translates to:
  /// **'Title position'**
  String get novelTitlePosition;

  /// No description provided for @novelTitleSegmentMode.
  ///
  /// In en, this message translates to:
  /// **'Title segment mode'**
  String get novelTitleSegmentMode;

  /// No description provided for @novelTitleSubScale.
  ///
  /// In en, this message translates to:
  /// **'Sub line font scale'**
  String get novelTitleSubScale;

  /// No description provided for @novelTitleSegmentSpacing.
  ///
  /// In en, this message translates to:
  /// **'Segment spacing'**
  String get novelTitleSegmentSpacing;

  /// No description provided for @novelTitleSubLineSpacing.
  ///
  /// In en, this message translates to:
  /// **'Sub line height'**
  String get novelTitleSubLineSpacing;

  /// No description provided for @novelTitleTopMargin.
  ///
  /// In en, this message translates to:
  /// **'Title top margin'**
  String get novelTitleTopMargin;

  /// No description provided for @novelTitleBottomMargin.
  ///
  /// In en, this message translates to:
  /// **'Title bottom margin'**
  String get novelTitleBottomMargin;

  /// No description provided for @novelSectionHeaderFooter.
  ///
  /// In en, this message translates to:
  /// **'Header & Footer'**
  String get novelSectionHeaderFooter;

  /// No description provided for @novelHeaderLeft.
  ///
  /// In en, this message translates to:
  /// **'Header left'**
  String get novelHeaderLeft;

  /// No description provided for @novelHeaderCenter.
  ///
  /// In en, this message translates to:
  /// **'Header center'**
  String get novelHeaderCenter;

  /// No description provided for @novelHeaderRight.
  ///
  /// In en, this message translates to:
  /// **'Header right'**
  String get novelHeaderRight;

  /// No description provided for @novelFooterLeft.
  ///
  /// In en, this message translates to:
  /// **'Footer left'**
  String get novelFooterLeft;

  /// No description provided for @novelFooterCenter.
  ///
  /// In en, this message translates to:
  /// **'Footer center'**
  String get novelFooterCenter;

  /// No description provided for @novelFooterRight.
  ///
  /// In en, this message translates to:
  /// **'Footer right'**
  String get novelFooterRight;

  /// No description provided for @novelHeaderFooterColor.
  ///
  /// In en, this message translates to:
  /// **'Header & Footer color'**
  String get novelHeaderFooterColor;

  /// No description provided for @novelHeaderFooterMargin.
  ///
  /// In en, this message translates to:
  /// **'Header & Footer margin'**
  String get novelHeaderFooterMargin;

  /// No description provided for @novelHfPageAndProgress.
  ///
  /// In en, this message translates to:
  /// **'Page & progress'**
  String get novelHfPageAndProgress;

  /// No description provided for @novelHfBookPageNumber.
  ///
  /// In en, this message translates to:
  /// **'Book page number'**
  String get novelHfBookPageNumber;

  /// No description provided for @novelTwoPageMode.
  ///
  /// In en, this message translates to:
  /// **'Dual-page mode'**
  String get novelTwoPageMode;

  /// No description provided for @novelAiIllustrate.
  ///
  /// In en, this message translates to:
  /// **'AI illustration'**
  String get novelAiIllustrate;

  /// No description provided for @novelAiIllustrateConfirm.
  ///
  /// In en, this message translates to:
  /// **'Generate an illustration for this chapter with the configured cloud AI and append it to the chapter content?'**
  String get novelAiIllustrateConfirm;

  /// No description provided for @novelAiIllustrating.
  ///
  /// In en, this message translates to:
  /// **'Generating illustration…'**
  String get novelAiIllustrating;

  /// No description provided for @novelAiIllustrateDone.
  ///
  /// In en, this message translates to:
  /// **'Illustration appended to chapter'**
  String get novelAiIllustrateDone;

  /// No description provided for @novelAiIllustrateFailed.
  ///
  /// In en, this message translates to:
  /// **'Illustration failed'**
  String get novelAiIllustrateFailed;

  /// No description provided for @novelTwoPageModeDesc.
  ///
  /// In en, this message translates to:
  /// **'In paged mode on wide screens, show two pages side by side like an open book'**
  String get novelTwoPageModeDesc;

  /// No description provided for @novelHfTimeAndBattery.
  ///
  /// In en, this message translates to:
  /// **'Time & battery'**
  String get novelHfTimeAndBattery;

  /// No description provided for @layoutDetailGroup.
  ///
  /// In en, this message translates to:
  /// **'Layout Details'**
  String get layoutDetailGroup;

  /// No description provided for @layoutProgressDisplay.
  ///
  /// In en, this message translates to:
  /// **'Progress Display'**
  String get layoutProgressDisplay;

  /// No description provided for @progressBar.
  ///
  /// In en, this message translates to:
  /// **'Progress Bar'**
  String get progressBar;

  /// No description provided for @progressText.
  ///
  /// In en, this message translates to:
  /// **'Percentage'**
  String get progressText;

  /// No description provided for @editRoute.
  ///
  /// In en, this message translates to:
  /// **'Edit Route'**
  String get editRoute;

  /// No description provided for @routeTitle.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get routeTitle;

  /// No description provided for @routeUrl.
  ///
  /// In en, this message translates to:
  /// **'URL'**
  String get routeUrl;

  /// No description provided for @routeSaved.
  ///
  /// In en, this message translates to:
  /// **'Route saved'**
  String get routeSaved;

  /// No description provided for @requiredHint.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get requiredHint;

  /// No description provided for @localImportPickFile.
  ///
  /// In en, this message translates to:
  /// **'Pick Local File'**
  String get localImportPickFile;

  /// No description provided for @sourceName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get sourceName;

  /// No description provided for @sourceBaseUrl.
  ///
  /// In en, this message translates to:
  /// **'Base URL'**
  String get sourceBaseUrl;

  /// No description provided for @sourceCannotEdit.
  ///
  /// In en, this message translates to:
  /// **'Built-in sources cannot be edited'**
  String get sourceCannotEdit;

  /// No description provided for @sourceCannotDelete.
  ///
  /// In en, this message translates to:
  /// **'Built-in sources cannot be deleted'**
  String get sourceCannotDelete;

  /// No description provided for @comicVisualZoomGroup.
  ///
  /// In en, this message translates to:
  /// **'Display & Zoom'**
  String get comicVisualZoomGroup;

  /// No description provided for @comicPageProgressGroup.
  ///
  /// In en, this message translates to:
  /// **'Page & Progress'**
  String get comicPageProgressGroup;

  /// No description provided for @generalSettingsGroup.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get generalSettingsGroup;

  /// No description provided for @playbackProgressGroup.
  ///
  /// In en, this message translates to:
  /// **'Playback Progress'**
  String get playbackProgressGroup;

  /// No description provided for @playbackModulesSection.
  ///
  /// In en, this message translates to:
  /// **'Module Settings'**
  String get playbackModulesSection;

  /// No description provided for @settingsCatAppearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance & Language'**
  String get settingsCatAppearance;

  /// No description provided for @settingsCatAppearanceDesc.
  ///
  /// In en, this message translates to:
  /// **'Theme, colors, dark mode & language'**
  String get settingsCatAppearanceDesc;

  /// No description provided for @settingsCatPlayback.
  ///
  /// In en, this message translates to:
  /// **'Playback & Reading'**
  String get settingsCatPlayback;

  /// No description provided for @settingsCatPlaybackDesc.
  ///
  /// In en, this message translates to:
  /// **'Player, comic, novel & danmaku display'**
  String get settingsCatPlaybackDesc;

  /// No description provided for @settingsCatContent.
  ///
  /// In en, this message translates to:
  /// **'Config & Network'**
  String get settingsCatContent;

  /// No description provided for @settingsCatContentDesc.
  ///
  /// In en, this message translates to:
  /// **'Sources, RSS subscriptions, scraping, AI & network'**
  String get settingsCatContentDesc;

  /// No description provided for @settingsCatDetailAppearance.
  ///
  /// In en, this message translates to:
  /// **'Detail Page Look'**
  String get settingsCatDetailAppearance;

  /// No description provided for @settingsCatDetailAppearanceDesc.
  ///
  /// In en, this message translates to:
  /// **'Cover-based accent & blurred backdrop'**
  String get settingsCatDetailAppearanceDesc;

  /// No description provided for @detailAppearanceDynamicAccent.
  ///
  /// In en, this message translates to:
  /// **'Dynamic accent from cover'**
  String get detailAppearanceDynamicAccent;

  /// No description provided for @detailAppearanceDynamicAccentDesc.
  ///
  /// In en, this message translates to:
  /// **'Tint the detail page accent with a color pulled from the cover or fetched image'**
  String get detailAppearanceDynamicAccentDesc;

  /// No description provided for @detailAppearanceBlurredBg.
  ///
  /// In en, this message translates to:
  /// **'Blurred cover background'**
  String get detailAppearanceBlurredBg;

  /// No description provided for @detailAppearanceBlurredBgDesc.
  ///
  /// In en, this message translates to:
  /// **'Replace the white page background with a blurred cover or fetched image; stays white when off'**
  String get detailAppearanceBlurredBgDesc;

  /// No description provided for @detailAppearanceBlurStrength.
  ///
  /// In en, this message translates to:
  /// **'Blur strength'**
  String get detailAppearanceBlurStrength;

  /// No description provided for @detailAppearanceLeftSwipe.
  ///
  /// In en, this message translates to:
  /// **'Swipe-left action'**
  String get detailAppearanceLeftSwipe;

  /// No description provided for @detailAppearanceLeftSwipeDesc.
  ///
  /// In en, this message translates to:
  /// **'Runs when swiping a chapter row left in the detail page chapter list'**
  String get detailAppearanceLeftSwipeDesc;

  /// No description provided for @detailAppearanceRightSwipe.
  ///
  /// In en, this message translates to:
  /// **'Swipe-right action'**
  String get detailAppearanceRightSwipe;

  /// No description provided for @detailAppearanceRightSwipeDesc.
  ///
  /// In en, this message translates to:
  /// **'Runs when swiping a chapter row right in the detail page chapter list'**
  String get detailAppearanceRightSwipeDesc;

  /// No description provided for @swipeActionDownload.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get swipeActionDownload;

  /// No description provided for @swipeActionBookmark.
  ///
  /// In en, this message translates to:
  /// **'Bookmark'**
  String get swipeActionBookmark;

  /// No description provided for @swipeActionRead.
  ///
  /// In en, this message translates to:
  /// **'Read'**
  String get swipeActionRead;

  /// No description provided for @aiSettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'AI Settings'**
  String get aiSettingsTitle;

  /// No description provided for @aiSettingsDesc.
  ///
  /// In en, this message translates to:
  /// **'Manage AI endpoints & features (summary / illustration / translation)'**
  String get aiSettingsDesc;

  /// No description provided for @aiCommonApiSection.
  ///
  /// In en, this message translates to:
  /// **'Common API'**
  String get aiCommonApiSection;

  /// No description provided for @aiCommonApiDesc.
  ///
  /// In en, this message translates to:
  /// **'Fallback endpoint for all AI features; a feature-specific endpoint takes priority'**
  String get aiCommonApiDesc;

  /// No description provided for @aiBaseUrl.
  ///
  /// In en, this message translates to:
  /// **'Base URL'**
  String get aiBaseUrl;

  /// No description provided for @aiBaseUrlHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. https://api.openai.com/v1'**
  String get aiBaseUrlHint;

  /// No description provided for @aiApiKey.
  ///
  /// In en, this message translates to:
  /// **'API key'**
  String get aiApiKey;

  /// No description provided for @aiModel.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get aiModel;

  /// No description provided for @aiModelHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. gpt-3.5-turbo'**
  String get aiModelHint;

  /// No description provided for @aiOverrideHint.
  ///
  /// In en, this message translates to:
  /// **'Leave empty to use the common API'**
  String get aiOverrideHint;

  /// No description provided for @aiSummarySection.
  ///
  /// In en, this message translates to:
  /// **'Chapter Summary'**
  String get aiSummarySection;

  /// No description provided for @aiSummaryDesc.
  ///
  /// In en, this message translates to:
  /// **'Summary mode & dedicated endpoint (empty = common API)'**
  String get aiSummaryDesc;

  /// No description provided for @aiSummaryMode.
  ///
  /// In en, this message translates to:
  /// **'Summary mode'**
  String get aiSummaryMode;

  /// No description provided for @aiIllustrationSection.
  ///
  /// In en, this message translates to:
  /// **'AI Illustration'**
  String get aiIllustrationSection;

  /// No description provided for @aiIllustrationDesc.
  ///
  /// In en, this message translates to:
  /// **'Illustration endpoint & generation options (empty = common API)'**
  String get aiIllustrationDesc;

  /// No description provided for @aiIllustrationModel.
  ///
  /// In en, this message translates to:
  /// **'Image model'**
  String get aiIllustrationModel;

  /// No description provided for @aiIllustrationModelHint.
  ///
  /// In en, this message translates to:
  /// **'Leave empty for server default'**
  String get aiIllustrationModelHint;

  /// No description provided for @aiIllustrationSize.
  ///
  /// In en, this message translates to:
  /// **'Image size'**
  String get aiIllustrationSize;

  /// No description provided for @aiSaved.
  ///
  /// In en, this message translates to:
  /// **'AI settings saved'**
  String get aiSaved;

  /// No description provided for @aiSettingsEntry.
  ///
  /// In en, this message translates to:
  /// **'AI Settings'**
  String get aiSettingsEntry;

  /// No description provided for @aiSettingsEntryDesc.
  ///
  /// In en, this message translates to:
  /// **'AI endpoint, chapter summary, illustration & translation'**
  String get aiSettingsEntryDesc;

  /// No description provided for @translationSettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Bilingual / Translation'**
  String get translationSettingsTitle;

  /// No description provided for @translationSettingsDesc.
  ///
  /// In en, this message translates to:
  /// **'Target language, endpoint & options'**
  String get translationSettingsDesc;

  /// No description provided for @translationApiSection.
  ///
  /// In en, this message translates to:
  /// **'Translation API'**
  String get translationApiSection;

  /// No description provided for @translationApiDesc.
  ///
  /// In en, this message translates to:
  /// **'Dedicated endpoint; falls back to common API when empty'**
  String get translationApiDesc;

  /// No description provided for @translationTargetLang.
  ///
  /// In en, this message translates to:
  /// **'Target language'**
  String get translationTargetLang;

  /// No description provided for @translationTargetLangHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Chinese / English / Japanese'**
  String get translationTargetLangHint;

  /// No description provided for @translationBatchSize.
  ///
  /// In en, this message translates to:
  /// **'Chunk size (paragraphs)'**
  String get translationBatchSize;

  /// No description provided for @translationBatchHint.
  ///
  /// In en, this message translates to:
  /// **'Retry in chunks when the whole-chapter request fails'**
  String get translationBatchHint;

  /// No description provided for @translationSaved.
  ///
  /// In en, this message translates to:
  /// **'Translation settings saved'**
  String get translationSaved;

  /// No description provided for @translationSettingsEntry.
  ///
  /// In en, this message translates to:
  /// **'Bilingual / Translation'**
  String get translationSettingsEntry;

  /// No description provided for @translationSettingsEntryDesc.
  ///
  /// In en, this message translates to:
  /// **'Target language & endpoint config'**
  String get translationSettingsEntryDesc;

  /// No description provided for @novelSectionAi.
  ///
  /// In en, this message translates to:
  /// **'AI Features'**
  String get novelSectionAi;

  /// No description provided for @novelAiOpenSummary.
  ///
  /// In en, this message translates to:
  /// **'Open chapter summary'**
  String get novelAiOpenSummary;

  /// No description provided for @novelAiOpenTranslation.
  ///
  /// In en, this message translates to:
  /// **'Open paragraph translation'**
  String get novelAiOpenTranslation;

  /// No description provided for @settingsCatData.
  ///
  /// In en, this message translates to:
  /// **'Data & Accounts'**
  String get settingsCatData;

  /// No description provided for @settingsCatDataDesc.
  ///
  /// In en, this message translates to:
  /// **'Stats, backup, cloud sync & Bangumi'**
  String get settingsCatDataDesc;

  /// No description provided for @settingsCatPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Privacy & Security'**
  String get settingsCatPrivacy;

  /// No description provided for @settingsCatPrivacyDesc.
  ///
  /// In en, this message translates to:
  /// **'Privacy, advanced settings & cache'**
  String get settingsCatPrivacyDesc;

  /// No description provided for @settingsCatAbout.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get settingsCatAbout;

  /// No description provided for @settingsCatAboutDesc.
  ///
  /// In en, this message translates to:
  /// **'Version, license & acknowledgements'**
  String get settingsCatAboutDesc;

  /// No description provided for @launchScreenTitle.
  ///
  /// In en, this message translates to:
  /// **'Launch Screen'**
  String get launchScreenTitle;

  /// No description provided for @dateFormatTitle.
  ///
  /// In en, this message translates to:
  /// **'Date Format'**
  String get dateFormatTitle;

  /// No description provided for @dateFormatDefault.
  ///
  /// In en, this message translates to:
  /// **'Default (yyyy/mm/dd)'**
  String get dateFormatDefault;

  /// No description provided for @dateFormatMmDdYy.
  ///
  /// In en, this message translates to:
  /// **'mm/dd/yy'**
  String get dateFormatMmDdYy;

  /// No description provided for @dateFormatDdMmYy.
  ///
  /// In en, this message translates to:
  /// **'dd/mm/yy'**
  String get dateFormatDdMmYy;

  /// No description provided for @dateFormatYyyyMmDd.
  ///
  /// In en, this message translates to:
  /// **'yyyy-mm-dd'**
  String get dateFormatYyyyMmDd;

  /// No description provided for @dateFormatDdMmmYyyy.
  ///
  /// In en, this message translates to:
  /// **'dd mmm yyyy'**
  String get dateFormatDdMmmYyyy;

  /// No description provided for @dateFormatMmmDd.
  ///
  /// In en, this message translates to:
  /// **'mmm dd'**
  String get dateFormatMmmDd;

  /// No description provided for @dateFormatYyyy.
  ///
  /// In en, this message translates to:
  /// **'yyyy'**
  String get dateFormatYyyy;

  /// No description provided for @comicSettingsOverview.
  ///
  /// In en, this message translates to:
  /// **'Current Settings'**
  String get comicSettingsOverview;

  /// No description provided for @comicResetConfirm.
  ///
  /// In en, this message translates to:
  /// **'Reset all comic reader settings to default? This cannot be undone.'**
  String get comicResetConfirm;

  /// No description provided for @on.
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get on;

  /// No description provided for @off.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get off;

  /// No description provided for @readerGroupPageTap.
  ///
  /// In en, this message translates to:
  /// **'Page & Tap'**
  String get readerGroupPageTap;

  /// No description provided for @readerGroupViewFilter.
  ///
  /// In en, this message translates to:
  /// **'Display & Filter'**
  String get readerGroupViewFilter;

  /// No description provided for @readerGroupProgress.
  ///
  /// In en, this message translates to:
  /// **'Progress & Display'**
  String get readerGroupProgress;

  /// No description provided for @readerGroupFlash.
  ///
  /// In en, this message translates to:
  /// **'Flash Effect'**
  String get readerGroupFlash;

  /// No description provided for @readerGroupAuto.
  ///
  /// In en, this message translates to:
  /// **'Auto (Download / Skip)'**
  String get readerGroupAuto;

  /// No description provided for @readerGroupAutoDesc.
  ///
  /// In en, this message translates to:
  /// **'Auto-download later chapters and skip read, filtered, or duplicate chapters when navigating.'**
  String get readerGroupAutoDesc;

  /// No description provided for @readerGroupOverlay.
  ///
  /// In en, this message translates to:
  /// **'Overlay (Clock / Battery)'**
  String get readerGroupOverlay;

  /// No description provided for @readerGroupOverlayDesc.
  ///
  /// In en, this message translates to:
  /// **'Show the current time and battery in the reader, with position, margin, opacity, and font size.'**
  String get readerGroupOverlayDesc;

  /// No description provided for @readerGroupMulti.
  ///
  /// In en, this message translates to:
  /// **'Multi-image & Spacing'**
  String get readerGroupMulti;

  /// No description provided for @readerGroupMultiDesc.
  ///
  /// In en, this message translates to:
  /// **'Multiple images per screen, single image on first page, and page spacing.'**
  String get readerGroupMultiDesc;

  /// No description provided for @readerCommonSettings.
  ///
  /// In en, this message translates to:
  /// **'Common'**
  String get readerCommonSettings;

  /// No description provided for @readerGroupPageTapDesc.
  ///
  /// In en, this message translates to:
  /// **'Basic reading controls: page mode, screen orientation, tap zones, and zoom.'**
  String get readerGroupPageTapDesc;

  /// No description provided for @readerGroupViewFilterDesc.
  ///
  /// In en, this message translates to:
  /// **'Adjust brightness, contrast, color temperature, grayscale, etc.'**
  String get readerGroupViewFilterDesc;

  /// No description provided for @readerGroupProgressDesc.
  ///
  /// In en, this message translates to:
  /// **'Page numbers, progress bar, fullscreen, keep-screen-on, rotation, and more.'**
  String get readerGroupProgressDesc;

  /// No description provided for @readerGroupFlashDesc.
  ///
  /// In en, this message translates to:
  /// **'Flash effect on page turn (simulated page-turn light).'**
  String get readerGroupFlashDesc;

  /// No description provided for @readerSearchSettings.
  ///
  /// In en, this message translates to:
  /// **'Search settings…'**
  String get readerSearchSettings;

  /// No description provided for @readerGroupMouseWheel.
  ///
  /// In en, this message translates to:
  /// **'Mouse Wheel'**
  String get readerGroupMouseWheel;

  /// No description provided for @readerGroupMouseWheelDesc.
  ///
  /// In en, this message translates to:
  /// **'Configure what the mouse wheel does (zoom or turn pages) and its scroll direction.'**
  String get readerGroupMouseWheelDesc;

  /// No description provided for @readerWheelZoom.
  ///
  /// In en, this message translates to:
  /// **'Zoom'**
  String get readerWheelZoom;

  /// No description provided for @readerWheelPage.
  ///
  /// In en, this message translates to:
  /// **'Page'**
  String get readerWheelPage;

  /// No description provided for @readerWheelAction.
  ///
  /// In en, this message translates to:
  /// **'Action'**
  String get readerWheelAction;

  /// No description provided for @favoriteGroups.
  ///
  /// In en, this message translates to:
  /// **'Groups'**
  String get favoriteGroups;

  /// No description provided for @noGroups.
  ///
  /// In en, this message translates to:
  /// **'No groups yet. Create one below.'**
  String get noGroups;

  /// No description provided for @groupAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get groupAll;

  /// No description provided for @groupUngrouped.
  ///
  /// In en, this message translates to:
  /// **'Ungrouped'**
  String get groupUngrouped;

  /// No description provided for @manageGroups.
  ///
  /// In en, this message translates to:
  /// **'Manage groups'**
  String get manageGroups;

  /// No description provided for @newGroup.
  ///
  /// In en, this message translates to:
  /// **'New group'**
  String get newGroup;

  /// No description provided for @renameGroup.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get renameGroup;

  /// No description provided for @renameHint.
  ///
  /// In en, this message translates to:
  /// **'Enter new name'**
  String get renameHint;

  /// No description provided for @groupName.
  ///
  /// In en, this message translates to:
  /// **'Group name'**
  String get groupName;

  /// No description provided for @groupNameEmpty.
  ///
  /// In en, this message translates to:
  /// **'Name cannot be empty'**
  String get groupNameEmpty;

  /// No description provided for @groupNameDuplicate.
  ///
  /// In en, this message translates to:
  /// **'A group with this name already exists'**
  String get groupNameDuplicate;

  /// No description provided for @deleteGroup.
  ///
  /// In en, this message translates to:
  /// **'Delete group'**
  String get deleteGroup;

  /// Group delete confirmation dialog content
  ///
  /// In en, this message translates to:
  /// **'Delete group \"{name}\"? Items are only unlinked from it and stay in your favorites.'**
  String deleteGroupConfirm(Object name);

  /// No description provided for @setGroups.
  ///
  /// In en, this message translates to:
  /// **'Set groups'**
  String get setGroups;

  /// No description provided for @filterByGroup.
  ///
  /// In en, this message translates to:
  /// **'Group'**
  String get filterByGroup;

  /// Item count shown next to a favorite group
  ///
  /// In en, this message translates to:
  /// **'{n} items'**
  String groupItemCount(Object n);

  /// No description provided for @hideCategory.
  ///
  /// In en, this message translates to:
  /// **'Hide'**
  String get hideCategory;

  /// No description provided for @showCategory.
  ///
  /// In en, this message translates to:
  /// **'Show'**
  String get showCategory;

  /// No description provided for @categoryHidden.
  ///
  /// In en, this message translates to:
  /// **'Hidden'**
  String get categoryHidden;

  /// No description provided for @noGroupsHint.
  ///
  /// In en, this message translates to:
  /// **'No categories yet — tap \"New group\" to create one'**
  String get noGroupsHint;

  /// No description provided for @comments.
  ///
  /// In en, this message translates to:
  /// **'Comments'**
  String get comments;

  /// Comment section header with count
  ///
  /// In en, this message translates to:
  /// **'Comments ({n})'**
  String commentsCount(Object n);

  /// No description provided for @writeComment.
  ///
  /// In en, this message translates to:
  /// **'Write a comment'**
  String get writeComment;

  /// No description provided for @replyComment.
  ///
  /// In en, this message translates to:
  /// **'Reply'**
  String get replyComment;

  /// No description provided for @viewAllComments.
  ///
  /// In en, this message translates to:
  /// **'View all comments'**
  String get viewAllComments;

  /// No description provided for @allCommentsTitle.
  ///
  /// In en, this message translates to:
  /// **'All comments'**
  String get allCommentsTitle;

  /// No description provided for @emptyComments.
  ///
  /// In en, this message translates to:
  /// **'No comments yet'**
  String get emptyComments;

  /// No description provided for @beFirstToComment.
  ///
  /// In en, this message translates to:
  /// **'Be the first to comment'**
  String get beFirstToComment;

  /// No description provided for @commentPublish.
  ///
  /// In en, this message translates to:
  /// **'Publish'**
  String get commentPublish;

  /// No description provided for @commentHint.
  ///
  /// In en, this message translates to:
  /// **'Share your thoughts…'**
  String get commentHint;

  /// No description provided for @commentPublishSuccess.
  ///
  /// In en, this message translates to:
  /// **'Comment published'**
  String get commentPublishSuccess;

  /// No description provided for @commentPublishFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to publish'**
  String get commentPublishFailed;

  /// No description provided for @likeAction.
  ///
  /// In en, this message translates to:
  /// **'Like'**
  String get likeAction;

  /// No description provided for @likeFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to like'**
  String get likeFailed;

  /// No description provided for @reportAction.
  ///
  /// In en, this message translates to:
  /// **'Report'**
  String get reportAction;

  /// No description provided for @reportSuccess.
  ///
  /// In en, this message translates to:
  /// **'Reported'**
  String get reportSuccess;

  /// No description provided for @reportFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to report'**
  String get reportFailed;

  /// No description provided for @viewMoreReplies.
  ///
  /// In en, this message translates to:
  /// **'More replies'**
  String get viewMoreReplies;

  /// No description provided for @commentsLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load comments'**
  String get commentsLoadFailed;

  /// No description provided for @loginToComment.
  ///
  /// In en, this message translates to:
  /// **'Log in to comment'**
  String get loginToComment;

  /// No description provided for @loginRequired.
  ///
  /// In en, this message translates to:
  /// **'Login required for this action'**
  String get loginRequired;

  /// No description provided for @sourceLogin.
  ///
  /// In en, this message translates to:
  /// **'Source login'**
  String get sourceLogin;

  /// No description provided for @getCookie.
  ///
  /// In en, this message translates to:
  /// **'Get Cookie'**
  String get getCookie;

  /// No description provided for @cookieNotFoundHint.
  ///
  /// In en, this message translates to:
  /// **'No login cookie detected. Confirm you are signed in, then retry'**
  String get cookieNotFoundHint;

  /// No description provided for @webLogin.
  ///
  /// In en, this message translates to:
  /// **'Web login'**
  String get webLogin;

  /// No description provided for @webLoginDesc.
  ///
  /// In en, this message translates to:
  /// **'Log in on the site page; the session is captured automatically'**
  String get webLoginDesc;

  /// No description provided for @pasteCookie.
  ///
  /// In en, this message translates to:
  /// **'Paste Cookie'**
  String get pasteCookie;

  /// No description provided for @pasteCookieDesc.
  ///
  /// In en, this message translates to:
  /// **'Manually paste the Cookie header from your browser'**
  String get pasteCookieDesc;

  /// No description provided for @cookieHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. token=abc; session=xyz'**
  String get cookieHint;

  /// No description provided for @loginSuccess.
  ///
  /// In en, this message translates to:
  /// **'Logged in'**
  String get loginSuccess;

  /// No description provided for @loginExpired.
  ///
  /// In en, this message translates to:
  /// **'Session expired, please log in again'**
  String get loginExpired;

  /// No description provided for @logoutAction.
  ///
  /// In en, this message translates to:
  /// **'Log out'**
  String get logoutAction;

  /// No description provided for @loggedInState.
  ///
  /// In en, this message translates to:
  /// **'Logged in'**
  String get loggedInState;

  /// No description provided for @loginDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get loginDone;

  /// No description provided for @webviewLoginUnsupported.
  ///
  /// In en, this message translates to:
  /// **'In-app web login is unavailable on this platform. Use \"Paste Cookie\" instead.'**
  String get webviewLoginUnsupported;

  /// No description provided for @apiKeyTitle.
  ///
  /// In en, this message translates to:
  /// **'API Key'**
  String get apiKeyTitle;

  /// No description provided for @apiKeyHint.
  ///
  /// In en, this message translates to:
  /// **'Copy the API Key from the source account settings page (required for favorites and protected requests).'**
  String get apiKeyHint;

  /// No description provided for @apiKeyPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Paste API Key'**
  String get apiKeyPlaceholder;

  /// No description provided for @apiKeySave.
  ///
  /// In en, this message translates to:
  /// **'Save & verify'**
  String get apiKeySave;

  /// No description provided for @apiKeyValid.
  ///
  /// In en, this message translates to:
  /// **'API Key is valid'**
  String get apiKeyValid;

  /// No description provided for @apiKeyInvalid.
  ///
  /// In en, this message translates to:
  /// **'API Key is invalid, please check and retry'**
  String get apiKeyInvalid;

  /// No description provided for @bangumiSettings.
  ///
  /// In en, this message translates to:
  /// **'Bangumi sync'**
  String get bangumiSettings;

  /// No description provided for @bangumiSettingsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Push favorites and progress to bgm.tv'**
  String get bangumiSettingsSubtitle;

  /// No description provided for @bangumiRatingSync.
  ///
  /// In en, this message translates to:
  /// **'Bangumi rating & sync'**
  String get bangumiRatingSync;

  /// No description provided for @bangumiAccount.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get bangumiAccount;

  /// No description provided for @bangumiTokenHint.
  ///
  /// In en, this message translates to:
  /// **'Paste your personal access token'**
  String get bangumiTokenHint;

  /// No description provided for @bangumiTokenVerify.
  ///
  /// In en, this message translates to:
  /// **'Verify and save'**
  String get bangumiTokenVerify;

  /// No description provided for @bangumiGetToken.
  ///
  /// In en, this message translates to:
  /// **'Get a token'**
  String get bangumiGetToken;

  /// No description provided for @bangumiLoggedInAs.
  ///
  /// In en, this message translates to:
  /// **'Logged in as {name}'**
  String bangumiLoggedInAs(String name);

  /// No description provided for @bangumiTokenSaved.
  ///
  /// In en, this message translates to:
  /// **'Token verified'**
  String get bangumiTokenSaved;

  /// No description provided for @bangumiTokenInvalid.
  ///
  /// In en, this message translates to:
  /// **'Invalid token, please check and retry'**
  String get bangumiTokenInvalid;

  /// No description provided for @bangumiNotLoggedIn.
  ///
  /// In en, this message translates to:
  /// **'Not logged in'**
  String get bangumiNotLoggedIn;

  /// No description provided for @bangumiSyncNow.
  ///
  /// In en, this message translates to:
  /// **'Sync now'**
  String get bangumiSyncNow;

  /// No description provided for @bangumiSyncDone.
  ///
  /// In en, this message translates to:
  /// **'Sync finished'**
  String get bangumiSyncDone;

  /// No description provided for @bangumiSyncFailed.
  ///
  /// In en, this message translates to:
  /// **'Sync failed'**
  String get bangumiSyncFailed;

  /// No description provided for @bangumiLastSync.
  ///
  /// In en, this message translates to:
  /// **'Last sync: {time}'**
  String bangumiLastSync(String time);

  /// No description provided for @bangumiNeverSynced.
  ///
  /// In en, this message translates to:
  /// **'Never synced'**
  String get bangumiNeverSynced;

  /// No description provided for @bangumiSyncTypes.
  ///
  /// In en, this message translates to:
  /// **'Sync types'**
  String get bangumiSyncTypes;

  /// No description provided for @bangumiSyncTypeAnime.
  ///
  /// In en, this message translates to:
  /// **'Anime & video'**
  String get bangumiSyncTypeAnime;

  /// No description provided for @bangumiSyncTypeManga.
  ///
  /// In en, this message translates to:
  /// **'Manga'**
  String get bangumiSyncTypeManga;

  /// No description provided for @bangumiSyncTypeNovel.
  ///
  /// In en, this message translates to:
  /// **'Novels'**
  String get bangumiSyncTypeNovel;

  /// No description provided for @bangumiSyncLog.
  ///
  /// In en, this message translates to:
  /// **'Sync log'**
  String get bangumiSyncLog;

  /// No description provided for @bangumiLogSuccess.
  ///
  /// In en, this message translates to:
  /// **'Synced'**
  String get bangumiLogSuccess;

  /// No description provided for @bangumiLogSkipped.
  ///
  /// In en, this message translates to:
  /// **'Skipped (no change)'**
  String get bangumiLogSkipped;

  /// No description provided for @bangumiLogFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get bangumiLogFailed;

  /// No description provided for @bangumiPendingBind.
  ///
  /// In en, this message translates to:
  /// **'Pending manual bind'**
  String get bangumiPendingBind;

  /// No description provided for @bangumiBindAndRate.
  ///
  /// In en, this message translates to:
  /// **'Bangumi bind & rating'**
  String get bangumiBindAndRate;

  /// No description provided for @bangumiBindSubject.
  ///
  /// In en, this message translates to:
  /// **'Bind Bangumi subject'**
  String get bangumiBindSubject;

  /// No description provided for @bangumiSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search Bangumi subjects'**
  String get bangumiSearchHint;

  /// No description provided for @bangumiNoResults.
  ///
  /// In en, this message translates to:
  /// **'No matching subjects'**
  String get bangumiNoResults;

  /// No description provided for @bangumiBoundTo.
  ///
  /// In en, this message translates to:
  /// **'Bound subject #{id}'**
  String bangumiBoundTo(int id);

  /// No description provided for @bangumiUnbind.
  ///
  /// In en, this message translates to:
  /// **'Unbind'**
  String get bangumiUnbind;

  /// No description provided for @bangumiMarkCollected.
  ///
  /// In en, this message translates to:
  /// **'Mark as collected'**
  String get bangumiMarkCollected;

  /// No description provided for @bangumiMyRating.
  ///
  /// In en, this message translates to:
  /// **'My rating'**
  String get bangumiMyRating;

  /// No description provided for @bangumiRatingNone.
  ///
  /// In en, this message translates to:
  /// **'Not rated'**
  String get bangumiRatingNone;

  /// No description provided for @bangumiMyComment.
  ///
  /// In en, this message translates to:
  /// **'My comment'**
  String get bangumiMyComment;

  /// No description provided for @bangumiCommentHint.
  ///
  /// In en, this message translates to:
  /// **'Short comment (synced to Bangumi)'**
  String get bangumiCommentHint;

  /// No description provided for @bangumiSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get bangumiSaved;

  /// No description provided for @bangumiSyncOptions.
  ///
  /// In en, this message translates to:
  /// **'Sync options'**
  String get bangumiSyncOptions;

  /// No description provided for @bangumiPrivateCollection.
  ///
  /// In en, this message translates to:
  /// **'Create collections as private'**
  String get bangumiPrivateCollection;

  /// No description provided for @bangumiPrivateCollectionHint.
  ///
  /// In en, this message translates to:
  /// **'Only affects newly created collections; existing ones stay unchanged'**
  String get bangumiPrivateCollectionHint;

  /// No description provided for @bangumiTagsSync.
  ///
  /// In en, this message translates to:
  /// **'Push favorite groups as tags'**
  String get bangumiTagsSync;

  /// No description provided for @bangumiTagsSyncHint.
  ///
  /// In en, this message translates to:
  /// **'Merged with remote tags; tags added on Bangumi are kept'**
  String get bangumiTagsSyncHint;

  /// No description provided for @bangumiImport.
  ///
  /// In en, this message translates to:
  /// **'Import from Bangumi'**
  String get bangumiImport;

  /// No description provided for @bangumiImportDone.
  ///
  /// In en, this message translates to:
  /// **'Import finished: {count} bound'**
  String bangumiImportDone(int count);

  /// No description provided for @bangumiForcedState.
  ///
  /// In en, this message translates to:
  /// **'Sync status override'**
  String get bangumiForcedState;

  /// No description provided for @bangumiStateAuto.
  ///
  /// In en, this message translates to:
  /// **'Auto detect'**
  String get bangumiStateAuto;

  /// No description provided for @bangumiStateWish.
  ///
  /// In en, this message translates to:
  /// **'Wish'**
  String get bangumiStateWish;

  /// No description provided for @bangumiStateDoing.
  ///
  /// In en, this message translates to:
  /// **'Watching'**
  String get bangumiStateDoing;

  /// No description provided for @bangumiStateCollect.
  ///
  /// In en, this message translates to:
  /// **'Collected'**
  String get bangumiStateCollect;

  /// No description provided for @bangumiStateOnHold.
  ///
  /// In en, this message translates to:
  /// **'On hold'**
  String get bangumiStateOnHold;

  /// No description provided for @bangumiStateDropped.
  ///
  /// In en, this message translates to:
  /// **'Dropped'**
  String get bangumiStateDropped;

  /// No description provided for @bangumiPullFromRemote.
  ///
  /// In en, this message translates to:
  /// **'Pull from Bangumi'**
  String get bangumiPullFromRemote;

  /// No description provided for @bangumiPullDone.
  ///
  /// In en, this message translates to:
  /// **'Pulled remote rating and comment'**
  String get bangumiPullDone;

  /// No description provided for @bangumiPullEmpty.
  ///
  /// In en, this message translates to:
  /// **'No remote collection for this subject'**
  String get bangumiPullEmpty;

  /// No description provided for @backupCategorySource.
  ///
  /// In en, this message translates to:
  /// **'Sources & subscriptions'**
  String get backupCategorySource;

  /// No description provided for @backupCategoryBookmark.
  ///
  /// In en, this message translates to:
  /// **'Favorites & bookmarks'**
  String get backupCategoryBookmark;

  /// No description provided for @backupCategoryProgress.
  ///
  /// In en, this message translates to:
  /// **'Progress & history'**
  String get backupCategoryProgress;

  /// No description provided for @backupCategorySettings.
  ///
  /// In en, this message translates to:
  /// **'Settings & preferences'**
  String get backupCategorySettings;

  /// No description provided for @backupCategoryDownload.
  ///
  /// In en, this message translates to:
  /// **'Downloads'**
  String get backupCategoryDownload;

  /// No description provided for @backupCategoryDanmaku.
  ///
  /// In en, this message translates to:
  /// **'Danmaku cache'**
  String get backupCategoryDanmaku;

  /// No description provided for @backupCategoryOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get backupCategoryOther;

  /// No description provided for @backupSelectScope.
  ///
  /// In en, this message translates to:
  /// **'Select backup content'**
  String get backupSelectScope;

  /// No description provided for @backupSelectAll.
  ///
  /// In en, this message translates to:
  /// **'Select all'**
  String get backupSelectAll;

  /// No description provided for @backupMerge.
  ///
  /// In en, this message translates to:
  /// **'Merge (keep local)'**
  String get backupMerge;

  /// No description provided for @backupReplace.
  ///
  /// In en, this message translates to:
  /// **'Replace (use backup)'**
  String get backupReplace;

  /// No description provided for @backupMergeDesc.
  ///
  /// In en, this message translates to:
  /// **'Merge backup into local; existing local data kept, same keys overwritten by backup'**
  String get backupMergeDesc;

  /// No description provided for @backupReplaceDesc.
  ///
  /// In en, this message translates to:
  /// **'Replace local data with backup entirely (irreversible)'**
  String get backupReplaceDesc;

  /// No description provided for @backupImportMode.
  ///
  /// In en, this message translates to:
  /// **'Restore mode'**
  String get backupImportMode;

  /// No description provided for @backupScopeNone.
  ///
  /// In en, this message translates to:
  /// **'Select at least one category to back up'**
  String get backupScopeNone;

  /// No description provided for @backupPreviewTitle.
  ///
  /// In en, this message translates to:
  /// **'About to restore {count} items'**
  String backupPreviewTitle(Object count);

  /// No description provided for @backupExported.
  ///
  /// In en, this message translates to:
  /// **'Backup exported ({count} items)'**
  String backupExported(Object count);

  /// No description provided for @pullNow.
  ///
  /// In en, this message translates to:
  /// **'Restore from cloud'**
  String get pullNow;

  /// No description provided for @cloudSyncPullMode.
  ///
  /// In en, this message translates to:
  /// **'Restore mode'**
  String get cloudSyncPullMode;

  /// No description provided for @cloudSyncErrorNoConfig.
  ///
  /// In en, this message translates to:
  /// **'WebDAV not configured; fill in URL, account and password first'**
  String get cloudSyncErrorNoConfig;

  /// No description provided for @cloudSyncErrorNoRemote.
  ///
  /// In en, this message translates to:
  /// **'No backup file available in the cloud'**
  String get cloudSyncErrorNoRemote;

  /// No description provided for @cloudSyncErrorEncode.
  ///
  /// In en, this message translates to:
  /// **'Failed to package backup; please retry'**
  String get cloudSyncErrorEncode;

  /// No description provided for @cloudSyncErrorNetwork.
  ///
  /// In en, this message translates to:
  /// **'Network error; check WebDAV URL and connection'**
  String get cloudSyncErrorNetwork;

  /// No description provided for @cloudSyncErrorUnknown.
  ///
  /// In en, this message translates to:
  /// **'Sync error: {detail}'**
  String cloudSyncErrorUnknown(Object detail);

  /// No description provided for @cloudSyncStatusSection.
  ///
  /// In en, this message translates to:
  /// **'Sync status'**
  String get cloudSyncStatusSection;

  /// No description provided for @cloudSyncStatusUpload.
  ///
  /// In en, this message translates to:
  /// **'Upload backup'**
  String get cloudSyncStatusUpload;

  /// No description provided for @cloudSyncStatusRestore.
  ///
  /// In en, this message translates to:
  /// **'Restore data'**
  String get cloudSyncStatusRestore;

  /// No description provided for @cloudSyncStatusSuccess.
  ///
  /// In en, this message translates to:
  /// **'Success'**
  String get cloudSyncStatusSuccess;

  /// No description provided for @cloudSyncStatusFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get cloudSyncStatusFailed;

  /// No description provided for @cloudSyncStatusNoChanges.
  ///
  /// In en, this message translates to:
  /// **'No changes'**
  String get cloudSyncStatusNoChanges;

  /// No description provided for @cloudSyncStatusNotRun.
  ///
  /// In en, this message translates to:
  /// **'Not run yet'**
  String get cloudSyncStatusNotRun;

  /// No description provided for @cloudSyncStatusItems.
  ///
  /// In en, this message translates to:
  /// **'{count} items'**
  String cloudSyncStatusItems(Object count);

  /// No description provided for @cloudSyncNextSync.
  ///
  /// In en, this message translates to:
  /// **'Next auto sync: {time}'**
  String cloudSyncNextSync(Object time);

  /// No description provided for @cloudSyncResolveConflicts.
  ///
  /// In en, this message translates to:
  /// **'Resolve conflicts'**
  String get cloudSyncResolveConflicts;

  /// No description provided for @cloudSyncConflictTitle.
  ///
  /// In en, this message translates to:
  /// **'Sync conflicts'**
  String get cloudSyncConflictTitle;

  /// No description provided for @cloudSyncConflictNone.
  ///
  /// In en, this message translates to:
  /// **'No conflicts between local and cloud'**
  String get cloudSyncConflictNone;

  /// No description provided for @cloudSyncConflictIntro.
  ///
  /// In en, this message translates to:
  /// **'The following categories differ between local and cloud. Choose which side to keep for each:'**
  String get cloudSyncConflictIntro;

  /// No description provided for @cloudSyncConflictUseRemote.
  ///
  /// In en, this message translates to:
  /// **'Use cloud'**
  String get cloudSyncConflictUseRemote;

  /// No description provided for @cloudSyncConflictKeepLocal.
  ///
  /// In en, this message translates to:
  /// **'Keep local'**
  String get cloudSyncConflictKeepLocal;

  /// No description provided for @cloudSyncConflictMerge.
  ///
  /// In en, this message translates to:
  /// **'Merge'**
  String get cloudSyncConflictMerge;

  /// No description provided for @cloudSyncConflictCount.
  ///
  /// In en, this message translates to:
  /// **'{count} conflicts'**
  String cloudSyncConflictCount(Object count);

  /// No description provided for @cloudSyncConflictLocal.
  ///
  /// In en, this message translates to:
  /// **'Local'**
  String get cloudSyncConflictLocal;

  /// No description provided for @cloudSyncConflictRemote.
  ///
  /// In en, this message translates to:
  /// **'Cloud'**
  String get cloudSyncConflictRemote;

  /// No description provided for @cloudSyncConflictApply.
  ///
  /// In en, this message translates to:
  /// **'Apply and restore'**
  String get cloudSyncConflictApply;

  /// No description provided for @cloudSyncConflictLoading.
  ///
  /// In en, this message translates to:
  /// **'Analyzing conflicts…'**
  String get cloudSyncConflictLoading;

  /// No description provided for @bangumiSyncThis.
  ///
  /// In en, this message translates to:
  /// **'Sync to Bangumi'**
  String get bangumiSyncThis;

  /// No description provided for @syncWorking.
  ///
  /// In en, this message translates to:
  /// **'Syncing to Bangumi…'**
  String get syncWorking;

  /// No description provided for @syncBusy.
  ///
  /// In en, this message translates to:
  /// **'Sync in progress, please wait'**
  String get syncBusy;

  /// No description provided for @bangumiFavoriteFirst.
  ///
  /// In en, this message translates to:
  /// **'Add to favorites to rate and comment'**
  String get bangumiFavoriteFirst;

  /// No description provided for @bangumiCollectionStatus.
  ///
  /// In en, this message translates to:
  /// **'Bangumi collection status'**
  String get bangumiCollectionStatus;

  /// No description provided for @bangumiBindFirst.
  ///
  /// In en, this message translates to:
  /// **'Bind a Bangumi subject first'**
  String get bangumiBindFirst;

  /// No description provided for @bangumiSiteRating.
  ///
  /// In en, this message translates to:
  /// **'Bangumi rating'**
  String get bangumiSiteRating;

  /// No description provided for @bangumiSyncSettings.
  ///
  /// In en, this message translates to:
  /// **'Sync settings'**
  String get bangumiSyncSettings;

  /// No description provided for @bangumiBindToViewRating.
  ///
  /// In en, this message translates to:
  /// **'Bind a subject to view its Bangumi rating and reviews'**
  String get bangumiBindToViewRating;

  /// No description provided for @bangumiRatingUsers.
  ///
  /// In en, this message translates to:
  /// **'{count} ratings'**
  String bangumiRatingUsers(int count);

  /// No description provided for @bangumiRank.
  ///
  /// In en, this message translates to:
  /// **'Rank #{rank}'**
  String bangumiRank(int rank);

  /// No description provided for @bangumiSummary.
  ///
  /// In en, this message translates to:
  /// **'Summary'**
  String get bangumiSummary;

  /// No description provided for @bangumiTags.
  ///
  /// In en, this message translates to:
  /// **'Tags'**
  String get bangumiTags;

  /// No description provided for @bangumiNoRating.
  ///
  /// In en, this message translates to:
  /// **'No rating yet'**
  String get bangumiNoRating;

  /// No description provided for @bangumiLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load'**
  String get bangumiLoadFailed;

  /// No description provided for @bangumiViewOnWeb.
  ///
  /// In en, this message translates to:
  /// **'Open on Bangumi'**
  String get bangumiViewOnWeb;

  /// No description provided for @bangumiBrowseCollection.
  ///
  /// In en, this message translates to:
  /// **'Browse Bangumi collection'**
  String get bangumiBrowseCollection;

  /// No description provided for @bangumiCollectionEmpty.
  ///
  /// In en, this message translates to:
  /// **'No items in this state'**
  String get bangumiCollectionEmpty;

  /// No description provided for @bangumiSubjectTypeAnime.
  ///
  /// In en, this message translates to:
  /// **'Anime'**
  String get bangumiSubjectTypeAnime;

  /// No description provided for @bangumiSubjectTypeBook.
  ///
  /// In en, this message translates to:
  /// **'Book'**
  String get bangumiSubjectTypeBook;

  /// No description provided for @bangumiSubjectTypeReal.
  ///
  /// In en, this message translates to:
  /// **'Real'**
  String get bangumiSubjectTypeReal;

  /// No description provided for @bangumiLoginWithOAuth.
  ///
  /// In en, this message translates to:
  /// **'Sign in with Bangumi'**
  String get bangumiLoginWithOAuth;

  /// No description provided for @bangumiOauthHint.
  ///
  /// In en, this message translates to:
  /// **'Safer: authorize in your browser and return to the app automatically.'**
  String get bangumiOauthHint;

  /// No description provided for @bangumiOauthNotConfigured.
  ///
  /// In en, this message translates to:
  /// **'OAuth not configured: create an app on the Bangumi developer console and fill in Client ID / Secret.'**
  String get bangumiOauthNotConfigured;

  /// No description provided for @bangumiOauthFailed.
  ///
  /// In en, this message translates to:
  /// **'Bangumi authorization failed. Please try again.'**
  String get bangumiOauthFailed;

  /// No description provided for @networkSettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Network Settings'**
  String get networkSettingsTitle;

  /// No description provided for @networkSettingsDesc.
  ///
  /// In en, this message translates to:
  /// **'Proxy, DNS, DoH/DoT, SNI, ECH and Hosts'**
  String get networkSettingsDesc;

  /// No description provided for @networkInfoTitle.
  ///
  /// In en, this message translates to:
  /// **'About network settings'**
  String get networkInfoTitle;

  /// No description provided for @networkInfoBody.
  ///
  /// In en, this message translates to:
  /// **'Global settings apply to all in-app HTTP traffic (covers, downloads, sync, scraping). Native components (webview, media player, cast) use the native stack and are not affected. Per-source overrides only affect that source\'s scraping.'**
  String get networkInfoBody;

  /// No description provided for @networkHelpDoc.
  ///
  /// In en, this message translates to:
  /// **'Help & documentation'**
  String get networkHelpDoc;

  /// No description provided for @networkExperimentalNote.
  ///
  /// In en, this message translates to:
  /// **'Experimental: limited by the Dart TLS stack; may not take effect on all paths.'**
  String get networkExperimentalNote;

  /// No description provided for @networkProxyTitle.
  ///
  /// In en, this message translates to:
  /// **'Proxy'**
  String get networkProxyTitle;

  /// No description provided for @networkProxyModeDirect.
  ///
  /// In en, this message translates to:
  /// **'Direct'**
  String get networkProxyModeDirect;

  /// No description provided for @networkProxyModeSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get networkProxyModeSystem;

  /// No description provided for @networkProxyModeManual.
  ///
  /// In en, this message translates to:
  /// **'Manual'**
  String get networkProxyModeManual;

  /// No description provided for @networkProxyProtocolHttp.
  ///
  /// In en, this message translates to:
  /// **'HTTP'**
  String get networkProxyProtocolHttp;

  /// No description provided for @networkProxyProtocolSocks5.
  ///
  /// In en, this message translates to:
  /// **'SOCKS5'**
  String get networkProxyProtocolSocks5;

  /// No description provided for @networkProxyHost.
  ///
  /// In en, this message translates to:
  /// **'Host'**
  String get networkProxyHost;

  /// No description provided for @networkProxyPort.
  ///
  /// In en, this message translates to:
  /// **'Port'**
  String get networkProxyPort;

  /// No description provided for @networkProxyUsername.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get networkProxyUsername;

  /// No description provided for @networkProxyPassword.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get networkProxyPassword;

  /// No description provided for @networkTestProxy.
  ///
  /// In en, this message translates to:
  /// **'Test proxy'**
  String get networkTestProxy;

  /// Network test success with latency
  ///
  /// In en, this message translates to:
  /// **'OK ({ms} ms)'**
  String networkTestSuccess(int ms);

  /// No description provided for @networkTestFailed.
  ///
  /// In en, this message translates to:
  /// **'Test failed'**
  String get networkTestFailed;

  /// No description provided for @networkDnsTitle.
  ///
  /// In en, this message translates to:
  /// **'DNS'**
  String get networkDnsTitle;

  /// No description provided for @networkDnsModeSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get networkDnsModeSystem;

  /// No description provided for @networkDnsModeCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get networkDnsModeCustom;

  /// No description provided for @networkDnsModeDoh.
  ///
  /// In en, this message translates to:
  /// **'DoH'**
  String get networkDnsModeDoh;

  /// No description provided for @networkDnsModeDot.
  ///
  /// In en, this message translates to:
  /// **'DoT'**
  String get networkDnsModeDot;

  /// No description provided for @networkDnsServers.
  ///
  /// In en, this message translates to:
  /// **'DNS servers'**
  String get networkDnsServers;

  /// No description provided for @networkDnsServersEmpty.
  ///
  /// In en, this message translates to:
  /// **'No servers configured'**
  String get networkDnsServersEmpty;

  /// No description provided for @networkAddServer.
  ///
  /// In en, this message translates to:
  /// **'Add server'**
  String get networkAddServer;

  /// No description provided for @networkDnsCacheEnabled.
  ///
  /// In en, this message translates to:
  /// **'Enable DNS cache'**
  String get networkDnsCacheEnabled;

  /// DNS cache entry count
  ///
  /// In en, this message translates to:
  /// **'Cached entries: {count}'**
  String networkDnsCacheStatus(int count);

  /// No description provided for @networkClearCache.
  ///
  /// In en, this message translates to:
  /// **'Clear cache'**
  String get networkClearCache;

  /// No description provided for @networkTestDns.
  ///
  /// In en, this message translates to:
  /// **'Test DNS resolution'**
  String get networkTestDns;

  /// No description provided for @networkDnsTestHost.
  ///
  /// In en, this message translates to:
  /// **'Host to resolve'**
  String get networkDnsTestHost;

  /// DNS resolution result with IPs and latency
  ///
  /// In en, this message translates to:
  /// **'{ips} ({ms} ms)'**
  String networkDnsTestResult(Object ips, int ms);

  /// No description provided for @networkDohTitle.
  ///
  /// In en, this message translates to:
  /// **'DNS over HTTPS (DoH)'**
  String get networkDohTitle;

  /// No description provided for @networkDohPreset.
  ///
  /// In en, this message translates to:
  /// **'Preset'**
  String get networkDohPreset;

  /// No description provided for @networkDohUrl.
  ///
  /// In en, this message translates to:
  /// **'DoH URL'**
  String get networkDohUrl;

  /// No description provided for @networkTestDoh.
  ///
  /// In en, this message translates to:
  /// **'Test DoH'**
  String get networkTestDoh;

  /// No description provided for @networkDotTitle.
  ///
  /// In en, this message translates to:
  /// **'DNS over TLS (DoT)'**
  String get networkDotTitle;

  /// No description provided for @networkDotHost.
  ///
  /// In en, this message translates to:
  /// **'DoT host'**
  String get networkDotHost;

  /// No description provided for @networkDotPort.
  ///
  /// In en, this message translates to:
  /// **'DoT port'**
  String get networkDotPort;

  /// No description provided for @networkHostsTitle.
  ///
  /// In en, this message translates to:
  /// **'Custom Hosts'**
  String get networkHostsTitle;

  /// No description provided for @networkHostsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No host entries'**
  String get networkHostsEmpty;

  /// No description provided for @networkAddHost.
  ///
  /// In en, this message translates to:
  /// **'Add host entry'**
  String get networkAddHost;

  /// No description provided for @networkHostsIp.
  ///
  /// In en, this message translates to:
  /// **'IP address'**
  String get networkHostsIp;

  /// No description provided for @networkHostsHost.
  ///
  /// In en, this message translates to:
  /// **'Hostname'**
  String get networkHostsHost;

  /// No description provided for @networkSniTitle.
  ///
  /// In en, this message translates to:
  /// **'SNI'**
  String get networkSniTitle;

  /// No description provided for @networkSniEnabled.
  ///
  /// In en, this message translates to:
  /// **'Enable custom SNI'**
  String get networkSniEnabled;

  /// No description provided for @networkSniDefault.
  ///
  /// In en, this message translates to:
  /// **'Default SNI value'**
  String get networkSniDefault;

  /// No description provided for @networkSniRuntimeNote.
  ///
  /// In en, this message translates to:
  /// **'Applies to direct HTTPS connections: the default SNI applies to all hosts, and `-` suppresses SNI entirely (the handshake omits server_name, bypassing SNI-based blocking; pair with custom hosts pinning a reachable IP). Per-host mappings below override the default. Not applied through a proxy.'**
  String get networkSniRuntimeNote;

  /// No description provided for @networkSniDomainTitle.
  ///
  /// In en, this message translates to:
  /// **'Host → SNI mappings'**
  String get networkSniDomainTitle;

  /// No description provided for @networkSniDomainEmpty.
  ///
  /// In en, this message translates to:
  /// **'No mappings'**
  String get networkSniDomainEmpty;

  /// No description provided for @networkSniAddDomain.
  ///
  /// In en, this message translates to:
  /// **'Add SNI mapping'**
  String get networkSniAddDomain;

  /// No description provided for @networkSniDomainHost.
  ///
  /// In en, this message translates to:
  /// **'Host pattern (.example.com for suffix match)'**
  String get networkSniDomainHost;

  /// No description provided for @networkSniDomainValue.
  ///
  /// In en, this message translates to:
  /// **'SNI value (- for none)'**
  String get networkSniDomainValue;

  /// No description provided for @networkSniTestHost.
  ///
  /// In en, this message translates to:
  /// **'Host to test'**
  String get networkSniTestHost;

  /// No description provided for @networkTestSni.
  ///
  /// In en, this message translates to:
  /// **'Test SNI handshake'**
  String get networkTestSni;

  /// SNI handshake test result with TLS name and latency
  ///
  /// In en, this message translates to:
  /// **'{name} ({ms} ms)'**
  String networkSniTestResult(String name, int ms);

  /// No description provided for @networkEchTitle.
  ///
  /// In en, this message translates to:
  /// **'ECH (Encrypted Client Hello)'**
  String get networkEchTitle;

  /// No description provided for @networkEchEnabled.
  ///
  /// In en, this message translates to:
  /// **'Enable ECH'**
  String get networkEchEnabled;

  /// No description provided for @networkEchConfigList.
  ///
  /// In en, this message translates to:
  /// **'ECH config list (base64)'**
  String get networkEchConfigList;

  /// No description provided for @networkEchRuntimeNote.
  ///
  /// In en, this message translates to:
  /// **'The in-app direct path uses the Dart TLS stack, which cannot do ECH. With this enabled, requests are routed through the built-in ECH proxy and the native TLS stack performs the ECH handshake; hosts that do not support ECH fall back to a direct connection automatically, so normal access is unaffected. If you provide an ECH config list it is used as-is; when left empty the proxy obtains one automatically.'**
  String get networkEchRuntimeNote;

  /// No description provided for @networkReset.
  ///
  /// In en, this message translates to:
  /// **'Reset network settings'**
  String get networkReset;

  /// No description provided for @networkResetTitle.
  ///
  /// In en, this message translates to:
  /// **'Reset network settings'**
  String get networkResetTitle;

  /// No description provided for @networkResetConfirm.
  ///
  /// In en, this message translates to:
  /// **'Restore all network settings to defaults?'**
  String get networkResetConfirm;

  /// No description provided for @networkResetDone.
  ///
  /// In en, this message translates to:
  /// **'Network settings restored to defaults'**
  String get networkResetDone;

  /// No description provided for @networkSaved.
  ///
  /// In en, this message translates to:
  /// **'Network settings saved'**
  String get networkSaved;

  /// No description provided for @networkCacheCleared.
  ///
  /// In en, this message translates to:
  /// **'DNS cache cleared'**
  String get networkCacheCleared;

  /// No description provided for @networkErrorInvalidHost.
  ///
  /// In en, this message translates to:
  /// **'Invalid host'**
  String get networkErrorInvalidHost;

  /// No description provided for @networkErrorInvalidPort.
  ///
  /// In en, this message translates to:
  /// **'Invalid port (1-65535)'**
  String get networkErrorInvalidPort;

  /// No description provided for @networkErrorInvalidIp.
  ///
  /// In en, this message translates to:
  /// **'Invalid IP address'**
  String get networkErrorInvalidIp;

  /// No description provided for @networkErrorInvalidDomain.
  ///
  /// In en, this message translates to:
  /// **'Invalid domain'**
  String get networkErrorInvalidDomain;

  /// No description provided for @networkErrorInvalidDohUrl.
  ///
  /// In en, this message translates to:
  /// **'Invalid DoH URL (must be https)'**
  String get networkErrorInvalidDohUrl;

  /// No description provided for @sourceNetworkOverride.
  ///
  /// In en, this message translates to:
  /// **'Network override'**
  String get sourceNetworkOverride;

  /// No description provided for @sourceNetworkScopeNote.
  ///
  /// In en, this message translates to:
  /// **'These settings only affect this source\'s scraping. They override the global network settings per aspect; aspects left off inherit the global configuration.'**
  String get sourceNetworkScopeNote;

  /// No description provided for @sourceNetworkFromSourceNote.
  ///
  /// In en, this message translates to:
  /// **'This source ships its own network configuration, which is applied automatically — no manual setup required. Edit the values below and save to keep a custom override.'**
  String get sourceNetworkFromSourceNote;

  /// No description provided for @networkOverrideEnable.
  ///
  /// In en, this message translates to:
  /// **'Override global'**
  String get networkOverrideEnable;

  /// No description provided for @networkInheritGlobal.
  ///
  /// In en, this message translates to:
  /// **'Inherit global'**
  String get networkInheritGlobal;

  /// No description provided for @sourceNetworkSaved.
  ///
  /// In en, this message translates to:
  /// **'Source network override saved'**
  String get sourceNetworkSaved;

  /// No description provided for @sourceNetworkClear.
  ///
  /// In en, this message translates to:
  /// **'Clear override'**
  String get sourceNetworkClear;

  /// No description provided for @sourceNetworkClearConfirm.
  ///
  /// In en, this message translates to:
  /// **'Remove this source\'s network override and inherit global settings?'**
  String get sourceNetworkClearConfirm;

  /// No description provided for @sourceNetworkClearConfirmFromSource.
  ///
  /// In en, this message translates to:
  /// **'This source ships its own network configuration. Clearing the custom override restores the source\'s built-in configuration (not global settings). Continue?'**
  String get sourceNetworkClearConfirmFromSource;

  /// No description provided for @sourceNetworkCleared.
  ///
  /// In en, this message translates to:
  /// **'Source network override cleared'**
  String get sourceNetworkCleared;

  /// No description provided for @sourceNetworkClearedToSource.
  ///
  /// In en, this message translates to:
  /// **'Custom override cleared; this source now uses its built-in network configuration'**
  String get sourceNetworkClearedToSource;

  /// No description provided for @bangumiNoMatch.
  ///
  /// In en, this message translates to:
  /// **'No matching Bangumi subject found'**
  String get bangumiNoMatch;

  /// No description provided for @bangumiManualBind.
  ///
  /// In en, this message translates to:
  /// **'Search & bind manually'**
  String get bangumiManualBind;

  /// No description provided for @bangumiConfirmBind.
  ///
  /// In en, this message translates to:
  /// **'Confirm binding to one of these'**
  String get bangumiConfirmBind;

  /// No description provided for @bangumiFromBangumi.
  ///
  /// In en, this message translates to:
  /// **'Data from Bangumi'**
  String get bangumiFromBangumi;

  /// No description provided for @bangumiHideCollection.
  ///
  /// In en, this message translates to:
  /// **'Hide collection'**
  String get bangumiHideCollection;

  /// No description provided for @bangumiProgress.
  ///
  /// In en, this message translates to:
  /// **'Progress (episodes/chapters watched)'**
  String get bangumiProgress;

  /// No description provided for @bangumiSaveSync.
  ///
  /// In en, this message translates to:
  /// **'Save & sync'**
  String get bangumiSaveSync;

  /// No description provided for @bangumiSavedLocal.
  ///
  /// In en, this message translates to:
  /// **'Not signed in: saved locally'**
  String get bangumiSavedLocal;

  /// No description provided for @websiteComments.
  ///
  /// In en, this message translates to:
  /// **'Site comments'**
  String get websiteComments;

  /// No description provided for @bangumiComments.
  ///
  /// In en, this message translates to:
  /// **'Bangumi comments'**
  String get bangumiComments;

  /// No description provided for @bangumiCommentsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No comments yet'**
  String get bangumiCommentsEmpty;

  /// No description provided for @bangumiCommentsLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load comments'**
  String get bangumiCommentsLoadFailed;

  /// No description provided for @bangumiGuessMatch.
  ///
  /// In en, this message translates to:
  /// **'Best-guess match: {name}'**
  String bangumiGuessMatch(Object name);

  /// No description provided for @bangumiEps.
  ///
  /// In en, this message translates to:
  /// **'{count} eps'**
  String bangumiEps(int count);

  /// No description provided for @bangumiAirDate.
  ///
  /// In en, this message translates to:
  /// **'Aired: {date}'**
  String bangumiAirDate(String date);

  /// No description provided for @bangumiCollectionWish.
  ///
  /// In en, this message translates to:
  /// **'{count} wish'**
  String bangumiCollectionWish(int count);

  /// No description provided for @bangumiCollectionDoing.
  ///
  /// In en, this message translates to:
  /// **'{count} watching'**
  String bangumiCollectionDoing(int count);

  /// No description provided for @bangumiCollectionCollect.
  ///
  /// In en, this message translates to:
  /// **'{count} watched'**
  String bangumiCollectionCollect(int count);

  /// No description provided for @bangumiCharacters.
  ///
  /// In en, this message translates to:
  /// **'Characters'**
  String get bangumiCharacters;

  /// No description provided for @bangumiRelated.
  ///
  /// In en, this message translates to:
  /// **'Related'**
  String get bangumiRelated;

  /// No description provided for @bangumiCollectionStat.
  ///
  /// In en, this message translates to:
  /// **'Collection Stats'**
  String get bangumiCollectionStat;

  /// No description provided for @bangumiProxyTitle.
  ///
  /// In en, this message translates to:
  /// **'Connection Mode'**
  String get bangumiProxyTitle;

  /// No description provided for @bangumiProxyDirect.
  ///
  /// In en, this message translates to:
  /// **'Direct'**
  String get bangumiProxyDirect;

  /// No description provided for @bangumiProxyMirror.
  ///
  /// In en, this message translates to:
  /// **'Mirror'**
  String get bangumiProxyMirror;

  /// No description provided for @bangumiProxyEch.
  ///
  /// In en, this message translates to:
  /// **'ECH'**
  String get bangumiProxyEch;

  /// No description provided for @bangumiProxyMainSite.
  ///
  /// In en, this message translates to:
  /// **'Main site domain'**
  String get bangumiProxyMainSite;

  /// No description provided for @bangumiProxyApi.
  ///
  /// In en, this message translates to:
  /// **'API domain'**
  String get bangumiProxyApi;

  /// No description provided for @bangumiProxyImage.
  ///
  /// In en, this message translates to:
  /// **'Image domain'**
  String get bangumiProxyImage;

  /// No description provided for @bangumiProxyHint.
  ///
  /// In en, this message translates to:
  /// **'In mirror/reverse-proxy mode, enter your self-hosted domain (no path). Leave blank to use Bangumi\'s default domain for that category.'**
  String get bangumiProxyHint;

  /// No description provided for @bangumiProxySaved.
  ///
  /// In en, this message translates to:
  /// **'Proxy settings saved'**
  String get bangumiProxySaved;

  /// No description provided for @bangumiEchProxyHint.
  ///
  /// In en, this message translates to:
  /// **'Connects to the official domains, but requests to Bangumi-related domains are transparently routed through a local ECH (Encrypted Client Hello) proxy that hides the SNI. No configuration needed. If this mode works, there is no need to consider \"Mirror / Reverse Proxy\". Requires a build that bundles the native ECH engine; without it this mode cannot be enabled.'**
  String get bangumiEchProxyHint;

  /// No description provided for @bangumiEchStatus.
  ///
  /// In en, this message translates to:
  /// **'ECH proxy status'**
  String get bangumiEchStatus;

  /// No description provided for @bangumiEchUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Failed to start the local ECH proxy. The native engine may not be bundled for this platform.'**
  String get bangumiEchUnavailable;

  /// No description provided for @bangumiEchProxyRunning.
  ///
  /// In en, this message translates to:
  /// **'Running (port {port})'**
  String bangumiEchProxyRunning(int port);

  /// No description provided for @bangumiEchProxyIdle.
  ///
  /// In en, this message translates to:
  /// **'Not running'**
  String get bangumiEchProxyIdle;

  /// No description provided for @bangumiDetail.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get bangumiDetail;

  /// No description provided for @bangumiStaff.
  ///
  /// In en, this message translates to:
  /// **'Staff'**
  String get bangumiStaff;

  /// No description provided for @bangumiTapToExpand.
  ///
  /// In en, this message translates to:
  /// **'Tap to expand'**
  String get bangumiTapToExpand;

  /// No description provided for @bangumiSyncRating.
  ///
  /// In en, this message translates to:
  /// **'Rating'**
  String get bangumiSyncRating;

  /// No description provided for @bangumiSyncComment.
  ///
  /// In en, this message translates to:
  /// **'Comment'**
  String get bangumiSyncComment;

  /// No description provided for @bangumiSync.
  ///
  /// In en, this message translates to:
  /// **'Sync'**
  String get bangumiSync;

  /// No description provided for @bangumiPublic.
  ///
  /// In en, this message translates to:
  /// **'Public'**
  String get bangumiPublic;

  /// No description provided for @bangumiPrivate.
  ///
  /// In en, this message translates to:
  /// **'Private'**
  String get bangumiPrivate;

  /// No description provided for @bangumiSyncLoginHint.
  ///
  /// In en, this message translates to:
  /// **'Sign in to Bangumi in Settings first'**
  String get bangumiSyncLoginHint;

  /// No description provided for @bangumiSyncSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get bangumiSyncSaved;

  /// No description provided for @bangumiSyncWatchedEpisodes.
  ///
  /// In en, this message translates to:
  /// **'Watched episodes'**
  String get bangumiSyncWatchedEpisodes;

  /// No description provided for @bangumiSyncWatchedChapters.
  ///
  /// In en, this message translates to:
  /// **'Read chapters'**
  String get bangumiSyncWatchedChapters;

  /// No description provided for @bangumiSyncProgressHint.
  ///
  /// In en, this message translates to:
  /// **'Leave empty to auto-sync local progress'**
  String get bangumiSyncProgressHint;

  /// No description provided for @bangumiSyncExpandList.
  ///
  /// In en, this message translates to:
  /// **'Pick specific episodes / chapters'**
  String get bangumiSyncExpandList;

  /// No description provided for @bangumiSyncCollapseList.
  ///
  /// In en, this message translates to:
  /// **'Collapse'**
  String get bangumiSyncCollapseList;

  /// Total count with unit (episodes/volumes/chapters) for the multi-select list
  ///
  /// In en, this message translates to:
  /// **'{count} {unit} total'**
  String bangumiSyncChaptersTotal(Object count, Object unit);

  /// Hint after Bangumi episode list is loaded
  ///
  /// In en, this message translates to:
  /// **'{count} {unit} loaded — pick individually'**
  String bangumiSyncChaptersLoadedHint(Object count, Object unit);

  /// Shown when subject has no episode metadata
  ///
  /// In en, this message translates to:
  /// **'Bangumi has no episode list for this subject ({eps}), cannot pick individually'**
  String bangumiSyncNoEpisodeList(Object eps);

  /// Failed to fetch Bangumi episode list
  ///
  /// In en, this message translates to:
  /// **'Failed to load episode list: {error}'**
  String bangumiSyncLoadEpisodesFailed(Object error);

  /// No description provided for @bangumiSyncUnitEp.
  ///
  /// In en, this message translates to:
  /// **'ep'**
  String get bangumiSyncUnitEp;

  /// No description provided for @bangumiSyncUnitVolume.
  ///
  /// In en, this message translates to:
  /// **'vol'**
  String get bangumiSyncUnitVolume;

  /// No description provided for @bangumiSyncUnitChapter.
  ///
  /// In en, this message translates to:
  /// **'ch'**
  String get bangumiSyncUnitChapter;

  /// Bangumi sync dialog progress section title (matches source website UI style)
  ///
  /// In en, this message translates to:
  /// **'My Completion'**
  String get bangumiSyncMyCompletion;

  /// Inline update button inside the progress section of the Bangumi sync dialog
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get bangumiSyncUpdate;

  /// ExpansionTile title in the Bangumi sync dialog containing rating / comment / state / privacy
  ///
  /// In en, this message translates to:
  /// **'Advanced'**
  String get bangumiSyncAdvancedOptions;

  /// Subtitle hint of the advanced options expansion tile
  ///
  /// In en, this message translates to:
  /// **'Rating / Comment / Status / Privacy'**
  String get bangumiSyncAdvancedHint;

  /// Chapter label in the book (manga/novel) sync dialog matching the source website UI
  ///
  /// In en, this message translates to:
  /// **'Chap.'**
  String get bangumiSyncChapLabel;

  /// Volume label in the book (manga/novel) sync dialog matching the source website UI
  ///
  /// In en, this message translates to:
  /// **'Vol.'**
  String get bangumiSyncVolLabel;

  /// Increment-by-one button next to the Chap./Vol. input in the book sync dialog
  ///
  /// In en, this message translates to:
  /// **'+'**
  String get bangumiSyncIncrement;

  /// Section title above the episode grid in the anime sync dialog (matches source website '章节' heading)
  ///
  /// In en, this message translates to:
  /// **'Episodes'**
  String get bangumiSyncAnimeGridTitle;

  /// Hint text under the episode grid explaining tap-to-toggle behavior
  ///
  /// In en, this message translates to:
  /// **'Tap a cell to toggle watched / unwatched'**
  String get bangumiSyncAnimeGridHint;

  /// Schedule label 'week' on the bottom bar of the anime sync dialog (informational placeholder, matches source website UI)
  ///
  /// In en, this message translates to:
  /// **'W'**
  String get bangumiSyncScheduleWeek;

  /// Schedule label 'hour' on the bottom bar of the anime sync dialog (informational placeholder)
  ///
  /// In en, this message translates to:
  /// **'H'**
  String get bangumiSyncScheduleHour;

  /// Schedule label 'minute' on the bottom bar of the anime sync dialog (informational placeholder)
  ///
  /// In en, this message translates to:
  /// **'M'**
  String get bangumiSyncScheduleMinute;

  /// Title of the picker dialog for editing the air schedule (weekday / hour / minute)
  ///
  /// In en, this message translates to:
  /// **'Air time'**
  String get bangumiSyncScheduleTitle;

  /// Page indicator text under the paginated episode grid (e.g. '●○')
  ///
  /// In en, this message translates to:
  /// **'Page {current} / {total}'**
  String bangumiSyncPageOf(int current, int total);

  /// Placeholder for unknown total in 'N / ?? ' progress display, matching source website UI
  ///
  /// In en, this message translates to:
  /// **'??'**
  String get bangumiSyncUnknown;

  /// No description provided for @bangumiRatingValue.
  ///
  /// In en, this message translates to:
  /// **'{count} / 10'**
  String bangumiRatingValue(int count);

  /// No description provided for @clear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// No description provided for @mirrorAddCustom.
  ///
  /// In en, this message translates to:
  /// **'Add custom mirror'**
  String get mirrorAddCustom;

  /// No description provided for @mirrorName.
  ///
  /// In en, this message translates to:
  /// **'Mirror name'**
  String get mirrorName;

  /// No description provided for @mirrorDomain.
  ///
  /// In en, this message translates to:
  /// **'Domain'**
  String get mirrorDomain;

  /// No description provided for @mirrorBaseUrl.
  ///
  /// In en, this message translates to:
  /// **'Base URL'**
  String get mirrorBaseUrl;

  /// No description provided for @mirrorCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get mirrorCustom;

  /// No description provided for @mirrorDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get mirrorDelete;

  /// No description provided for @mirrorExtractFromPublish.
  ///
  /// In en, this message translates to:
  /// **'Extract mirrors from publish page'**
  String get mirrorExtractFromPublish;

  /// No description provided for @mirrorExtracting.
  ///
  /// In en, this message translates to:
  /// **'Extracting…'**
  String get mirrorExtracting;

  /// No description provided for @mirrorNoMirrorsExtracted.
  ///
  /// In en, this message translates to:
  /// **'No mirrors found'**
  String get mirrorNoMirrorsExtracted;

  /// No description provided for @mirrorImportSelected.
  ///
  /// In en, this message translates to:
  /// **'Import selected'**
  String get mirrorImportSelected;

  /// No description provided for @mirrorExtractFailed.
  ///
  /// In en, this message translates to:
  /// **'Extraction failed'**
  String get mirrorExtractFailed;

  /// No description provided for @mirrorAddInvalid.
  ///
  /// In en, this message translates to:
  /// **'Base URL must start with http:// or https://'**
  String get mirrorAddInvalid;

  /// No description provided for @importLibraryTab.
  ///
  /// In en, this message translates to:
  /// **'Library import'**
  String get importLibraryTab;

  /// No description provided for @libraryUrlHint.
  ///
  /// In en, this message translates to:
  /// **'Enter source library URL'**
  String get libraryUrlHint;

  /// No description provided for @fetchLibrary.
  ///
  /// In en, this message translates to:
  /// **'Fetch'**
  String get fetchLibrary;

  /// No description provided for @saveLibrary.
  ///
  /// In en, this message translates to:
  /// **'Save bookmark'**
  String get saveLibrary;

  /// No description provided for @libraryBookmarks.
  ///
  /// In en, this message translates to:
  /// **'Library'**
  String get libraryBookmarks;

  /// No description provided for @sourceNotLoggedIn.
  ///
  /// In en, this message translates to:
  /// **'Not logged in'**
  String get sourceNotLoggedIn;

  /// No description provided for @novelThemeFollowApp.
  ///
  /// In en, this message translates to:
  /// **'Follow app'**
  String get novelThemeFollowApp;

  /// No description provided for @novelThemeFollowDark.
  ///
  /// In en, this message translates to:
  /// **'Always night'**
  String get novelThemeFollowDark;

  /// No description provided for @novelThemeFollowLight.
  ///
  /// In en, this message translates to:
  /// **'Always day'**
  String get novelThemeFollowLight;

  /// No description provided for @libraryEmpty.
  ///
  /// In en, this message translates to:
  /// **'No saved library URLs'**
  String get libraryEmpty;

  /// No description provided for @addLibraryTitle.
  ///
  /// In en, this message translates to:
  /// **'Add source library'**
  String get addLibraryTitle;

  /// No description provided for @libraryNameHint.
  ///
  /// In en, this message translates to:
  /// **'Name (optional)'**
  String get libraryNameHint;

  /// No description provided for @subscribeLibrary.
  ///
  /// In en, this message translates to:
  /// **'Subscribe'**
  String get subscribeLibrary;

  /// No description provided for @fetchLibraryAndImport.
  ///
  /// In en, this message translates to:
  /// **'Update & Import'**
  String get fetchLibraryAndImport;

  /// No description provided for @openHomepage.
  ///
  /// In en, this message translates to:
  /// **'Open homepage'**
  String get openHomepage;

  /// No description provided for @unsubscribeLibrary.
  ///
  /// In en, this message translates to:
  /// **'Unsubscribe'**
  String get unsubscribeLibrary;

  /// No description provided for @unsubscribeLibraryConfirm.
  ///
  /// In en, this message translates to:
  /// **'Unsubscribe from \"{name}\"?'**
  String unsubscribeLibraryConfirm(String name);

  /// No description provided for @viewLibrarySources.
  ///
  /// In en, this message translates to:
  /// **'View sources'**
  String get viewLibrarySources;

  /// No description provided for @librarySubscribeFailed.
  ///
  /// In en, this message translates to:
  /// **'Subscribe failed. Please check the URL.'**
  String get librarySubscribeFailed;

  /// No description provided for @libraryImportResult.
  ///
  /// In en, this message translates to:
  /// **'Imported {success}/{total} sources ({failed} failed)'**
  String libraryImportResult(int success, int total, int failed);

  /// No description provided for @libraryVersion.
  ///
  /// In en, this message translates to:
  /// **'Lib v{lib} · Installed v{installed}'**
  String libraryVersion(int lib, int installed);

  /// No description provided for @libraryNotInstalled.
  ///
  /// In en, this message translates to:
  /// **'Not installed'**
  String get libraryNotInstalled;

  /// No description provided for @libraryUpdate.
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get libraryUpdate;

  /// No description provided for @libraryUpdateAll.
  ///
  /// In en, this message translates to:
  /// **'Update all'**
  String get libraryUpdateAll;

  /// No description provided for @libraryUpdateAvailable.
  ///
  /// In en, this message translates to:
  /// **'Update available'**
  String get libraryUpdateAvailable;

  /// No description provided for @libraryUpdating.
  ///
  /// In en, this message translates to:
  /// **'Updating…'**
  String get libraryUpdating;

  /// No description provided for @libraryUpdated.
  ///
  /// In en, this message translates to:
  /// **'Updated'**
  String get libraryUpdated;

  /// No description provided for @libraryUpdateFailed.
  ///
  /// In en, this message translates to:
  /// **'Update failed'**
  String get libraryUpdateFailed;

  /// No description provided for @libraryAllUpToDate.
  ///
  /// In en, this message translates to:
  /// **'All up to date'**
  String get libraryAllUpToDate;

  /// No description provided for @libraryAlreadyLatestCount.
  ///
  /// In en, this message translates to:
  /// **'{count} already latest'**
  String libraryAlreadyLatestCount(int count);

  /// No description provided for @sourcePin.
  ///
  /// In en, this message translates to:
  /// **'Pin'**
  String get sourcePin;

  /// No description provided for @sourceUnpin.
  ///
  /// In en, this message translates to:
  /// **'Unpin'**
  String get sourceUnpin;

  /// No description provided for @mirrorTestAll.
  ///
  /// In en, this message translates to:
  /// **'Test all'**
  String get mirrorTestAll;

  /// No description provided for @sourceTypeOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get sourceTypeOther;

  /// No description provided for @official.
  ///
  /// In en, this message translates to:
  /// **'Official'**
  String get official;

  /// No description provided for @loginStatusLoggedIn.
  ///
  /// In en, this message translates to:
  /// **'Logged in'**
  String get loginStatusLoggedIn;

  /// No description provided for @loginStatusLoggedOut.
  ///
  /// In en, this message translates to:
  /// **'Logged out'**
  String get loginStatusLoggedOut;

  /// No description provided for @cookieInputHint.
  ///
  /// In en, this message translates to:
  /// **'Paste the cookie string for this source'**
  String get cookieInputHint;

  /// No description provided for @incognitoMode.
  ///
  /// In en, this message translates to:
  /// **'Incognito mode'**
  String get incognitoMode;

  /// No description provided for @incognitoModeHint.
  ///
  /// In en, this message translates to:
  /// **'Don\'t record history or search for this source'**
  String get incognitoModeHint;

  /// No description provided for @incognitoModeOn.
  ///
  /// In en, this message translates to:
  /// **'Incognito on'**
  String get incognitoModeOn;

  /// No description provided for @incognitoOnToast.
  ///
  /// In en, this message translates to:
  /// **'Incognito on: history and search won\'t be recorded for this source'**
  String get incognitoOnToast;

  /// No description provided for @incognitoOffToast.
  ///
  /// In en, this message translates to:
  /// **'Incognito off: history recording resumed for this source'**
  String get incognitoOffToast;

  /// No description provided for @globalIncognito.
  ///
  /// In en, this message translates to:
  /// **'Global incognito'**
  String get globalIncognito;

  /// No description provided for @globalIncognitoHint.
  ///
  /// In en, this message translates to:
  /// **'When on, no source records history or search. Per-source toggle in source management still overrides individually.'**
  String get globalIncognitoHint;

  /// No description provided for @rememberPosition.
  ///
  /// In en, this message translates to:
  /// **'Remember playback/reading position'**
  String get rememberPosition;

  /// No description provided for @rememberPositionHint.
  ///
  /// In en, this message translates to:
  /// **'When on, reopening anime/comic/novel resumes from the last position; when off, always starts from the beginning'**
  String get rememberPositionHint;

  /// No description provided for @mirrorAutoAdded.
  ///
  /// In en, this message translates to:
  /// **'Auto-added {count} mirror(s) from the publish page'**
  String mirrorAutoAdded(Object count);

  /// No description provided for @sourceAnnouncementView.
  ///
  /// In en, this message translates to:
  /// **'View details'**
  String get sourceAnnouncementView;

  /// No description provided for @announcementDontShowAgain.
  ///
  /// In en, this message translates to:
  /// **'Don\'t show again'**
  String get announcementDontShowAgain;

  /// No description provided for @announcementSettingsDesc.
  ///
  /// In en, this message translates to:
  /// **'View past announcements and release notes'**
  String get announcementSettingsDesc;

  /// No description provided for @announcementsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No announcements yet'**
  String get announcementsEmpty;

  /// No description provided for @appAnnouncement.
  ///
  /// In en, this message translates to:
  /// **'App announcement'**
  String get appAnnouncement;

  /// No description provided for @appAnnouncementGotIt.
  ///
  /// In en, this message translates to:
  /// **'Got it'**
  String get appAnnouncementGotIt;

  /// No description provided for @watchedThreshold.
  ///
  /// In en, this message translates to:
  /// **'Watched threshold'**
  String get watchedThreshold;

  /// No description provided for @watchedThresholdHint.
  ///
  /// In en, this message translates to:
  /// **'Progress reaching this percentage is considered watched'**
  String get watchedThresholdHint;

  /// No description provided for @watchedThresholdUnit.
  ///
  /// In en, this message translates to:
  /// **'%'**
  String get watchedThresholdUnit;

  /// Tab label for source-site web favorites (bookshelf)
  ///
  /// In en, this message translates to:
  /// **'Web favorites'**
  String get onlineTabWebFavorite;

  /// Option to add to local device favorites
  ///
  /// In en, this message translates to:
  /// **'Local favorite'**
  String get favoriteLocal;

  /// Hint for local favorite option
  ///
  /// In en, this message translates to:
  /// **'Save to this device'**
  String get favoriteLocalHint;

  /// Option to add to source-site web favorites
  ///
  /// In en, this message translates to:
  /// **'Add to web favorites'**
  String get favoriteWeb;

  /// Hint for web favorite option
  ///
  /// In en, this message translates to:
  /// **'Save to your source-site account (needs network)'**
  String get favoriteWebHint;

  /// Note shown when web favorite requires login
  ///
  /// In en, this message translates to:
  /// **'Requires source-site login first'**
  String get favoriteWebRequiresLogin;

  /// Label for the default (un-categorized) web favorite folder
  ///
  /// In en, this message translates to:
  /// **'Default folder'**
  String get webFavoriteDefaultFolder;

  /// Toast shown after a gallery is added to web favorites
  ///
  /// In en, this message translates to:
  /// **'Added to web favorites'**
  String get webFavoriteAdded;

  /// Toast shown when adding to web favorites fails
  ///
  /// In en, this message translates to:
  /// **'Failed to add to web favorites'**
  String get webFavoriteAddFailed;

  /// Age rating badge: all ages
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get ageRatingGeneral;

  /// Age rating badge: teen
  ///
  /// In en, this message translates to:
  /// **'Teen (16+)'**
  String get ageRatingTeen;

  /// Age rating badge: mature/restricted
  ///
  /// In en, this message translates to:
  /// **'Mature (18+)'**
  String get ageRatingMature;

  /// Label for selecting source age rating
  ///
  /// In en, this message translates to:
  /// **'Age rating'**
  String get ageRatingLabel;

  /// Shown when user tries to import a 18+ source while age restriction is on
  ///
  /// In en, this message translates to:
  /// **'Age restriction is on; 18+ sources cannot be imported (turn it off in settings)'**
  String get ageRestrictionImportMatureBlocked;

  /// Banner in source management when age restriction hides mature sources
  ///
  /// In en, this message translates to:
  /// **'Hid {count} 18+ source(s) (visible after turning off age restriction)'**
  String ageBlockedManageHint(int count);

  /// Banner in import preview when age restriction hides mature sources
  ///
  /// In en, this message translates to:
  /// **'Due to age restriction, {count} 18+ source(s) were not imported'**
  String ageBlockedImportHint(int count);

  /// Settings toggle to hide mature (18+) sources
  ///
  /// In en, this message translates to:
  /// **'Age restriction'**
  String get ageRestriction;

  /// Hint for age restriction toggle
  ///
  /// In en, this message translates to:
  /// **'When on, hides sources rated Mature (18+)'**
  String get ageRestrictionHint;

  /// Title of forced-reading disclaimer when disabling age restriction
  ///
  /// In en, this message translates to:
  /// **'Disclaimer'**
  String get ageRestrictionDisclaimerTitle;

  /// Body text of the forced-reading age restriction disclaimer
  ///
  /// In en, this message translates to:
  /// **'By disabling age restriction you acknowledge that this app may display content rated Mature (18+), including explicit adult material. You confirm that you are of legal age in your jurisdiction to view such content, and you accept full responsibility for any content accessed. The developer is not responsible for any content provided by third-party sources. Please comply with local laws and regulations.'**
  String get ageRestrictionDisclaimerBody;

  /// Confirm button of the forced-reading disclaimer
  ///
  /// In en, this message translates to:
  /// **'I have read and understand, continue'**
  String get ageRestrictionDisclaimerConfirm;

  /// Hint shown when user hasn't scrolled to bottom of disclaimer
  ///
  /// In en, this message translates to:
  /// **'Scroll to the bottom to read the full disclaimer before confirming'**
  String get ageRestrictionDisclaimerScrollHint;

  /// Countdown hint while waiting for the forced-reading timer
  ///
  /// In en, this message translates to:
  /// **'Wait {seconds}s to confirm'**
  String ageRestrictionDisclaimerCounting(Object seconds);

  /// Confirm button label while counting down
  ///
  /// In en, this message translates to:
  /// **'Confirm (wait {seconds}s)'**
  String ageRestrictionDisclaimerWait(Object seconds);

  /// Comic reader settings - Page Turning & Tap section title
  ///
  /// In en, this message translates to:
  /// **'Page Turning & Tap'**
  String get comicSectionTapPage;

  /// Comic reader settings - Visual & Filters section title
  ///
  /// In en, this message translates to:
  /// **'Visual & Filters'**
  String get comicSectionVisualFilter;

  /// Comic reader settings - Progress & Display section title
  ///
  /// In en, this message translates to:
  /// **'Progress & Display'**
  String get comicSectionProgress;

  /// Comic reader settings - Flash Effects section title
  ///
  /// In en, this message translates to:
  /// **'Flash Effects'**
  String get comicSectionFlash;

  /// Comic reader settings - Mouse Wheel section title
  ///
  /// In en, this message translates to:
  /// **'Mouse Wheel'**
  String get comicSectionMouseWheel;

  /// Comic reader settings - Auto download & chapter skip section title
  ///
  /// In en, this message translates to:
  /// **'Auto (download / chapter skip)'**
  String get comicReaderAutoSection;

  /// Comic reader settings - Clock/battery overlay section title
  ///
  /// In en, this message translates to:
  /// **'Overlay (clock / battery)'**
  String get comicReaderOverlaySection;

  /// Comic reader settings - Multi-image & spacing section title
  ///
  /// In en, this message translates to:
  /// **'Multi-image / spacing'**
  String get comicReaderMultiImageSection;

  /// Statistics page title
  ///
  /// In en, this message translates to:
  /// **'Statistics'**
  String get statsOverviewTitle;

  /// Statistics page search field hint
  ///
  /// In en, this message translates to:
  /// **'Search records'**
  String get statsSearchHint;

  /// Heatmap sheet title
  ///
  /// In en, this message translates to:
  /// **'Heatmap'**
  String get statsHeatmap;

  /// No description provided for @statsSectionTrend.
  ///
  /// In en, this message translates to:
  /// **'Trend'**
  String get statsSectionTrend;

  /// No description provided for @statsTrend7d.
  ///
  /// In en, this message translates to:
  /// **'7 days'**
  String get statsTrend7d;

  /// No description provided for @statsTrend30d.
  ///
  /// In en, this message translates to:
  /// **'30 days'**
  String get statsTrend30d;

  /// Summary metric: total duration
  ///
  /// In en, this message translates to:
  /// **'Total duration'**
  String get statsTotalDuration;

  /// Summary metric: number of works
  ///
  /// In en, this message translates to:
  /// **'Works'**
  String get statsWorkCount;

  /// Summary metric: session count
  ///
  /// In en, this message translates to:
  /// **'Sessions'**
  String get statsSessionCount;

  /// List item subtitle prefix: last read time
  ///
  /// In en, this message translates to:
  /// **'Last read'**
  String get statsLastRead;

  /// Empty state text on statistics page
  ///
  /// In en, this message translates to:
  /// **'No records yet, go read something'**
  String get statsNoRecords;

  /// Duration format: seconds only
  ///
  /// In en, this message translates to:
  /// **'{s} s'**
  String statsDurSec(int s);

  /// Duration format: whole hours
  ///
  /// In en, this message translates to:
  /// **'{h} hours'**
  String statsDurHours(int h);

  /// Duration format: hours + minutes
  ///
  /// In en, this message translates to:
  /// **'{h} h {m} m'**
  String statsDurHm(int h, int m);

  /// Duration format: minutes + seconds
  ///
  /// In en, this message translates to:
  /// **'{m} m {s} s'**
  String statsDurMs(int m, int s);

  /// Dialog title for clearing a single work's stats
  ///
  /// In en, this message translates to:
  /// **'Clear stats'**
  String get statsClearTitle;

  /// Confirmation text for clearing a single work's stats
  ///
  /// In en, this message translates to:
  /// **'Clear all stats for \"{name}\"?'**
  String statsClearBody(String name);

  /// Clear confirmation button
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get statsClearConfirm;

  /// Heatmap month navigation: previous
  ///
  /// In en, this message translates to:
  /// **'Previous month'**
  String get statsPrevMonth;

  /// Heatmap month navigation: next
  ///
  /// In en, this message translates to:
  /// **'Next month'**
  String get statsNextMonth;

  /// Heatmap current month title
  ///
  /// In en, this message translates to:
  /// **'{y}/{m}'**
  String statsHeatmapMonthYear(String y, String m);

  /// Heatmap type switch: all
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get statsAll;

  /// Heatmap legend: less
  ///
  /// In en, this message translates to:
  /// **'Less'**
  String get statsHeatmapLess;

  /// Heatmap legend: more
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get statsHeatmapMore;

  /// Heatmap footer total label
  ///
  /// In en, this message translates to:
  /// **'This month'**
  String get statsHeatmapTotal;

  /// Stats activity section: works read within 7 days
  ///
  /// In en, this message translates to:
  /// **'Active (7d)'**
  String get stats7dActive;

  /// Stats activity section: works read within 30 days
  ///
  /// In en, this message translates to:
  /// **'Active (30d)'**
  String get stats30dActive;

  /// Stats activity section: total active days for current tab
  ///
  /// In en, this message translates to:
  /// **'Active days'**
  String get statsActiveDays;

  /// Stats pace section: total duration / session count
  ///
  /// In en, this message translates to:
  /// **'Avg per session'**
  String get statsAvgSession;

  /// Stats pace section: longest single-day duration
  ///
  /// In en, this message translates to:
  /// **'Best day'**
  String get statsMaxDaily;

  /// Stats pace section: consecutive active days from today
  ///
  /// In en, this message translates to:
  /// **'Current streak'**
  String get statsStreak;

  /// Stats section title: total/works/sessions
  ///
  /// In en, this message translates to:
  /// **'Overview'**
  String get statsSectionOverview;

  /// Stats section title: 7d/30d/active days
  ///
  /// In en, this message translates to:
  /// **'Activity'**
  String get statsSectionActivity;

  /// Stats section title: avg/best/streak
  ///
  /// In en, this message translates to:
  /// **'Pace'**
  String get statsSectionPace;

  /// Heatmap top summary: active days this month
  ///
  /// In en, this message translates to:
  /// **'Active days'**
  String get heatmapActiveDays;

  /// Heatmap top summary: longest day this month
  ///
  /// In en, this message translates to:
  /// **'Best day'**
  String get heatmapMaxDaily;

  /// Heatmap top summary: current consecutive active days
  ///
  /// In en, this message translates to:
  /// **'Current streak'**
  String get heatmapStreak;

  /// Download settings: auto-delete downloaded files after finishing
  ///
  /// In en, this message translates to:
  /// **'Auto-delete after finishing'**
  String get downloadAutoDelete;

  /// Auto-delete subtitle hint
  ///
  /// In en, this message translates to:
  /// **'Remove downloaded files once you finish this item'**
  String get downloadAutoDeleteHint;

  /// Auto-delete excluded categories entry
  ///
  /// In en, this message translates to:
  /// **'Excluded categories'**
  String get downloadAutoDeleteExclude;

  /// Subtitle when no category is excluded
  ///
  /// In en, this message translates to:
  /// **'Auto-delete all categories'**
  String get downloadAutoDeleteExcludeNone;

  /// Auto pre-download upcoming content while watching/reading
  ///
  /// In en, this message translates to:
  /// **'Pre-download next content'**
  String get downloadPreDownload;

  /// Pre-download count is 0 (disabled)
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get downloadPreDownloadOff;

  /// Pre-download content count unit
  ///
  /// In en, this message translates to:
  /// **'{count} items'**
  String downloadEpisodesCount(int count);

  /// Settings categories management entry title
  ///
  /// In en, this message translates to:
  /// **'Categories'**
  String get categoriesManageTitle;

  /// Settings categories management entry subtitle
  ///
  /// In en, this message translates to:
  /// **'Manage collection categories for anime, comics and novels'**
  String get categoriesManageDesc;

  /// Settings home privacy group title
  ///
  /// In en, this message translates to:
  /// **'Privacy'**
  String get settingsGroupPrivacy;

  /// No description provided for @onboardingWelcomeTitle.
  ///
  /// In en, this message translates to:
  /// **'Welcome to NexHub'**
  String get onboardingWelcomeTitle;

  /// No description provided for @onboardingWelcomeBody.
  ///
  /// In en, this message translates to:
  /// **'An all-in-one media client: anime, manga, novel, and video. The app ships no built-in sites; content comes from the sources you import.'**
  String get onboardingWelcomeBody;

  /// No description provided for @onboardingSourcesTitle.
  ///
  /// In en, this message translates to:
  /// **'Add your sources'**
  String get onboardingSourcesTitle;

  /// No description provided for @onboardingSourcesBody.
  ///
  /// In en, this message translates to:
  /// **'Go to Source Management and import community-maintained sources to start browsing and searching.'**
  String get onboardingSourcesBody;

  /// No description provided for @onboardingBangumiTitle.
  ///
  /// In en, this message translates to:
  /// **'Connect Bangumi'**
  String get onboardingBangumiTitle;

  /// No description provided for @onboardingBangumiBody.
  ///
  /// In en, this message translates to:
  /// **'Sign in to sync your \'watching / want-to-watch\' to Bangumi and view ratings and comments on detail pages.'**
  String get onboardingBangumiBody;

  /// No description provided for @onboardingBangumiLogin.
  ///
  /// In en, this message translates to:
  /// **'Sign in now'**
  String get onboardingBangumiLogin;

  /// No description provided for @onboardingDandanplayTitle.
  ///
  /// In en, this message translates to:
  /// **'Connect DanDanPlay'**
  String get onboardingDandanplayTitle;

  /// No description provided for @onboardingDandanplayBody.
  ///
  /// In en, this message translates to:
  /// **'Sign in to post and sync danmaku to DanDanPlay and share comment libraries across devices.'**
  String get onboardingDandanplayBody;

  /// No description provided for @onboardingDandanplayLogin.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get onboardingDandanplayLogin;

  /// No description provided for @onboardingPrivacyTitle.
  ///
  /// In en, this message translates to:
  /// **'Privacy & compliance'**
  String get onboardingPrivacyTitle;

  /// No description provided for @onboardingPrivacyBody.
  ///
  /// In en, this message translates to:
  /// **'Your sources, credentials, and browsing history are stored only on this device and never uploaded. The app hardcodes no secrets.'**
  String get onboardingPrivacyBody;

  /// No description provided for @onboardingSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get onboardingSkip;

  /// No description provided for @onboardingNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get onboardingNext;

  /// No description provided for @onboardingGetStarted.
  ///
  /// In en, this message translates to:
  /// **'Get started'**
  String get onboardingGetStarted;

  /// No description provided for @onboardingSettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Basic settings'**
  String get onboardingSettingsTitle;

  /// No description provided for @onboardingSettingsBody.
  ///
  /// In en, this message translates to:
  /// **'Choose your theme and interface language. You can change these later in Settings.'**
  String get onboardingSettingsBody;

  /// No description provided for @onboardingThemeLabel.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get onboardingThemeLabel;

  /// No description provided for @onboardingLanguageLabel.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get onboardingLanguageLabel;

  /// No description provided for @onboardingPermissionTitle.
  ///
  /// In en, this message translates to:
  /// **'Grant permissions'**
  String get onboardingPermissionTitle;

  /// No description provided for @onboardingPermissionBody.
  ///
  /// In en, this message translates to:
  /// **'To import local files, save downloads and screenshots, we recommend granting these permissions. You can also do it later in Settings.'**
  String get onboardingPermissionBody;

  /// No description provided for @onboardingGrantPermission.
  ///
  /// In en, this message translates to:
  /// **'Grant permissions'**
  String get onboardingGrantPermission;

  /// No description provided for @onboardingPermissionGranted.
  ///
  /// In en, this message translates to:
  /// **'Required permissions granted'**
  String get onboardingPermissionGranted;

  /// No description provided for @onboardingPermissionNotNeeded.
  ///
  /// In en, this message translates to:
  /// **'No runtime permission needed on this platform'**
  String get onboardingPermissionNotNeeded;

  /// No description provided for @onboardingPermissionStorage.
  ///
  /// In en, this message translates to:
  /// **'Storage'**
  String get onboardingPermissionStorage;

  /// No description provided for @onboardingPermissionStorageDesc.
  ///
  /// In en, this message translates to:
  /// **'Access local files (legacy Android versions)'**
  String get onboardingPermissionStorageDesc;

  /// No description provided for @onboardingPermissionPhotos.
  ///
  /// In en, this message translates to:
  /// **'Photos'**
  String get onboardingPermissionPhotos;

  /// No description provided for @onboardingPermissionPhotosDesc.
  ///
  /// In en, this message translates to:
  /// **'Read images from your gallery'**
  String get onboardingPermissionPhotosDesc;

  /// No description provided for @onboardingPermissionVideos.
  ///
  /// In en, this message translates to:
  /// **'Videos'**
  String get onboardingPermissionVideos;

  /// No description provided for @onboardingPermissionVideosDesc.
  ///
  /// In en, this message translates to:
  /// **'Read videos from your gallery'**
  String get onboardingPermissionVideosDesc;

  /// No description provided for @onboardingPermissionAudio.
  ///
  /// In en, this message translates to:
  /// **'Audio'**
  String get onboardingPermissionAudio;

  /// No description provided for @onboardingPermissionAudioDesc.
  ///
  /// In en, this message translates to:
  /// **'Read local audio files'**
  String get onboardingPermissionAudioDesc;

  /// No description provided for @onboardingPermissionItemGranted.
  ///
  /// In en, this message translates to:
  /// **'Granted'**
  String get onboardingPermissionItemGranted;

  /// No description provided for @onboardingPermissionItemDenied.
  ///
  /// In en, this message translates to:
  /// **'Not granted'**
  String get onboardingPermissionItemDenied;

  /// No description provided for @onboardingDownloadTitle.
  ///
  /// In en, this message translates to:
  /// **'Download location'**
  String get onboardingDownloadTitle;

  /// No description provided for @onboardingDownloadBody.
  ///
  /// In en, this message translates to:
  /// **'Choose where downloaded anime / manga / novel / video content is saved. You can change it later under Settings → Downloads.'**
  String get onboardingDownloadBody;

  /// No description provided for @onboardingChooseDownloadPath.
  ///
  /// In en, this message translates to:
  /// **'Choose download folder'**
  String get onboardingChooseDownloadPath;

  /// No description provided for @onboardingThemeColorLabel.
  ///
  /// In en, this message translates to:
  /// **'Accent color'**
  String get onboardingThemeColorLabel;

  /// No description provided for @onboardingThemePreviewLabel.
  ///
  /// In en, this message translates to:
  /// **'Style preview'**
  String get onboardingThemePreviewLabel;

  /// Privacy settings page title
  ///
  /// In en, this message translates to:
  /// **'Privacy Settings'**
  String get privacySettingsTitle;

  /// Settings home privacy entry subtitle
  ///
  /// In en, this message translates to:
  /// **'Notification masking and incognito options'**
  String get privacySettingsDesc;

  /// Privacy page notifications group title
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get privacyNotificationsGroup;

  /// Privacy page hide notification content switch
  ///
  /// In en, this message translates to:
  /// **'Hide Notification Content'**
  String get hideNotificationContent;

  /// Hide notification content switch description
  ///
  /// In en, this message translates to:
  /// **'When on, notifications only show \"New content\" without specific counts, preventing shoulder surfing'**
  String get hideNotificationContentHint;

  /// Privacy page network group title
  ///
  /// In en, this message translates to:
  /// **'Network'**
  String get privacyNetworkGroup;

  /// Privacy page bottom hint
  ///
  /// In en, this message translates to:
  /// **'Global incognito randomizes request delays and rotates browser fingerprints to reduce the chance of being detected as a script'**
  String get privacyPageHint;

  /// Settings home advanced group title
  ///
  /// In en, this message translates to:
  /// **'Advanced & Cache'**
  String get settingsGroupAdvanced;

  /// Advanced settings page title
  ///
  /// In en, this message translates to:
  /// **'Advanced Settings'**
  String get advancedSettingsTitle;

  /// Settings home advanced entry subtitle
  ///
  /// In en, this message translates to:
  /// **'Crash logs, detailed logs, data cleanup and request fingerprint'**
  String get advancedSettingsDesc;

  /// Advanced page logs group title
  ///
  /// In en, this message translates to:
  /// **'Logs'**
  String get advancedLogGroup;

  /// Advanced page detailed logging switch
  ///
  /// In en, this message translates to:
  /// **'Detailed Logging'**
  String get detailedLogging;

  /// Detailed logging switch description
  ///
  /// In en, this message translates to:
  /// **'Log each network request and response to help debug scraping issues'**
  String get detailedLoggingHint;

  /// Advanced page crash log entry title
  ///
  /// In en, this message translates to:
  /// **'Crash Log'**
  String get crashLog;

  /// Crash log entry subtitle
  ///
  /// In en, this message translates to:
  /// **'View runtime errors and uncaught exceptions'**
  String get crashLogDesc;

  /// Crash log page title
  ///
  /// In en, this message translates to:
  /// **'Crash Log'**
  String get crashLogTitle;

  /// Crash log page empty state
  ///
  /// In en, this message translates to:
  /// **'No crash records yet. If you hit a problem, reproduce it and check back'**
  String get crashLogEmpty;

  /// Crash log copied toast
  ///
  /// In en, this message translates to:
  /// **'Copied to clipboard'**
  String get crashLogCopied;

  /// Crash log clear button
  ///
  /// In en, this message translates to:
  /// **'Clear Crash Log'**
  String get crashLogClear;

  /// Crash log cleared toast
  ///
  /// In en, this message translates to:
  /// **'Cleared'**
  String get crashLogCleared;

  /// Crash log copy all button
  ///
  /// In en, this message translates to:
  /// **'Copy All'**
  String get crashLogCopyAll;

  /// Runtime log screen title
  ///
  /// In en, this message translates to:
  /// **'Runtime Log'**
  String get runtimeLog;

  /// Runtime log empty state / hint
  ///
  /// In en, this message translates to:
  /// **'In-memory log of this session\'s network requests, responses and errors (detailed logging toggle controls verbosity)'**
  String get runtimeLogDesc;

  /// Runtime log empty state
  ///
  /// In en, this message translates to:
  /// **'No logs yet. Enable \"Detailed Logging\", reproduce the issue, then come back.'**
  String get logEmpty;

  /// Runtime log copy done toast
  ///
  /// In en, this message translates to:
  /// **'Log copied to clipboard'**
  String get logCopied;

  /// Advanced page data cleanup group title
  ///
  /// In en, this message translates to:
  /// **'Data Cleanup'**
  String get advancedCleanGroup;

  /// Advanced page clear cookies entry
  ///
  /// In en, this message translates to:
  /// **'Clear Cookies'**
  String get clearCookies;

  /// Clear cookies subtitle
  ///
  /// In en, this message translates to:
  /// **'Clear session cookies of crawler and WebView'**
  String get clearCookiesDesc;

  /// Cookies cleared toast
  ///
  /// In en, this message translates to:
  /// **'Cookies cleared'**
  String get cookiesCleared;

  /// No description provided for @cloudSyncAutoUploadNovelExports.
  ///
  /// In en, this message translates to:
  /// **'Auto-upload novel exports'**
  String get cloudSyncAutoUploadNovelExports;

  /// No description provided for @cloudSyncAutoUploadNovelExportsDesc.
  ///
  /// In en, this message translates to:
  /// **'Upload exported EPUB files to WebDAV nexhub/exports after download completes'**
  String get cloudSyncAutoUploadNovelExportsDesc;

  /// No description provided for @uploadToWebdav.
  ///
  /// In en, this message translates to:
  /// **'Upload exports to WebDAV'**
  String get uploadToWebdav;

  /// No description provided for @uploadToWebdavDone.
  ///
  /// In en, this message translates to:
  /// **'export file(s) uploaded to WebDAV'**
  String get uploadToWebdavDone;

  /// No description provided for @uploadToWebdavNoFiles.
  ///
  /// In en, this message translates to:
  /// **'No downloaded EPUB exports for this title yet'**
  String get uploadToWebdavNoFiles;

  /// No description provided for @uploadToWebdavFailed.
  ///
  /// In en, this message translates to:
  /// **'Export upload failed, check WebDAV config'**
  String get uploadToWebdavFailed;

  /// No description provided for @novelExportTemplate.
  ///
  /// In en, this message translates to:
  /// **'Export template (EPUB)'**
  String get novelExportTemplate;

  /// No description provided for @novelExportTemplateDesc.
  ///
  /// In en, this message translates to:
  /// **'Custom stylesheet, cover page and intro page embedded in the EPUB export'**
  String get novelExportTemplateDesc;

  /// No description provided for @novelExportCss.
  ///
  /// In en, this message translates to:
  /// **'Custom CSS (style.css)'**
  String get novelExportCss;

  /// No description provided for @novelExportCssHint.
  ///
  /// In en, this message translates to:
  /// **'Plain CSS rules applied to every chapter (font family, line height…)'**
  String get novelExportCssHint;

  /// No description provided for @novelExportIntro.
  ///
  /// In en, this message translates to:
  /// **'Book intro page'**
  String get novelExportIntro;

  /// No description provided for @novelExportIntroHint.
  ///
  /// In en, this message translates to:
  /// **'Blank line separates paragraphs; title and author placeholders are auto-substituted'**
  String get novelExportIntroHint;

  /// No description provided for @novelExportIncludeCover.
  ///
  /// In en, this message translates to:
  /// **'Embed network cover as first cover page'**
  String get novelExportIncludeCover;

  /// No description provided for @novelExportIncludeIntro.
  ///
  /// In en, this message translates to:
  /// **'Append intro page after cover'**
  String get novelExportIncludeIntro;

  /// No description provided for @novelExportSaved.
  ///
  /// In en, this message translates to:
  /// **'Export template saved'**
  String get novelExportSaved;

  /// No description provided for @advancedImageCache.
  ///
  /// In en, this message translates to:
  /// **'Image cache'**
  String get advancedImageCache;

  /// No description provided for @advancedImageCacheDesc.
  ///
  /// In en, this message translates to:
  /// **'Disk usage of downloaded images; tap to clear'**
  String get advancedImageCacheDesc;

  /// No description provided for @imageCacheCleared.
  ///
  /// In en, this message translates to:
  /// **'Image cache cleared'**
  String get imageCacheCleared;

  /// No description provided for @imageCacheClearConfirm.
  ///
  /// In en, this message translates to:
  /// **'Clear image cache?'**
  String get imageCacheClearConfirm;

  /// No description provided for @imageCacheCalculating.
  ///
  /// In en, this message translates to:
  /// **'Calculating…'**
  String get imageCacheCalculating;

  /// No description provided for @cacheManagerTitle.
  ///
  /// In en, this message translates to:
  /// **'Cache manager'**
  String get cacheManagerTitle;

  /// No description provided for @cacheManagerTotal.
  ///
  /// In en, this message translates to:
  /// **'Total cache usage'**
  String get cacheManagerTotal;

  /// Cache total usage description ({size} is formatted usage)
  ///
  /// In en, this message translates to:
  /// **'{size} in total; clear per category below'**
  String cacheManagerTotalDesc(String size);

  /// No description provided for @cacheManagerHint.
  ///
  /// In en, this message translates to:
  /// **'Clearing the cache never removes favorites, downloads or sources; images saved in the image-favorites gallery live in the favorites folder and are unaffected.'**
  String get cacheManagerHint;

  /// No description provided for @cacheCategoryGroup.
  ///
  /// In en, this message translates to:
  /// **'Cache categories'**
  String get cacheCategoryGroup;

  /// No description provided for @cacheCatImages.
  ///
  /// In en, this message translates to:
  /// **'Image cache'**
  String get cacheCatImages;

  /// No description provided for @cacheCatImagesDesc.
  ///
  /// In en, this message translates to:
  /// **'Covers, comic pages and RSS inline images'**
  String get cacheCatImagesDesc;

  /// No description provided for @cacheCatDanmaku.
  ///
  /// In en, this message translates to:
  /// **'Danmaku cache'**
  String get cacheCatDanmaku;

  /// No description provided for @cacheCatDanmakuDesc.
  ///
  /// In en, this message translates to:
  /// **'Cached video danmaku (expired entries auto-evicted)'**
  String get cacheCatDanmakuDesc;

  /// No description provided for @cacheCatTranslations.
  ///
  /// In en, this message translates to:
  /// **'Translation cache'**
  String get cacheCatTranslations;

  /// No description provided for @cacheCatTranslationsDesc.
  ///
  /// In en, this message translates to:
  /// **'AI translations for novels / comics / subtitles'**
  String get cacheCatTranslationsDesc;

  /// No description provided for @cacheCatWebview.
  ///
  /// In en, this message translates to:
  /// **'WebView data'**
  String get cacheCatWebview;

  /// No description provided for @cacheCatWebviewDesc.
  ///
  /// In en, this message translates to:
  /// **'Embedded browser cache and local storage'**
  String get cacheCatWebviewDesc;

  /// No description provided for @cacheCatTemp.
  ///
  /// In en, this message translates to:
  /// **'Temporary files'**
  String get cacheCatTemp;

  /// No description provided for @cacheCatTempDesc.
  ///
  /// In en, this message translates to:
  /// **'Derived files such as PDF renders and archive extraction'**
  String get cacheCatTempDesc;

  /// No description provided for @cacheCatUpdates.
  ///
  /// In en, this message translates to:
  /// **'Update package leftovers'**
  String get cacheCatUpdates;

  /// No description provided for @cacheCatUpdatesDesc.
  ///
  /// In en, this message translates to:
  /// **'Downloaded installers and stale version folders'**
  String get cacheCatUpdatesDesc;

  /// No description provided for @cacheSizeUnknown.
  ///
  /// In en, this message translates to:
  /// **'Not measurable'**
  String get cacheSizeUnknown;

  /// No description provided for @cacheClearCategory.
  ///
  /// In en, this message translates to:
  /// **'Clear this category'**
  String get cacheClearCategory;

  /// Single category clear confirmation title
  ///
  /// In en, this message translates to:
  /// **'Clear \"{name}\"?'**
  String cacheClearCategoryConfirm(String name);

  /// No description provided for @cacheClearAll.
  ///
  /// In en, this message translates to:
  /// **'Clear all'**
  String get cacheClearAll;

  /// No description provided for @cacheClearAllConfirm.
  ///
  /// In en, this message translates to:
  /// **'Clear every cache category?'**
  String get cacheClearAllConfirm;

  /// No description provided for @cacheCategoryCleared.
  ///
  /// In en, this message translates to:
  /// **'Cleared'**
  String get cacheCategoryCleared;

  /// No description provided for @cacheClearFailed.
  ///
  /// In en, this message translates to:
  /// **'Cleanup failed, please retry later'**
  String get cacheClearFailed;

  /// No description provided for @cacheAutoCleanGroup.
  ///
  /// In en, this message translates to:
  /// **'Automatic cache cleanup'**
  String get cacheAutoCleanGroup;

  /// No description provided for @cacheAutoCleanGroupDesc.
  ///
  /// In en, this message translates to:
  /// **'Runs in the background on launch using age + size limits'**
  String get cacheAutoCleanGroupDesc;

  /// No description provided for @cacheAutoClean.
  ///
  /// In en, this message translates to:
  /// **'Auto-clean cache'**
  String get cacheAutoClean;

  /// No description provided for @cacheAutoCleanDesc.
  ///
  /// In en, this message translates to:
  /// **'When off, caches are only cleared manually here'**
  String get cacheAutoCleanDesc;

  /// No description provided for @cacheMaxAge.
  ///
  /// In en, this message translates to:
  /// **'Keep cache for'**
  String get cacheMaxAge;

  /// Cache max age display value
  ///
  /// In en, this message translates to:
  /// **'{days} days'**
  String cacheMaxAgeValue(int days);

  /// No description provided for @cacheMaxTotal.
  ///
  /// In en, this message translates to:
  /// **'Total cache size limit'**
  String get cacheMaxTotal;

  /// No description provided for @cacheAutoCleanNow.
  ///
  /// In en, this message translates to:
  /// **'Run cleanup policy'**
  String get cacheAutoCleanNow;

  /// Auto cleanup finished toast
  ///
  /// In en, this message translates to:
  /// **'Freed {size}'**
  String cacheAutoCleanDone(String size);

  /// No description provided for @cacheAutoCleanNothing.
  ///
  /// In en, this message translates to:
  /// **'Nothing to clean up'**
  String get cacheAutoCleanNothing;

  /// No description provided for @readerUpscale.
  ///
  /// In en, this message translates to:
  /// **'Image super-resolution'**
  String get readerUpscale;

  /// No description provided for @readerUpscaleMode.
  ///
  /// In en, this message translates to:
  /// **'Super-resolution mode'**
  String get readerUpscaleMode;

  /// No description provided for @readerUpscaleOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get readerUpscaleOff;

  /// No description provided for @readerUpscaleResample.
  ///
  /// In en, this message translates to:
  /// **'High-quality resample'**
  String get readerUpscaleResample;

  /// No description provided for @readerUpscaleSharpen.
  ///
  /// In en, this message translates to:
  /// **'Super-resolution (sharpen)'**
  String get readerUpscaleSharpen;

  /// No description provided for @readerUpscaleDesc.
  ///
  /// In en, this message translates to:
  /// **'Paged (single-page) mode only: the GPU resamples and sharpens lines when an image is upscaled (webtoon strips and oversized single images keep plain rendering); turn off on low-end devices'**
  String get readerUpscaleDesc;

  /// Dangerous action confirmation hint
  ///
  /// In en, this message translates to:
  /// **'This action cannot be undone. Continue?'**
  String get confirmActionHint;

  /// Advanced page request fingerprint group title
  ///
  /// In en, this message translates to:
  /// **'Request Fingerprint'**
  String get advancedRequestGroup;

  /// Advanced page default UA setting
  ///
  /// In en, this message translates to:
  /// **'Default User-Agent'**
  String get defaultUserAgent;

  /// UA auto option
  ///
  /// In en, this message translates to:
  /// **'Auto (built-in fingerprint rotation)'**
  String get userAgentAuto;

  /// UA auto option description
  ///
  /// In en, this message translates to:
  /// **'Different sites automatically use different browser fingerprints'**
  String get userAgentAutoHint;

  /// UA custom input label
  ///
  /// In en, this message translates to:
  /// **'Custom User-Agent'**
  String get userAgentCustom;

  /// Advanced page bottom hint
  ///
  /// In en, this message translates to:
  /// **'The default UA takes effect immediately; some sites may be more sensitive to a fixed fingerprint'**
  String get advancedPageHint;

  /// Generic refresh button
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// Generic text shown when notification content is hidden
  ///
  /// In en, this message translates to:
  /// **'New content available'**
  String get rssNewContentGeneric;

  /// No description provided for @readerClockPosTopLeft.
  ///
  /// In en, this message translates to:
  /// **'Top Left'**
  String get readerClockPosTopLeft;

  /// No description provided for @readerClockPosTopRight.
  ///
  /// In en, this message translates to:
  /// **'Top Right'**
  String get readerClockPosTopRight;

  /// No description provided for @readerClockPosBottomLeft.
  ///
  /// In en, this message translates to:
  /// **'Bottom Left'**
  String get readerClockPosBottomLeft;

  /// No description provided for @readerClockPosBottomRight.
  ///
  /// In en, this message translates to:
  /// **'Bottom Right'**
  String get readerClockPosBottomRight;

  /// No description provided for @cacheBook.
  ///
  /// In en, this message translates to:
  /// **'Cache'**
  String get cacheBook;

  /// No description provided for @cacheChaptersTitle.
  ///
  /// In en, this message translates to:
  /// **'Select chapters to cache'**
  String get cacheChaptersTitle;

  /// No description provided for @cacheSelected.
  ///
  /// In en, this message translates to:
  /// **'Cache selected'**
  String get cacheSelected;

  /// Selected chapter count in cache dialog
  ///
  /// In en, this message translates to:
  /// **'Selected {count} chapters'**
  String cacheSelectedCount(int count);

  /// No description provided for @searchPause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get searchPause;

  /// No description provided for @searchResume.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get searchResume;

  /// No description provided for @searchScope.
  ///
  /// In en, this message translates to:
  /// **'Scope'**
  String get searchScope;

  /// No description provided for @searchScopeAll.
  ///
  /// In en, this message translates to:
  /// **'Whole book'**
  String get searchScopeAll;

  /// No description provided for @searchScopeFromHere.
  ///
  /// In en, this message translates to:
  /// **'From current'**
  String get searchScopeFromHere;

  /// No description provided for @searchScopeRange.
  ///
  /// In en, this message translates to:
  /// **'Range'**
  String get searchScopeRange;

  /// No description provided for @searchUseRegex.
  ///
  /// In en, this message translates to:
  /// **'Regex'**
  String get searchUseRegex;

  /// No description provided for @searchRegexInvalid.
  ///
  /// In en, this message translates to:
  /// **'Invalid regex'**
  String get searchRegexInvalid;

  /// No description provided for @searchRangeStart.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get searchRangeStart;

  /// No description provided for @searchRangeEnd.
  ///
  /// In en, this message translates to:
  /// **'End'**
  String get searchRangeEnd;

  /// No description provided for @overviewChapterSummary.
  ///
  /// In en, this message translates to:
  /// **'Chapter overview'**
  String get overviewChapterSummary;

  /// No description provided for @overviewMode.
  ///
  /// In en, this message translates to:
  /// **'Summary mode'**
  String get overviewMode;

  /// No description provided for @overviewModeLocal.
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get overviewModeLocal;

  /// No description provided for @overviewModeApi.
  ///
  /// In en, this message translates to:
  /// **'Cloud AI'**
  String get overviewModeApi;

  /// No description provided for @overviewGenerate.
  ///
  /// In en, this message translates to:
  /// **'Generate'**
  String get overviewGenerate;

  /// No description provided for @overviewGenerating.
  ///
  /// In en, this message translates to:
  /// **'Generating…'**
  String get overviewGenerating;

  /// No description provided for @overviewEmpty.
  ///
  /// In en, this message translates to:
  /// **'No content to summarize'**
  String get overviewEmpty;

  /// No description provided for @overviewApiSettings.
  ///
  /// In en, this message translates to:
  /// **'Summary API'**
  String get overviewApiSettings;

  /// No description provided for @overviewApiBaseUrl.
  ///
  /// In en, this message translates to:
  /// **'API base URL'**
  String get overviewApiBaseUrl;

  /// No description provided for @overviewApiKey.
  ///
  /// In en, this message translates to:
  /// **'API key'**
  String get overviewApiKey;

  /// No description provided for @overviewApiModel.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get overviewApiModel;

  /// No description provided for @overviewApiError.
  ///
  /// In en, this message translates to:
  /// **'Request failed'**
  String get overviewApiError;

  /// No description provided for @overviewApiMissing.
  ///
  /// In en, this message translates to:
  /// **'API not configured'**
  String get overviewApiMissing;

  /// No description provided for @overviewRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get overviewRetry;

  /// No description provided for @overviewCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get overviewCopy;

  /// No description provided for @importLegadoSource.
  ///
  /// In en, this message translates to:
  /// **'Import legado sources'**
  String get importLegadoSource;

  /// No description provided for @legadoImportTitle.
  ///
  /// In en, this message translates to:
  /// **'legado source import'**
  String get legadoImportTitle;

  /// No description provided for @legadoImportHint.
  ///
  /// In en, this message translates to:
  /// **'Select legado source JSON'**
  String get legadoImportHint;

  /// No description provided for @legadoImportedCount.
  ///
  /// In en, this message translates to:
  /// **'Imported \$count sources'**
  String get legadoImportedCount;

  /// No description provided for @legadoParseError.
  ///
  /// In en, this message translates to:
  /// **'Failed to parse source'**
  String get legadoParseError;

  /// No description provided for @legadoGroupDefault.
  ///
  /// In en, this message translates to:
  /// **'legado'**
  String get legadoGroupDefault;

  /// No description provided for @searchPaused.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get searchPaused;

  /// No description provided for @selectionCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get selectionCopy;

  /// No description provided for @selectionCopied.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get selectionCopied;

  /// No description provided for @selectionHighlight.
  ///
  /// In en, this message translates to:
  /// **'Highlight'**
  String get selectionHighlight;

  /// No description provided for @selectionUnderline.
  ///
  /// In en, this message translates to:
  /// **'Underline'**
  String get selectionUnderline;

  /// No description provided for @underlineStyle.
  ///
  /// In en, this message translates to:
  /// **'Underline Style'**
  String get underlineStyle;

  /// No description provided for @underlineColor.
  ///
  /// In en, this message translates to:
  /// **'Underline Color'**
  String get underlineColor;

  /// No description provided for @underlineStyleSolid.
  ///
  /// In en, this message translates to:
  /// **'Solid'**
  String get underlineStyleSolid;

  /// No description provided for @underlineStyleWavy.
  ///
  /// In en, this message translates to:
  /// **'Wavy'**
  String get underlineStyleWavy;

  /// No description provided for @underlineStyleDotted.
  ///
  /// In en, this message translates to:
  /// **'Dotted'**
  String get underlineStyleDotted;

  /// No description provided for @customColorApply.
  ///
  /// In en, this message translates to:
  /// **'Apply Custom Color'**
  String get customColorApply;

  /// No description provided for @selectionNote.
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get selectionNote;

  /// No description provided for @selectionShare.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get selectionShare;

  /// No description provided for @selectionTranslate.
  ///
  /// In en, this message translates to:
  /// **'Translate'**
  String get selectionTranslate;

  /// No description provided for @selectionAskAi.
  ///
  /// In en, this message translates to:
  /// **'Ask AI'**
  String get selectionAskAi;

  /// No description provided for @selTranslateTitle.
  ///
  /// In en, this message translates to:
  /// **'Translate selection'**
  String get selTranslateTitle;

  /// No description provided for @selTranslateSource.
  ///
  /// In en, this message translates to:
  /// **'Source'**
  String get selTranslateSource;

  /// No description provided for @selTranslateResult.
  ///
  /// In en, this message translates to:
  /// **'Translation'**
  String get selTranslateResult;

  /// No description provided for @selTranslateRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get selTranslateRetry;

  /// No description provided for @selTranslateFailed.
  ///
  /// In en, this message translates to:
  /// **'Translation failed'**
  String get selTranslateFailed;

  /// No description provided for @askAiTitle.
  ///
  /// In en, this message translates to:
  /// **'Ask AI'**
  String get askAiTitle;

  /// No description provided for @askAiHint.
  ///
  /// In en, this message translates to:
  /// **'Ask about the selection or this chapter…'**
  String get askAiHint;

  /// No description provided for @askAiSend.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get askAiSend;

  /// No description provided for @askAiThinking.
  ///
  /// In en, this message translates to:
  /// **'Thinking…'**
  String get askAiThinking;

  /// No description provided for @askAiFailed.
  ///
  /// In en, this message translates to:
  /// **'Request failed, please retry'**
  String get askAiFailed;

  /// No description provided for @askAiNoEndpoints.
  ///
  /// In en, this message translates to:
  /// **'No AI endpoint configured. Configure one in \"Settings → AI\" first'**
  String get askAiNoEndpoints;

  /// Ask AI dialog context label
  ///
  /// In en, this message translates to:
  /// **'Context: {book} · {chapter}'**
  String askAiContextTag(String book, String chapter);

  /// No description provided for @notesSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get notesSheetTitle;

  /// No description provided for @notesExport.
  ///
  /// In en, this message translates to:
  /// **'Export Markdown'**
  String get notesExport;

  /// Highlight notes export done toast
  ///
  /// In en, this message translates to:
  /// **'Generated Markdown with {count} items'**
  String notesExported(int count);

  /// No description provided for @shareChangeCover.
  ///
  /// In en, this message translates to:
  /// **'Change Cover'**
  String get shareChangeCover;

  /// No description provided for @selectionCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get selectionCancel;

  /// No description provided for @selectionParagraph.
  ///
  /// In en, this message translates to:
  /// **'Paragraph'**
  String get selectionParagraph;

  /// No description provided for @highlightList.
  ///
  /// In en, this message translates to:
  /// **'Highlights'**
  String get highlightList;

  /// No description provided for @highlightEmpty.
  ///
  /// In en, this message translates to:
  /// **'No highlights'**
  String get highlightEmpty;

  /// No description provided for @highlightDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete highlight'**
  String get highlightDelete;

  /// No description provided for @highlightEditNote.
  ///
  /// In en, this message translates to:
  /// **'Edit note'**
  String get highlightEditNote;

  /// No description provided for @highlightNoteHint.
  ///
  /// In en, this message translates to:
  /// **'Write your thought…'**
  String get highlightNoteHint;

  /// No description provided for @highlightSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get highlightSave;

  /// No description provided for @highlightJump.
  ///
  /// In en, this message translates to:
  /// **'Go to'**
  String get highlightJump;

  /// No description provided for @highlightColor.
  ///
  /// In en, this message translates to:
  /// **'Color'**
  String get highlightColor;

  /// No description provided for @comicTranslateSettingLabel.
  ///
  /// In en, this message translates to:
  /// **'Manga translation'**
  String get comicTranslateSettingLabel;

  /// No description provided for @comicTranslateTurnOn.
  ///
  /// In en, this message translates to:
  /// **'Translate this page'**
  String get comicTranslateTurnOn;

  /// No description provided for @comicTranslateTurnOff.
  ///
  /// In en, this message translates to:
  /// **'Turn off translation'**
  String get comicTranslateTurnOff;

  /// No description provided for @comicTranslateLoading.
  ///
  /// In en, this message translates to:
  /// **'Translating…'**
  String get comicTranslateLoading;

  /// No description provided for @comicTranslateFailed.
  ///
  /// In en, this message translates to:
  /// **'Translation failed'**
  String get comicTranslateFailed;

  /// No description provided for @comicTranslatePartial.
  ///
  /// In en, this message translates to:
  /// **'Partially translated'**
  String get comicTranslatePartial;

  /// No description provided for @subTransSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Live translation'**
  String get subTransSectionTitle;

  /// No description provided for @subTransToggle.
  ///
  /// In en, this message translates to:
  /// **'Translate subtitles in real time'**
  String get subTransToggle;

  /// No description provided for @subTransToggleDesc.
  ///
  /// In en, this message translates to:
  /// **'Detect the current subtitle line and show the translation on screen'**
  String get subTransToggleDesc;

  /// No description provided for @subTransShowOriginal.
  ///
  /// In en, this message translates to:
  /// **'Show original text'**
  String get subTransShowOriginal;

  /// No description provided for @subTransOcrFallback.
  ///
  /// In en, this message translates to:
  /// **'Recognize screen when no subtitles'**
  String get subTransOcrFallback;

  /// No description provided for @subTransOcrFallbackDesc.
  ///
  /// In en, this message translates to:
  /// **'Capture frames periodically and recognize dialogue (uses more data)'**
  String get subTransOcrFallbackDesc;

  /// No description provided for @aiComicTranslationSection.
  ///
  /// In en, this message translates to:
  /// **'Manga translation'**
  String get aiComicTranslationSection;

  /// No description provided for @aiComicTranslationDesc.
  ///
  /// In en, this message translates to:
  /// **'Vision endpoint for manga page OCR + translation; falls back to common API when empty'**
  String get aiComicTranslationDesc;

  /// No description provided for @aiComicModelHint.
  ///
  /// In en, this message translates to:
  /// **'A vision-capable model, e.g. gpt-4o-mini'**
  String get aiComicModelHint;

  /// No description provided for @aiMediaTranslationSection.
  ///
  /// In en, this message translates to:
  /// **'Video subtitle translation'**
  String get aiMediaTranslationSection;

  /// No description provided for @aiMediaTranslationDesc.
  ///
  /// In en, this message translates to:
  /// **'Endpoint for real-time subtitle translation in the player; falls back to common API when empty'**
  String get aiMediaTranslationDesc;

  /// No description provided for @translationCacheTitle.
  ///
  /// In en, this message translates to:
  /// **'Translation cache'**
  String get translationCacheTitle;

  /// No description provided for @translationCacheDesc.
  ///
  /// In en, this message translates to:
  /// **'Per-item AI translation results cached locally; clearing them means re-translating (and re-charging)'**
  String get translationCacheDesc;

  /// No description provided for @translationCacheNovel.
  ///
  /// In en, this message translates to:
  /// **'Novel paragraph translation'**
  String get translationCacheNovel;

  /// No description provided for @translationCacheComic.
  ///
  /// In en, this message translates to:
  /// **'Manga page translation'**
  String get translationCacheComic;

  /// No description provided for @translationCacheSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Video subtitle translation'**
  String get translationCacheSubtitle;

  /// No description provided for @translationCacheEntries.
  ///
  /// In en, this message translates to:
  /// **'{count} entries'**
  String translationCacheEntries(Object count);

  /// No description provided for @translationCacheClear.
  ///
  /// In en, this message translates to:
  /// **'Clear all translation caches'**
  String get translationCacheClear;

  /// No description provided for @translationCacheClearConfirm.
  ///
  /// In en, this message translates to:
  /// **'Clear all translation caches? Translated content will be re-translated with additional API cost.'**
  String get translationCacheClearConfirm;

  /// No description provided for @translationCacheCleared.
  ///
  /// In en, this message translates to:
  /// **'Translation caches cleared'**
  String get translationCacheCleared;

  /// No description provided for @glossaryTitle.
  ///
  /// In en, this message translates to:
  /// **'Translation glossary'**
  String get glossaryTitle;

  /// No description provided for @glossaryTargetLang.
  ///
  /// In en, this message translates to:
  /// **'Target language: {lang}'**
  String glossaryTargetLang(String lang);

  /// No description provided for @glossaryEmpty.
  ///
  /// In en, this message translates to:
  /// **'No glossary entries yet. Add character names and proper nouns so translations stay consistent across chapters.'**
  String get glossaryEmpty;

  /// No description provided for @glossaryAdd.
  ///
  /// In en, this message translates to:
  /// **'Add term'**
  String get glossaryAdd;

  /// No description provided for @glossaryEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit term'**
  String get glossaryEdit;

  /// No description provided for @glossaryTerm.
  ///
  /// In en, this message translates to:
  /// **'Source term'**
  String get glossaryTerm;

  /// No description provided for @glossaryPreferred.
  ///
  /// In en, this message translates to:
  /// **'Preferred translation'**
  String get glossaryPreferred;

  /// No description provided for @glossaryAliases.
  ///
  /// In en, this message translates to:
  /// **'Accepted aliases (separated by 、 or comma, optional)'**
  String get glossaryAliases;

  /// No description provided for @glossaryNote.
  ///
  /// In en, this message translates to:
  /// **'Note (optional)'**
  String get glossaryNote;

  /// No description provided for @glossaryImport.
  ///
  /// In en, this message translates to:
  /// **'Import from JSON'**
  String get glossaryImport;

  /// No description provided for @glossaryExport.
  ///
  /// In en, this message translates to:
  /// **'Export as JSON'**
  String get glossaryExport;

  /// No description provided for @glossaryImportOk.
  ///
  /// In en, this message translates to:
  /// **'Imported {count} entries'**
  String glossaryImportOk(int count);

  /// No description provided for @glossaryImportFail.
  ///
  /// In en, this message translates to:
  /// **'Import failed: invalid glossary file'**
  String get glossaryImportFail;

  /// No description provided for @glossaryDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete term “{term}”?'**
  String glossaryDeleteConfirm(String term);

  /// No description provided for @glossaryAliasesPreview.
  ///
  /// In en, this message translates to:
  /// **'Aliases: {aliases}'**
  String glossaryAliasesPreview(String aliases);

  /// No description provided for @glossaryOpen.
  ///
  /// In en, this message translates to:
  /// **'Glossary editor'**
  String get glossaryOpen;

  /// No description provided for @glossaryWorkTitle.
  ///
  /// In en, this message translates to:
  /// **'Work glossary'**
  String get glossaryWorkTitle;

  /// No description provided for @glossaryScopeGlobal.
  ///
  /// In en, this message translates to:
  /// **'Global glossary · applies to all works'**
  String get glossaryScopeGlobal;

  /// No description provided for @glossaryScopeWork.
  ///
  /// In en, this message translates to:
  /// **'This work + global glossary'**
  String get glossaryScopeWork;

  /// No description provided for @glossaryConflictsTitle.
  ///
  /// In en, this message translates to:
  /// **'Glossary conflicts to resolve ({count})'**
  String glossaryConflictsTitle(int count);

  /// No description provided for @glossaryConflictExisting.
  ///
  /// In en, this message translates to:
  /// **'Current translation'**
  String get glossaryConflictExisting;

  /// No description provided for @glossaryConflictProposed.
  ///
  /// In en, this message translates to:
  /// **'Translation seen this batch'**
  String get glossaryConflictProposed;

  /// No description provided for @glossaryConflictChapter.
  ///
  /// In en, this message translates to:
  /// **'From: {chapter}'**
  String glossaryConflictChapter(String chapter);

  /// No description provided for @glossaryConflictAdopt.
  ///
  /// In en, this message translates to:
  /// **'Use new translation'**
  String get glossaryConflictAdopt;

  /// No description provided for @glossaryConflictKeep.
  ///
  /// In en, this message translates to:
  /// **'Keep current translation'**
  String get glossaryConflictKeep;

  /// No description provided for @glossaryConflictResolved.
  ///
  /// In en, this message translates to:
  /// **'Conflict resolved'**
  String get glossaryConflictResolved;

  /// No description provided for @glossaryConflictBadge.
  ///
  /// In en, this message translates to:
  /// **'Needs review'**
  String get glossaryConflictBadge;

  /// No description provided for @glossaryGlobalEntryHint.
  ///
  /// In en, this message translates to:
  /// **'Global entry; edit or delete it in the global glossary'**
  String get glossaryGlobalEntryHint;

  /// No description provided for @glossaryTypeTerm.
  ///
  /// In en, this message translates to:
  /// **'Term'**
  String get glossaryTypeTerm;

  /// No description provided for @glossaryTypePerson.
  ///
  /// In en, this message translates to:
  /// **'Person'**
  String get glossaryTypePerson;

  /// No description provided for @glossaryTypePlace.
  ///
  /// In en, this message translates to:
  /// **'Place'**
  String get glossaryTypePlace;

  /// No description provided for @glossaryTypeOrg.
  ///
  /// In en, this message translates to:
  /// **'Organization'**
  String get glossaryTypeOrg;

  /// No description provided for @glossaryTypeAppellation.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get glossaryTypeAppellation;

  /// No description provided for @glossaryTypeHonorific.
  ///
  /// In en, this message translates to:
  /// **'Honorific'**
  String get glossaryTypeHonorific;

  /// No description provided for @glossaryTypeSpeech.
  ///
  /// In en, this message translates to:
  /// **'Verbal tic'**
  String get glossaryTypeSpeech;

  /// No description provided for @glossaryTypeFixed.
  ///
  /// In en, this message translates to:
  /// **'Fixed expression'**
  String get glossaryTypeFixed;

  /// No description provided for @glossaryExtractedNotice.
  ///
  /// In en, this message translates to:
  /// **'{terms} terms added, {conflicts} conflicts to resolve'**
  String glossaryExtractedNotice(int terms, int conflicts);

  /// No description provided for @glossaryExtractedOpen.
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get glossaryExtractedOpen;

  /// No description provided for @translationStyle.
  ///
  /// In en, this message translates to:
  /// **'Translation style'**
  String get translationStyle;

  /// No description provided for @translationStyleStandard.
  ///
  /// In en, this message translates to:
  /// **'Standard'**
  String get translationStyleStandard;

  /// No description provided for @translationStyleColloquial.
  ///
  /// In en, this message translates to:
  /// **'Colloquial'**
  String get translationStyleColloquial;

  /// No description provided for @translationStyleElegant.
  ///
  /// In en, this message translates to:
  /// **'Elegant'**
  String get translationStyleElegant;

  /// No description provided for @translationStyleInternet.
  ///
  /// In en, this message translates to:
  /// **'Internet slang'**
  String get translationStyleInternet;

  /// No description provided for @translationCot.
  ///
  /// In en, this message translates to:
  /// **'Deliberate translation (chain of thought)'**
  String get translationCot;

  /// No description provided for @translationCotHint.
  ///
  /// In en, this message translates to:
  /// **'Let the model reason about context and terminology before translating. Higher quality but slower and more costly; best for short passages.'**
  String get translationCotHint;

  /// No description provided for @translationSubtitleLightweight.
  ///
  /// In en, this message translates to:
  /// **'Lightweight subtitle output'**
  String get translationSubtitleLightweight;

  /// No description provided for @translationSubtitleLightweightHint.
  ///
  /// In en, this message translates to:
  /// **'Subtitles are output line-by-line without numbering to save tokens; falls back to numbered protocol automatically when alignment fails.'**
  String get translationSubtitleLightweightHint;

  /// No description provided for @translationAutoExtract.
  ///
  /// In en, this message translates to:
  /// **'Auto-extract glossary'**
  String get translationAutoExtract;

  /// No description provided for @translationAutoExtractHint.
  ///
  /// In en, this message translates to:
  /// **'After each batch, collect character names, places and fixed renderings; differing renderings become conflicts to resolve. Turn off to reduce requests.'**
  String get translationAutoExtractHint;

  /// No description provided for @translationExportLayout.
  ///
  /// In en, this message translates to:
  /// **'Novel translation appendix layout'**
  String get translationExportLayout;

  /// No description provided for @translationLayoutTranslationFirst.
  ///
  /// In en, this message translates to:
  /// **'Translation first'**
  String get translationLayoutTranslationFirst;

  /// No description provided for @translationLayoutSourceFirst.
  ///
  /// In en, this message translates to:
  /// **'Source first'**
  String get translationLayoutSourceFirst;

  /// No description provided for @translationLayoutBilingual.
  ///
  /// In en, this message translates to:
  /// **'Bilingual'**
  String get translationLayoutBilingual;

  /// No description provided for @novelTranslateResume.
  ///
  /// In en, this message translates to:
  /// **'Resume translation'**
  String get novelTranslateResume;

  /// No description provided for @novelTranslateResumable.
  ///
  /// In en, this message translates to:
  /// **'{done} of {total} paragraphs translated - resume from where it stopped'**
  String novelTranslateResumable(Object done, Object total);

  /// No description provided for @prescanStart.
  ///
  /// In en, this message translates to:
  /// **'Prescan whole book'**
  String get prescanStart;

  /// No description provided for @prescanProgress.
  ///
  /// In en, this message translates to:
  /// **'Prescanning: {done} of {total} chapters'**
  String prescanProgress(Object done, Object total);

  /// No description provided for @prescanReady.
  ///
  /// In en, this message translates to:
  /// **'Book overview injected into translation context'**
  String get prescanReady;

  /// No description provided for @translationPolish.
  ///
  /// In en, this message translates to:
  /// **'Translation polish (second pass)'**
  String get translationPolish;

  /// No description provided for @translationPolishHint.
  ///
  /// In en, this message translates to:
  /// **'After a chapter is translated, polish it once more for natural phrasing and consistent terminology. Off by default; each polished chapter costs one extra request.'**
  String get translationPolishHint;

  /// No description provided for @polishAction.
  ///
  /// In en, this message translates to:
  /// **'Polish this chapter'**
  String get polishAction;

  /// No description provided for @translationVariantOriginal.
  ///
  /// In en, this message translates to:
  /// **'First pass'**
  String get translationVariantOriginal;

  /// No description provided for @translationVariantPolished.
  ///
  /// In en, this message translates to:
  /// **'Polished'**
  String get translationVariantPolished;

  /// No description provided for @reviewOpen.
  ///
  /// In en, this message translates to:
  /// **'Translation review reports'**
  String get reviewOpen;

  /// No description provided for @reviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Translation review'**
  String get reviewTitle;

  /// No description provided for @reviewBooksEmpty.
  ///
  /// In en, this message translates to:
  /// **'No translated chapters cached yet. Translate some chapters first, then run a review here.'**
  String get reviewBooksEmpty;

  /// No description provided for @reviewBookChapters.
  ///
  /// In en, this message translates to:
  /// **'{count} chapters translated'**
  String reviewBookChapters(Object count);

  /// No description provided for @reviewBookFindings.
  ///
  /// In en, this message translates to:
  /// **'{count} findings in the latest report'**
  String reviewBookFindings(Object count);

  /// No description provided for @reviewRunFailed.
  ///
  /// In en, this message translates to:
  /// **'Review failed'**
  String get reviewRunFailed;

  /// No description provided for @reviewFindingCount.
  ///
  /// In en, this message translates to:
  /// **'{count} findings'**
  String reviewFindingCount(Object count);

  /// No description provided for @reviewNoFindings.
  ///
  /// In en, this message translates to:
  /// **'No issues found. All checks passed.'**
  String get reviewNoFindings;

  /// No description provided for @reviewTruncated.
  ///
  /// In en, this message translates to:
  /// **'Summary version: showing the first 100 findings. The full report was saved as a JSON file.'**
  String get reviewTruncated;

  /// No description provided for @reviewTypeGlossary.
  ///
  /// In en, this message translates to:
  /// **'Glossary'**
  String get reviewTypeGlossary;

  /// No description provided for @reviewTypeMissing.
  ///
  /// In en, this message translates to:
  /// **'Missing'**
  String get reviewTypeMissing;

  /// No description provided for @reviewTypeLiteral.
  ///
  /// In en, this message translates to:
  /// **'Literal'**
  String get reviewTypeLiteral;

  /// No description provided for @reviewTypeAdded.
  ///
  /// In en, this message translates to:
  /// **'Over-translation'**
  String get reviewTypeAdded;

  /// No description provided for @reviewTypeMistranslation.
  ///
  /// In en, this message translates to:
  /// **'Mistranslation'**
  String get reviewTypeMistranslation;

  /// No description provided for @reviewTypeTerminology.
  ///
  /// In en, this message translates to:
  /// **'Terminology'**
  String get reviewTypeTerminology;

  /// No description provided for @reviewTypePronoun.
  ///
  /// In en, this message translates to:
  /// **'Pronoun'**
  String get reviewTypePronoun;

  /// No description provided for @reviewAiAction.
  ///
  /// In en, this message translates to:
  /// **'AI review'**
  String get reviewAiAction;

  /// No description provided for @reviewAiProgress.
  ///
  /// In en, this message translates to:
  /// **'AI reviewing {done}/{total}'**
  String reviewAiProgress(Object done, Object total);

  /// No description provided for @reviewAiPartial.
  ///
  /// In en, this message translates to:
  /// **'Some chunks were skipped. The report may be incomplete.'**
  String get reviewAiPartial;

  /// No description provided for @reviewRevision.
  ///
  /// In en, this message translates to:
  /// **'Revision'**
  String get reviewRevision;

  /// No description provided for @reviewAccept.
  ///
  /// In en, this message translates to:
  /// **'Accept'**
  String get reviewAccept;

  /// No description provided for @reviewIgnore.
  ///
  /// In en, this message translates to:
  /// **'Ignore'**
  String get reviewIgnore;

  /// No description provided for @reviewApplyAll.
  ///
  /// In en, this message translates to:
  /// **'Apply all'**
  String get reviewApplyAll;

  /// No description provided for @reviewAppliedCount.
  ///
  /// In en, this message translates to:
  /// **'Applied {count} revisions'**
  String reviewAppliedCount(Object count);

  /// No description provided for @offlineTranslateTitle.
  ///
  /// In en, this message translates to:
  /// **'Offline whole-video translation'**
  String get offlineTranslateTitle;

  /// No description provided for @offlineHint.
  ///
  /// In en, this message translates to:
  /// **'Pick an external subtitle file (SRT / VTT / ASS); all sentences are translated in batches and can be exported as bilingual subtitles. Interrupted jobs resume automatically.'**
  String get offlineHint;

  /// No description provided for @offlinePickSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Pick subtitle file to translate'**
  String get offlinePickSubtitle;

  /// No description provided for @offlineJobProgress.
  ///
  /// In en, this message translates to:
  /// **'Translated {done} of {total} cues'**
  String offlineJobProgress(Object done, Object total);

  /// No description provided for @offlineJobDone.
  ///
  /// In en, this message translates to:
  /// **'Translation complete - export below'**
  String get offlineJobDone;

  /// No description provided for @offlineJobFailed.
  ///
  /// In en, this message translates to:
  /// **'Translation failed'**
  String get offlineJobFailed;

  /// No description provided for @offlineResume.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get offlineResume;

  /// No description provided for @offlineCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel job'**
  String get offlineCancel;

  /// No description provided for @offlineRetranslate.
  ///
  /// In en, this message translates to:
  /// **'Translate again / fill gaps'**
  String get offlineRetranslate;

  /// No description provided for @offlineExportSrt.
  ///
  /// In en, this message translates to:
  /// **'Export bilingual SRT'**
  String get offlineExportSrt;

  /// No description provided for @offlineExportAss.
  ///
  /// In en, this message translates to:
  /// **'Export bilingual ASS'**
  String get offlineExportAss;

  /// No description provided for @offlineUpload.
  ///
  /// In en, this message translates to:
  /// **'Upload to WebDAV'**
  String get offlineUpload;

  /// No description provided for @offlineUploaded.
  ///
  /// In en, this message translates to:
  /// **'Uploaded: {url}'**
  String offlineUploaded(Object url);

  /// No description provided for @comicTranslateBackfillLabel.
  ///
  /// In en, this message translates to:
  /// **'Bubble backfill layout'**
  String get comicTranslateBackfillLabel;

  /// No description provided for @comicTranslateBackfillDesc.
  ///
  /// In en, this message translates to:
  /// **'Render translations inside speech bubbles with stroked text, bubble-width wrapping and adaptive font size. Vertical text pages degrade to horizontal centered layout.'**
  String get comicTranslateBackfillDesc;

  /// No description provided for @aiBackupSection.
  ///
  /// In en, this message translates to:
  /// **'Backup endpoint (auto failover)'**
  String get aiBackupSection;

  /// No description provided for @comicTranslationExport.
  ///
  /// In en, this message translates to:
  /// **'Export translations (JSON)'**
  String get comicTranslationExport;

  /// No description provided for @comicTranslationImport.
  ///
  /// In en, this message translates to:
  /// **'Import translations'**
  String get comicTranslationImport;

  /// No description provided for @comicTranslationImportOk.
  ///
  /// In en, this message translates to:
  /// **'Imported {imported} pages, skipped {skipped} existing'**
  String comicTranslationImportOk(Object imported, Object skipped);

  /// No description provided for @comicTranslationImportFail.
  ///
  /// In en, this message translates to:
  /// **'Import failed: invalid translations file'**
  String get comicTranslationImportFail;

  /// No description provided for @offlineExportAll.
  ///
  /// In en, this message translates to:
  /// **'Export all completed (bilingual SRT)'**
  String get offlineExportAll;

  /// RSS subscriptions also honor this network settings page (proxy/DNS/SNI/Hosts)
  ///
  /// In en, this message translates to:
  /// **'RSS subscriptions also apply this page\'s proxy, DNS, SNI and Hosts settings: global network configured here takes effect for both RSS fetching and RSSHub speed tests.'**
  String get networkRssAppliesNote;

  /// Global RSS subscriptions shared with the Browse tab
  ///
  /// In en, this message translates to:
  /// **'Global RSS subscriptions shared with the Browse tab'**
  String get rssGlobalSubscriptionDesc;

  /// Dialog title for binding an RSS feed to a module
  ///
  /// In en, this message translates to:
  /// **'Bind to module'**
  String get rssBindModuleTitle;

  /// Bind RSS feed to novel module
  ///
  /// In en, this message translates to:
  /// **'Bind to novel'**
  String get rssBindToNovel;

  /// Bind RSS feed to anime/video module
  ///
  /// In en, this message translates to:
  /// **'Bind to video'**
  String get rssBindToAnime;

  /// Bind RSS feed to manga module
  ///
  /// In en, this message translates to:
  /// **'Bind to manga'**
  String get rssBindToManga;

  /// Unbind RSS feed back to global subscriptions
  ///
  /// In en, this message translates to:
  /// **'Unbind to global'**
  String get rssUnbindGlobal;

  /// Added to favorites
  ///
  /// In en, this message translates to:
  /// **'Added to favorites'**
  String get rssArticleFavorited;

  /// Removed from favorites
  ///
  /// In en, this message translates to:
  /// **'Removed from favorites'**
  String get rssArticleUnfavorited;

  /// RSS favorites page title and entry
  ///
  /// In en, this message translates to:
  /// **'RSS Favorites'**
  String get rssFavorites;

  /// RSS favorites entry subtitle
  ///
  /// In en, this message translates to:
  /// **'Favorited RSS articles'**
  String get rssFavoritesDesc;

  /// RSS favorites empty state
  ///
  /// In en, this message translates to:
  /// **'No favorites yet'**
  String get rssFavoritesEmpty;

  /// Mark all articles as read
  ///
  /// In en, this message translates to:
  /// **'Mark all as read'**
  String get rssMarkAllRead;

  /// Marked all as read snackbar
  ///
  /// In en, this message translates to:
  /// **'Marked all as read'**
  String get rssMarkedAllRead;

  /// Offline cache banner on RSS detail when network fetch failed
  ///
  /// In en, this message translates to:
  /// **'Offline cache (last fetched)'**
  String get rssOfflineCached;

  /// Filter: show all articles
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get rssShowAll;

  /// Filter: show only unread articles
  ///
  /// In en, this message translates to:
  /// **'Unread'**
  String get rssShowUnread;

  /// Star button tooltip: favorite this article
  ///
  /// In en, this message translates to:
  /// **'Add to favorites'**
  String get rssStarAdd;

  /// Star button tooltip: unfavorite this article
  ///
  /// In en, this message translates to:
  /// **'Remove from favorites'**
  String get rssStarRemove;

  /// Discover feeds: add selected button
  ///
  /// In en, this message translates to:
  /// **'Add selected ({count})'**
  String rssDiscoverAddSelected(Object count);

  /// Discover feeds: added toast
  ///
  /// In en, this message translates to:
  /// **'Added {count} feeds'**
  String rssDiscoverAdded(Object count);

  /// Discover feeds: button label
  ///
  /// In en, this message translates to:
  /// **'Find feeds'**
  String get rssDiscoverButton;

  /// Discover feeds: page description
  ///
  /// In en, this message translates to:
  /// **'Enter a site address to find its RSS / Atom feeds'**
  String get rssDiscoverDesc;

  /// Discover feeds: failure toast
  ///
  /// In en, this message translates to:
  /// **'Discovery failed: {error}'**
  String rssDiscoverFailed(Object error);

  /// Discover feeds: found count
  ///
  /// In en, this message translates to:
  /// **'Found {count} feeds'**
  String rssDiscoverFound(Object count);

  /// Discover feeds: source = page link
  ///
  /// In en, this message translates to:
  /// **'Declared by page'**
  String get rssDiscoverFromLink;

  /// Discover feeds: source = common path probe
  ///
  /// In en, this message translates to:
  /// **'Common path'**
  String get rssDiscoverFromProbe;

  /// Discover feeds: URL input hint
  ///
  /// In en, this message translates to:
  /// **'https://example.com'**
  String get rssDiscoverInputHint;

  /// Discover feeds: invalid URL
  ///
  /// In en, this message translates to:
  /// **'Enter a valid URL'**
  String get rssDiscoverInvalidUrl;

  /// Discover feeds: none found
  ///
  /// In en, this message translates to:
  /// **'No feeds found'**
  String get rssDiscoverNone;

  /// Discover feeds: probing
  ///
  /// In en, this message translates to:
  /// **'Probing common paths…'**
  String get rssDiscoverProbing;

  /// Discover feeds: screen title
  ///
  /// In en, this message translates to:
  /// **'Discover feeds from a site'**
  String get rssDiscoverTitle;

  /// Export OPML: menu entry
  ///
  /// In en, this message translates to:
  /// **'Export as OPML'**
  String get rssExportOpml;

  /// Groups: new (manage-groups sheet / feed menu)
  ///
  /// In en, this message translates to:
  /// **'New group'**
  String get rssGroupAdd;

  /// Groups: duplicate-name hint when creating
  ///
  /// In en, this message translates to:
  /// **'Group \"{name}\" already exists'**
  String rssGroupAddExists(Object name);

  /// Attachment: audio load failed
  ///
  /// In en, this message translates to:
  /// **'Audio failed to load'**
  String get rssAudioFailed;

  /// Attachment: external fallback when load fails
  ///
  /// In en, this message translates to:
  /// **'Open in external app'**
  String get rssOpenExternally;

  /// Attachment: video load failed
  ///
  /// In en, this message translates to:
  /// **'Video failed to load'**
  String get rssVideoFailed;

  /// Attachment: play video
  ///
  /// In en, this message translates to:
  /// **'Play video'**
  String get rssVideoPlay;

  /// No description provided for @rssFetchWebsite.
  ///
  /// In en, this message translates to:
  /// **'Fetch from website'**
  String get rssFetchWebsite;

  /// No description provided for @rssFetchSucceeded.
  ///
  /// In en, this message translates to:
  /// **'Article updated from website'**
  String get rssFetchSucceeded;

  /// No description provided for @rssListLayout.
  ///
  /// In en, this message translates to:
  /// **'List layout'**
  String get rssListLayout;

  /// No description provided for @rssLayoutList.
  ///
  /// In en, this message translates to:
  /// **'List'**
  String get rssLayoutList;

  /// No description provided for @rssLayoutCard.
  ///
  /// In en, this message translates to:
  /// **'Cards'**
  String get rssLayoutCard;

  /// No description provided for @rssLayoutCompact.
  ///
  /// In en, this message translates to:
  /// **'Compact'**
  String get rssLayoutCompact;

  /// No description provided for @rssLayoutMagazine.
  ///
  /// In en, this message translates to:
  /// **'Magazine'**
  String get rssLayoutMagazine;

  /// No description provided for @rssSort.
  ///
  /// In en, this message translates to:
  /// **'Sort'**
  String get rssSort;

  /// No description provided for @rssSortNewest.
  ///
  /// In en, this message translates to:
  /// **'Newest first'**
  String get rssSortNewest;

  /// No description provided for @rssSortOldest.
  ///
  /// In en, this message translates to:
  /// **'Oldest first'**
  String get rssSortOldest;

  /// No description provided for @rssSortUnreadFirst.
  ///
  /// In en, this message translates to:
  /// **'Unread first'**
  String get rssSortUnreadFirst;

  /// No description provided for @rssPrevArticle.
  ///
  /// In en, this message translates to:
  /// **'Previous'**
  String get rssPrevArticle;

  /// No description provided for @rssNextArticle.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get rssNextArticle;

  /// No description provided for @rssAutoReadTitle.
  ///
  /// In en, this message translates to:
  /// **'Auto-read keywords'**
  String get rssAutoReadTitle;

  /// No description provided for @rssAutoReadDesc.
  ///
  /// In en, this message translates to:
  /// **'New articles whose title matches a keyword are marked as read and excluded from the unread count'**
  String get rssAutoReadDesc;

  /// No description provided for @rssAutoReadAdd.
  ///
  /// In en, this message translates to:
  /// **'Add keyword'**
  String get rssAutoReadAdd;

  /// No description provided for @rssAutoReadEmpty.
  ///
  /// In en, this message translates to:
  /// **'No keywords yet'**
  String get rssAutoReadEmpty;

  /// No description provided for @rssAutoReadHint.
  ///
  /// In en, this message translates to:
  /// **'Keyword contained in the article title'**
  String get rssAutoReadHint;

  /// No description provided for @rssOpenInBrowser.
  ///
  /// In en, this message translates to:
  /// **'Open in browser'**
  String get rssOpenInBrowser;

  /// No description provided for @rssAutoFetchFullText.
  ///
  /// In en, this message translates to:
  /// **'Auto-fetch full text'**
  String get rssAutoFetchFullText;

  /// Inline frame: open in in-app browser
  ///
  /// In en, this message translates to:
  /// **'Open in built-in browser'**
  String get rssIframeOpen;

  /// Article: fetch full page content
  ///
  /// In en, this message translates to:
  /// **'Fetch full page'**
  String get rssFetchFullText;

  /// Article: fetching in progress
  ///
  /// In en, this message translates to:
  /// **'Fetching…'**
  String get rssFetching;

  /// Article: fetch failed
  ///
  /// In en, this message translates to:
  /// **'Fetch failed'**
  String get rssFetchFullTextFailed;

  /// Article: no content extracted
  ///
  /// In en, this message translates to:
  /// **'Could not extract content'**
  String get rssFetchFullTextEmpty;

  /// Image viewer: saved
  ///
  /// In en, this message translates to:
  /// **'Image saved'**
  String get rssImageSaved;

  /// Image viewer: save failed
  ///
  /// In en, this message translates to:
  /// **'Save failed'**
  String get rssImageSaveFailed;

  /// Article: hint when a link scheme is blocked
  ///
  /// In en, this message translates to:
  /// **'This link is not supported'**
  String get rssLinkUnsupported;

  /// Groups: all
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get rssGroupAll;

  /// Groups: delete
  ///
  /// In en, this message translates to:
  /// **'Delete group'**
  String get rssGroupDelete;

  /// Groups: delete confirm
  ///
  /// In en, this message translates to:
  /// **'Delete group \"{name}\"? Subscriptions stay; only the tag is removed.'**
  String rssGroupDeleteConfirm(Object name);

  /// Groups: empty state
  ///
  /// In en, this message translates to:
  /// **'No groups yet'**
  String get rssGroupEmpty;

  /// Groups: feed count
  ///
  /// In en, this message translates to:
  /// **'{count} feeds'**
  String rssGroupFeedCount(Object count);

  /// Groups: manage
  ///
  /// In en, this message translates to:
  /// **'Manage groups'**
  String get rssGroupManage;

  /// Groups: rename
  ///
  /// In en, this message translates to:
  /// **'Rename group'**
  String get rssGroupRename;

  /// Groups: updated
  ///
  /// In en, this message translates to:
  /// **'Groups updated'**
  String get rssGroupSetDone;

  /// Groups: ungrouped
  ///
  /// In en, this message translates to:
  /// **'Ungrouped'**
  String get rssGroupUngrouped;

  /// Import OPML: menu entry
  ///
  /// In en, this message translates to:
  /// **'Import OPML'**
  String get rssImportOpml;

  /// OPML import: group badge
  ///
  /// In en, this message translates to:
  /// **'Group: {name}'**
  String rssOpmlCategory(Object name);

  /// OPML import: confirm button
  ///
  /// In en, this message translates to:
  /// **'Import selected'**
  String get rssOpmlConfirmImport;

  /// OPML import: nothing to import
  ///
  /// In en, this message translates to:
  /// **'No subscriptions to import'**
  String get rssOpmlEmpty;

  /// OPML export: subtitle
  ///
  /// In en, this message translates to:
  /// **'Export all subscriptions to standard OPML'**
  String get rssOpmlExportDesc;

  /// OPML export: subtitle 2
  ///
  /// In en, this message translates to:
  /// **'Create an OPML backup and share it'**
  String get rssOpmlExportDesc2;

  /// OPML export: section title
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get rssOpmlExportTitle;

  /// OPML import: section description
  ///
  /// In en, this message translates to:
  /// **'Import subscriptions from a file or pasted text'**
  String get rssOpmlImportDesc;

  /// OPML import: from file
  ///
  /// In en, this message translates to:
  /// **'Import from file'**
  String get rssOpmlImportFile;

  /// OPML import: from file hint
  ///
  /// In en, this message translates to:
  /// **'Pick a local .opml / .xml file'**
  String get rssOpmlImportFileDesc;

  /// OPML import: preview title
  ///
  /// In en, this message translates to:
  /// **'Import preview'**
  String get rssOpmlImportPreviewTitle;

  /// OPML import: paste text
  ///
  /// In en, this message translates to:
  /// **'Import from pasted text'**
  String get rssOpmlImportText;

  /// OPML import: paste text hint
  ///
  /// In en, this message translates to:
  /// **'Paste OPML content directly'**
  String get rssOpmlImportTextDesc;

  /// OPML import: section title
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get rssOpmlImportTitle;

  /// OPML parse failed
  ///
  /// In en, this message translates to:
  /// **'Failed to parse OPML: {error}'**
  String rssOpmlParseFailed(Object error);

  /// OPML import preview: selected/total
  ///
  /// In en, this message translates to:
  /// **'Selected {selected} / {total} total'**
  String rssOpmlPreviewSummary(Object selected, Object total);

  /// OPML import preview: selected/total with skipped
  ///
  /// In en, this message translates to:
  /// **'Selected {selected} / {total} total (skipped {skipped} invalid nodes)'**
  String rssOpmlPreviewSummarySkipped(
      Object selected, Object skipped, Object total);

  /// Set groups: button/title
  ///
  /// In en, this message translates to:
  /// **'Set groups'**
  String get rssSetGroups;

  /// OPML Import & Export: screen title
  ///
  /// In en, this message translates to:
  /// **'OPML Import & Export'**
  String get rssOpmlTitle;

  /// OPML export: entry title
  ///
  /// In en, this message translates to:
  /// **'Export as OPML'**
  String get rssOpmlExport;

  /// OPML import: paste hint
  ///
  /// In en, this message translates to:
  /// **'Paste OPML content here'**
  String get rssOpmlPasteHint;

  /// OPML import: imported toast
  ///
  /// In en, this message translates to:
  /// **'Imported {count} subscriptions'**
  String rssOpmlImported(Object count);

  /// Groups: name label
  ///
  /// In en, this message translates to:
  /// **'Group name'**
  String get rssGroupName;

  /// Global RSS search: screen title
  ///
  /// In en, this message translates to:
  /// **'RSS Search'**
  String get rssSearchTitle;

  /// Global RSS search: input hint
  ///
  /// In en, this message translates to:
  /// **'Search articles in your subscriptions'**
  String get rssSearchHint;

  /// Global RSS search: no result for query
  ///
  /// In en, this message translates to:
  /// **'No matching articles'**
  String get rssSearchNoResult;

  /// Global RSS search: building cache index
  ///
  /// In en, this message translates to:
  /// **'Building index…'**
  String get rssSearchBuilding;

  /// Global RSS search: no cached articles
  ///
  /// In en, this message translates to:
  /// **'No cached articles yet. Open a feed first.'**
  String get rssSearchEmpty;

  /// Global RSS search: result count (shown / total)
  ///
  /// In en, this message translates to:
  /// **'Matched {shown} of {total}'**
  String rssSearchCount(Object shown, Object total);

  /// RSS article detail: attachments section title (non-audio enclosures like video/file)
  ///
  /// In en, this message translates to:
  /// **'Attachments'**
  String get rssAttachments;

  /// RSS update notification setting: toggle to send OS notification
  ///
  /// In en, this message translates to:
  /// **'System notification'**
  String get rssSystemNotification;

  /// RSS update notification setting: subtitle noting platform support
  ///
  /// In en, this message translates to:
  /// **'Send OS notification on new articles (Android/iOS/Linux/macOS)'**
  String get rssSystemNotificationSubtitle;

  /// No description provided for @articleMargin.
  ///
  /// In en, this message translates to:
  /// **'Margin'**
  String get articleMargin;

  /// No description provided for @articleFontUnderline.
  ///
  /// In en, this message translates to:
  /// **'Underline'**
  String get articleFontUnderline;

  /// No description provided for @articleUnderlineDashed.
  ///
  /// In en, this message translates to:
  /// **'Dashed underline'**
  String get articleUnderlineDashed;

  /// No description provided for @articleUnderlineThickness.
  ///
  /// In en, this message translates to:
  /// **'Underline width'**
  String get articleUnderlineThickness;

  /// No description provided for @articleUnderlineColor.
  ///
  /// In en, this message translates to:
  /// **'Underline color'**
  String get articleUnderlineColor;

  /// No description provided for @articleBackground.
  ///
  /// In en, this message translates to:
  /// **'Background'**
  String get articleBackground;

  /// No description provided for @articleTextColor.
  ///
  /// In en, this message translates to:
  /// **'Text color'**
  String get articleTextColor;

  /// No description provided for @articleEmphasisColor.
  ///
  /// In en, this message translates to:
  /// **'Accent color'**
  String get articleEmphasisColor;

  /// No description provided for @articleShadow.
  ///
  /// In en, this message translates to:
  /// **'Text shadow'**
  String get articleShadow;

  /// No description provided for @articleShadowBlur.
  ///
  /// In en, this message translates to:
  /// **'Shadow blur'**
  String get articleShadowBlur;

  /// No description provided for @articleShadowOffsetX.
  ///
  /// In en, this message translates to:
  /// **'Shadow X offset'**
  String get articleShadowOffsetX;

  /// No description provided for @articleShadowOffsetY.
  ///
  /// In en, this message translates to:
  /// **'Shadow Y offset'**
  String get articleShadowOffsetY;

  /// No description provided for @articleChooseFont.
  ///
  /// In en, this message translates to:
  /// **'Choose font file'**
  String get articleChooseFont;

  /// No description provided for @articleClearFont.
  ///
  /// In en, this message translates to:
  /// **'Clear font'**
  String get articleClearFont;

  /// No description provided for @articleFontCurrent.
  ///
  /// In en, this message translates to:
  /// **'Current: {file}'**
  String articleFontCurrent(Object file);

  /// No description provided for @articleTitleScale.
  ///
  /// In en, this message translates to:
  /// **'Title size'**
  String get articleTitleScale;

  /// No description provided for @articleTitleBold.
  ///
  /// In en, this message translates to:
  /// **'Bold title'**
  String get articleTitleBold;

  /// No description provided for @articleTitleColor.
  ///
  /// In en, this message translates to:
  /// **'Title color'**
  String get articleTitleColor;

  /// No description provided for @articleTitleAlign.
  ///
  /// In en, this message translates to:
  /// **'Title alignment'**
  String get articleTitleAlign;

  /// No description provided for @alignLeft.
  ///
  /// In en, this message translates to:
  /// **'Left'**
  String get alignLeft;

  /// No description provided for @alignCenter.
  ///
  /// In en, this message translates to:
  /// **'Center'**
  String get alignCenter;

  /// No description provided for @alignRight.
  ///
  /// In en, this message translates to:
  /// **'Right'**
  String get alignRight;

  /// No description provided for @colorFollowDefault.
  ///
  /// In en, this message translates to:
  /// **'Follow default'**
  String get colorFollowDefault;

  /// RSS update notification setting: trigger a check when charging
  ///
  /// In en, this message translates to:
  /// **'Check on charging'**
  String get rssChargeCheck;

  /// RSS update notification setting: subtitle for the charging trigger
  ///
  /// In en, this message translates to:
  /// **'Auto-check for new content once the charger is connected (trigger: charging)'**
  String get rssChargeCheckSubtitle;

  /// No description provided for @articleSecTypography.
  ///
  /// In en, this message translates to:
  /// **'Typography'**
  String get articleSecTypography;

  /// No description provided for @articleSecTextStyle.
  ///
  /// In en, this message translates to:
  /// **'Text style'**
  String get articleSecTextStyle;

  /// No description provided for @articleSecColor.
  ///
  /// In en, this message translates to:
  /// **'Color & background'**
  String get articleSecColor;

  /// No description provided for @articleSecShadow.
  ///
  /// In en, this message translates to:
  /// **'Shadow'**
  String get articleSecShadow;

  /// No description provided for @articleSecFont.
  ///
  /// In en, this message translates to:
  /// **'Font'**
  String get articleSecFont;

  /// No description provided for @articleSecTitle.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get articleSecTitle;

  /// No description provided for @mediaServerSettings.
  ///
  /// In en, this message translates to:
  /// **'Media servers'**
  String get mediaServerSettings;

  /// No description provided for @mediaServerSettingsDesc.
  ///
  /// In en, this message translates to:
  /// **'Manage Emby / Jellyfin server connections and sign-in'**
  String get mediaServerSettingsDesc;

  /// No description provided for @mediaServerSettingsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Connect Emby / Jellyfin with two-way watch progress sync'**
  String get mediaServerSettingsSubtitle;

  /// mediaServerTileConnected
  ///
  /// In en, this message translates to:
  /// **'{n} connected'**
  String mediaServerTileConnected(Object n);

  /// No description provided for @mediaServerAddServer.
  ///
  /// In en, this message translates to:
  /// **'Add server'**
  String get mediaServerAddServer;

  /// No description provided for @mediaServerAddressLabel.
  ///
  /// In en, this message translates to:
  /// **'Server address'**
  String get mediaServerAddressLabel;

  /// No description provided for @mediaServerAddressHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. http://192.168.1.10:8096'**
  String get mediaServerAddressHint;

  /// No description provided for @mediaServerDetect.
  ///
  /// In en, this message translates to:
  /// **'Detect'**
  String get mediaServerDetect;

  /// No description provided for @mediaServerDetecting.
  ///
  /// In en, this message translates to:
  /// **'Detecting…'**
  String get mediaServerDetecting;

  /// No description provided for @mediaServerTypeLabel.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get mediaServerTypeLabel;

  /// mediaServerDetectedAs
  ///
  /// In en, this message translates to:
  /// **'Detected: {name}'**
  String mediaServerDetectedAs(Object name);

  /// No description provided for @mediaServerManualTypeHint.
  ///
  /// In en, this message translates to:
  /// **'Detection failed? Pick the type manually and sign in.'**
  String get mediaServerManualTypeHint;

  /// No description provided for @mediaServerUsernameLabel.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get mediaServerUsernameLabel;

  /// No description provided for @mediaServerPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get mediaServerPasswordLabel;

  /// No description provided for @mediaServerLogin.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get mediaServerLogin;

  /// No description provided for @mediaServerLoggingIn.
  ///
  /// In en, this message translates to:
  /// **'Signing in…'**
  String get mediaServerLoggingIn;

  /// No description provided for @mediaServerNotLoggedIn.
  ///
  /// In en, this message translates to:
  /// **'Not signed in'**
  String get mediaServerNotLoggedIn;

  /// mediaServerLoggedInAs
  ///
  /// In en, this message translates to:
  /// **'Account: {user}'**
  String mediaServerLoggedInAs(Object user);

  /// No description provided for @mediaServerStatusOnline.
  ///
  /// In en, this message translates to:
  /// **'Online'**
  String get mediaServerStatusOnline;

  /// No description provided for @mediaServerStatusOffline.
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get mediaServerStatusOffline;

  /// No description provided for @mediaServerStatusNeedRelogin.
  ///
  /// In en, this message translates to:
  /// **'Re-login required'**
  String get mediaServerStatusNeedRelogin;

  /// No description provided for @mediaServerStatusChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking…'**
  String get mediaServerStatusChecking;

  /// No description provided for @mediaServerRename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get mediaServerRename;

  /// No description provided for @mediaServerRenameTitle.
  ///
  /// In en, this message translates to:
  /// **'Rename server'**
  String get mediaServerRenameTitle;

  /// No description provided for @mediaServerRelogin.
  ///
  /// In en, this message translates to:
  /// **'Re-login'**
  String get mediaServerRelogin;

  /// mediaServerReloginTitle
  ///
  /// In en, this message translates to:
  /// **'Re-login to \"{name}\"'**
  String mediaServerReloginTitle(Object name);

  /// No description provided for @mediaServerDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get mediaServerDelete;

  /// No description provided for @mediaServerDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete server'**
  String get mediaServerDeleteTitle;

  /// mediaServerDeleteBody
  ///
  /// In en, this message translates to:
  /// **'This removes the local configuration and credentials for \"{name}\". Your server\'s libraries and watch progress are not affected.'**
  String mediaServerDeleteBody(Object name);

  /// No description provided for @mediaServerEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No servers yet'**
  String get mediaServerEmptyTitle;

  /// No description provided for @mediaServerEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Supports Emby and Jellyfin. Enter a LAN or reverse-proxy address, sign in, then browse and play.'**
  String get mediaServerEmptyHint;

  /// mediaServerOperationFailed
  ///
  /// In en, this message translates to:
  /// **'Operation failed: {error}'**
  String mediaServerOperationFailed(Object error);

  /// No description provided for @mediaServerAddressRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter a server address first'**
  String get mediaServerAddressRequired;

  /// No description provided for @mediaServerCredentialsRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter a username and password'**
  String get mediaServerCredentialsRequired;

  /// No description provided for @mediaServerHomeResume.
  ///
  /// In en, this message translates to:
  /// **'Continue watching'**
  String get mediaServerHomeResume;

  /// No description provided for @mediaServerHomeLatest.
  ///
  /// In en, this message translates to:
  /// **'Latest additions'**
  String get mediaServerHomeLatest;

  /// No description provided for @mediaServerHomeLibraries.
  ///
  /// In en, this message translates to:
  /// **'Libraries'**
  String get mediaServerHomeLibraries;

  /// No description provided for @mediaServerUnsupportedLibraries.
  ///
  /// In en, this message translates to:
  /// **'Music / photo and other library types are not supported yet and are hidden.'**
  String get mediaServerUnsupportedLibraries;

  /// No description provided for @mediaServerRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get mediaServerRetry;

  /// mediaServerLoadFailed
  ///
  /// In en, this message translates to:
  /// **'Failed to load: {error}'**
  String mediaServerLoadFailed(Object error);

  /// No description provided for @mediaServerSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search within server'**
  String get mediaServerSearchHint;

  /// No description provided for @mediaServerNoResults.
  ///
  /// In en, this message translates to:
  /// **'No results'**
  String get mediaServerNoResults;

  /// No description provided for @mediaServerPlay.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get mediaServerPlay;

  /// No description provided for @mediaServerResumePlay.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get mediaServerResumePlay;

  /// No description provided for @mediaServerPlayFromStart.
  ///
  /// In en, this message translates to:
  /// **'Play from start'**
  String get mediaServerPlayFromStart;

  /// No description provided for @mediaServerTypeSeries.
  ///
  /// In en, this message translates to:
  /// **'Series'**
  String get mediaServerTypeSeries;

  /// No description provided for @mediaServerPgsSubtitleWarn.
  ///
  /// In en, this message translates to:
  /// **'Graphical subtitles in this episode require transcoding (unsupported).'**
  String get mediaServerPgsSubtitleWarn;

  /// No description provided for @mediaServerTranscodeRequired.
  ///
  /// In en, this message translates to:
  /// **'This format requires transcoding (unsupported).'**
  String get mediaServerTranscodeRequired;

  /// mediaServerRuntimeMinutes
  ///
  /// In en, this message translates to:
  /// **'{m} min'**
  String mediaServerRuntimeMinutes(Object m);

  /// mediaServerRuntimeHoursMinutes
  ///
  /// In en, this message translates to:
  /// **'{h} h {m} min'**
  String mediaServerRuntimeHoursMinutes(Object h, Object m);

  /// No description provided for @mediaServerGoAdd.
  ///
  /// In en, this message translates to:
  /// **'Add a server'**
  String get mediaServerGoAdd;

  /// No description provided for @mediaServerCredentialsWrong.
  ///
  /// In en, this message translates to:
  /// **'Incorrect username or password. Please check and try again.'**
  String get mediaServerCredentialsWrong;

  /// No description provided for @mediaServerManageAction.
  ///
  /// In en, this message translates to:
  /// **'Add or manage media servers'**
  String get mediaServerManageAction;

  /// No description provided for @mediaServerConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting to server…'**
  String get mediaServerConnecting;

  /// No description provided for @mediaServerBlockedByChallenge.
  ///
  /// In en, this message translates to:
  /// **'Blocked by the server\'s protection (Cloudflare challenge). Open the server address in a browser to verify once, or ask the admin to exempt API paths'**
  String get mediaServerBlockedByChallenge;

  /// No description provided for @mediaServerUnreachable.
  ///
  /// In en, this message translates to:
  /// **'Cannot reach the media server (network error or temporary rate limit). Try again later'**
  String get mediaServerUnreachable;

  /// No description provided for @mediaServerBitrateTier.
  ///
  /// In en, this message translates to:
  /// **'Bitrate tier'**
  String get mediaServerBitrateTier;

  /// No description provided for @mediaServerBitrateAuto.
  ///
  /// In en, this message translates to:
  /// **'Auto (server decides)'**
  String get mediaServerBitrateAuto;

  /// No description provided for @mediaServerBitrateOriginal.
  ///
  /// In en, this message translates to:
  /// **'Original (direct play only)'**
  String get mediaServerBitrateOriginal;

  /// No description provided for @mediaServerBitrate720p.
  ///
  /// In en, this message translates to:
  /// **'720p cap'**
  String get mediaServerBitrate720p;

  /// No description provided for @mediaServerTranscodingNotice.
  ///
  /// In en, this message translates to:
  /// **'Direct play not supported for this format, transcoding instead'**
  String get mediaServerTranscodingNotice;

  /// No description provided for @mediaServerOriginalNeedsDirect.
  ///
  /// In en, this message translates to:
  /// **'Original tier requires direct play, which this format does not support; pick another bitrate tier'**
  String get mediaServerOriginalNeedsDirect;

  /// No description provided for @mediaServerAudioTrack.
  ///
  /// In en, this message translates to:
  /// **'Audio track'**
  String get mediaServerAudioTrack;

  /// No description provided for @mediaServerFavorites.
  ///
  /// In en, this message translates to:
  /// **'My favorites'**
  String get mediaServerFavorites;

  /// No description provided for @mediaServerNextUp.
  ///
  /// In en, this message translates to:
  /// **'Next up'**
  String get mediaServerNextUp;

  /// No description provided for @mediaServerFavorite.
  ///
  /// In en, this message translates to:
  /// **'Favorite'**
  String get mediaServerFavorite;

  /// No description provided for @mediaServerFavoriteAdded.
  ///
  /// In en, this message translates to:
  /// **'Added to favorites'**
  String get mediaServerFavoriteAdded;

  /// No description provided for @mediaServerFavoriteRemoved.
  ///
  /// In en, this message translates to:
  /// **'Removed from favorites'**
  String get mediaServerFavoriteRemoved;

  /// No description provided for @mediaServerMarkWatched.
  ///
  /// In en, this message translates to:
  /// **'Mark watched'**
  String get mediaServerMarkWatched;

  /// No description provided for @mediaServerMarkUnwatched.
  ///
  /// In en, this message translates to:
  /// **'Mark unwatched'**
  String get mediaServerMarkUnwatched;

  /// No description provided for @mediaServerMarkAllWatched.
  ///
  /// In en, this message translates to:
  /// **'Mark all watched'**
  String get mediaServerMarkAllWatched;

  /// mediaServerRemaining
  ///
  /// In en, this message translates to:
  /// **'{m} min left'**
  String mediaServerRemaining(Object m);

  /// No description provided for @mediaServerFilterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get mediaServerFilterAll;

  /// No description provided for @mediaServerFilterUnwatched.
  ///
  /// In en, this message translates to:
  /// **'Unwatched'**
  String get mediaServerFilterUnwatched;

  /// No description provided for @mediaServerFilterWatched.
  ///
  /// In en, this message translates to:
  /// **'Watched'**
  String get mediaServerFilterWatched;

  /// No description provided for @mediaServerFilterGenre.
  ///
  /// In en, this message translates to:
  /// **'Genre'**
  String get mediaServerFilterGenre;

  /// No description provided for @mediaServerFilterYear.
  ///
  /// In en, this message translates to:
  /// **'Year'**
  String get mediaServerFilterYear;

  /// No description provided for @mediaServerSort.
  ///
  /// In en, this message translates to:
  /// **'Sort'**
  String get mediaServerSort;

  /// No description provided for @mediaServerSortByName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get mediaServerSortByName;

  /// No description provided for @mediaServerSortByYear.
  ///
  /// In en, this message translates to:
  /// **'Year'**
  String get mediaServerSortByYear;

  /// No description provided for @mediaServerSortByAdded.
  ///
  /// In en, this message translates to:
  /// **'Date added'**
  String get mediaServerSortByAdded;

  /// No description provided for @mediaServerAddresses.
  ///
  /// In en, this message translates to:
  /// **'Server addresses'**
  String get mediaServerAddresses;

  /// No description provided for @mediaServerAddressesHint.
  ///
  /// In en, this message translates to:
  /// **'One address per line; the first reachable one becomes active (LAN & WAN can coexist)'**
  String get mediaServerAddressesHint;

  /// No description provided for @mediaServerAddressSaved.
  ///
  /// In en, this message translates to:
  /// **'Addresses updated'**
  String get mediaServerAddressSaved;

  /// No description provided for @mediaServerTypeBoxSet.
  ///
  /// In en, this message translates to:
  /// **'Collection'**
  String get mediaServerTypeBoxSet;

  /// No description provided for @mediaServerStatsPlayMethod.
  ///
  /// In en, this message translates to:
  /// **'Play method'**
  String get mediaServerStatsPlayMethod;

  /// No description provided for @mediaServerPlayMethodDirect.
  ///
  /// In en, this message translates to:
  /// **'Direct play'**
  String get mediaServerPlayMethodDirect;

  /// No description provided for @mediaServerPlayMethodDirectStream.
  ///
  /// In en, this message translates to:
  /// **'Direct stream'**
  String get mediaServerPlayMethodDirectStream;

  /// No description provided for @mediaServerPlayMethodTranscode.
  ///
  /// In en, this message translates to:
  /// **'Transcoding'**
  String get mediaServerPlayMethodTranscode;

  /// No description provided for @mediaServerSearchHistory.
  ///
  /// In en, this message translates to:
  /// **'Search history'**
  String get mediaServerSearchHistory;

  /// No description provided for @mediaServerSearchHistoryClear.
  ///
  /// In en, this message translates to:
  /// **'Clear search history'**
  String get mediaServerSearchHistoryClear;

  /// No description provided for @bingTranslationTitle.
  ///
  /// In en, this message translates to:
  /// **'Bing free translation'**
  String get bingTranslationTitle;

  /// No description provided for @bingTranslationDesc.
  ///
  /// In en, this message translates to:
  /// **'No API key required; also powers titles, tags, summaries and comments'**
  String get bingTranslationDesc;

  /// No description provided for @bingTranslationEnable.
  ///
  /// In en, this message translates to:
  /// **'Enable Bing free translation'**
  String get bingTranslationEnable;

  /// No description provided for @bingTranslationEnableHint.
  ///
  /// In en, this message translates to:
  /// **'When off, novels and subtitles use AI only; auto translation on detail pages is disabled'**
  String get bingTranslationEnableHint;

  /// No description provided for @bingTranslationPriority.
  ///
  /// In en, this message translates to:
  /// **'Engine priority'**
  String get bingTranslationPriority;

  /// No description provided for @bingTranslationBingFirst.
  ///
  /// In en, this message translates to:
  /// **'Bing first'**
  String get bingTranslationBingFirst;

  /// No description provided for @bingTranslationAiFirst.
  ///
  /// In en, this message translates to:
  /// **'AI first'**
  String get bingTranslationAiFirst;

  /// No description provided for @bingTranslationAutoTitle.
  ///
  /// In en, this message translates to:
  /// **'Auto-translate titles'**
  String get bingTranslationAutoTitle;

  /// No description provided for @bingTranslationAutoTags.
  ///
  /// In en, this message translates to:
  /// **'Auto-translate tags'**
  String get bingTranslationAutoTags;

  /// No description provided for @bingTranslationAutoSummary.
  ///
  /// In en, this message translates to:
  /// **'Auto-translate summaries'**
  String get bingTranslationAutoSummary;

  /// No description provided for @bingTranslationAutoComments.
  ///
  /// In en, this message translates to:
  /// **'Auto-translate comments'**
  String get bingTranslationAutoComments;

  /// No description provided for @bingTranslationTest.
  ///
  /// In en, this message translates to:
  /// **'Test Bing connection'**
  String get bingTranslationTest;

  /// No description provided for @bingTranslationTesting.
  ///
  /// In en, this message translates to:
  /// **'Testing...'**
  String get bingTranslationTesting;

  /// No description provided for @bingTranslationTestOk.
  ///
  /// In en, this message translates to:
  /// **'Bing translation is available'**
  String get bingTranslationTestOk;

  /// No description provided for @bingTranslationTestFail.
  ///
  /// In en, this message translates to:
  /// **'Bing is unavailable right now; AI fallback will be used'**
  String get bingTranslationTestFail;

  /// No description provided for @translationNotNeeded.
  ///
  /// In en, this message translates to:
  /// **'Already in the target language; no translation needed'**
  String get translationNotNeeded;

  /// No description provided for @bingTranslationPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Text is sent to Microsoft\'s translation service. This is an unofficial endpoint and may change or stop working at any time.'**
  String get bingTranslationPrivacy;

  /// No description provided for @translationCacheUiText.
  ///
  /// In en, this message translates to:
  /// **'Detail page & comment translation'**
  String get translationCacheUiText;

  /// No description provided for @storageLocationAppPrivate.
  ///
  /// In en, this message translates to:
  /// **'App private folder'**
  String get storageLocationAppPrivate;

  /// No description provided for @storageLocationAppPrivateHint.
  ///
  /// In en, this message translates to:
  /// **'Inside the app; deleted with the app'**
  String get storageLocationAppPrivateHint;

  /// No description provided for @storageLocationSystemDownloads.
  ///
  /// In en, this message translates to:
  /// **'System Downloads folder'**
  String get storageLocationSystemDownloads;

  /// No description provided for @storageLocationSystemDownloadsHint.
  ///
  /// In en, this message translates to:
  /// **'Visible in Files and kept after uninstall'**
  String get storageLocationSystemDownloadsHint;

  /// No description provided for @storageLocationSystemScreenshots.
  ///
  /// In en, this message translates to:
  /// **'System Downloads / Screenshots'**
  String get storageLocationSystemScreenshots;

  /// No description provided for @storageLocationSystemScreenshotsHint.
  ///
  /// In en, this message translates to:
  /// **'Visible in Files and kept after uninstall'**
  String get storageLocationSystemScreenshotsHint;

  /// TTS cast sheet string
  ///
  /// In en, this message translates to:
  /// **'Auto-continue chapters'**
  String get ttsAutoNext;

  /// TTS cast sheet string
  ///
  /// In en, this message translates to:
  /// **'Load and read the next chapter automatically when one finishes'**
  String get ttsAutoNextDesc;

  /// TTS cast sheet string
  ///
  /// In en, this message translates to:
  /// **'Characters & voices'**
  String get ttsCastTitle;

  /// TTS cast sheet string
  ///
  /// In en, this message translates to:
  /// **'Assign different voices per character; unassigned roles fall back to narrator/gender slots'**
  String get ttsCastSubtitle;

  /// TTS cast sheet string
  ///
  /// In en, this message translates to:
  /// **'Online voice fallback (HTTP TTS)'**
  String get ttsCastHttpSlots;

  /// TTS cast sheet string
  ///
  /// In en, this message translates to:
  /// **'System voices (device engine)'**
  String get ttsCastSystemSlots;

  /// TTS cast sheet string
  ///
  /// In en, this message translates to:
  /// **'Narrator voice'**
  String get ttsCastNarratorVoice;

  /// TTS cast sheet string
  ///
  /// In en, this message translates to:
  /// **'Male fallback voice'**
  String get ttsCastMaleVoice;

  /// TTS cast sheet string
  ///
  /// In en, this message translates to:
  /// **'Female fallback voice'**
  String get ttsCastFemaleVoice;

  /// TTS cast sheet string
  ///
  /// In en, this message translates to:
  /// **'Online voice ID (HTTP TTS)'**
  String get ttsCastHttpVoice;

  /// TTS cast sheet string
  ///
  /// In en, this message translates to:
  /// **'System voice'**
  String get ttsCastSystemVoice;

  /// TTS cast sheet string
  ///
  /// In en, this message translates to:
  /// **'Engine default'**
  String get ttsCastEngineDefault;

  /// TTS cast sheet string
  ///
  /// In en, this message translates to:
  /// **'Characters in this book'**
  String get ttsCastCharacters;

  /// TTS cast sheet string
  ///
  /// In en, this message translates to:
  /// **'No character cards yet. AI identifies speakers while reading; you can also add manually.'**
  String get ttsCastEmpty;

  /// TTS cast sheet string
  ///
  /// In en, this message translates to:
  /// **'Add character'**
  String get ttsCastAddRole;

  /// TTS cast sheet string
  ///
  /// In en, this message translates to:
  /// **'Edit character'**
  String get ttsCastEditRole;

  /// TTS cast sheet string
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get ttsCastRoleName;

  /// TTS cast sheet string
  ///
  /// In en, this message translates to:
  /// **'Aliases (optional)'**
  String get ttsCastAliases;

  /// TTS cast sheet string
  ///
  /// In en, this message translates to:
  /// **'Separate multiple aliases with commas'**
  String get ttsCastAliasesHint;

  /// TTS cast sheet string
  ///
  /// In en, this message translates to:
  /// **'Male'**
  String get ttsCastMale;

  /// TTS cast sheet string
  ///
  /// In en, this message translates to:
  /// **'Female'**
  String get ttsCastFemale;

  /// TTS cast sheet string
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get ttsCastGenderUnknown;

  /// TTS cast sheet string
  ///
  /// In en, this message translates to:
  /// **'Enable'**
  String get ttsCastEnable;

  /// TTS cast sheet string
  ///
  /// In en, this message translates to:
  /// **'Disable'**
  String get ttsCastDisable;

  /// TTS cast sheet string
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get ttsCastDelete;

  /// TTS cast sheet string
  ///
  /// In en, this message translates to:
  /// **'AI attribution for this chapter'**
  String get ttsCastAiRelabel;

  /// TTS cast sheet string
  ///
  /// In en, this message translates to:
  /// **'AI attributing…'**
  String get ttsCastAiRunning;

  /// AI 归因完成句数提示
  ///
  /// In en, this message translates to:
  /// **'AI attribution done: {count} lines labeled'**
  String ttsCastAiDone(int count);

  /// TTS cast sheet string
  ///
  /// In en, this message translates to:
  /// **'No AI endpoint configured. Set the novel-overview or default endpoint in Settings → AI first.'**
  String get ttsCastAiNoConfig;

  /// TTS cast sheet string
  ///
  /// In en, this message translates to:
  /// **'AI attribution failed; local results kept'**
  String get ttsCastAiFailed;

  /// TTS cast sheet string
  ///
  /// In en, this message translates to:
  /// **'Global fallback map (name=voiceId, one per line); per-book setup lives in the reader\'s Characters & voices panel'**
  String get ttsCastVoiceMapHint;

  /// TTS audio cache settings entry
  ///
  /// In en, this message translates to:
  /// **'Clear TTS audio cache'**
  String get ttsCacheClear;

  /// TTS audio cache settings entry
  ///
  /// In en, this message translates to:
  /// **'No cached audio'**
  String get ttsCacheEmpty;

  /// TTS audio cache settings entry
  ///
  /// In en, this message translates to:
  /// **'{count} audio clips cached'**
  String ttsCacheCount(int count);

  /// TTS audio cache settings entry
  ///
  /// In en, this message translates to:
  /// **'Cleared {count} TTS audio clips'**
  String ttsCacheCleared(int count);

  /// Home screen widget: number of saved works (real new-chapter count comes later)
  ///
  /// In en, this message translates to:
  /// **'Updates · {count} saved'**
  String homeWidgetUpdates(int count);

  /// Home screen widget: no saved works yet
  ///
  /// In en, this message translates to:
  /// **'Updates · nothing saved'**
  String get homeWidgetUpdatesIdle;

  /// Home screen widget: active download tasks and overall percentage
  ///
  /// In en, this message translates to:
  /// **'Downloads · {count} at {percent}%'**
  String homeWidgetDownloads(int count, int percent);

  /// Home screen widget: no active download tasks
  ///
  /// In en, this message translates to:
  /// **'Downloads · idle'**
  String get homeWidgetDownloadsIdle;

  /// Home screen widget: total reading/watching minutes in the last 7 days
  ///
  /// In en, this message translates to:
  /// **'This week · {minutes} min'**
  String homeWidgetWeek(int minutes);

  /// Home screen widget: no activity in the last 7 days
  ///
  /// In en, this message translates to:
  /// **'This week · not started'**
  String get homeWidgetWeekIdle;

  /// Home screen widget empty state title
  ///
  /// In en, this message translates to:
  /// **'Nothing watched yet'**
  String get homeWidgetEmptyTitle;

  /// Home screen widget empty state hint
  ///
  /// In en, this message translates to:
  /// **'Open NexHub and pick something'**
  String get homeWidgetEmptyHint;

  /// Home screen widget section label: continue watching
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get homeWidgetContinueLabel;

  /// Home screen widget section label: updates
  ///
  /// In en, this message translates to:
  /// **'Updates'**
  String get homeWidgetUpdatesLabel;

  /// Home screen widget section label: downloads
  ///
  /// In en, this message translates to:
  /// **'Downloads'**
  String get homeWidgetDownloadsLabel;

  /// Home screen widget section label: stats
  ///
  /// In en, this message translates to:
  /// **'Stats'**
  String get homeWidgetStatsLabel;

  /// Home screen widget: real reading progress for comics/novels
  ///
  /// In en, this message translates to:
  /// **'Ch. {index} of {total}'**
  String homeWidgetChapterProgress(int index, int total);

  /// Home screen widget: reading progress when total is unknown
  ///
  /// In en, this message translates to:
  /// **'Ch. {index}'**
  String homeWidgetChapterProgressOpen(int index);

  /// Home screen widget: real watching progress for video
  ///
  /// In en, this message translates to:
  /// **'Ep. {index} · {minutes} min watched'**
  String homeWidgetEpisodeProgress(int index, int minutes);

  /// Home screen widget: watching progress without position record
  ///
  /// In en, this message translates to:
  /// **'Ep. {index}'**
  String homeWidgetEpisodeWatched(int index);

  /// Home screen widget: today's reading/watching minutes
  ///
  /// In en, this message translates to:
  /// **'Today · {minutes} min'**
  String homeWidgetToday(int minutes);

  /// Home screen widget: no activity today
  ///
  /// In en, this message translates to:
  /// **'Today · not started'**
  String get homeWidgetTodayIdle;

  /// Home screen widget: active days in last 7 days and current streak
  ///
  /// In en, this message translates to:
  /// **'{active} days active · {streak} streak'**
  String homeWidgetStreak(int active, int streak);

  /// Settings category: home screen widgets
  ///
  /// In en, this message translates to:
  /// **'Home widgets'**
  String get settingsCatWidget;

  /// Settings category description: home screen widgets
  ///
  /// In en, this message translates to:
  /// **'Background, blur and record count'**
  String get settingsCatWidgetDesc;

  /// Widget settings group: background
  ///
  /// In en, this message translates to:
  /// **'Background'**
  String get widgetBackgroundSection;

  /// Widget background source: cover art
  ///
  /// In en, this message translates to:
  /// **'Cover art'**
  String get widgetBgCover;

  /// Widget background source description: cover art
  ///
  /// In en, this message translates to:
  /// **'Blur the cover of what you last watched'**
  String get widgetBgCoverDesc;

  /// Widget background source: theme color
  ///
  /// In en, this message translates to:
  /// **'Theme color'**
  String get widgetBgTheme;

  /// Widget background source description: theme color
  ///
  /// In en, this message translates to:
  /// **'Gradient based on the current theme color'**
  String get widgetBgThemeDesc;

  /// Widget background source: none
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get widgetBgNone;

  /// Widget background source description: none
  ///
  /// In en, this message translates to:
  /// **'Keep only the card base color'**
  String get widgetBgNoneDesc;

  /// Widget settings group: appearance
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get widgetTuningSection;

  /// Widget background blur strength
  ///
  /// In en, this message translates to:
  /// **'Blur strength'**
  String get widgetBlurStrength;

  /// Widget background opacity
  ///
  /// In en, this message translates to:
  /// **'Opacity'**
  String get widgetOpacity;

  /// Widget settings group: record count
  ///
  /// In en, this message translates to:
  /// **'Records'**
  String get widgetRecordsSection;

  /// Widget: how many continue-watching items to keep
  ///
  /// In en, this message translates to:
  /// **'Continue-watching items'**
  String get widgetContinueLimit;

  /// Widget: current continue-watching item count
  ///
  /// In en, this message translates to:
  /// **'Show {count} items'**
  String widgetContinueLimitDesc(int count);

  /// Widget: platform limitation title
  ///
  /// In en, this message translates to:
  /// **'Platform limit'**
  String get widgetLimitNote;

  /// Widget: platform limitation description
  ///
  /// In en, this message translates to:
  /// **'Widgets show 4–5 items depending on platform'**
  String get widgetLimitNoteDesc;

  /// Heatmap widget: range caption
  ///
  /// In en, this message translates to:
  /// **'This month'**
  String get widgetHeatmapCaption;

  /// Stats widget: duration unit
  ///
  /// In en, this message translates to:
  /// **'min'**
  String get widgetMinuteUnit;

  /// Streak widget: title
  ///
  /// In en, this message translates to:
  /// **'Streak'**
  String get widgetStreakCaption;

  /// 桌面卡片：统计补充信息
  ///
  /// In en, this message translates to:
  /// **'{hours} h total'**
  String widgetLifetimeHours(int hours);

  /// 桌面卡片：统计补充信息
  ///
  /// In en, this message translates to:
  /// **'{count} sessions this week'**
  String widgetWeekSessions(int count);

  /// 桌面卡片：趋势文案
  ///
  /// In en, this message translates to:
  /// **'+{percent}%'**
  String widgetTrendUp(int percent);

  /// 桌面卡片：趋势文案
  ///
  /// In en, this message translates to:
  /// **'-{percent}%'**
  String widgetTrendDown(int percent);

  /// 桌面卡片：趋势文案
  ///
  /// In en, this message translates to:
  /// **'flat'**
  String get widgetTrendFlat;

  /// 桌面卡片：趋势文案
  ///
  /// In en, this message translates to:
  /// **'new'**
  String get widgetTrendNew;
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
      'that was used.');
}
