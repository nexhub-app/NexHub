// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'NexHub';

  @override
  String get navBrowse => 'Browse';

  @override
  String get navNovel => 'Novel';

  @override
  String get navMedia => 'Media';

  @override
  String get navComic => 'Comic';

  @override
  String get navSettings => 'Settings';

  @override
  String get homeTitle => 'Browse';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsTagline => 'Craft your personal media space';

  @override
  String get sourceManagementTitle => 'Source Management';

  @override
  String get sourceManagementDesc =>
      'Import, enable and reorder content sources';

  @override
  String get downloadSettingsTitle => 'Download';

  @override
  String get downloadManagementTitle => 'Download Management';

  @override
  String get aboutTitle => 'About';

  @override
  String get themeTitle => 'Appearance';

  @override
  String get tabLibrary => 'Library';

  @override
  String get tabMediaLibrary => 'Media Library';

  @override
  String get tabOnline => 'Online';

  @override
  String get tabSubscribe => 'Subscribe';

  @override
  String get tabSources => 'Sources';

  @override
  String get browseLocalFiles => 'Local Files';

  @override
  String get browseLocalFilesSubtitle =>
      'Browse local novels, videos and comics';

  @override
  String get browseNetworkFiles => 'Network Files';

  @override
  String get browseNetworkFilesSubtitle => 'Browse HTTP file servers';

  @override
  String get browseWebScrape => 'Web Scrape';

  @override
  String get browseWebScrapeSubtitle =>
      'Extract novels, comics, videos or articles from the web';

  @override
  String get browseRss => 'RSS Subscriptions';

  @override
  String get browseRssSubtitle => 'Manage and browse RSS feeds';

  @override
  String get browseSniff => 'Sniffer';

  @override
  String get browseSniffSubtitle => 'Sniff web videos and play them in-app';

  @override
  String get subTabLocal => 'Local';

  @override
  String get subTabHistory => 'History';

  @override
  String get subTabFavorite => 'Favorites';

  @override
  String get filter => 'Filter';

  @override
  String get filterTitle => 'Filter';

  @override
  String get sortBy => 'Sort by';

  @override
  String get sortRecent => 'Recent';

  @override
  String get sortTitle => 'Title';

  @override
  String get sortAuthor => 'Author';

  @override
  String get sortLatestChapter => 'Latest chapter';

  @override
  String get sortTitleZh => 'Chinese title';

  @override
  String get sortManual => 'Manual';

  @override
  String get sortDirector => 'Director';

  @override
  String get sortActors => 'Cast';

  @override
  String get sortLatestUpdate => 'Latest';

  @override
  String get sortLatestMangaChapter => 'Latest chapter';

  @override
  String get filterByStatus => 'Status';

  @override
  String get filterByCategory => 'Category';

  @override
  String get filterByProgress => 'Progress';

  @override
  String get allLabel => 'All';

  @override
  String get progressReading => 'Reading';

  @override
  String get progressNotStarted => 'Not started';

  @override
  String get filterReset => 'Reset';

  @override
  String get filterApply => 'Apply';

  @override
  String get filterSelectedPrefix => 'Selected';

  @override
  String get play => 'Play';

  @override
  String get readChapter => 'Read';

  @override
  String episodesWithLine(Object line) {
    return 'Episodes · $line';
  }

  @override
  String get recommendations => 'You may also like';

  @override
  String episodeN(Object n) {
    return 'Episode $n';
  }

  @override
  String get cancel => 'Cancel';

  @override
  String get confirm => 'Confirm';

  @override
  String get delete => 'Delete';

  @override
  String get save => 'Save';

  @override
  String get import => 'Import';

  @override
  String get export => 'Export';

  @override
  String get close => 'Close';

  @override
  String get search => 'Search';

  @override
  String get retry => 'Retry';

  @override
  String get ok => 'OK';

  @override
  String get next => 'Next';

  @override
  String get previous => 'Previous';

  @override
  String get emptyLibrary => 'Your library is empty';

  @override
  String get emptySearch => 'No results found';

  @override
  String get emptyDownloads => 'No downloads yet';

  @override
  String get emptySources => 'No sources added';

  @override
  String get emptyBrowse => 'Nothing here';

  @override
  String get emptyLocalNovel => 'No local novels';

  @override
  String get emptyLocalMedia => 'No local media';

  @override
  String get emptyLocalComic => 'No local comics';

  @override
  String get emptyLocalNovelAction => 'Import novel';

  @override
  String get emptyLocalMediaAction => 'Import media';

  @override
  String get emptyLocalComicAction => 'Import comic';

  @override
  String get loading => 'Loading…';

  @override
  String get noResults => 'No results';

  @override
  String get loadFailed => 'Failed to load';

  @override
  String chapterLoadPartial(Object count) {
    return 'Table of contents incomplete — showing $count chapters (network may be unstable)';
  }

  @override
  String get noMoreResults => 'No more results';

  @override
  String get authorColon => 'Author: ';

  @override
  String get tagColon => 'Tag: ';

  @override
  String get searchFailed => 'Search failed, please retry';

  @override
  String get searching => 'Searching…';

  @override
  String updatedAt(Object time) {
    return 'Updated $time';
  }

  @override
  String get statusOngoing => 'Ongoing';

  @override
  String get statusCompleted => 'Completed';

  @override
  String get deprecated => 'Deprecated';

  @override
  String get mirrorSettings => 'Mirror & stealth settings';

  @override
  String get stealthMode => 'Stealth mode';

  @override
  String get gridView => 'Grid view';

  @override
  String get listView => 'List view';

  @override
  String get toggleLayout => 'Toggle layout';

  @override
  String get all => 'All';

  @override
  String get emptyCategory => 'No content in this category';

  @override
  String get emptyContent => 'No content yet';

  @override
  String get contentExpired => 'Content expired, please search again';

  @override
  String get sourceNotFound =>
      'Source unavailable, please switch source or search again';

  @override
  String get onlineBrowse => 'Online Browse';

  @override
  String get switchSource => 'Switch source';

  @override
  String get searchSourceHint => 'Search sources';

  @override
  String get refreshList => 'Refresh list';

  @override
  String get goToVerification => 'Verify now';

  @override
  String get openSourceWebsite => 'Open source site';

  @override
  String get errorGeneric => 'Something went wrong';

  @override
  String get errorNetwork => 'Network error, please try again';

  @override
  String get errorParse => 'Failed to parse content';

  @override
  String get errorVerification =>
      'Verification required, please complete the challenge';

  @override
  String get verificationFailed => 'Verification failed, please retry later';

  @override
  String get errorVideoExpired => 'Video link expired, please retry';

  @override
  String get danmaku => 'Danmaku';

  @override
  String get danmakuSend => 'Send danmaku';

  @override
  String get danmakuSendHint => 'Enter danmaku text';

  @override
  String get danmakuUploadSuccess => 'Danmaku posted';

  @override
  String danmakuUploadFailed(String error) {
    return 'Failed to post danmaku: $error';
  }

  @override
  String get danmakuSendNoEpisode =>
      'No matched danmaku episode; shown locally only';

  @override
  String get danmakuSendTimeInvalid =>
      'Position beyond video duration; shown locally only';

  @override
  String get danmakuLoginTitle => 'Sign in to DanDanPlay';

  @override
  String get danmakuLoginRequiredHint =>
      'Sign in to your DanDanPlay account to post danmaku';

  @override
  String get danmakuUsername => 'Username';

  @override
  String get danmakuPassword => 'Password';

  @override
  String get danmakuLoginAction => 'Sign in';

  @override
  String get danmakuLoginEmptyFields => 'Please enter username and password';

  @override
  String get danmakuAccountSection => 'DanDanPlay Account';

  @override
  String danmakuAccountLoggedInAs(String name) {
    return 'Signed in as $name';
  }

  @override
  String get dandanplayLoggedOut => 'Signed out of DanDanPlay';

  @override
  String get dandanplayAppNotConfigured =>
      'DanDanPlay app is not configured; login unavailable';

  @override
  String get dandanplayLoginTab => 'Sign in';

  @override
  String get dandanplayRegisterTab => 'Register';

  @override
  String get dandanplayEmail => 'Email';

  @override
  String get dandanplayNickname => 'Nickname';

  @override
  String get dandanplayRegisterAction => 'Register & sign in';

  @override
  String get dandanplayRegisterSuccess => 'Registered and signed in';

  @override
  String get dandanplayRegisterEmptyFields =>
      'Please enter username, password and email';

  @override
  String get dandanplayRegisterEmailInvalid => 'Invalid email format';

  @override
  String get danmakuStyle => 'Danmaku style';

  @override
  String get danmakuStyleScroll => 'Scroll';

  @override
  String get danmakuStyleTop => 'Top';

  @override
  String get danmakuStyleBottom => 'Bottom';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get themeSystem => 'System';

  @override
  String get useMonet => 'Use dynamic color (Monet)';

  @override
  String get glassEffectTitle => 'Frosted glass bars';

  @override
  String get glassEffectDesc =>
      'Translucent blurred nav rail/bar with content scrolling behind; turn off on low-end devices';

  @override
  String get sourceDragSplitTitle => 'Reorder split effect';

  @override
  String get sourceDragSplitDesc =>
      'Split the source card with live corner updates while reordering; off keeps the card intact (simpler effect)';

  @override
  String get statusBarTapToTopTitle => 'Tap status bar to top';

  @override
  String get statusBarTapToTopDesc =>
      'On HarmonyOS, tap the system status bar to quickly scroll the current page back to the top';

  @override
  String get glassBlurStrength => 'Blur strength';

  @override
  String get glassBarOpacity => 'Bar opacity';

  @override
  String get customColor => 'Custom Color';

  @override
  String get presetColor => 'Preset colors';

  @override
  String get paletteStyleTitle => 'Palette style';

  @override
  String get paletteStyleDesc => 'Color algorithm variant for the current seed';

  @override
  String get paletteStyleTonalSpot => 'Tonal spot';

  @override
  String get paletteStyleFidelity => 'Fidelity';

  @override
  String get paletteStyleContent => 'Content';

  @override
  String get paletteStyleNeutral => 'Neutral';

  @override
  String get paletteStyleMonochrome => 'Monochrome';

  @override
  String get paletteStyleVibrant => 'Vibrant';

  @override
  String get paletteStyleExpressive => 'Expressive';

  @override
  String get paletteStyleRainbow => 'Rainbow';

  @override
  String get paletteStyleFruitSalad => 'Fruit salad';

  @override
  String get appearanceThemeMode => 'Theme mode';

  @override
  String get appearanceThemeSection => 'Theme';

  @override
  String get appearanceColorsSection => 'Colors';

  @override
  String get appearanceFontSection => 'Font';

  @override
  String get appearanceFont => 'App font';

  @override
  String get appFontFollowSystem => 'Follow system';

  @override
  String get appFontFollowSystemDesc => 'Use the system default font';

  @override
  String get appFontPreviewSample => 'Preview: Aa Bb, 123';

  @override
  String get appFontCustomDesc => 'Custom font';

  @override
  String get appFontCustomImport => 'Import font file (.ttf / .otf)';

  @override
  String get appFontClearCustom => 'Remove custom font';

  @override
  String get appFontLoadFailed =>
      'Couldn\'t load that font. Try another .ttf / .otf file';

  @override
  String get appearanceStartupSection => 'Launch & Display';

  @override
  String get heroSettingsTitle => 'Hero Images';

  @override
  String get appearanceHeroSection => 'Background';

  @override
  String get heroEmptyHint =>
      'Add a few images to cycle at the top of Settings';

  @override
  String get heroAddFromUrl => 'Add from URL';

  @override
  String get heroAddFromDevice => 'Pick from device';

  @override
  String get heroUrlDialogTitle => 'Add image URL';

  @override
  String get heroUrlFieldHint => 'Image address (https://... or file://...)';

  @override
  String get heroRemoveTooltip => 'Remove';

  @override
  String get deleteConfirmTitle => 'Delete confirmation';

  @override
  String deleteConfirmContent(String name) {
    return 'Delete \"$name\"? This cannot be undone.';
  }

  @override
  String get deleteRecordOnly => 'Delete record only';

  @override
  String get deleteRecordAndFile => 'Delete record and files';

  @override
  String get addSource => 'Add source';

  @override
  String get importSource => 'Import source';

  @override
  String get exportSource => 'Export source';

  @override
  String get aboutDescription =>
      'NexHub — a four-in-one media aggregator (anime / manga / novel / film).';

  @override
  String get videoSourceLine => 'Line';

  @override
  String get defaultLine => 'Default';

  @override
  String get errorWebView => 'WebView verification required';

  @override
  String get verifying => 'Verifying…';

  @override
  String get mirrorTest => 'Speed test';

  @override
  String get sourceHealthy => 'Healthy';

  @override
  String get resolveTimeout => 'Resolve timeout';

  @override
  String resolveFailed(Object message) {
    return 'Resolve failed: $message';
  }

  @override
  String get categories => 'Categories';

  @override
  String chapterN(Object n) {
    return 'Ch. $n';
  }

  @override
  String pageIndicator(Object cur, Object total) {
    return 'Page $cur / $total';
  }

  @override
  String readerDoublePageIndicator(Object first, Object last, Object total) {
    return '$first-$last / $total';
  }

  @override
  String get prevChapter => 'Prev chapter';

  @override
  String get nextChapter => 'Next chapter';

  @override
  String get readerLastChapterReached => 'Already at the last chapter';

  @override
  String get readerFirstChapterReached => 'Already at the first chapter';

  @override
  String readerNextChapterSkipped(Object title) {
    return 'Next chapter: $title';
  }

  @override
  String get readerNextChapterSkippedHint => 'Tap to jump now';

  @override
  String get readerSettings => 'Reader settings';

  @override
  String get readerMode => 'Reading mode';

  @override
  String get readerBackground => 'Background';

  @override
  String get readerOrientation => 'Orientation';

  @override
  String get readerTapZone => 'Tap zones';

  @override
  String get readerZoom => 'Double-tap zoom';

  @override
  String get noImages => 'No readable images in this chapter';

  @override
  String get preloading => 'Preloading next chapter…';

  @override
  String get readerModeSingleLTR => 'Single page (L→R)';

  @override
  String get readerModeSingleRTL => 'Single page (R→L)';

  @override
  String get readerModeSingleVertical => 'Single page (vertical)';

  @override
  String get readerModeWebtoon => 'Webtoon';

  @override
  String get readerModeWebtoonWithGap => 'Webtoon (with gap)';

  @override
  String get readerOrientationDefault => 'Default';

  @override
  String get readerOrientationSystem => 'Follow system';

  @override
  String get readerOrientationPortrait => 'Portrait';

  @override
  String get readerOrientationLandscape => 'Landscape';

  @override
  String get readerOrientationLockPortrait => 'Lock portrait';

  @override
  String get readerOrientationLockLandscape => 'Lock landscape';

  @override
  String get readerOrientationReversePortrait => 'Reverse portrait';

  @override
  String get readerBgBlack => 'Black';

  @override
  String get readerBgGray => 'Gray';

  @override
  String get readerBgDarkGray => 'Dark gray';

  @override
  String get readerBgEyeCare => 'Eye care';

  @override
  String get readerBgParchment => 'Parchment';

  @override
  String get readerBgWarmLinen => 'Warm linen';

  @override
  String get readerBgLightBrown => 'Light brown';

  @override
  String get readerBgBeanGreen => 'Bean green';

  @override
  String get readerBgMint => 'Mint';

  @override
  String get readerBgApricot => 'Apricot';

  @override
  String get readerBgGrayBlue => 'Gray blue';

  @override
  String get readerBgEInk => 'E-Ink paper';

  @override
  String get readerBgWhite => 'White';

  @override
  String get readerBgAuto => 'Auto';

  @override
  String get readerTapLeftRight => 'Left/Right';

  @override
  String get readerTapLShape => 'L-shape';

  @override
  String get readerTapKindle => 'Kindle';

  @override
  String get readerTapBothSides => 'Both sides';

  @override
  String get readerTapOff => 'Off';

  @override
  String get readerTapInvert => 'Tap flip';

  @override
  String get readerTapInvertNone => 'None';

  @override
  String get readerTapInvertLeftRight => 'Left/Right';

  @override
  String get readerTapInvertUpDown => 'Up/Down';

  @override
  String get readerTapInvertAll => 'All';

  @override
  String get readerSideMargin => 'Side margin';

  @override
  String get readerFlashEnabled => 'Page-turn flash';

  @override
  String get readerFlashTime => 'Flash duration';

  @override
  String get readerFlashInterval => 'Flash delay';

  @override
  String get readerFlashColor => 'Flash color';

  @override
  String get readerFlashBlack => 'Black';

  @override
  String get readerFlashWhite => 'White';

  @override
  String get readerFlashBlackWhite => 'Black→White';

  @override
  String get readerTapPreviewHint => 'Tap zone preview (live)';

  @override
  String get tapPreviewPrev => 'Prev page';

  @override
  String get tapPreviewNext => 'Next page';

  @override
  String get tapPreviewToggle => 'Toggle';

  @override
  String get filterInverted => 'Invert';

  @override
  String get favorite => 'Favorite';

  @override
  String get moreActions => 'More';

  @override
  String get demoNormal => 'Default view';

  @override
  String get demoEmpty => 'Show empty state';

  @override
  String get demoError => 'Show error state';

  @override
  String get noContent => 'No content in this chapter';

  @override
  String get novelFontSize => 'Font size';

  @override
  String get novelLineHeight => 'Line height';

  @override
  String get novelParagraphSpacing => 'Paragraph spacing';

  @override
  String get novelMargin => 'Margin';

  @override
  String get novelPageAnimation => 'Page animation';

  @override
  String get novelTextShadow => 'Text shadow';

  @override
  String get novelAnimNone => 'None';

  @override
  String get novelAnimSlide => 'Slide';

  @override
  String get novelAnimScroll => 'Scroll';

  @override
  String get novelAnimFade => 'Fade';

  @override
  String get novelAnimCover => 'Cover';

  @override
  String get novelAnimSimulation => 'Simulation';

  @override
  String get novelHfNone => 'None';

  @override
  String get novelHfTime => 'Time';

  @override
  String get novelHfBattery => 'Battery';

  @override
  String get novelHfChapterTitle => 'Chapter title';

  @override
  String get novelHfBookName => 'Book name';

  @override
  String get novelHfPageNumber => 'Page number';

  @override
  String get novelHfProgressPercent => 'Progress %';

  @override
  String novelChapterN(Object n) {
    return 'Chapter $n';
  }

  @override
  String get download => 'Download';

  @override
  String get downloads => 'Downloads';

  @override
  String get downloadListTitle => 'Downloads';

  @override
  String get downloadedContent => 'Downloaded';

  @override
  String get downloadSettings => 'Download Settings';

  @override
  String get emptyDownloadList => 'No active downloads';

  @override
  String get emptyDownloaded => 'No downloaded content';

  @override
  String get clearAll => 'Clear All';

  @override
  String get clearAllConfirm =>
      'This clears all active/paused/failed download records across all filters. Finished downloads are kept and remain readable. Continue?';

  @override
  String get clearHistory => 'Clear History';

  @override
  String get recentSearches => 'Recent searches';

  @override
  String get clearHistoryConfirm =>
      'Clear all browsing history for this module? Reading progress will be kept and restored when you revisit.';

  @override
  String get historyCleared => 'History cleared';

  @override
  String get batchPause => 'Batch Pause';

  @override
  String get batchResume => 'Batch Resume';

  @override
  String get deleteSelected => 'Delete Selected';

  @override
  String deleteSelectedConfirm(Object count) {
    return 'Delete the $count selected download records?';
  }

  @override
  String get pause => 'Pause';

  @override
  String get selectAll => 'Select All';

  @override
  String get select => 'Select';

  @override
  String get deleteConfirm => 'Delete selected downloads?';

  @override
  String get statusPending => 'Pending';

  @override
  String get statusDownloading => 'Downloading';

  @override
  String get statusPaused => 'Paused';

  @override
  String get statusFailed => 'Failed';

  @override
  String get statusWaitingForWifi => 'Waiting for Wi-Fi';

  @override
  String get statusCancelled => 'Cancelled';

  @override
  String get downloadWifiOnly => 'Wi-Fi only downloads';

  @override
  String get downloadWifiOnlyHint =>
      'Start downloads only when connected to Wi-Fi';

  @override
  String get comicDownloadFormat => 'Comic Download Format';

  @override
  String get novelDownloadFormat => 'Novel Download Format';

  @override
  String get formatCbz => 'CBZ Archive';

  @override
  String get formatCbzSubtitle => 'All images packed into a single .cbz file';

  @override
  String get formatFolder => 'Image Folder';

  @override
  String get formatFolderSubtitle => 'One folder per chapter with loose images';

  @override
  String get formatEpub => 'EPUB eBook';

  @override
  String get formatEpubSubtitle =>
      'Standard eBook format with table of contents';

  @override
  String get formatTxt => 'TXT Plain Text';

  @override
  String get formatTxtSubtitle => 'Plain text format, widest compatibility';

  @override
  String get emptyHistory => 'No browsing history';

  @override
  String get emptyFavorites => 'No favorites yet';

  @override
  String get emptyRssFeeds => 'No RSS feeds';

  @override
  String get emptyRssItems => 'No articles';

  @override
  String get addRssFeed => 'Add RSS Feed';

  @override
  String get rssFeedTitle => 'Title';

  @override
  String get rssFeedTitleHint => 'Custom title (optional)';

  @override
  String get opening => 'Opening';

  @override
  String get verificationRequired => 'Verification Required';

  @override
  String get verificationHint =>
      'This content requires web verification. Tap the button below to complete verification in your browser, then return and retry.';

  @override
  String get openInBrowser => 'Open externally';

  @override
  String get verificationDone => 'Verification Done, Retry';

  @override
  String get webViewNotAvailable =>
      'In-app browser is not available on this platform. Please use an external browser to complete verification.';

  @override
  String get extractFromPage => 'Extract from this page';

  @override
  String get extractHint =>
      'After completing verification on the page, tap \"Extract from this page\" to auto-extract the content URL. Falls back to manual browser verification on failure.';

  @override
  String get extracting => 'Extracting…';

  @override
  String get extractSuccess => 'Extraction succeeded';

  @override
  String get extractNoResult =>
      'Nothing extracted, please retry or verify manually';

  @override
  String get extractFailed => 'Extraction failed';

  @override
  String get captureFromPage => 'Capture rendered page';

  @override
  String get captureHint =>
      'Once the page finishes rendering, tap \"Capture rendered page\" to parse the list/detail with the existing selectors. No manual script needed.';

  @override
  String get capturing => 'Capturing…';

  @override
  String get snifferTitle => 'Video Sniffer';

  @override
  String get snifferAddressHint => 'Open a video page to sniff';

  @override
  String get snifferHint =>
      'Open a video page; dynamically loaded m3u8/mp4 streams are auto-detected below.';

  @override
  String get snifferNoResult => 'No video stream detected yet';

  @override
  String get snifferCopy => 'Copy';

  @override
  String get snifferPlay => 'Play';

  @override
  String get snifferInPagePlaying => 'Playing in page';

  @override
  String get snifferInPageHint =>
      'This stream is blob/MSE and cannot be opened in an external player; it is now playing inside the page.';

  @override
  String get snifferCopyPageLink => 'Copy page link';

  @override
  String get snifferClear => 'Clear list';

  @override
  String get snifferGo => 'Go';

  @override
  String get snifferDeep => 'Deep sniff';

  @override
  String get snifferSave => 'Save';

  @override
  String get snifferFilterAll => 'All';

  @override
  String get snifferFilterVideo => 'Video';

  @override
  String get snifferFilterAudio => 'Audio';

  @override
  String get snifferFilterOther => 'Other';

  @override
  String get snifferSizeUnknown => 'Size unknown';

  @override
  String snifferResultCount(int count) {
    return '$count results';
  }

  @override
  String get snifferPanelHandle =>
      'Sniffer results panel; drag up or down to resize, tap to collapse or expand';

  @override
  String get snifferResolveTitle => 'Sniff Resolve';

  @override
  String get snifferResolving => 'Sniffing the video address…';

  @override
  String get snifferResolveTimeout =>
      'No direct link captured yet. Keep waiting or cancel.';

  @override
  String get failed => 'failed';

  @override
  String get share => 'Share';

  @override
  String get shareCopied => 'Copied to clipboard';

  @override
  String get browserTitle => 'Browser';

  @override
  String get browserAddressHint => 'Enter URL or search';

  @override
  String get browserBack => 'Back';

  @override
  String get browserForward => 'Forward';

  @override
  String get browserRefresh => 'Refresh';

  @override
  String get browserCopyLink => 'Copy link';

  @override
  String get browserShare => 'Share';

  @override
  String get browserLinkCopied => 'Link copied';

  @override
  String get browserUseAsVerification => 'Use this page for verification';

  @override
  String get browserOpenSniffer => 'Video sniffer mode';

  @override
  String get browserUseAsVerificationDone =>
      'Verification completed using this page\'s cookies';

  @override
  String get browserNotAvailable =>
      'The built-in browser is not available on this platform. Please use an external browser.';

  @override
  String get openInternalBrowser => 'Open built-in browser';

  @override
  String get downloadStarted => 'Download started';

  @override
  String get downloadEpisodes => 'Download Episodes';

  @override
  String get episodeRange => 'Episode Range';

  @override
  String get addToDownload => 'Add to Download';

  @override
  String get deselectAll => 'Deselect All';

  @override
  String selectedCount(Object selected, Object total) {
    return 'Selected $selected/$total';
  }

  @override
  String get rangeStart => 'Start';

  @override
  String get rangeEnd => 'End';

  @override
  String get applyRange => 'Apply';

  @override
  String get alreadyDownloaded => 'Already downloaded';

  @override
  String get favoriteAdded => 'Added to favorites';

  @override
  String get favoriteRemoved => 'Removed from favorites';

  @override
  String get aboutApp => 'About App';

  @override
  String get appVersion => 'Version';

  @override
  String get privacySettings => 'Privacy Settings';

  @override
  String get stealthSettings => 'Stealth Settings';

  @override
  String get browseLocalTitle => 'Local Files';

  @override
  String get browseLocalEmpty => 'No readable local files found';

  @override
  String get browseLocalScan => 'Scan Files';

  @override
  String get browseLocalFileTypeAll => 'All';

  @override
  String get browseLocalFileTypeNovel => 'Novel';

  @override
  String get browseLocalFileTypeComic => 'Comic';

  @override
  String get browseLocalFileTypeVideo => 'Video';

  @override
  String get browseLocalSelectFolder => 'Select Folder';

  @override
  String get browseNetworkTitle => 'Network Files';

  @override
  String get browseNetworkUrlHint => 'Enter HTTP file server address';

  @override
  String get browseNetworkConnect => 'Connect';

  @override
  String get browseNetworkEmpty => 'No files found';

  @override
  String get browseNetworkHistory => 'History';

  @override
  String get browseNetworkParentDir => 'Parent directory';

  @override
  String get browseNetworkFileSize => 'Size';

  @override
  String get scrapeModeGeneral => 'General';

  @override
  String get scrapeModeNovel => 'Novel';

  @override
  String get scrapeModeComic => 'Comic';

  @override
  String get scrapeModeVideo => 'Video';

  @override
  String get scrapeModeArticle => 'Article';

  @override
  String get scrapeUrlHint => 'Enter URL to scrape';

  @override
  String get scrapeStart => 'Start Scraping';

  @override
  String get scrapeResultTitle => 'Page Title';

  @override
  String get scrapeResultLinks => 'All Links';

  @override
  String get scrapeResultText => 'Body Text';

  @override
  String get scrapeResultImages => 'Images';

  @override
  String get scrapeResultVideos => 'Videos';

  @override
  String get scrapeOpenInReader => 'Open in Reader';

  @override
  String get scrapeOpenInPlayer => 'Open in Player';

  @override
  String get scrapeNoResults => 'No content extracted';

  @override
  String get scrapeSelectorHint => 'CSS selector (optional)';

  @override
  String get scrapeAdvanced => 'Advanced';

  @override
  String get rssFeedUrl => 'Feed URL';

  @override
  String get rssFeedUrlHint => 'https://example.com/feed.xml';

  @override
  String get rssFeedDescription => 'Description';

  @override
  String get rssFeedModule => 'Module';

  @override
  String get rssFeedModuleNone => 'Global (Browse)';

  @override
  String get rssFeedTestConnection => 'Test Connection';

  @override
  String get rssFeedTesting => 'Testing…';

  @override
  String get rssFeedTestSuccess => 'Connection successful';

  @override
  String get rssFeedTestFailed => 'Connection failed';

  @override
  String get rssFeedPreview => 'Preview';

  @override
  String get rssFeedSaved => 'Feed saved';

  @override
  String get articleDetailAuthor => 'Author';

  @override
  String get articleDetailPublishedAt => 'Published';

  @override
  String get articleDetailReadFull => 'Read Full Article';

  @override
  String get articleDetailSource => 'Source';

  @override
  String get articleDetailEmpty => 'Article has no content';

  @override
  String get articleReadingSettings => 'Reading Settings';

  @override
  String get articleFontSize => 'Font Size';

  @override
  String get articleLineHeight => 'Line Height';

  @override
  String get articleNightMode => 'Night Mode';

  @override
  String get articleContentWidth => 'Content width';

  @override
  String get articleJustify => 'Justify text';

  @override
  String get articleParagraphSpacing => 'Paragraph spacing';

  @override
  String get articleWidthNarrow => 'Narrow';

  @override
  String get articleWidthNormal => 'Normal';

  @override
  String get articleWidthWide => 'Wide';

  @override
  String get articleFontFamily => 'Font Family';

  @override
  String get fontSystem => 'System';

  @override
  String get fontSerif => 'Serif';

  @override
  String get fontMono => 'Mono';

  @override
  String get articleLetterSpacing => 'Letter Spacing';

  @override
  String get mirrorListTitle => 'Mirror List';

  @override
  String get mirrorTesting => 'Testing…';

  @override
  String mirrorTestResultMs(Object ms) {
    return '$ms ms';
  }

  @override
  String get mirrorTestFailed => 'Failed';

  @override
  String get mirrorCurrent => 'Current';

  @override
  String get mirrorSwitched => 'Mirror switched';

  @override
  String get mirrorStealthLocked => 'Stealth mode is locked on';

  @override
  String get mirrorNoMirrors => 'No mirrors configured';

  @override
  String get collectApiImportTitle => 'Collect API Import';

  @override
  String get collectApiUrlHint => 'https://example.com/api.php/provide/vod/';

  @override
  String get collectApiDetect => 'Detect';

  @override
  String get collectApiDetecting => 'Detecting…';

  @override
  String get collectApiDetectSuccess => 'Detection successful';

  @override
  String get collectApiDetectFailed => 'Detection failed';

  @override
  String get collectApiSiteName => 'Site Name';

  @override
  String get collectApiCategories => 'Categories';

  @override
  String get collectApiPreview => 'Content Preview';

  @override
  String get collectApiSourceName => 'Source Name';

  @override
  String get collectApiSourceId => 'Source ID';

  @override
  String get collectApiSave => 'Save Source';

  @override
  String get collectApiSaved => 'Source saved';

  @override
  String get collectApiInvalidUrl => 'Invalid URL';

  @override
  String get sourceImportFromUrl => 'Import from URL';

  @override
  String get sourceImportFromFile => 'Import from File';

  @override
  String get sourceImportFromJson => 'Enter JSON Manually';

  @override
  String get sourceImportUrlHint => 'URL of source JSON';

  @override
  String get sourceImportFilePicker => 'Select JSON File';

  @override
  String get sourceImportJsonHint => 'Paste source JSON config';

  @override
  String get sourceImportValidate => 'Validate';

  @override
  String get sourceImportValid => 'Validation passed';

  @override
  String get sourceImportInvalid => 'Validation failed';

  @override
  String get sourceImportErrors => 'Errors';

  @override
  String get sourceImportCollectApiDetected => 'MacCMS Collect API detected';

  @override
  String get sourceImportCollectApiRedirect => 'Use Collect API Import';

  @override
  String get sourceImportSaved => 'Source imported';

  @override
  String get contentImportTitle => 'Import Content';

  @override
  String get contentImportSelectFile => 'Select File';

  @override
  String get contentImportSupportedFormats => 'Supported Formats';

  @override
  String get contentImportHistory => 'Import History';

  @override
  String get contentImportEmpty => 'No imports yet';

  @override
  String get contentImportOpened => 'Opened';

  @override
  String comicDirImported(Object name) {
    return 'Imported comic: $name';
  }

  @override
  String novelDirImported(String name, int count) {
    return 'Imported novel: $name ($count chapters)';
  }

  @override
  String get contentImportNovelFormats => '.txt, .epub';

  @override
  String get contentImportComicFormats => '.cbz, image folder';

  @override
  String get contentImportMediaFormats => '.mp4, .mkv, .avi';

  @override
  String get downloadedGroupChapters => 'Chapters';

  @override
  String get downloadedGroupFormat => 'Format';

  @override
  String get downloadedGroupOpen => 'Open';

  @override
  String get downloadedGroupFileMissing => 'File not found';

  @override
  String get downloadedGroupDeleteConfirm => 'Delete this download?';

  @override
  String downloadBatches(Object count) {
    return '$count batches';
  }

  @override
  String downloadBatchLabel(Object index) {
    return 'Batch $index';
  }

  @override
  String get browsePageTitle => 'Browse';

  @override
  String get rssSubscribeTitle => 'RSS Subscriptions';

  @override
  String get emptyRssSubscribe => 'No RSS subscriptions yet';

  @override
  String get addSubscription => 'Add Subscription';

  @override
  String get subscribeAddressLabel => 'Subscribe URL';

  @override
  String get rsshubRoutesTitle => 'RSSHub Routes';

  @override
  String get rsshubRouteRecommend => 'RSSHub Route Recommendations';

  @override
  String get rsshubRouteHint =>
      'Tap a route to auto-fill with RSSHub instance URL';

  @override
  String get novelLibraryName => 'Novel Library';

  @override
  String get mediaLibraryName => 'Media Library';

  @override
  String get comicLibraryName => 'Comic Library';

  @override
  String get emptySubscribe => 'No subscriptions';

  @override
  String get sourceListTab => 'Source List';

  @override
  String get networkImportTab => 'Network Import';

  @override
  String get localImportTab => 'Local Import';

  @override
  String get sourceListEmpty => 'No sources';

  @override
  String get networkImportHint => 'Paste source URL (.json/.txt)';

  @override
  String get networkImportPasteHint => 'Paste URL and tap to fetch';

  @override
  String get localImportTitle => 'Import from Local File';

  @override
  String get localImportFormats => 'Supports .json, .txt, .xml';

  @override
  String get selectFile => 'Select File';

  @override
  String get selectFolder => 'Select Folder';

  @override
  String get noLocalSource => 'No source files found';

  @override
  String get localImportHint =>
      'Pick a single file or a folder to scan for source files (.json/.txt/.xml)';

  @override
  String importPreviewTitle(Object count) {
    return '$count files found';
  }

  @override
  String get confirmImport => 'Confirm import';

  @override
  String importSelectedCount(Object count) {
    return '$count selected';
  }

  @override
  String importTypeOnly(Object type) {
    return 'Only $type sources will be imported';
  }

  @override
  String importTypeFiltered(int count) {
    return '$count other-type source(s) skipped';
  }

  @override
  String importNoMatchingType(Object type, int count) {
    return 'No $type sources found in the selection ($count other-type source(s) skipped)';
  }

  @override
  String sourceImportResult(int success, int total) {
    return 'Imported $success/$total sources';
  }

  @override
  String batchImportHint(int count) {
    return 'Recognized $count sources. Select to batch import (includes novel / media / comic).';
  }

  @override
  String get sourceUnrecognized =>
      'No valid source recognized (novel / media / comic).';

  @override
  String importDistributedHint(int count) {
    return 'Sources will be sorted into their modules automatically ($count from other modules).';
  }

  @override
  String get settingsGroupDownload => 'Download Management';

  @override
  String get settingsGroupTools => 'Tools';

  @override
  String get settingsGroupPlugins => 'Plugins';

  @override
  String get settingsGroupData => 'Data';

  @override
  String get settingsGroupPlayback => 'Playback & Reading';

  @override
  String get settingsGroupContentSources => 'Content Sources';

  @override
  String get settingsGroupNetwork => 'Network';

  @override
  String get settingsGroupSubscriptions => 'Subscriptions & Notifications';

  @override
  String get settingsGroupDownloadsData => 'Downloads & Data';

  @override
  String get webScrapeSetting => 'Web Scraping';

  @override
  String get webScrapeSettingSameAsBrowse => 'Same as browse page web scraping';

  @override
  String get subscriptionManagement => 'Subscription Management';

  @override
  String get subscriptionManagementDesc =>
      'Unified management by type, manage RSS subscriptions';

  @override
  String get rsshubInstance => 'RSSHub Instance';

  @override
  String get rsshubInstanceDesc => 'Self-hosted RSSHub address';

  @override
  String get rsshubSettingsTitle => 'RSSHub Settings';

  @override
  String get rsshubSettingsDesc => 'Choose a preset or self-hosted instance';

  @override
  String get rssNotifications => 'RSS update notifications';

  @override
  String get rssNotificationsDesc => 'Detect new items in subscriptions';

  @override
  String get rssNotificationsTitle => 'RSS Update Notifications';

  @override
  String get rssNotificationEnabled => 'Enable update detection';

  @override
  String get rssNotificationEnabledSubtitle =>
      'Poll subscriptions periodically while in foreground';

  @override
  String get rssUpdateInterval => 'Check interval';

  @override
  String get interval15m => '15 minutes';

  @override
  String get interval30m => '30 minutes';

  @override
  String get interval1h => '1 hour';

  @override
  String get interval2h => '2 hours';

  @override
  String get interval4h => '4 hours';

  @override
  String get rssCheckNow => 'Check now';

  @override
  String rssTotalNewCount(int count) {
    return 'Unread: $count';
  }

  @override
  String get rssCheckDone => 'Check complete';

  @override
  String get rssNotificationHint =>
      'Polls only while the app is in foreground; new items show an unread count badge on the feed card.';

  @override
  String get currentInstance => 'Current Instance';

  @override
  String get presetInstances => 'Preset Instances';

  @override
  String get presetInstanceOfficial => 'Official';

  @override
  String get customInstance => 'Custom Instance';

  @override
  String get restoreDefault => 'Restore Default';

  @override
  String get rsshubTestAll => 'Test all';

  @override
  String get rsshubTestingAll => 'Testing all instances…';

  @override
  String rsshubTestAllDone(Object count) {
    return 'Tested $count instances';
  }

  @override
  String get saveCustomInstance => 'Save Custom';

  @override
  String get instanceTestFail => 'Test failed';

  @override
  String get instanceTestSuccess => 'Connection successful';

  @override
  String get rsshubTroubleshoot => 'Troubleshooting';

  @override
  String get rsshubTroubleshootHint =>
      'If you encounter issues:\n• Ensure the address is accessible and not blocked by firewall\n• Try switching to a different preset instance\n• Self-hosted users please check if service is running normally';

  @override
  String get danmakuSettings => 'DanDanPlay Danmaku';

  @override
  String get danmakuSettingsDesc => 'Danmaku configuration';

  @override
  String get danmakuConfigTitle => 'DanDanPlay Danmaku Config';

  @override
  String get unconfigured => 'Unconfigured';

  @override
  String get configured => 'Configured';

  @override
  String get appIdLabel => 'AppId';

  @override
  String get appIdHint => 'Enter AppId';

  @override
  String get appSecretLabel => 'AppSecret';

  @override
  String get appSecretHint => 'Enter AppSecret';

  @override
  String get saveDanmaku => 'Save';

  @override
  String get danmakuDesc =>
      'Get your AppId and AppSecret from https://daplay.danmaku.net. After configuration, danmaku will appear in the player.';

  @override
  String get pluginManagement => 'Manage Plugins';

  @override
  String get dataImportExport => 'Import/Export';

  @override
  String get dataImportExportTitle => 'Import/Export';

  @override
  String get importData => 'Import Data';

  @override
  String get importDataDesc => 'Import subscriptions, plugins and progress';

  @override
  String get exportData => 'Export Data';

  @override
  String get exportDataDesc => 'Export all data to file';

  @override
  String get exportSubscription => 'Export Subscriptions';

  @override
  String get exportSubscriptionDesc => 'Export only RSS subscriptions';

  @override
  String get exportPlugins => 'Export Plugins';

  @override
  String get exportPluginsDesc => 'Export plugin configurations';

  @override
  String get selectExportFolder => 'Select Export Folder';

  @override
  String get exportFolderCustom => 'Custom export folder supported';

  @override
  String get downloadListTab => 'Download List';

  @override
  String get downloadedListTab => 'Downloaded';

  @override
  String get maxConcurrentDownloads => 'Max Concurrent Downloads';

  @override
  String get maxConcurrentDownloadsDesc => 'Number of simultaneous downloads';

  @override
  String get downloadPath => 'Download Path';

  @override
  String get folderImportOhosUnsupported =>
      'Folder import isn\'t supported on HarmonyOS yet. Use file import instead.';

  @override
  String get folderImportCopyProgress => 'Importing folder';

  @override
  String get folderImportCopyProgressHint =>
      'Copying into app storage. Keep the app open.';

  @override
  String get folderImportCopyFailed =>
      'Couldn\'t copy the folder. Please try again.';

  @override
  String get downloadPathSet => 'Download path updated';

  @override
  String get contentImportActions => 'Actions';

  @override
  String get downloaderType => 'Downloader';

  @override
  String get downloaderInternal => 'Built-in Downloader';

  @override
  String get downloaderExternal => 'External Downloader';

  @override
  String get threadCount => 'Thread Count';

  @override
  String get threadCountDesc => 'Number of download threads';

  @override
  String get comicFormatSetting => 'Comic Format';

  @override
  String get novelFormatSetting => 'Novel Format';

  @override
  String get downloadTabsAll => 'All';

  @override
  String get downloadTabsNovel => 'Novel';

  @override
  String get downloadTabsMedia => 'Media';

  @override
  String get downloadTabsComic => 'Comic';

  @override
  String get downloadedTabsAll => 'All';

  @override
  String get downloadedTabsNovel => 'Novel';

  @override
  String get downloadedTabsMedia => 'Media';

  @override
  String get downloadedTabsComic => 'Comic';

  @override
  String get downloadedTabsArchived => 'Archived';

  @override
  String get noDownloads => 'No downloads';

  @override
  String get downloadPause => 'Pause';

  @override
  String get downloadResume => 'Resume';

  @override
  String get sourceCategoryNovel => 'Novel';

  @override
  String get sourceCategoryMedia => 'Media';

  @override
  String get sourceCategoryComic => 'Comic';

  @override
  String sourceCategoryEmpty(Object category) {
    return 'No $category sources';
  }

  @override
  String rsshubLatencyMs(Object ms) {
    return '${ms}ms';
  }

  @override
  String get rsshubLatencyFailed => 'Failed';

  @override
  String get downloaderSelectTitle => 'Downloader Selection';

  @override
  String get comicFormatSelectTitle => 'Comic Format';

  @override
  String get comicFormatJpg => 'Single Page JPG';

  @override
  String get comicFormatPng => 'Single Page PNG';

  @override
  String get comicFormatCbz => 'CBZ Archive';

  @override
  String get novelFormatSelectTitle => 'Novel Format';

  @override
  String get novelFormatTxt => 'TXT';

  @override
  String get novelFormatEpub => 'EPUB';

  @override
  String get rsshubRouteBilibiliBangumi => 'Bilibili Bangumi';

  @override
  String get rsshubRouteBilibiliBangumiPath =>
      '/bilibili/bangumi/media/:mediaid';

  @override
  String get rsshubRouteBilibiliMangaUpdate => 'Bilibili Manga Update';

  @override
  String get rsshubRouteBilibiliMangaUpdatePath =>
      '/bilibili/manga/update/:comicid';

  @override
  String get rsshubRouteBilibiliUserVideo => 'Bilibili User Videos';

  @override
  String get rsshubRouteBilibiliUserVideoPath => '/bilibili/user/video/:uid';

  @override
  String get rsshubRouteBilibiliRanking => 'Bilibili Ranking';

  @override
  String get rsshubRouteBilibiliRankingPath =>
      '/bilibili/partion/ranking/:tid/:days?';

  @override
  String get rsshubRouteYoutubeChannel => 'YouTube Channel';

  @override
  String get rsshubRouteYoutubeChannelPath => '/youtube/channel/:id';

  @override
  String get rsshubRouteTwitterUser => 'Twitter User';

  @override
  String get rsshubRouteLinovelib => 'Linovelib';

  @override
  String get rsshubRouteSfacg => 'SFACG';

  @override
  String get importMediaTitle => 'Import Media';

  @override
  String get importMediaFormatsHint =>
      'Supports mp4, mkv, avi, mov and common video formats';

  @override
  String get importMediaPickFile => 'Select Video File';

  @override
  String get importMediaPickFolder => 'Select Video Folder';

  @override
  String get importNovelTitle => 'Import Novel';

  @override
  String get importNovelFormatsHint =>
      'Supports .txt / .epub files and archives (.zip / .cbz / .rar / .7z) containing them';

  @override
  String get novelArchiveImported => 'archive(s) unpacked';

  @override
  String get importNovelPickFile => 'Select File';

  @override
  String get importNovelPickFolder => 'Select Folder';

  @override
  String get importComicTitle => 'Import Comic';

  @override
  String get importComicFormatsHint =>
      'Supports cbz, cbr, cbt and common comic archive formats';

  @override
  String get importComicPickFile => 'Select Comic File';

  @override
  String get importComicPickFolder => 'Select Comic Folder';

  @override
  String get novelBrightness => 'Brightness';

  @override
  String get playerLock => 'Lock';

  @override
  String get playerUnlock => 'Unlock';

  @override
  String get playerAutoPlayNext => 'Auto-play next';

  @override
  String get playerAddToQueue => 'Add to queue';

  @override
  String get playerPlayNext => 'Play next';

  @override
  String get playerQueue => 'Play queue';

  @override
  String get playerQueueEmpty => 'Queue is empty';

  @override
  String get playerQueueAdded => 'Added to queue';

  @override
  String get playerQueuePlayNextAdded => 'Set as next';

  @override
  String get playerQueueCleared => 'Queue cleared';

  @override
  String get playerQueueRemoved => 'Removed from queue';

  @override
  String get playerQueueNoEpisodes => 'No episodes available';

  @override
  String get playerQueueLoadFailed =>
      'Failed to load next work, auto-play stopped';

  @override
  String playerQueueLoading(String title) {
    return 'Loading: $title';
  }

  @override
  String playerQueueResumeLast(String title) {
    return 'Resume: $title';
  }

  @override
  String playerAutoNextWork(String title) {
    return 'Up next: $title';
  }

  @override
  String get playerQueueMoveUp => 'Move up';

  @override
  String get playerQueueMoveDown => 'Move down';

  @override
  String get playerQueueRemove => 'Remove';

  @override
  String get playerDecodeMode => 'Decode mode';

  @override
  String get playerDecodeAuto => 'Auto';

  @override
  String get playerDecodeSw => 'Software';

  @override
  String get playerDecodeHw => 'Hardware';

  @override
  String get playerDecodeHwPlus => 'Hardware+';

  @override
  String get playerDecodeHwPlusHint => 'Recommended for screen artifacts';

  @override
  String get playerUpscaleShader => 'Super resolution';

  @override
  String get playerUpscaleShaderOff => 'Off';

  @override
  String get playerUpscaleShaderPerformance => 'Fast';

  @override
  String get playerUpscaleShaderQuality => 'Quality';

  @override
  String get playerUpscaleShaderHint =>
      'Real-time upscale for low-res sources; use Fast or Off if frames drop';

  @override
  String playerDecodeFallback(String mode) {
    return 'Decoding issue detected, switched to $mode';
  }

  @override
  String get playerStats => 'Playback stats';

  @override
  String get playerStatsDecoder => 'Decoder';

  @override
  String get playerStatsHardware => 'Hardware decoding';

  @override
  String get playerStatsSoftware => 'Software decoding';

  @override
  String get playerStatsVideoCodec => 'Video codec';

  @override
  String get playerStatsPixelFormat => 'Pixel format';

  @override
  String get playerStatsResolution => 'Resolution';

  @override
  String get playerStatsDroppedFrames => 'Dropped frames (render / decode)';

  @override
  String get playerStatsBitrate => 'Video bitrate';

  @override
  String get playerStatsBuffering => 'Cache buffering';

  @override
  String get playerStatsUnavailable => 'Playback stats unavailable';

  @override
  String get playerAudioChannel => 'Audio channel';

  @override
  String get playerAudioStereo => 'Stereo';

  @override
  String get playerAudioMono => 'Mono';

  @override
  String get playerAudioAutoProtect => 'Auto-protect';

  @override
  String get playerAudioReverseStereo => 'Reverse stereo';

  @override
  String get playerAspectRatio => 'Aspect ratio';

  @override
  String get playerAspectDefault => 'Default';

  @override
  String get playerAspectFill => 'Fill';

  @override
  String get playerAspect43 => '4:3';

  @override
  String get playerAspect169 => '16:9';

  @override
  String get playerPlaybackSpeed => 'Playback speed';

  @override
  String get playerLongPressSpeed => 'Long Press Speed';

  @override
  String get playerSubtitle => 'Subtitle';

  @override
  String get playerSubtitleSettings => 'Subtitle settings';

  @override
  String get playerSubtitleDelay => 'Subtitle delay (ms)';

  @override
  String get playerFontSize => 'Font size';

  @override
  String get playerSubtitleOutline => 'Subtitle outline';

  @override
  String get playerTimer => 'Sleep timer';

  @override
  String get playerPlayInfo => 'Play info';

  @override
  String get playerExternalPlay => 'External play';

  @override
  String get playerVideoExpired => 'Video link expired, please retry';

  @override
  String get playerOhosUnsupported =>
      'Video playback isn\'t supported on HarmonyOS yet. This feature is being adapted.';

  @override
  String get playerEpisodeSwitchFailed =>
      'Failed to switch episode, please retry';

  @override
  String get playerStallDetected => 'Playback stalled, reconnecting…';

  @override
  String get playerRetry => 'Retry';

  @override
  String get playerNextEpisode => 'Next episode';

  @override
  String get playerPreviousEpisode => 'Previous episode';

  @override
  String get playerNextFrame => 'Next frame';

  @override
  String get playerPreviousFrame => 'Previous frame';

  @override
  String get playerShare => 'Share';

  @override
  String get danmakuFilterKeywords => 'Filter keywords';

  @override
  String get danmakuTimeOffset => 'Time offset (s)';

  @override
  String get danmakuArea => 'Display area';

  @override
  String get danmakuDuration => 'Duration (s)';

  @override
  String get danmakuLineHeight => 'Line height';

  @override
  String get danmakuHideTop => 'Hide top';

  @override
  String get danmakuHideBottom => 'Hide bottom';

  @override
  String get danmakuHideScroll => 'Hide scroll';

  @override
  String get danmakuFollowSpeed => 'Follow playback speed';

  @override
  String get danmakuAddKeyword => 'Add keyword';

  @override
  String get danmakuKeywordHint => 'Enter keyword or regex';

  @override
  String get danmakuSearch => 'Search danmaku';

  @override
  String get danmakuSearchHint => 'Enter anime name to search';

  @override
  String get danmakuMatchEpisode => 'Match episode';

  @override
  String get danmakuNoResult => 'No results';

  @override
  String get danmakuLoadFailed => 'Failed to load danmaku';

  @override
  String get danmakuLoaded => 'Danmaku loaded';

  @override
  String get danmakuCacheHit => 'Danmaku cached';

  @override
  String get danmakuSourceTitle => 'Danmaku Source';

  @override
  String get danmakuSourceHint => 'Choose danmaku source';

  @override
  String get danmakuSourceDandanplay => 'dandanplay';

  @override
  String get danmakuSourceBilibili => 'bilibili';

  @override
  String get danmakuSourceOff => 'Off';

  @override
  String get danmakuSourceDandanplayDesc => 'Auto-match by anime title';

  @override
  String get danmakuSourceBilibiliDesc => 'Match by video av/BV id';

  @override
  String get danmakuSourceOffDesc => 'No danmaku';

  @override
  String get danmakuDisplaySettingsTitle => 'Danmaku Display Settings';

  @override
  String get danmakuDisplaySettingsDesc =>
      'Font size, opacity, time offset, etc.';

  @override
  String get danmakuFontSize => 'Font Size';

  @override
  String get danmakuOpacity => 'Opacity';

  @override
  String get playerSettingsTitle => 'Player Settings';

  @override
  String get playerSettingsDesc =>
      'Decode mode, aspect ratio, playback speed, etc.';

  @override
  String get playerDefaultDecodeMode => 'Default Decode Mode';

  @override
  String get playerDefaultAudioChannel => 'Default Audio Channel';

  @override
  String get playerDefaultAspectRatio => 'Default Aspect Ratio';

  @override
  String get playerDefaultSpeed => 'Default Playback Speed';

  @override
  String get playerDefaultAutoPlay => 'Default Auto-play Next';

  @override
  String get playerSubtitleFontSize => 'Subtitle Font Size';

  @override
  String get subtitleTitle => 'Subtitles';

  @override
  String get subtitleOffset => 'Offset';

  @override
  String get subtitlePosTop => 'Top';

  @override
  String get subtitlePosCenter => 'Center';

  @override
  String get subtitlePosBottom => 'Bottom';

  @override
  String get subtitleAssYes => 'Yes';

  @override
  String get subtitleAssNo => 'No';

  @override
  String get subtitleAssStrip => 'Strip';

  @override
  String get subtitleAssForce => 'Force';

  @override
  String get subtitleShow => 'Show subtitles';

  @override
  String get subtitleNone => 'Off';

  @override
  String get subtitleNoTracks => 'No subtitle tracks available';

  @override
  String get subtitleStyleTitle => 'Subtitle Style';

  @override
  String get subtitleFontSize => 'Font Size';

  @override
  String get subtitleScale => 'Scale';

  @override
  String get subtitleBorderSize => 'Border Width';

  @override
  String get subtitleShadowOffset => 'Shadow Offset';

  @override
  String get subtitleTextColor => 'Text Color';

  @override
  String get subtitleBorderColorLabel => 'Border Color';

  @override
  String get subtitleShadowColorLabel => 'Shadow Color';

  @override
  String get subtitlePosition => 'Position';

  @override
  String get subtitleAssOverride => 'Override ASS/SSA Style';

  @override
  String subtitleTrackN(Object n) {
    return 'Track $n';
  }

  @override
  String get readerSettingsTitle => 'Reader Settings';

  @override
  String get readerSettingsDesc =>
      'Reading mode, background, orientation, etc.';

  @override
  String get readerGeneralGroup => 'General Reading Preferences';

  @override
  String get novelReaderSettingsTitle => 'Novel Reader Settings';

  @override
  String get novelReaderSettingsDesc => 'Global novel reader defaults';

  @override
  String get comicReaderSettingsTitle => 'Comic Reader Settings';

  @override
  String get comicReaderSettingsDesc =>
      'Direction, tap zone, filter, zoom & gesture';

  @override
  String get novelTypographyGroup => 'Novel Typography';

  @override
  String get novelShadow => 'Shadow toggle';

  @override
  String get novelBackgroundPreset => 'Background preset';

  @override
  String get novelTapZoneInvert => 'Tap zone invert';

  @override
  String get comicFilterGroup => 'Image Filter';

  @override
  String get comicFilterBrightness => 'Brightness';

  @override
  String get comicFilterContrast => 'Contrast';

  @override
  String get comicFilterColorTemp => 'Color Temperature';

  @override
  String get comicFilterInverted => 'Invert Filter';

  @override
  String get comicTapZoneInvert => 'Tap Zone Invert';

  @override
  String get novelZoomGroup => 'Zoom & Typography';

  @override
  String get comicZoomGroup => 'Zoom & Gesture';

  @override
  String get readerDefaultMode => 'Default Reading Mode';

  @override
  String get readerDefaultBackground => 'Default Background';

  @override
  String get readerBackgroundWhite => 'White';

  @override
  String get readerBackgroundBeige => 'Beige';

  @override
  String get readerBackgroundDark => 'Dark';

  @override
  String get readerDefaultOrientation => 'Default Orientation';

  @override
  String get readerOrientationHorizontal => 'Horizontal';

  @override
  String get readerOrientationVertical => 'Vertical';

  @override
  String get readerDoubleTapZoom => 'Double Tap Zoom';

  @override
  String get readerOrientationLock => 'Orientation Lock';

  @override
  String get layoutSettings => 'Layout Settings';

  @override
  String get layoutSettingsDesc => 'Bookshelf grid/list, density';

  @override
  String get bookshelfLayoutMode => 'Bookshelf Layout Mode';

  @override
  String get bookshelfLayoutGrid => 'Grid';

  @override
  String get bookshelfLayoutList => 'List';

  @override
  String get bookshelfLayoutDensity => 'Grid Density';

  @override
  String get bookshelfDensityCompact => 'Compact';

  @override
  String get bookshelfDensityStandard => 'Standard';

  @override
  String get bookshelfDensityComfortable => 'Comfortable';

  @override
  String get sourceHide => 'Hide';

  @override
  String get sourceShowHidden => 'Show Hidden Sources';

  @override
  String get sourceEdit => 'Edit Source';

  @override
  String get sourceDelete => 'Delete Source';

  @override
  String get sourceMigrate => 'View migration note';

  @override
  String get sourceEditBuiltinNotAllowed => 'Built-in sources cannot be edited';

  @override
  String get sourceEditSaved => 'Source updated';

  @override
  String get sourceEditFailed => 'Failed to update source';

  @override
  String get sourceEditJsonHint =>
      'Edit all fields of this source as JSON in collapsible modules. Tap a module title to expand or collapse; a module\'s content is only loaded when expanded. Clearing a module and saving deletes that field. The id is locked and cannot be changed.';

  @override
  String get sourceEditInvalidJson =>
      'JSON format or field validation failed. Please fix and retry.';

  @override
  String sourceEditSectionItems(int count) {
    return '$count entries';
  }

  @override
  String get sourceEditAddField => 'Add field';

  @override
  String get sourceEditFieldName => 'Field name';

  @override
  String get sourceEditFieldExists => 'This field already exists';

  @override
  String get sourceEditIdLocked => 'id is locked and stays unchanged on save';

  @override
  String get sourceEditTabBasic => 'Basic';

  @override
  String get sourceEditTabParse => 'Site & Parsing';

  @override
  String get sourceEditTabRoutes => 'Routes';

  @override
  String get sourceEditTabBrowse => 'Category & Filters';

  @override
  String get sourceEditTabAdvanced => 'Network & Other';

  @override
  String get sourceDeleteBuiltinNotAllowed =>
      'Built-in sources cannot be deleted';

  @override
  String get sourceDeleted => 'Source deleted';

  @override
  String get sourceDeleteFailed => 'Failed to delete source';

  @override
  String get sourceDeprecatedHint =>
      'This source is deprecated. Please use an alternative.';

  @override
  String get sourceNameLabel => 'Source Name';

  @override
  String get sourceUrlLabel => 'Source URL';

  @override
  String get back => 'Back';

  @override
  String get sourceType => 'Type';

  @override
  String get sourceTypeAnime => 'Anime';

  @override
  String get sourceTypeManga => 'Manga';

  @override
  String get sourceTypeNovel => 'Novel';

  @override
  String get playerTimerOff => 'Turn off timer';

  @override
  String playerTimerMinutes(int minutes) {
    return '$minutes minutes';
  }

  @override
  String get playerTimerCustom => 'Custom';

  @override
  String get playerTimerCanceled => 'Sleep timer canceled';

  @override
  String get playerTimerFired => 'Sleep timer fired, playback paused';

  @override
  String playerTimerEpisodes(int count) {
    return 'Pause after $count more episodes';
  }

  @override
  String get playerTimerEpisodesFired =>
      'Playback paused by episode sleep timer';

  @override
  String get noDescription => 'No description available';

  @override
  String get aboutAppTitle => 'About';

  @override
  String get openSourceLicenses => 'Open source licenses';

  @override
  String get thirdPartyLibraries => 'Third-party libraries';

  @override
  String get acknowledgements => 'Acknowledgements';

  @override
  String get acknowledgementsLegado =>
      'NexHub\'s novel paginator re-implements its ChapterProvider pagination algorithm as an independent Dart implementation (no source copied). The upstream repo ships no explicit open-source license; this credit is inspiration attribution only.';

  @override
  String get acknowledgementsMihon =>
      'Its extension-source architecture and comic-reader interaction informed NexHub\'s manga parsing and reading experience. Licensed under Apache License 2.0 (© Mihon contributors).';

  @override
  String get acknowledgementsRssHub =>
      'Powers the RSS aggregation behind NexHub\'s subscription feature. Licensed under AGPL-3.0 (© DIYgod); NexHub only calls it as a client and does not modify or redistribute its source.';

  @override
  String get acknowledgementsWenyi =>
      'Its novel AI-translation pipeline design (context enrichment, terminology loop, review and refined drafting) informed the deep optimization of NexHub\'s built-in novel translation. Licensed under the MIT License (© BigDawnGhost); NexHub copied no source code and implemented independently.';

  @override
  String get acknowledgementsAnime4K =>
      'The player\'s \"Super resolution\" ships its GLSL shader presets (Mode A Fast/Quality). Licensed under the MIT License (© 2019-2021 bloc97).';

  @override
  String get acknowledgementsViewProject => 'View project';

  @override
  String get acknowledgementsMoreLibs =>
      'Other third-party libraries are listed under \"Open source licenses\".';

  @override
  String get projectRepository => 'Project repository';

  @override
  String get checkUpdate => 'Check for updates';

  @override
  String get updateChecking => 'Checking for updates…';

  @override
  String get updateLatest => 'You are on the latest version';

  @override
  String updateAvailable(Object version) {
    return 'New version $version available';
  }

  @override
  String get updateAvailableHint => 'Open the releases page to download?';

  @override
  String get updateGoToDownload => 'Go to download';

  @override
  String get updateCheckFailed =>
      'Failed to check for updates. Try again later.';

  @override
  String get updateMirrorSettings => 'Update Mirror Settings';

  @override
  String get updateMirror => 'Mirror';

  @override
  String get updateSilentDownload => 'Silent download';

  @override
  String get updateDownloadAndInstall => 'Download & Install';

  @override
  String get updateDownloaded => 'Download complete. Ready to install.';

  @override
  String get updateInstallNow => 'Install Now';

  @override
  String get updateAutoSwitchMirror => 'Auto-switch to fastest mirror';

  @override
  String get updateAutoSwitchMirrorDesc =>
      'Test mirror latency during download and pick the fastest';

  @override
  String get updateMirrorSelection => 'Mirror Selection';

  @override
  String get updateCustomMirrors => 'Custom Mirrors';

  @override
  String get updateNoCustomMirrors => 'No custom mirrors';

  @override
  String get updateAddMirror => 'Add Mirror';

  @override
  String get updateMirrorName => 'Mirror Name';

  @override
  String get updateMirrorUrl => 'Mirror URL';

  @override
  String get updateMirrorUrlInvalid =>
      'Invalid mirror URL: must be a full http/https URL';

  @override
  String get updateTestMirrors => 'Test All Mirrors';

  @override
  String get updateMirrorTimeout => 'Timeout';

  @override
  String get updateSettings => 'Update Settings';

  @override
  String get updateSettingsDesc =>
      'Check for updates, upgrade channel and download mode';

  @override
  String get updateChannelSection => 'Upgrade channel';

  @override
  String get updateChannelStable => 'Stable';

  @override
  String get updateChannelStableDesc => 'Receive stable releases only';

  @override
  String get updateChannelBeta => 'Beta';

  @override
  String get updateChannelBetaDesc =>
      'Early access to alpha/beta/rc releases (may be unstable)';

  @override
  String get updateAutoCheck => 'Check updates automatically';

  @override
  String get updateAutoCheckDesc =>
      'Check for new versions in the background on startup';

  @override
  String get updateAutoDownload => 'Download updates automatically';

  @override
  String get updateAutoDownloadDesc =>
      'Download the installer automatically when a new version is found';

  @override
  String get updateWifiOnlyAutoDownload => 'Only auto-download on Wi-Fi';

  @override
  String get updateWifiOnlyAutoDownloadDesc =>
      'Wait for a Wi-Fi connection before auto-downloading';

  @override
  String get updateInAppDownload => 'In-app download';

  @override
  String get updateInAppDownloadDesc =>
      'Download inside the app; open the browser otherwise';

  @override
  String get updateMirrorSection => 'Download mirrors';

  @override
  String get updateMirrorCommunityThanks =>
      'Mirrors are contributed by the community and stability is not guaranteed. Thanks to every generous contributor 🙏';

  @override
  String updateMirrorShowAll(Object count) {
    return 'Show all ($count)';
  }

  @override
  String get updateMirrorCollapse => 'Collapse';

  @override
  String get updateMirrorAllUnreachable =>
      'All mirrors are unreachable under the current network. Downloads will use GitHub official directly. Retry later or add a custom mirror.';

  @override
  String get updateOpenedBrowser => 'Opened the browser for download';

  @override
  String get updateCannotOpenBrowser => 'Unable to open the browser';

  @override
  String get settingsGroupLanguage => 'Language';

  @override
  String get languageTitle => 'Interface language';

  @override
  String get languageFollowSystem => 'Follow system';

  @override
  String get languageChinese => '简体中文';

  @override
  String get languageEnglish => 'English';

  @override
  String get chapterList => 'Chapter list';

  @override
  String get currentChapter => 'Current chapter';

  @override
  String get searchByAuthor => 'Search by author';

  @override
  String get noRecommendation => 'No recommendations';

  @override
  String get restore => 'Restore';

  @override
  String get archive => 'Archive';

  @override
  String get archivedEmpty => 'No archived content';

  @override
  String get archivedHint =>
      'Archived files are kept on disk and can be restored anytime';

  @override
  String get deletePermanently => 'Delete permanently';

  @override
  String get restoreSuccess => 'Restored';

  @override
  String get statusArchived => 'Archived';

  @override
  String get searchHistoryTitle => 'Search history';

  @override
  String get clearSearchHistory => 'Clear history';

  @override
  String get clearSearchHistoryConfirm => 'Clear all search history?';

  @override
  String get noSearchHistory => 'No search history';

  @override
  String get deleteSearchHistoryConfirm => 'Delete this search history entry?';

  @override
  String get hotSearch => 'Hot search';

  @override
  String get noHotSearch => 'No hot search';

  @override
  String get importDataParsing => 'Parsing…';

  @override
  String get importDataSuccess => 'Import successful';

  @override
  String get importDataFailed => 'Import failed';

  @override
  String get importDataInvalidFormat => 'Invalid file format';

  @override
  String importDataSummary(int plugins, int favorites, int history) {
    return 'Imported $plugins plugins / $favorites favorites / $history history';
  }

  @override
  String get exportFolderDefault => 'Default path (Documents)';

  @override
  String get exportDataSuccess => 'Export successful';

  @override
  String get exportDataFailed => 'Export failed';

  @override
  String get exportDataInProgress => 'Exporting…';

  @override
  String exportDataFileSaved(String path) {
    return 'Saved to $path';
  }

  @override
  String get exportNothingToExport => 'Nothing to export';

  @override
  String get notImplemented => 'Not implemented yet';

  @override
  String get cast => 'Cast';

  @override
  String get castNotSupportedYet => 'Cast is not supported yet';

  @override
  String get cloudSync => 'Cloud sync';

  @override
  String get cloudSyncNotSupportedYet => 'Coming soon';

  @override
  String get cloudSyncNotConfigured => 'Not configured, tap to set up';

  @override
  String get cloudSyncFeatureWebdav => 'WebDAV backup';

  @override
  String get cloudSyncFeatureSync =>
      'Sync favorites and progress across devices';

  @override
  String get enableRecommendedSources => 'Enable Recommended Sources';

  @override
  String get enableRecommendedSourcesHint =>
      'Enable all available recommended sources at once';

  @override
  String recommendedSourcesEnabled(int count) {
    return 'Enabled $count recommended sources';
  }

  @override
  String get castToDevice => 'Cast to device';

  @override
  String castingTo(Object device) {
    return 'Casting to $device';
  }

  @override
  String get castNoDevices => 'No cast devices found';

  @override
  String get castNotSupportedOnDevice =>
      'Casting is not supported on this device';

  @override
  String get castDisconnect => 'Disconnect';

  @override
  String get castDisconnected => 'Casting disconnected';

  @override
  String get pip => 'Picture-in-Picture';

  @override
  String get pipNotSupportedOnDevice =>
      'Picture-in-Picture is not supported on this device';

  @override
  String get pipNotWhileCasting => 'Cannot enter PiP while casting';

  @override
  String get pipNotReady => 'PiP is unavailable until the media is ready';

  @override
  String get pipActionPlay => 'Play';

  @override
  String get pipActionPause => 'Pause';

  @override
  String get pipActionDanmaku => 'Danmaku';

  @override
  String get pipActionRewind => 'Rewind 10s';

  @override
  String get pipActionForward => 'Forward 30s';

  @override
  String get screenshot => 'Screenshot';

  @override
  String get screenshotSaved => 'Screenshot saved';

  @override
  String get screenshotFailed => 'Screenshot failed';

  @override
  String get screenshotPathSetting => 'Screenshot save path';

  @override
  String get screenshotPathDefault => 'Default (Documents/screenshots)';

  @override
  String get imageLoadFailed => 'Image load failed';

  @override
  String get imageFavoriteGalleryTitle => 'Image Favorites';

  @override
  String get imageFavoriteEmpty => 'No favorited images yet';

  @override
  String get imageFavoriteDeleteConfirm => 'Delete this favorited image?';

  @override
  String get imageFavoriteDeleted => 'Removed from image favorites';

  @override
  String get seriesTitle => 'Series';

  @override
  String get seasonsTitle => 'Seasons';

  @override
  String episodeCount(int count) {
    return '$count episodes';
  }

  @override
  String seasonCount(int count) {
    return '$count seasons';
  }

  @override
  String get imageFilter => 'Image Filter';

  @override
  String get brightness => 'Brightness';

  @override
  String get contrast => 'Contrast';

  @override
  String get colorTemperature => 'Color Temperature';

  @override
  String get saturation => 'Saturation';

  @override
  String get hue => 'Hue';

  @override
  String get resetFilter => 'Reset Filter';

  @override
  String get saveImage => 'Save Image';

  @override
  String get shareImage => 'Share Image';

  @override
  String imageSavedTo(String path) {
    return 'Image saved to $path';
  }

  @override
  String get imageSaveFailed => 'Failed to save image';

  @override
  String get imagePathCopied => 'Image path copied to clipboard';

  @override
  String get chineseConverter => 'Chinese Conversion';

  @override
  String get noConvert => 'No Conversion';

  @override
  String get traditionalToSimplified => 'Traditional to Simplified';

  @override
  String get simplifiedToTraditional => 'Simplified to Traditional';

  @override
  String get autoPageInterval => 'Auto Page Interval';

  @override
  String get autoPageSmooth => 'Smooth Auto-Page';

  @override
  String get autoPageOff => 'Off';

  @override
  String get pauseAutoPage => 'Pause Auto Page';

  @override
  String get resumeAutoPage => 'Resume Auto Page';

  @override
  String get customFont => 'Custom Font';

  @override
  String get fontMonospace => 'Monospace';

  @override
  String get addBookmark => 'Add Bookmark';

  @override
  String get bookmarkList => 'Bookmark List';

  @override
  String get bookmarkAdded => 'Bookmark Added';

  @override
  String get novelSwipeKeepGoing => 'Keep swiping down to add bookmark';

  @override
  String get novelSwipeRelease => 'Release to add bookmark';

  @override
  String get novelSwipeReleaseRemove => 'Release to remove bookmark';

  @override
  String get novelBookmarkRemoved => 'Bookmark removed';

  @override
  String get deleteBookmark => 'Delete Bookmark';

  @override
  String get bookmarkBadgeCustom => 'Custom Badge Image';

  @override
  String get bookmarkBadgeReset => 'Reset Default Icon';

  @override
  String get noBookmarks => 'No Bookmarks';

  @override
  String get bookmarkNoteHint => 'Note (optional)';

  @override
  String novelChapterProgress(int current, int total) {
    return 'Ch. $current / $total';
  }

  @override
  String get novelLetterSpacing => 'Letter spacing';

  @override
  String get novelFontStyle => 'Font style';

  @override
  String get fontBold => 'Bold';

  @override
  String get fontItalic => 'Italic';

  @override
  String get fontUnderline => 'Underline';

  @override
  String get novelTextColor => 'Text color';

  @override
  String get novelTextColorFollowBg => 'Auto (follow background)';

  @override
  String get novelShadowColor => 'Shadow color';

  @override
  String get novelShadowColorAuto => 'Auto (text color, translucent)';

  @override
  String get novelSectionText => 'Reading basics';

  @override
  String get novelSectionTitle => 'Chapter Title';

  @override
  String get novelSectionColor => 'Color & Background';

  @override
  String get novelSectionPage => 'Page & Gesture';

  @override
  String get novelWheelInverted => 'Invert mouse wheel page direction';

  @override
  String get novelSectionMisc => 'Other';

  @override
  String get novelSectionPreDownload => 'Pre-download';

  @override
  String get preDownloadEnabled =>
      'Pre-download upcoming chapters while reading';

  @override
  String get preDownloadThreshold =>
      'Trigger threshold (current chapter progress)';

  @override
  String get preDownloadCount => 'Chapters to pre-download';

  @override
  String preDownloadStarted(Object count) {
    return 'Pre-downloading next $count chapters in background';
  }

  @override
  String preDownloadDone(Object count) {
    return 'Pre-downloaded $count chapters';
  }

  @override
  String get preDownloadFailedHint =>
      'Pre-download failed (may need verification or network timed out)';

  @override
  String get localReadContinueOnline =>
      'Local content finished, switching to online to continue…';

  @override
  String get localContinueOnlineFailed => 'Failed to continue online';

  @override
  String get localContinueOnlineUpToDate => 'You have read the latest content';

  @override
  String get novelShowChapterTitle => 'Show chapter title in body';

  @override
  String get novelTitleFontScale => 'Title font scale';

  @override
  String get novelTitleBold => 'Title bold';

  @override
  String get novelTitleColor => 'Title color';

  @override
  String get novelTitleColorAuto => 'Follow accent color';

  @override
  String get importShuyuan => 'Import Book Source';

  @override
  String get shuyuanImportTitle => 'Import Book Source';

  @override
  String get shuyuanImportHint =>
      'Supports book source rules (@css/@xpath/@json/@js + ## regex)';

  @override
  String get shuyuanImportFromUrl => 'URL';

  @override
  String get shuyuanImportFromFile => 'File';

  @override
  String get shuyuanImportFromJson => 'JSON';

  @override
  String get shuyuanImportUrlHint => 'URL of book source JSON';

  @override
  String get shuyuanImportJsonHint => 'Paste book source JSON config';

  @override
  String get shuyuanImportFilePicker => 'Select Book Source File';

  @override
  String get shuyuanImportParse => 'Parse';

  @override
  String get shuyuanImportParsing => 'Parsing…';

  @override
  String get shuyuanImportParseFailed =>
      'Parse failed, no valid book sources detected';

  @override
  String shuyuanImportPreview(int count) {
    return 'Preview ($count)';
  }

  @override
  String get shuyuanImportSaveAll => 'Import All';

  @override
  String get shuyuanImportEmpty => 'No parsed results';

  @override
  String get shuyuanImportValid => 'Valid';

  @override
  String get shuyuanImportInvalid => 'Invalid';

  @override
  String get shuyuanImportTypeUnsupported => 'Unsupported type (text only)';

  @override
  String shuyuanImportSuccess(int count) {
    return 'Imported $count book sources';
  }

  @override
  String shuyuanImportSelected(int count) {
    return 'Import $count selected';
  }

  @override
  String get shuyuanImportFailed => 'Import failed';

  @override
  String get shareFailed => 'Share failed';

  @override
  String get openInBrowserFailed => 'Failed to open browser';

  @override
  String get updatedAtLabel => 'Updated: ';

  @override
  String get searchChapter => 'Search chapters';

  @override
  String get noChaptersFound => 'No matching chapters found';

  @override
  String expandRemainingChapters(int count) {
    return 'Show remaining $count chapters';
  }

  @override
  String get sortAscending => 'Ascending';

  @override
  String get sortDescending => 'Descending';

  @override
  String get downloadSingleChapter => 'Download chapter';

  @override
  String get chapterBookmark => 'Chapter bookmark';

  @override
  String get chapterRead => 'Read mark';

  @override
  String get chapterSortMode => 'Chapter sort';

  @override
  String get aggModeFileExpanded =>
      'By file order (EPUB chapters expanded in place)';

  @override
  String get aggModeEpubLast => 'EPUB chapters at the end';

  @override
  String get aggModeCollapsed => 'One chapter per file (EPUB not expanded)';

  @override
  String get continueReading => 'Continue reading';

  @override
  String get continueWatching => 'Continue watching';

  @override
  String get startFromBeginning => 'Start from beginning';

  @override
  String get openInAppBrowser => 'Open in app';

  @override
  String get refreshMetadata => 'Refresh metadata';

  @override
  String get removeFromFavorites => 'Remove from favorites';

  @override
  String get coverViewer => 'Cover';

  @override
  String get downloadPreset1 => 'Download latest 1';

  @override
  String get downloadPreset5 => 'Download latest 5';

  @override
  String get downloadPreset10 => 'Download latest 10';

  @override
  String get downloadUnread => 'Download unread';

  @override
  String get downloadFavorited => 'Download favorited';

  @override
  String get tagLabel => 'Tags';

  @override
  String get sourceLabel => 'Source';

  @override
  String get reloadChapter => 'Reload chapter';

  @override
  String get clearReadingProgress => 'Clear reading progress';

  @override
  String get readingProgressCleared => 'Reading progress cleared';

  @override
  String get novelMenuBookmarkList => 'Bookmark list';

  @override
  String get novelMenuConfigureToolbar => 'Configure bottom toolbar';

  @override
  String get novelTtsBackground => 'Background playback';

  @override
  String get httpTtsEnable => 'Online TTS engine';

  @override
  String get httpTtsEnableDesc =>
      'Synthesize speech online (built-in Edge voices, or a self-hosted/third-party HTTP endpoint)';

  @override
  String get httpTtsProvider => 'Online voice source';

  @override
  String get httpTtsProviderEdge => 'Edge voices';

  @override
  String get httpTtsProviderCustom => 'Custom endpoint';

  @override
  String get httpTtsEdgeHint =>
      'Microsoft Edge read-aloud interface: free online synthesis, no service to configure; usually better than system TTS, requires network';

  @override
  String get httpTtsUrlTemplate => 'URL template';

  @override
  String get httpTtsDefaultVoice => 'Default voice';

  @override
  String get httpTtsVoiceFollowDefault => 'Follow default voice';

  @override
  String get httpTtsVoicePreview => 'Preview';

  @override
  String get httpTtsVoicePreviewSample => 'Hello, this is a voice preview.';

  @override
  String get httpTtsVoicePreviewFail =>
      'Preview failed. Please check the network';

  @override
  String get highlightsSyncNow => 'Sync highlights';

  @override
  String highlightsSyncResult(int uploaded, int applied) {
    return 'Uploaded $uploaded books · merged $applied from cloud';
  }

  @override
  String get highlightsSyncedNone => 'Highlights already up to date';

  @override
  String get highlightsSyncStatusTitle => 'Highlight sync';

  @override
  String highlightsSyncLocal(int total, int books) {
    return '$total highlights · $books books on this device';
  }

  @override
  String get highlightsSyncLastNone => 'Not synced yet';

  @override
  String get highlightsSyncFailed =>
      'Highlight sync failed. Check network and WebDAV settings';

  @override
  String get aiAskSection => 'Ask AI';

  @override
  String get aiAskDesc =>
      'Endpoint for the reader\'s \"Ask AI\" action; falls back to the common endpoint when empty';

  @override
  String get aiGroupGeneration => 'Content generation';

  @override
  String get aiGroupTranslation => 'Translation';

  @override
  String get httpTtsVoiceMap => 'Role → voice (one \'role=voice\' per line)';

  @override
  String get httpTtsConcurrency => 'Preload concurrency (1-8)';

  @override
  String get httpTtsMaxFailures => 'Consecutive failure stop threshold';

  @override
  String get httpTtsSilentPlaceholder => 'Silent placeholder on failure';

  @override
  String get httpTtsSilentPlaceholderDesc =>
      'Skip failed sentences and keep reading; disable to stop immediately';

  @override
  String get novelSectionFont => 'Font style';

  @override
  String get searchInBook => 'Search in book';

  @override
  String get wholeBook => 'Whole book';

  @override
  String get noSearchResults => 'No results';

  @override
  String searchProgress(int searched, int total) {
    return 'Searched $searched/$total chapters';
  }

  @override
  String get customBgColor => 'Custom background';

  @override
  String get tapZoneInvert => 'Tap invert';

  @override
  String get tapInvertNone => 'None';

  @override
  String get tapInvertLeftRight => 'Left/Right';

  @override
  String get tapInvertAll => 'All';

  @override
  String get tapZonePreview => 'Preview tap zones';

  @override
  String get tapZonePrev => 'Prev page';

  @override
  String get tapZoneNext => 'Next page';

  @override
  String get tapZoneToggle => 'Toggle UI';

  @override
  String get startReading => 'Start reading';

  @override
  String get stopReading => 'Stop reading';

  @override
  String get noteList => 'Notes';

  @override
  String get noNotes => 'No notes yet';

  @override
  String get noteEditUnsupported =>
      'Independent notes cannot be edited. Delete and recreate.';

  @override
  String get add => 'Add';

  @override
  String get testConnection => 'Test connection';

  @override
  String get noCustomInstances => 'No custom instances';

  @override
  String get searchByDirector => 'Search by director';

  @override
  String get searchByActor => 'Search by actor';

  @override
  String get searchByTag => 'Search by tag';

  @override
  String get searchAggregate => 'All sources';

  @override
  String get searchSingle => 'Single source';

  @override
  String get searchSelectSource => 'Select a source';

  @override
  String get searchByWork => 'Search by title';

  @override
  String get searchFieldAuthor => 'Author';

  @override
  String get searchFieldDirector => 'Director';

  @override
  String get searchFieldActor => 'Cast';

  @override
  String get searchFieldWork => 'Title';

  @override
  String get rsshubRouteQidian => 'Qidian';

  @override
  String get rsshubRouteJjwxc => 'JJWXC';

  @override
  String get rsshubRouteDoubanBooks => 'Douban Books';

  @override
  String get rsshubRouteDmzj => 'DMZJ';

  @override
  String get rsshubRouteJmcomic => 'JM Comic';

  @override
  String browseNetworkSelectedCount(int count) {
    return 'Selected $count';
  }

  @override
  String get browseNetworkOpenSelected => 'Open';

  @override
  String get browseNetworkDownloadSelected => 'Download';

  @override
  String browseNetworkDownloadStarted(int count) {
    return 'Started downloading $count files';
  }

  @override
  String browseNetworkDownloadDone(int count) {
    return 'Downloaded $count items';
  }

  @override
  String get browseNetworkDownloadFailed => 'Download failed';

  @override
  String get browseNetworkDownloadPathMissing => 'Download path unavailable';

  @override
  String get unknown => 'Unknown';

  @override
  String get rssFeedListTitle => 'RSS subscriptions';

  @override
  String get rssTestAllSpeed => 'Test all speeds';

  @override
  String get rssTestSpeed => 'Test speed';

  @override
  String get rssSpeedFailed => 'Speed test failed';

  @override
  String rssSpeedMs(int ms) {
    return '${ms}ms';
  }

  @override
  String unrecognizedFile(String fileName) {
    return 'Unrecognized file: $fileName';
  }

  @override
  String importFailed(String reason) {
    return 'Import failed: $reason';
  }

  @override
  String get folderScanFailed =>
      'Folder scan failed, please check permissions or path';

  @override
  String get emptyFolder => 'Folder is empty or has no usable files';

  @override
  String get storagePermissionDenied =>
      'Storage permission denied, cannot pick files';

  @override
  String get pickFileNoPath =>
      'Could not get the path of the selected file (possibly a system limitation). Please try another file';

  @override
  String get folderPickUnsupportedSaf =>
      'Folder selection is not supported on this system (Android SAF). Please use \"Select File\" to add files one by one';

  @override
  String folderImportChoiceTitle(Object name) {
    return 'Import folder \"$name\"';
  }

  @override
  String folderImportChoiceHint(Object type) {
    return 'Multiple $type files detected. Merge to treat the whole folder as one work (each file = a chapter/volume), or import each file separately.';
  }

  @override
  String get folderImportChoiceMerge => 'Merge into one work';

  @override
  String get folderImportChoicePerFile => 'Import files separately';

  @override
  String get folderFileSelectTitle => 'Select comic files to import';

  @override
  String folderFileSelectHint(Object count) {
    return 'Found $count files in the folder (each is one chapter). Check the files you want to import.';
  }

  @override
  String get folderFileSelectAll => 'Select all';

  @override
  String get folderFileSelectNone => 'Select none';

  @override
  String get folderFileSelectMerge => 'Merge into one';

  @override
  String get folderFileSelectSeparate => 'Separate entries';

  @override
  String folderFileSelectConfirm(Object count) {
    return 'Import selected ($count)';
  }

  @override
  String get setAsShelfCover => 'Set as shelf cover';

  @override
  String get openDownloadManager => 'Open download manager';

  @override
  String get details => 'Details';

  @override
  String get coverUpdated => 'Cover updated';

  @override
  String get coverUpdateFailed =>
      'Cover update failed: favorite entry not found';

  @override
  String get authorLabel => 'Author';

  @override
  String get statusLabel => 'Status';

  @override
  String get setAsCover => 'Set as cover';

  @override
  String get mediaInfo => 'Media info';

  @override
  String get playExternal => 'Play external';

  @override
  String get loadExternalSubtitle => 'Load external subtitle';

  @override
  String get loadExternalSubtitleFailed => 'External subtitle loading failed';

  @override
  String get danmakuCustomUrl => 'Custom URL';

  @override
  String get danmakuCustomUrlHint => 'Enter danmaku source URL';

  @override
  String get danmakuCustomUrlDesc => 'Load danmaku from a custom URL';

  @override
  String get onlineTabHome => 'Home';

  @override
  String get onlineTabSchedule => 'Schedule';

  @override
  String get onlineTabRanking => 'Ranking';

  @override
  String get filterYear => 'Year';

  @override
  String get filterRegion => 'Region';

  @override
  String get filterSort => 'Sort';

  @override
  String get filterCategory => 'Category';

  @override
  String get filterTag => 'Tag';

  @override
  String get sortHottest => 'Hottest';

  @override
  String get sortRating => 'Rating';

  @override
  String get viewAll => 'View all';

  @override
  String get latestUpdates => 'Latest updates';

  @override
  String get hotRecommendations => 'Hot picks';

  @override
  String get weekdayMon => 'Mon';

  @override
  String get weekdayTue => 'Tue';

  @override
  String get weekdayWed => 'Wed';

  @override
  String get weekdayThu => 'Thu';

  @override
  String get weekdayFri => 'Fri';

  @override
  String get weekdaySat => 'Sat';

  @override
  String get weekdaySun => 'Sun';

  @override
  String get regionChina => 'China';

  @override
  String get regionHongKong => 'Hong Kong, China';

  @override
  String get regionTaiwan => 'Taiwan, China';

  @override
  String get regionJapan => 'Japan';

  @override
  String get regionKorea => 'Korea';

  @override
  String get regionUSA => 'USA';

  @override
  String get regionOther => 'Other';

  @override
  String get unsupportedRarFormat => 'RAR format comics are not supported';

  @override
  String get unsupportedEpubFormat =>
      'EPUB format is not supported, please use a dedicated reader';

  @override
  String get unsupportedFormat => 'This format is not supported';

  @override
  String get localFileLabel => 'Local file';

  @override
  String get localFileLoadFailed => 'Failed to read local file';

  @override
  String get playerDefaultOrientation => 'Lock Orientation';

  @override
  String get playerOrientationAuto => 'Follow System';

  @override
  String get playerOrientationPortrait => 'Portrait';

  @override
  String get playerOrientationLandscape => 'Landscape';

  @override
  String get playerGestureSeekMultiplier => 'Drag Seek Multiplier';

  @override
  String get playerSeekHalf => '0.5x';

  @override
  String get playerSeekNormal => '1x';

  @override
  String get playerSeekDouble => '2x';

  @override
  String get playerLongPressSpeedUp => 'Long Press Speed Boost';

  @override
  String get playerBottomProgress =>
      'Show bottom progress bar when controls hidden';

  @override
  String get playerAutoSelectLine => 'Auto-select available line';

  @override
  String get playerCurrentPlayingLine => 'Currently playing line';

  @override
  String playerLineSwitched(Object line) {
    return 'Switched to line $line';
  }

  @override
  String playerLineFailover(Object from, Object to) {
    return 'Line $from unavailable, switched to line $to';
  }

  @override
  String get playerDefaultVolume => 'Default Volume';

  @override
  String get playerResetEpisodeSettings => 'Reset This Video Settings';

  @override
  String get playerResetEpisodeSettingsDone =>
      'Restored this video to global defaults';

  @override
  String get playerCoreGroup => 'Playback Core';

  @override
  String get playerSubtitleGroup => 'Subtitle';

  @override
  String get playerGestureGroup => 'Gesture & Control';

  @override
  String get playerScreenshotGroup => 'Screenshot';

  @override
  String get novelDefaultGroupTitle => 'Novel Defaults';

  @override
  String get novelDefaultPageTurnAnimation => 'Page Turn Animation';

  @override
  String get novelDefaultFontSize => 'Default font size';

  @override
  String get novelDefaultLineHeight => 'Default line height';

  @override
  String get novelDefaultBackground => 'Background';

  @override
  String get novelDefaultTtsRate => 'TTS Rate';

  @override
  String get novelDefaultChineseConversion => 'Chinese Conversion';

  @override
  String get novelBgWhite => 'White';

  @override
  String get novelBgCream => 'Cream';

  @override
  String get novelBgDarkGray => 'Dark Gray';

  @override
  String get novelBgBlack => 'Black';

  @override
  String get comicDefaultGroupTitle => 'Comic Defaults';

  @override
  String get comicDefaultReadingDirection => 'Reading Direction';

  @override
  String get comicDefaultTapZoneLayout => 'Tap Zone Layout';

  @override
  String get comicDefaultInvertFilter => 'Invert Filter';

  @override
  String get comicDefaultInitialZoom => 'Initial Zoom';

  @override
  String get comicDefaultDoubleTapZoom => 'Double Tap Zoom';

  @override
  String get comicDefaultScrollWheel => 'Scroll Wheel Direction';

  @override
  String get comicTapLayout1 => 'Layout 1';

  @override
  String get comicTapLayout2 => 'Layout 2';

  @override
  String get comicTapLayout3 => 'Layout 3';

  @override
  String get comicTapLayout4 => 'Layout 4';

  @override
  String get comicTapLayout5 => 'Layout 5';

  @override
  String get comicZoomFitWidth => 'Fit Width';

  @override
  String get comicZoomFitHeight => 'Fit Height';

  @override
  String get comicZoomOriginal => 'Original';

  @override
  String get comicZoom2x => '2x';

  @override
  String get comicZoom3x => '3x';

  @override
  String get comicWheelNatural => 'Natural';

  @override
  String get comicWheelInverted => 'Inverted';

  @override
  String get comicDirLtr => 'LTR';

  @override
  String get comicDirRtl => 'RTL';

  @override
  String get comicDirVertical => 'Vertical';

  @override
  String get comicDirWebtoon => 'Webtoon';

  @override
  String get comicDirWebtoonGap => 'Webtoon (gap)';

  @override
  String get danmakuDisplayFontSize => 'Font Size';

  @override
  String get danmakuDisplayOpacity => 'Opacity';

  @override
  String get danmakuDisplayScrollSpeed => 'Scroll Speed';

  @override
  String get danmakuDisplayArea => 'Display Area';

  @override
  String get danmakuDisplayMaxOnScreen => 'Max On Screen';

  @override
  String get danmakuSizeSmall => 'Small';

  @override
  String get danmakuSizeMedium => 'Medium';

  @override
  String get danmakuSizeLarge => 'Large';

  @override
  String get danmakuSpeedSlow => 'Slow';

  @override
  String get danmakuSpeedMedium => 'Medium';

  @override
  String get danmakuSpeedFast => 'Fast';

  @override
  String get danmakuAreaQuarter => 'Quarter';

  @override
  String get danmakuAreaHalf => 'Half';

  @override
  String get danmakuAreaFull => 'Full';

  @override
  String get danmakuMaxTen => '10';

  @override
  String get danmakuMaxTwenty => '20';

  @override
  String get danmakuMaxFifty => '50';

  @override
  String get danmakuMaxHundred => '100';

  @override
  String get danmakuDisplayGroupFilter => 'Filter & Block';

  @override
  String get danmakuDisplayGroupAppearance => 'Appearance';

  @override
  String get danmakuDisplayGroupDisplay => 'Display';

  @override
  String get danmakuDisplayGroupDisplayRange => 'Display Range';

  @override
  String get danmakuDisplayGroupSpeed => 'Speed';

  @override
  String get layoutTypeLabel => 'Layout Type';

  @override
  String get layoutGridLarge => 'Large Grid';

  @override
  String get layoutGridMedium => 'Medium Grid';

  @override
  String get layoutGridSmall => 'Small Grid';

  @override
  String get layoutListComfortable => 'Comfortable List';

  @override
  String get layoutListCompact => 'Compact List';

  @override
  String get layoutGridColumns => 'Grid Columns';

  @override
  String get layoutGridSpacing => 'Grid Spacing';

  @override
  String get layoutCoverRadius => 'Cover Radius';

  @override
  String get layoutTitleFontSize => 'Title Font Size';

  @override
  String get layoutShowTitle => 'Show Title';

  @override
  String get layoutTitleMaxLines => 'Title Max Lines';

  @override
  String get layoutShowAuthor => 'Show Author';

  @override
  String get layoutShowProgress => 'Show Progress';

  @override
  String get layoutOpenSettings => 'Open Layout Settings';

  @override
  String get bookshelfLayoutGroup => 'Bookshelf Layout';

  @override
  String get layoutTypeGroup => 'Global Layout Type';

  @override
  String get layoutGridCoverGroup => 'Grid & Cover';

  @override
  String get layoutDisplayGroup => 'Display Options';

  @override
  String get downloadStatusInProgress => 'In Progress';

  @override
  String get cloudSyncWebdavUrl => 'WebDAV URL';

  @override
  String get cloudSyncWebdavUsername => 'Username';

  @override
  String get cloudSyncWebdavPassword => 'Password';

  @override
  String get cloudSyncTestConnection => 'Test Connection';

  @override
  String cloudSyncConnectionSuccess(int ms) {
    return 'Connected (${ms}ms)';
  }

  @override
  String get cloudSyncConnectionFailed => 'Connection Failed';

  @override
  String get cloudSyncAutoSync => 'Auto Sync';

  @override
  String get cloudSyncSyncFrequencyManual => 'Manual';

  @override
  String get cloudSyncSyncFrequencyDaily => 'Daily';

  @override
  String get cloudSyncSyncFrequencyWeekly => 'Weekly';

  @override
  String get cloudSyncSyncNow => 'Sync Now';

  @override
  String get novelProgressSyncNow => 'Sync reading progress';

  @override
  String get novelProgressConflictTitle => 'Reading progress conflict';

  @override
  String novelProgressConflictBody(int n) {
    return 'Cloud progress is ahead for $n books. Use cloud progress?';
  }

  @override
  String get novelProgressUseRemote => 'Use cloud';

  @override
  String novelProgressSyncedUploaded(int n) {
    return '$n uploaded';
  }

  @override
  String novelProgressSyncedRestored(int n) {
    return '$n restored';
  }

  @override
  String novelProgressSyncedConflicted(int n) {
    return '$n need confirmation';
  }

  @override
  String get novelProgressSyncedNone => 'No progress changes';

  @override
  String cloudSyncLastSyncTime(String time) {
    return 'Last sync: $time';
  }

  @override
  String get cloudSyncNeverSynced => 'Never synced';

  @override
  String get cloudSyncSyncSuccess => 'Sync successful';

  @override
  String get cloudSyncSyncFailed => 'Sync failed';

  @override
  String get cloudSyncSaveConfig => 'Save Config';

  @override
  String get readingProgress => 'Reading progress';

  @override
  String get watchingProgress => 'Watching progress';

  @override
  String get totalChapters => 'Total chapters';

  @override
  String get totalEpisodes => 'Total episodes';

  @override
  String get chaptersRead => 'Read';

  @override
  String get episodesWatched => 'Watched';

  @override
  String get progressLabel => 'Progress';

  @override
  String get layoutModeLabel => 'Layout mode';

  @override
  String get layoutListStyle => 'List style';

  @override
  String get lastReadAt => 'Last read';

  @override
  String get lastWatchedAt => 'Last watched';

  @override
  String get anime => 'Anime';

  @override
  String get episodeList => 'Episodes';

  @override
  String chapterListWithCount(int count) {
    return 'Chapter list ($count)';
  }

  @override
  String episodeListWithCount(int count) {
    return 'Episodes ($count)';
  }

  @override
  String lastReadInfo(String time, String chapter) {
    return 'Last read: $time · $chapter';
  }

  @override
  String lastWatchedInfo(String time, String episode) {
    return 'Last watched: $time · $episode';
  }

  @override
  String get notStartedYet => 'Not started yet';

  @override
  String get timeJustNow => 'Just now';

  @override
  String timeMinutesAgo(int n) {
    return '$n minutes ago';
  }

  @override
  String timeHoursAgo(int n) {
    return '$n hours ago';
  }

  @override
  String timeDaysAgo(int n) {
    return '$n days ago';
  }

  @override
  String get expand => 'Expand';

  @override
  String get collapse => 'Collapse';

  @override
  String expandCount(int count) {
    return 'Show $count more';
  }

  @override
  String get sortSectionTitle => 'Sort';

  @override
  String get displayTitle => 'Display';

  @override
  String sortByIndex(Object unitWord) {
    return 'By $unitWord index';
  }

  @override
  String sortByName(Object unitWord) {
    return 'By $unitWord name';
  }

  @override
  String get sortBySource => 'By source';

  @override
  String get sortByUploadDate => 'By upload date';

  @override
  String get sortAscendingLabel => 'Ascending';

  @override
  String get sortDescendingLabel => 'Descending';

  @override
  String get filterUnread => 'Unread';

  @override
  String get filterDownloaded => 'Downloaded';

  @override
  String get filterBookmarked => 'Bookmarked';

  @override
  String get displaySourceTitle => 'Source title';

  @override
  String displayNumber(Object unitWord) {
    return '$unitWord number';
  }

  @override
  String get resetButton => 'Reset';

  @override
  String get doneButton => 'Done';

  @override
  String get wordCount => 'Word count';

  @override
  String updatedTo(Object n) {
    return 'Updated to $n';
  }

  @override
  String get unitWordChapter => 'chapter';

  @override
  String get unitWordComicChapter => 'chapter';

  @override
  String get unitWordEpisode => 'episode';

  @override
  String get prevPage => 'Previous page';

  @override
  String get nextPage => 'Next page';

  @override
  String get nightMode => 'Night mode';

  @override
  String get toolToc => 'Contents';

  @override
  String get toolPrevChapter => 'Previous chapter';

  @override
  String get toolNextChapter => 'Next chapter';

  @override
  String get toolNightMode => 'Night mode';

  @override
  String get toolAutoPage => 'Auto page';

  @override
  String get toolSettings => 'Settings';

  @override
  String get toolBookmark => 'Bookmark';

  @override
  String get toolBookmarkList => 'Bookmarks';

  @override
  String get toolSearch => 'Search in book';

  @override
  String get toolTts => 'Read aloud';

  @override
  String get configureBottomToolbar => 'Configure toolbar';

  @override
  String get bottomToolbarConfigTitle => 'Bottom toolbar';

  @override
  String get slotsShown => 'Shown';

  @override
  String get slotsHidden => 'Hidden (tap + to add)';

  @override
  String get novelCacheBook => 'Cache';

  @override
  String get novelResetBookPrefs => 'Reset book to default';

  @override
  String get novelResetBookDone => 'Book settings reset to default';

  @override
  String get readerCropEdge => 'Crop edges';

  @override
  String get readerRotatePage => 'Rotate page';

  @override
  String get readerKeepScreenOn => 'Keep screen on';

  @override
  String get readerProgressBarOnRight => 'Progress bar on right';

  @override
  String get readerShowChapterSlider => 'Chapter navigation slider';

  @override
  String get readerShowPageNumber => 'Show page number';

  @override
  String get readerSplitDoublePage => 'Split double page';

  @override
  String get readerSplitDoublePageHint =>
      'Double-page split enabled; switched to horizontal single-page mode';

  @override
  String get readerInitialZoom => 'Initial zoom';

  @override
  String get readerZoomFitWidth => 'Fit width';

  @override
  String get readerZoomFitHeight => 'Fit height';

  @override
  String get readerZoomOriginal => 'Original size';

  @override
  String get readerFullscreen => 'Fullscreen';

  @override
  String get readerLongPressMenu => 'Long-press menu';

  @override
  String get readerGrayscale => 'Grayscale';

  @override
  String get readerPreventShrink => 'Prevent shrink';

  @override
  String get readerChapterTransition => 'Chapter transition';

  @override
  String get readerPreloadCount => 'Preload count';

  @override
  String get readerPreloadCountDesc =>
      'Pages from the chapter end/start to begin preloading adjacent chapters (higher = smoother, uses more data)';

  @override
  String get readerSeamlessReading => 'Seamless cross-chapter reading';

  @override
  String get readerSeamlessReadingDesc =>
      'Keep reading the adjacent chapter right at the chapter end/start using the preloaded cache, without reloading the chapter or flashing white';

  @override
  String get readerChapterSeparator => 'Chapter separator';

  @override
  String get readerChapterSeparatorDesc =>
      'Insert a chapter title card between chapters in webtoon continuous mode';

  @override
  String get readerWebtoonDecodeLimit => 'Limit webtoon decode size';

  @override
  String get readerScrollSpeed => 'Scroll speed';

  @override
  String get readerScrollSpeedDesc =>
      'Multiplier applied to the webtoon scroll amount from the mouse wheel (0.5x–3x)';

  @override
  String get readerVolumeKeyPageTurn => 'Volume key page turn';

  @override
  String get readerVolumeKeyPageTurnDesc =>
      'Intercept volume up/down to turn pages on Android and HarmonyOS (paged: turn page; webtoon: scroll by distance)';

  @override
  String get readerVolumeKeyDistance => 'Volume key scroll distance';

  @override
  String get readerVolumeKeyDistanceDesc =>
      'How far the volume key scrolls in webtoon mode (percent of viewport height)';

  @override
  String get readerLongPressZoom => 'Long-press to zoom';

  @override
  String get readerLongPressZoomDesc =>
      'Long-press enters 1.75x zoom (long-press/release exits); when off, long-press shows the menu';

  @override
  String get readerLongPressAtPress => 'At press point';

  @override
  String get readerLongPressAtCenter => 'Screen center';

  @override
  String get readerLongPressZoomPosition => 'Long-press zoom anchor';

  @override
  String get readerZoomStart => 'Zoom anchor';

  @override
  String get readerZoomStartLeft => 'Left';

  @override
  String get readerZoomStartCenter => 'Center';

  @override
  String get readerZoomStartRight => 'Right';

  @override
  String get readerAutoPageTurning => 'Auto page turning';

  @override
  String get readerAutoPageTurningDesc =>
      'Automatically turn pages in paged mode at a fixed interval (0 = off)';

  @override
  String get readerAutoPageInterval => 'Auto page interval (s)';

  @override
  String get readerAutoScroll => 'Auto scroll';

  @override
  String get readerAutoScrollDesc =>
      'Smoothly auto-scroll in webtoon mode at the scroll speed above';

  @override
  String get readerSleepTimer => 'Sleep timer';

  @override
  String get readerSleepTimerDesc =>
      'Pause reading after a set time or chapter count';

  @override
  String get readerSleepTimerOff => 'Turn off timer';

  @override
  String readerSleepTimerChapters(Object count) {
    return 'Pause after $count more chapters';
  }

  @override
  String get readerSleepTimerFired => 'Sleep timer fired, reading paused';

  @override
  String get readerPageAnimation => 'Page transition animation';

  @override
  String get readerPageAnimNone => 'None';

  @override
  String get readerPageAnimSlide => 'Slide';

  @override
  String get readerPageAnimFade => 'Fade';

  @override
  String get motionEffectTitle => 'Motion effects';

  @override
  String get motionEffectDesc =>
      'Render static comic pages into layered motion (parallax / breathing / particles / light / manga action). Works in paged and webtoon modes';

  @override
  String get motionEffectEnabled => 'Enable motion effects';

  @override
  String get motionEffectEnabledDesc =>
      'About a second after you stop on a page (page turn or scroll settle) it is rendered in the background; toggle and tune each effect below';

  @override
  String get motionInteractiveTitle => 'Interactive reading';

  @override
  String get motionInteractiveDesc =>
      'In single-page paged mode, tap the centre of the page to focus it and reveal the motion through a tear; tap again to dismiss. Zoomed, rotated, webtoon and double-page views keep the plain motion overlay';

  @override
  String get motionEffectStateOff => 'Off';

  @override
  String get motionEffectStateOn => 'On';

  @override
  String get motionPresets => 'Quick presets';

  @override
  String get motionPresetClassic => 'Classic';

  @override
  String get motionPresetSakura => 'Sakura';

  @override
  String get motionPresetNightRain => 'Night rain';

  @override
  String get motionPresetStarryNight => 'Starry night';

  @override
  String get motionPresetBattle => 'Battle';

  @override
  String get motionQuality => 'Quality & smoothness';

  @override
  String get motionFps => 'Frame rate';

  @override
  String get motionDuration => 'Loop duration';

  @override
  String get motionResolution => 'Render resolution cap';

  @override
  String get motionQualityHint =>
      'Higher values look sharper but render slower and produce larger GIFs. Pages are rendered in the background shortly after you stop on them; zooming in temporarily falls back to the static image';

  @override
  String get motionWebtoonModeTitle => 'Webtoon render timing';

  @override
  String get motionWebtoonModeDwell => 'On settle (battery saver)';

  @override
  String get motionWebtoonModeFollow => 'Realtime follow (more battery)';

  @override
  String get motionWebtoonModeHint =>
      'On settle: visible pages are rendered only after scrolling stops for about a second. Realtime follow: the render target switches as your view moves — a fast preview (fewer frames / lower resolution) appears while scrolling and is automatically upgraded to full quality once you stop, at higher CPU / battery cost';

  @override
  String get motionEffectCountHint =>
      'Each effect can be toggled independently and expanded to tune its parameters. Turning all off equals a static page';

  @override
  String get motionGroupAmbient => 'Ambient basics';

  @override
  String get motionGroupParticles => 'Particles & weather';

  @override
  String get motionGroupLight => 'Light & shadow';

  @override
  String get motionGroupManga => 'Manga action';

  @override
  String get motionFxParallax => 'Parallax';

  @override
  String get motionFxBreathing => 'Breathing';

  @override
  String get motionFxSlowPush => 'Slow push-in';

  @override
  String get motionFxHeartbeat => 'Heartbeat';

  @override
  String get motionFxToneShift => 'Tone shift';

  @override
  String get motionFxVignette => 'Vignette';

  @override
  String get motionFxAmbient => 'Ambient particles';

  @override
  String get motionFxDust => 'Dust';

  @override
  String get motionFxRain => 'Rain';

  @override
  String get motionFxSnow => 'Snow';

  @override
  String get motionFxSakura => 'Sakura petals';

  @override
  String get motionFxLeaves => 'Falling leaves';

  @override
  String get motionFxBubbles => 'Bubbles';

  @override
  String get motionFxFireflies => 'Fireflies';

  @override
  String get motionFxEmbers => 'Embers';

  @override
  String get motionFxMeteors => 'Meteors';

  @override
  String get motionFxFog => 'Fog';

  @override
  String get motionFxSmoke => 'Smoke';

  @override
  String get motionFxFlame => 'Flame';

  @override
  String get motionFxGodRays => 'God rays';

  @override
  String get motionFxLightSweep => 'Light sweep';

  @override
  String get motionFxShimmer => 'Shimmer';

  @override
  String get motionFxStarlight => 'Starlight';

  @override
  String get motionFxLightning => 'Lightning';

  @override
  String get motionFxImpactFlash => 'Impact flash';

  @override
  String get motionFxSpeedLines => 'Speed lines';

  @override
  String get motionFxFocusLines => 'Focus lines';

  @override
  String get motionFxScreenTone => 'Screen tone';

  @override
  String get motionFxMangaShake => 'Screen shake';

  @override
  String get motionFxImpactRings => 'Impact rings';

  @override
  String get motionFxBrushStreak => 'Brush streaks';

  @override
  String get motionFxMoodScript => 'Mood modulation';

  @override
  String get motionParamAmplitude => 'Amplitude';

  @override
  String get motionParamPeriod => 'Period (s)';

  @override
  String get motionParamVerticalRatio => 'Vertical ratio';

  @override
  String get motionParamPushFrac => 'Push amount';

  @override
  String get motionParamBeats => 'Beats';

  @override
  String get motionParamIntensity => 'Intensity';

  @override
  String get motionParamShift => 'Shift';

  @override
  String get motionParamStrength => 'Depth';

  @override
  String get motionParamCount => 'Count';

  @override
  String get motionParamSpeed => 'Speed';

  @override
  String get motionParamOpacity => 'Opacity';

  @override
  String get motionParamAngle => 'Angle';

  @override
  String get motionParamSize => 'Size';

  @override
  String get motionParamSpin => 'Spins';

  @override
  String get motionParamGlow => 'Glow';

  @override
  String get motionParamLengthFrac => 'Length';

  @override
  String get motionParamBlobs => 'Blobs';

  @override
  String get motionParamPuffs => 'Puffs';

  @override
  String get motionParamTongues => 'Tongues';

  @override
  String get motionParamRows => 'Rows';

  @override
  String get motionParamStrikes => 'Strikes';

  @override
  String get motionParamFlashes => 'Flashes';

  @override
  String get motionParamPulses => 'Pulses';

  @override
  String get motionParamLines => 'Lines';

  @override
  String get motionParamSpacing => 'Spacing';

  @override
  String get motionParamDensity => 'Density';

  @override
  String get motionParamShakes => 'Shakes';

  @override
  String get motionParamRings => 'Rings';

  @override
  String get motionParamStreaks => 'Streaks';

  @override
  String get motionParamHeightFrac => 'Height';

  @override
  String get readerDoubleTapAnimSpeed => 'Double-tap zoom animation';

  @override
  String get readerDoubleTapAnimSpeedDesc =>
      'Duration of the double-tap zoom animation in milliseconds (scaled with system reduce-motion)';

  @override
  String get readerPageSpacing => 'Page spacing';

  @override
  String get readerPageSpacingDesc => 'Gap between webtoon pages (px)';

  @override
  String get readerShowSingleImageOnFirstPage => 'Single image on first page';

  @override
  String get readerShowSingleImageOnFirstPageDesc =>
      'Show the first page alone in spread mode on chapter one, then resume spread';

  @override
  String get readerClockBattery => 'Clock / battery overlay';

  @override
  String get readerClockBatteryDesc =>
      'Show current time and battery in the reader, toggled with the controls';

  @override
  String get readerClockPosition => 'Overlay position';

  @override
  String get readerClockPosTop => 'Top';

  @override
  String get readerClockPosBottom => 'Bottom';

  @override
  String get readerClockMargin => 'Margin';

  @override
  String get readerClockOpacity => 'Opacity';

  @override
  String get readerClockFontSize => 'Font size';

  @override
  String get readerBrightness => 'Reading brightness';

  @override
  String get readerBrightnessDesc =>
      'Positive writes to system brightness; negative dims system brightness and overlays a black mask';

  @override
  String get readerNightLight => 'Night light';

  @override
  String get readerNightLightDesc =>
      'Overlay a warm tint to reduce blue light; independent of reading brightness';

  @override
  String get readerNightLightOpacity => 'Night light intensity';

  @override
  String get readerAutoDownload => 'Auto-download later chapters';

  @override
  String get readerAutoDownloadDesc =>
      'Queue later chapters for download after reading 25% of the current one (silent on failure)';

  @override
  String get readerSkipReadChapters => 'Skip read chapters';

  @override
  String get readerSkipReadChaptersDesc =>
      'Skip already-read chapters when going to the next/previous chapter';

  @override
  String get readerSkipFilteredChapters => 'Skip filtered chapters';

  @override
  String get readerSkipFilteredChaptersDesc =>
      'Skip filtered chapters when going to the next/previous chapter';

  @override
  String get readerSkipDuplicateChapters => 'Skip duplicate chapters';

  @override
  String get readerSkipDuplicateChaptersDesc =>
      'Skip chapters with duplicate titles when going to the next/previous chapter';

  @override
  String get readerColorProfile => 'Color profile';

  @override
  String get readerColorProfileNone => 'None';

  @override
  String get readerColorProfileSrgb => 'sRGB';

  @override
  String get readerColorProfileWarm => 'Warm';

  @override
  String get readerColorProfileCool => 'Cool';

  @override
  String get readerColorProfileManga => 'Manga';

  @override
  String get readerColorProfilePaper => 'Paper';

  @override
  String get readerEInkRefresh => 'E-Ink refresh';

  @override
  String get readerEInkRefreshDesc =>
      'E-ink ghosting fix: auto full-screen flash by page-turn interval';

  @override
  String get readerEInkRefreshInterval => 'Refresh interval (pages)';

  @override
  String get readerEInkRefreshDuration => 'Refresh duration (ms)';

  @override
  String get readerEInkRefreshWhite => 'White flash';

  @override
  String get readerEInkRefreshBlack => 'Black flash';

  @override
  String get readerEInkRefreshStyle => 'Refresh style';

  @override
  String get readerGroupEInk => 'E-Ink refresh';

  @override
  String get readerGroupEInkDesc =>
      'E-ink devices only: anti-ghosting full-screen refresh';

  @override
  String get readerAutoFavorite => 'Auto-favorite';

  @override
  String get readerAutoFavoriteDesc =>
      'Add to favorites when opening a comic (skips if already favorited)';

  @override
  String get readerScreenPicNumberPortrait => 'Images per screen (portrait)';

  @override
  String get readerScreenPicNumberLandscape => 'Images per screen (landscape)';

  @override
  String get readerScreenPicNumberDesc =>
      'Stack multiple images vertically per screen (1–5)';

  @override
  String get readerChapterBookmark => 'Bookmark this chapter';

  @override
  String get readerChapterBookmarked => 'Chapter bookmarked';

  @override
  String get readerChapterBookmarkRemoved => 'Chapter bookmark removed';

  @override
  String get readerImageFavorite => 'Image favorites';

  @override
  String get readerFavoriteImage => 'Favorite this image';

  @override
  String get imageFavoriteAdded => 'Image favorited';

  @override
  String get imageFavoriteRemoved => 'Image unfavorited';

  @override
  String get imageFavoriteAdd => 'Save to gallery';

  @override
  String get imageFavoriteSourceComic => 'Comic';

  @override
  String get imageFavoriteSourcePlayer => 'Media';

  @override
  String get imageFavoriteSourceNovel => 'Novel';

  @override
  String get imageFavoriteAll => 'All';

  @override
  String get imageFavoriteSearchHint => 'Search title, work or link';

  @override
  String get imageFavoriteSortNewest => 'Newest';

  @override
  String get imageFavoriteSortOldest => 'Oldest';

  @override
  String get imageFavoriteSortTitle => 'By title';

  @override
  String imageFavoriteCount(Object count) {
    return '$count images';
  }

  @override
  String get imageFavoriteNoMatch => 'No matching favorites';

  @override
  String get imageFavoriteFilter => 'Filter by source';

  @override
  String get imageFavoriteTimeAll => 'All time';

  @override
  String get imageFavoriteTimeToday => 'Today';

  @override
  String get imageFavoriteTimeWeek => 'This week';

  @override
  String get imageFavoriteTimeMonth => 'This month';

  @override
  String get imageFavoriteTimeYear => 'This year';

  @override
  String get imageFavoriteTimeOlder => 'Earlier';

  @override
  String get imageFavoriteLayoutGrid => 'Grid';

  @override
  String get imageFavoriteLayoutMasonry => 'Masonry';

  @override
  String get imageFavoriteGroupByWork => 'By work';

  @override
  String get imageFavoriteDisplayOptions => 'Display & sort';

  @override
  String get imageFavoriteShowTitle => 'Show title';

  @override
  String get imageFavoriteShowTime => 'Show time';

  @override
  String get imageFavoriteRename => 'Rename title';

  @override
  String get imageFavoriteRenamed => 'Renamed';

  @override
  String get imageFavoriteTitleHint => 'New title';

  @override
  String get imageFavoriteAllFolders => 'All folders';

  @override
  String get backToFolders => 'Back to folders';

  @override
  String get imageFavoriteFiltersToggle => 'Collapse / expand filters';

  @override
  String get imageFavoriteUnfiled => 'Unfiled';

  @override
  String get imageFavoriteNewFolder => 'New folder';

  @override
  String get imageFavoriteFolderHint => 'Folder name';

  @override
  String get imageFavoriteDeleteFolder => 'Delete folder';

  @override
  String imageFavoriteDeleteFolderConfirm(Object folder) {
    return 'Delete folder $folder? Images inside will return to unfiled';
  }

  @override
  String imageFavoriteSelected(Object count) {
    return '$count selected';
  }

  @override
  String get imageFavoriteSelectAll => 'Select all';

  @override
  String get imageFavoriteMoveTo => 'Move to folder';

  @override
  String get imageFavoriteMoved => 'Moved';

  @override
  String imageFavoriteDeleteMulti(Object count) {
    return 'Delete $count selected images?';
  }

  @override
  String get imageFavoriteRenameSingle => 'Select exactly one image to rename';

  @override
  String get imageFavoriteGalleryDesc =>
      'Unified gallery of comic pages, player screenshots and novel images (folders / multi-select)';

  @override
  String get readingQueueTitle => 'Reading queue';

  @override
  String get readingQueueAdd => 'Add to reading queue';

  @override
  String get readingQueueAdded => 'Added to reading queue';

  @override
  String get readingQueueOpen => 'Reading queue';

  @override
  String get readingQueueEmpty =>
      'Reading queue is empty\nAdd works from the work menu or bookshelf long-press';

  @override
  String get readingQueueClear => 'Clear';

  @override
  String readingQueueLoading(Object title) {
    return 'Opening $title…';
  }

  @override
  String get readingQueueLoadFailed => 'Failed to open queued work';

  @override
  String get readingQueueTypeNovel => 'Novel';

  @override
  String get readingQueueTypeComic => 'Comic';

  @override
  String readerClockBatteryPercent(int percent) {
    return '$percent%';
  }

  @override
  String get comicDefaultFullscreen => 'Fullscreen';

  @override
  String get comicDefaultLongPressMenu => 'Long-press menu';

  @override
  String get comicDefaultGrayscale => 'Grayscale';

  @override
  String get comicDefaultPreventShrink => 'Prevent shrink';

  @override
  String get comicDefaultChapterTransition => 'Chapter transition';

  @override
  String get copyImage => 'Copy image';

  @override
  String get copyImageSuccess => 'Image copied to clipboard';

  @override
  String get copyImageFailed => 'Failed to copy image';

  @override
  String chapterTransitionCard(Object title) {
    return 'Chapter: $title';
  }

  @override
  String get readerProgress => 'Progress';

  @override
  String get regexSearch => 'Regex';

  @override
  String get locateCurrent => 'Locate current';

  @override
  String get scrollToTop => 'Top';

  @override
  String get scrollToBottom => 'Bottom';

  @override
  String get bookmarkedHint => 'Bookmarked';

  @override
  String get playerFullscreen => 'Fullscreen';

  @override
  String get playerExitFullscreen => 'Exit fullscreen';

  @override
  String get playerScreenshot => 'Screenshot';

  @override
  String get playerBrightness => 'Brightness';

  @override
  String get playerVolume => 'Volume';

  @override
  String get playerSuperRes => 'Super resolution';

  @override
  String get playerLine => 'Playback line';

  @override
  String get playerSelectLine => 'Select line';

  @override
  String get playerLineEmpty =>
      'No playback lines (parse failed or source did not provide a video URL).';

  @override
  String get playerLineSingleHint =>
      'This source returned only 1 line; no switch available.\nTo enable line switching, ask the source author to return a `urls` array in the video parser.';

  @override
  String playerLineEpisodesProgress(int current, int total) {
    return 'Episode $current / $total';
  }

  @override
  String get playerEpisodes => 'Episodes';

  @override
  String get playerPip => 'Picture in picture';

  @override
  String get playerCast => 'Cast';

  @override
  String get playerMore => 'More';

  @override
  String get seekForward10 => 'Forward 10s';

  @override
  String get seekBackward10 => 'Backward 10s';

  @override
  String get playerSeekCancel => 'Seek canceled';

  @override
  String get playerSkipOpEd => 'Skip intro & outro';

  @override
  String get playerSkipOp => 'Skip intro';

  @override
  String get playerSkipEd => 'Skip outro';

  @override
  String get playerSkipOpEndLabel => 'Intro ends (m:ss)';

  @override
  String get playerSkipEdStartLabel => 'Outro starts (m:ss)';

  @override
  String get playerSkipUseCurrent => 'Use current';

  @override
  String get playerSkipAuto => 'Auto skip';

  @override
  String get playerSkipHint =>
      'Leave empty to disable. Applies to all episodes of this series.';

  @override
  String get novelReadingSummary => 'Reading overview';

  @override
  String get novelParagraphTranslate => 'Paragraph translation';

  @override
  String get novelTranslateAction => 'Translate chapter';

  @override
  String get novelTranslateRetranslate => 'Re-translate';

  @override
  String get translationStaleNotice =>
      'The source, glossary, or translation style has changed. The cached translation may be outdated.';

  @override
  String get translationRefinedMode =>
      'Refined mode (3-draft synthesis, ≈4× tokens)';

  @override
  String novelTranslateProgress(String done, String total) {
    return '$done of $total paragraphs';
  }

  @override
  String get novelTranslateNoApi =>
      'Translation failed — configure the cloud AI endpoint in Reading Overview';

  @override
  String get novelTranslating => 'Translating…';

  @override
  String get novelTranslateHint =>
      'Tap Translate chapter to render a bilingual view of this chapter';

  @override
  String get novelContentEdit => 'Edit chapter content';

  @override
  String get novelContentEditHint =>
      'One paragraph per block; lines starting with @@NEXHUB_IMG@@ are illustrations and @@NEXHUB_TITLE@@ marks headings';

  @override
  String get novelContentEditSaved => 'Chapter content updated';

  @override
  String get novelContentEditEmpty => 'Nothing to save: content is empty';

  @override
  String get novelContentEditBadge => 'edited';

  @override
  String get novelContentEditRestore => 'Restore original';

  @override
  String get novelContentEditRestoreConfirm =>
      'Discard your edits and restore the chapter to its original content?';

  @override
  String get novelContentEditRestored => 'Original content restored';

  @override
  String novelSummaryProgress(int read, int total) {
    return 'Progress: chapter $read of $total';
  }

  @override
  String get novelSummaryTotalRead => 'Total reading time';

  @override
  String get novelSummaryToday => 'Today';

  @override
  String novelSummarySessionsValue(int count) {
    return '$count sessions';
  }

  @override
  String novelSummaryRemaining(String duration) {
    return 'Est. time to finish: $duration';
  }

  @override
  String novelSummaryCurrentChars(int count) {
    return '$count chars in this chapter';
  }

  @override
  String novelDurationHourMin(int h, int m) {
    return '${h}h ${m}m';
  }

  @override
  String novelDurationHour(int h) {
    return '${h}h';
  }

  @override
  String novelDurationMin(int m) {
    return '$m min';
  }

  @override
  String get novelSummaryNoStats => 'No reading stats yet';

  @override
  String novelSummaryPosition(String chapter, int page, int pages) {
    return 'Now: $chapter · page $page/$pages';
  }

  @override
  String get playerAutoPlayCountdown => 'Auto-play next countdown';

  @override
  String get playerCountdownImmediate => 'Immediate';

  @override
  String playerAutoNextCountdown(int left) {
    return 'Next episode in ${left}s';
  }

  @override
  String get novelTitleAlignLeft => 'Left';

  @override
  String get novelTitleAlignCenter => 'Center';

  @override
  String get novelTitleAlignRight => 'Right';

  @override
  String get novelTitleAlignHidden => 'Hidden';

  @override
  String get novelSectionToolbar => 'Bottom toolbar';

  @override
  String get novelSectionTts => 'TTS Settings';

  @override
  String get ttsRate => 'Speech rate';

  @override
  String get ttsPlaybackFailed =>
      'Reading failed. Check the system speech engine.';

  @override
  String get ttsSleepTimer => 'Sleep timer';

  @override
  String get ttsSleepOff => 'Off';

  @override
  String get ttsSleepCustom => 'Custom';

  @override
  String get ttsSleepCustomMinutes => 'Custom minutes';

  @override
  String ttsSleepRemaining(int min, int sec) {
    return 'Remaining $min min $sec sec';
  }

  @override
  String get ttsPrevSentence => 'Previous sentence';

  @override
  String get ttsPauseOrResume => 'Pause / Resume';

  @override
  String get ttsExit => 'Exit reading';

  @override
  String get ttsNextSentence => 'Next sentence';

  @override
  String minuteUnit(int minutes) {
    return '$minutes min';
  }

  @override
  String get novelFontFileGroup => 'Font file & emphasis color';

  @override
  String get novelChooseFontFile => 'Body font file';

  @override
  String get novelTitleFontFile => 'Title font file';

  @override
  String get novelResetConfirm =>
      'Reset all novel reader settings to default? This cannot be undone.';

  @override
  String get novelSettingsSearch => 'Search settings';

  @override
  String get novelSettingsCommon => 'Common';

  @override
  String get novelSettingsNoResult => 'No matching settings';

  @override
  String novelFontFileCurrent(String name) {
    return 'Selected: $name';
  }

  @override
  String get novelClearFontFile => 'Clear font file';

  @override
  String get novelEmphasisColor => 'Emphasis color';

  @override
  String get novelEmphasisColorAuto => 'Auto (title color)';

  @override
  String get novelSectionShadowUnderline => 'Shadow & underline';

  @override
  String get novelShadowBlur => 'Shadow blur radius';

  @override
  String get novelShadowOffsetX => 'Shadow horizontal offset';

  @override
  String get novelShadowOffsetY => 'Shadow vertical offset';

  @override
  String get novelUnderlineColor => 'Underline color';

  @override
  String get novelUnderlineColorAuto => 'Auto (body color)';

  @override
  String get novelUnderlineDashed => 'Dashed underline';

  @override
  String get novelUnderlineStyle => 'Underline style';

  @override
  String get novelUnderlineStyleSolid => 'Solid';

  @override
  String get novelUnderlineStyleDashed => 'Dashed';

  @override
  String get novelUnderlineStyleWavy => 'Wavy';

  @override
  String get novelUnderlineStyleDotted => 'Dotted';

  @override
  String get novelFontWeightFine => 'Bold weight (100-900)';

  @override
  String get novelTextAlignMode => 'Text alignment';

  @override
  String get novelTextAlignStart => 'Natural (left)';

  @override
  String get novelTextAlignJustify => 'Justified';

  @override
  String get novelLineBreakMode => 'CJK line breaking';

  @override
  String get novelLineBreakStandard => 'Native wrapping';

  @override
  String get novelLineBreakCjkStrict => 'Char-wise + kinsoku';

  @override
  String get novelScrollImageMode => 'Scroll image style';

  @override
  String get novelScrollImageModeBanner => 'Full-width';

  @override
  String get novelScrollImageModeCard => 'Card';

  @override
  String get novelScrollImageAlign => 'Image alignment';

  @override
  String get novelScrollImageAlignLeft => 'Left';

  @override
  String get novelScrollImageAlignCenter => 'Center';

  @override
  String get novelScrollImageAlignRight => 'Right';

  @override
  String get novelUnderlineThickness => 'Underline thickness';

  @override
  String get novelUnderlineDashLength => 'Dash length';

  @override
  String get novelUnderlineDashGap => 'Dash gap';

  @override
  String get novelTitlePosition => 'Title position';

  @override
  String get novelTitleSegmentMode => 'Title segment mode';

  @override
  String get novelTitleSubScale => 'Sub line font scale';

  @override
  String get novelTitleSegmentSpacing => 'Segment spacing';

  @override
  String get novelTitleSubLineSpacing => 'Sub line height';

  @override
  String get novelTitleTopMargin => 'Title top margin';

  @override
  String get novelTitleBottomMargin => 'Title bottom margin';

  @override
  String get novelSectionHeaderFooter => 'Header & Footer';

  @override
  String get novelHeaderLeft => 'Header left';

  @override
  String get novelHeaderCenter => 'Header center';

  @override
  String get novelHeaderRight => 'Header right';

  @override
  String get novelFooterLeft => 'Footer left';

  @override
  String get novelFooterCenter => 'Footer center';

  @override
  String get novelFooterRight => 'Footer right';

  @override
  String get novelHeaderFooterColor => 'Header & Footer color';

  @override
  String get novelHeaderFooterMargin => 'Header & Footer margin';

  @override
  String get novelHfPageAndProgress => 'Page & progress';

  @override
  String get novelHfBookPageNumber => 'Book page number';

  @override
  String get novelTwoPageMode => 'Dual-page mode';

  @override
  String get novelAiIllustrate => 'AI illustration';

  @override
  String get novelAiIllustrateConfirm =>
      'Generate an illustration for this chapter with the configured cloud AI and append it to the chapter content?';

  @override
  String get novelAiIllustrating => 'Generating illustration…';

  @override
  String get novelAiIllustrateDone => 'Illustration appended to chapter';

  @override
  String get novelAiIllustrateFailed => 'Illustration failed';

  @override
  String get novelTwoPageModeDesc =>
      'In paged mode on wide screens, show two pages side by side like an open book';

  @override
  String get novelHfTimeAndBattery => 'Time & battery';

  @override
  String get layoutDetailGroup => 'Layout Details';

  @override
  String get layoutProgressDisplay => 'Progress Display';

  @override
  String get progressBar => 'Progress Bar';

  @override
  String get progressText => 'Percentage';

  @override
  String get editRoute => 'Edit Route';

  @override
  String get routeTitle => 'Title';

  @override
  String get routeUrl => 'URL';

  @override
  String get routeSaved => 'Route saved';

  @override
  String get requiredHint => 'Required';

  @override
  String get localImportPickFile => 'Pick Local File';

  @override
  String get sourceName => 'Name';

  @override
  String get sourceBaseUrl => 'Base URL';

  @override
  String get sourceCannotEdit => 'Built-in sources cannot be edited';

  @override
  String get sourceCannotDelete => 'Built-in sources cannot be deleted';

  @override
  String get comicVisualZoomGroup => 'Display & Zoom';

  @override
  String get comicPageProgressGroup => 'Page & Progress';

  @override
  String get generalSettingsGroup => 'General';

  @override
  String get playbackProgressGroup => 'Playback Progress';

  @override
  String get playbackModulesSection => 'Module Settings';

  @override
  String get settingsCatAppearance => 'Appearance & Language';

  @override
  String get settingsCatAppearanceDesc => 'Theme, colors, dark mode & language';

  @override
  String get settingsCatPlayback => 'Playback & Reading';

  @override
  String get settingsCatPlaybackDesc =>
      'Player, comic, novel & danmaku display';

  @override
  String get settingsCatContent => 'Config & Network';

  @override
  String get settingsCatContentDesc =>
      'Sources, RSS subscriptions, scraping, AI & network';

  @override
  String get settingsCatDetailAppearance => 'Detail Page Look';

  @override
  String get settingsCatDetailAppearanceDesc =>
      'Cover-based accent & blurred backdrop';

  @override
  String get detailAppearanceDynamicAccent => 'Dynamic accent from cover';

  @override
  String get detailAppearanceDynamicAccentDesc =>
      'Tint the detail page accent with a color pulled from the cover or fetched image';

  @override
  String get detailAppearanceBlurredBg => 'Blurred cover background';

  @override
  String get detailAppearanceBlurredBgDesc =>
      'Replace the white page background with a blurred cover or fetched image; stays white when off';

  @override
  String get detailAppearanceBlurStrength => 'Blur strength';

  @override
  String get detailAppearanceLeftSwipe => 'Swipe-left action';

  @override
  String get detailAppearanceLeftSwipeDesc =>
      'Runs when swiping a chapter row left in the detail page chapter list';

  @override
  String get detailAppearanceRightSwipe => 'Swipe-right action';

  @override
  String get detailAppearanceRightSwipeDesc =>
      'Runs when swiping a chapter row right in the detail page chapter list';

  @override
  String get swipeActionDownload => 'Download';

  @override
  String get swipeActionBookmark => 'Bookmark';

  @override
  String get swipeActionRead => 'Read';

  @override
  String get aiSettingsTitle => 'AI Settings';

  @override
  String get aiSettingsDesc =>
      'Manage AI endpoints & features (summary / illustration / translation)';

  @override
  String get aiCommonApiSection => 'Common API';

  @override
  String get aiCommonApiDesc =>
      'Fallback endpoint for all AI features; a feature-specific endpoint takes priority';

  @override
  String get aiBaseUrl => 'Base URL';

  @override
  String get aiBaseUrlHint => 'e.g. https://api.openai.com/v1';

  @override
  String get aiApiKey => 'API key';

  @override
  String get aiModel => 'Model';

  @override
  String get aiModelHint => 'e.g. gpt-3.5-turbo';

  @override
  String get aiOverrideHint => 'Leave empty to use the common API';

  @override
  String get aiSummarySection => 'Chapter Summary';

  @override
  String get aiSummaryDesc =>
      'Summary mode & dedicated endpoint (empty = common API)';

  @override
  String get aiSummaryMode => 'Summary mode';

  @override
  String get aiIllustrationSection => 'AI Illustration';

  @override
  String get aiIllustrationDesc =>
      'Illustration endpoint & generation options (empty = common API)';

  @override
  String get aiIllustrationModel => 'Image model';

  @override
  String get aiIllustrationModelHint => 'Leave empty for server default';

  @override
  String get aiIllustrationSize => 'Image size';

  @override
  String get aiSaved => 'AI settings saved';

  @override
  String get aiSettingsEntry => 'AI Settings';

  @override
  String get aiSettingsEntryDesc =>
      'AI endpoint, chapter summary, illustration & translation';

  @override
  String get translationSettingsTitle => 'Bilingual / Translation';

  @override
  String get translationSettingsDesc => 'Target language, endpoint & options';

  @override
  String get translationApiSection => 'Translation API';

  @override
  String get translationApiDesc =>
      'Dedicated endpoint; falls back to common API when empty';

  @override
  String get translationTargetLang => 'Target language';

  @override
  String get translationTargetLangHint => 'e.g. Chinese / English / Japanese';

  @override
  String get translationBatchSize => 'Chunk size (paragraphs)';

  @override
  String get translationBatchHint =>
      'Retry in chunks when the whole-chapter request fails';

  @override
  String get translationSaved => 'Translation settings saved';

  @override
  String get translationSettingsEntry => 'Bilingual / Translation';

  @override
  String get translationSettingsEntryDesc =>
      'Target language & endpoint config';

  @override
  String get novelSectionAi => 'AI Features';

  @override
  String get novelAiOpenSummary => 'Open chapter summary';

  @override
  String get novelAiOpenTranslation => 'Open paragraph translation';

  @override
  String get settingsCatData => 'Data & Accounts';

  @override
  String get settingsCatDataDesc => 'Stats, backup, cloud sync & Bangumi';

  @override
  String get settingsCatPrivacy => 'Privacy & Security';

  @override
  String get settingsCatPrivacyDesc => 'Privacy, advanced settings & cache';

  @override
  String get settingsCatAbout => 'About';

  @override
  String get settingsCatAboutDesc => 'Version, license & acknowledgements';

  @override
  String get launchScreenTitle => 'Launch Screen';

  @override
  String get dateFormatTitle => 'Date Format';

  @override
  String get dateFormatDefault => 'Default (yyyy/mm/dd)';

  @override
  String get dateFormatMmDdYy => 'mm/dd/yy';

  @override
  String get dateFormatDdMmYy => 'dd/mm/yy';

  @override
  String get dateFormatYyyyMmDd => 'yyyy-mm-dd';

  @override
  String get dateFormatDdMmmYyyy => 'dd mmm yyyy';

  @override
  String get dateFormatMmmDd => 'mmm dd';

  @override
  String get dateFormatYyyy => 'yyyy';

  @override
  String get comicSettingsOverview => 'Current Settings';

  @override
  String get comicResetConfirm =>
      'Reset all comic reader settings to default? This cannot be undone.';

  @override
  String get on => 'On';

  @override
  String get off => 'Off';

  @override
  String get readerGroupPageTap => 'Page & Tap';

  @override
  String get readerGroupViewFilter => 'Display & Filter';

  @override
  String get readerGroupProgress => 'Progress & Display';

  @override
  String get readerGroupFlash => 'Flash Effect';

  @override
  String get readerGroupAuto => 'Auto (Download / Skip)';

  @override
  String get readerGroupAutoDesc =>
      'Auto-download later chapters and skip read, filtered, or duplicate chapters when navigating.';

  @override
  String get readerGroupOverlay => 'Overlay (Clock / Battery)';

  @override
  String get readerGroupOverlayDesc =>
      'Show the current time and battery in the reader, with position, margin, opacity, and font size.';

  @override
  String get readerGroupMulti => 'Multi-image & Spacing';

  @override
  String get readerGroupMultiDesc =>
      'Multiple images per screen, single image on first page, and page spacing.';

  @override
  String get readerCommonSettings => 'Common';

  @override
  String get readerGroupPageTapDesc =>
      'Basic reading controls: page mode, screen orientation, tap zones, and zoom.';

  @override
  String get readerGroupViewFilterDesc =>
      'Adjust brightness, contrast, color temperature, grayscale, etc.';

  @override
  String get readerGroupProgressDesc =>
      'Page numbers, progress bar, fullscreen, keep-screen-on, rotation, and more.';

  @override
  String get readerGroupFlashDesc =>
      'Flash effect on page turn (simulated page-turn light).';

  @override
  String get readerSearchSettings => 'Search settings…';

  @override
  String get readerGroupMouseWheel => 'Mouse Wheel';

  @override
  String get readerGroupMouseWheelDesc =>
      'Configure what the mouse wheel does (zoom or turn pages) and its scroll direction.';

  @override
  String get readerWheelZoom => 'Zoom';

  @override
  String get readerWheelPage => 'Page';

  @override
  String get readerWheelAction => 'Action';

  @override
  String get favoriteGroups => 'Groups';

  @override
  String get noGroups => 'No groups yet. Create one below.';

  @override
  String get groupAll => 'All';

  @override
  String get groupUngrouped => 'Ungrouped';

  @override
  String get manageGroups => 'Manage groups';

  @override
  String get newGroup => 'New group';

  @override
  String get renameGroup => 'Rename';

  @override
  String get renameHint => 'Enter new name';

  @override
  String get groupName => 'Group name';

  @override
  String get groupNameEmpty => 'Name cannot be empty';

  @override
  String get groupNameDuplicate => 'A group with this name already exists';

  @override
  String get deleteGroup => 'Delete group';

  @override
  String deleteGroupConfirm(Object name) {
    return 'Delete group \"$name\"? Items are only unlinked from it and stay in your favorites.';
  }

  @override
  String get setGroups => 'Set groups';

  @override
  String get filterByGroup => 'Group';

  @override
  String groupItemCount(Object n) {
    return '$n items';
  }

  @override
  String get hideCategory => 'Hide';

  @override
  String get showCategory => 'Show';

  @override
  String get categoryHidden => 'Hidden';

  @override
  String get noGroupsHint =>
      'No categories yet — tap \"New group\" to create one';

  @override
  String get comments => 'Comments';

  @override
  String commentsCount(Object n) {
    return 'Comments ($n)';
  }

  @override
  String get writeComment => 'Write a comment';

  @override
  String get replyComment => 'Reply';

  @override
  String get viewAllComments => 'View all comments';

  @override
  String get allCommentsTitle => 'All comments';

  @override
  String get emptyComments => 'No comments yet';

  @override
  String get beFirstToComment => 'Be the first to comment';

  @override
  String get commentPublish => 'Publish';

  @override
  String get commentHint => 'Share your thoughts…';

  @override
  String get commentPublishSuccess => 'Comment published';

  @override
  String get commentPublishFailed => 'Failed to publish';

  @override
  String get likeAction => 'Like';

  @override
  String get likeFailed => 'Failed to like';

  @override
  String get reportAction => 'Report';

  @override
  String get reportSuccess => 'Reported';

  @override
  String get reportFailed => 'Failed to report';

  @override
  String get viewMoreReplies => 'More replies';

  @override
  String get commentsLoadFailed => 'Failed to load comments';

  @override
  String get loginToComment => 'Log in to comment';

  @override
  String get loginRequired => 'Login required for this action';

  @override
  String get sourceLogin => 'Source login';

  @override
  String get getCookie => 'Get Cookie';

  @override
  String get cookieNotFoundHint =>
      'No login cookie detected. Confirm you are signed in, then retry';

  @override
  String get webLogin => 'Web login';

  @override
  String get webLoginDesc =>
      'Log in on the site page; the session is captured automatically';

  @override
  String get pasteCookie => 'Paste Cookie';

  @override
  String get pasteCookieDesc =>
      'Manually paste the Cookie header from your browser';

  @override
  String get cookieHint => 'e.g. token=abc; session=xyz';

  @override
  String get loginSuccess => 'Logged in';

  @override
  String get loginExpired => 'Session expired, please log in again';

  @override
  String get logoutAction => 'Log out';

  @override
  String get loggedInState => 'Logged in';

  @override
  String get loginDone => 'Done';

  @override
  String get webviewLoginUnsupported =>
      'In-app web login is unavailable on this platform. Use \"Paste Cookie\" instead.';

  @override
  String get apiKeyTitle => 'API Key';

  @override
  String get apiKeyHint =>
      'Copy the API Key from the source account settings page (required for favorites and protected requests).';

  @override
  String get apiKeyPlaceholder => 'Paste API Key';

  @override
  String get apiKeySave => 'Save & verify';

  @override
  String get apiKeyValid => 'API Key is valid';

  @override
  String get apiKeyInvalid => 'API Key is invalid, please check and retry';

  @override
  String get bangumiSettings => 'Bangumi sync';

  @override
  String get bangumiSettingsSubtitle => 'Push favorites and progress to bgm.tv';

  @override
  String get bangumiRatingSync => 'Bangumi rating & sync';

  @override
  String get bangumiAccount => 'Account';

  @override
  String get bangumiTokenHint => 'Paste your personal access token';

  @override
  String get bangumiTokenVerify => 'Verify and save';

  @override
  String get bangumiGetToken => 'Get a token';

  @override
  String bangumiLoggedInAs(String name) {
    return 'Logged in as $name';
  }

  @override
  String get bangumiTokenSaved => 'Token verified';

  @override
  String get bangumiTokenInvalid => 'Invalid token, please check and retry';

  @override
  String get bangumiNotLoggedIn => 'Not logged in';

  @override
  String get bangumiSyncNow => 'Sync now';

  @override
  String get bangumiSyncDone => 'Sync finished';

  @override
  String get bangumiSyncFailed => 'Sync failed';

  @override
  String bangumiLastSync(String time) {
    return 'Last sync: $time';
  }

  @override
  String get bangumiNeverSynced => 'Never synced';

  @override
  String get bangumiSyncTypes => 'Sync types';

  @override
  String get bangumiSyncTypeAnime => 'Anime & video';

  @override
  String get bangumiSyncTypeManga => 'Manga';

  @override
  String get bangumiSyncTypeNovel => 'Novels';

  @override
  String get bangumiSyncLog => 'Sync log';

  @override
  String get bangumiLogSuccess => 'Synced';

  @override
  String get bangumiLogSkipped => 'Skipped (no change)';

  @override
  String get bangumiLogFailed => 'Failed';

  @override
  String get bangumiPendingBind => 'Pending manual bind';

  @override
  String get bangumiBindAndRate => 'Bangumi bind & rating';

  @override
  String get bangumiBindSubject => 'Bind Bangumi subject';

  @override
  String get bangumiSearchHint => 'Search Bangumi subjects';

  @override
  String get bangumiNoResults => 'No matching subjects';

  @override
  String bangumiBoundTo(int id) {
    return 'Bound subject #$id';
  }

  @override
  String get bangumiUnbind => 'Unbind';

  @override
  String get bangumiMarkCollected => 'Mark as collected';

  @override
  String get bangumiMyRating => 'My rating';

  @override
  String get bangumiRatingNone => 'Not rated';

  @override
  String get bangumiMyComment => 'My comment';

  @override
  String get bangumiCommentHint => 'Short comment (synced to Bangumi)';

  @override
  String get bangumiSaved => 'Saved';

  @override
  String get bangumiSyncOptions => 'Sync options';

  @override
  String get bangumiPrivateCollection => 'Create collections as private';

  @override
  String get bangumiPrivateCollectionHint =>
      'Only affects newly created collections; existing ones stay unchanged';

  @override
  String get bangumiTagsSync => 'Push favorite groups as tags';

  @override
  String get bangumiTagsSyncHint =>
      'Merged with remote tags; tags added on Bangumi are kept';

  @override
  String get bangumiImport => 'Import from Bangumi';

  @override
  String bangumiImportDone(int count) {
    return 'Import finished: $count bound';
  }

  @override
  String get bangumiForcedState => 'Sync status override';

  @override
  String get bangumiStateAuto => 'Auto detect';

  @override
  String get bangumiStateWish => 'Wish';

  @override
  String get bangumiStateDoing => 'Watching';

  @override
  String get bangumiStateCollect => 'Collected';

  @override
  String get bangumiStateOnHold => 'On hold';

  @override
  String get bangumiStateDropped => 'Dropped';

  @override
  String get bangumiPullFromRemote => 'Pull from Bangumi';

  @override
  String get bangumiPullDone => 'Pulled remote rating and comment';

  @override
  String get bangumiPullEmpty => 'No remote collection for this subject';

  @override
  String get backupCategorySource => 'Sources & subscriptions';

  @override
  String get backupCategoryBookmark => 'Favorites & bookmarks';

  @override
  String get backupCategoryProgress => 'Progress & history';

  @override
  String get backupCategorySettings => 'Settings & preferences';

  @override
  String get backupCategoryDownload => 'Downloads';

  @override
  String get backupCategoryDanmaku => 'Danmaku cache';

  @override
  String get backupCategoryOther => 'Other';

  @override
  String get backupSelectScope => 'Select backup content';

  @override
  String get backupSelectAll => 'Select all';

  @override
  String get backupMerge => 'Merge (keep local)';

  @override
  String get backupReplace => 'Replace (use backup)';

  @override
  String get backupMergeDesc =>
      'Merge backup into local; existing local data kept, same keys overwritten by backup';

  @override
  String get backupReplaceDesc =>
      'Replace local data with backup entirely (irreversible)';

  @override
  String get backupImportMode => 'Restore mode';

  @override
  String get backupScopeNone => 'Select at least one category to back up';

  @override
  String backupPreviewTitle(Object count) {
    return 'About to restore $count items';
  }

  @override
  String backupExported(Object count) {
    return 'Backup exported ($count items)';
  }

  @override
  String get pullNow => 'Restore from cloud';

  @override
  String get cloudSyncPullMode => 'Restore mode';

  @override
  String get cloudSyncErrorNoConfig =>
      'WebDAV not configured; fill in URL, account and password first';

  @override
  String get cloudSyncErrorNoRemote => 'No backup file available in the cloud';

  @override
  String get cloudSyncErrorEncode => 'Failed to package backup; please retry';

  @override
  String get cloudSyncErrorNetwork =>
      'Network error; check WebDAV URL and connection';

  @override
  String cloudSyncErrorUnknown(Object detail) {
    return 'Sync error: $detail';
  }

  @override
  String get cloudSyncStatusSection => 'Sync status';

  @override
  String get cloudSyncStatusUpload => 'Upload backup';

  @override
  String get cloudSyncStatusRestore => 'Restore data';

  @override
  String get cloudSyncStatusSuccess => 'Success';

  @override
  String get cloudSyncStatusFailed => 'Failed';

  @override
  String get cloudSyncStatusNoChanges => 'No changes';

  @override
  String get cloudSyncStatusNotRun => 'Not run yet';

  @override
  String cloudSyncStatusItems(Object count) {
    return '$count items';
  }

  @override
  String cloudSyncNextSync(Object time) {
    return 'Next auto sync: $time';
  }

  @override
  String get cloudSyncResolveConflicts => 'Resolve conflicts';

  @override
  String get cloudSyncConflictTitle => 'Sync conflicts';

  @override
  String get cloudSyncConflictNone => 'No conflicts between local and cloud';

  @override
  String get cloudSyncConflictIntro =>
      'The following categories differ between local and cloud. Choose which side to keep for each:';

  @override
  String get cloudSyncConflictUseRemote => 'Use cloud';

  @override
  String get cloudSyncConflictKeepLocal => 'Keep local';

  @override
  String get cloudSyncConflictMerge => 'Merge';

  @override
  String cloudSyncConflictCount(Object count) {
    return '$count conflicts';
  }

  @override
  String get cloudSyncConflictLocal => 'Local';

  @override
  String get cloudSyncConflictRemote => 'Cloud';

  @override
  String get cloudSyncConflictApply => 'Apply and restore';

  @override
  String get cloudSyncConflictLoading => 'Analyzing conflicts…';

  @override
  String get bangumiSyncThis => 'Sync to Bangumi';

  @override
  String get syncWorking => 'Syncing to Bangumi…';

  @override
  String get syncBusy => 'Sync in progress, please wait';

  @override
  String get bangumiFavoriteFirst => 'Add to favorites to rate and comment';

  @override
  String get bangumiCollectionStatus => 'Bangumi collection status';

  @override
  String get bangumiBindFirst => 'Bind a Bangumi subject first';

  @override
  String get bangumiSiteRating => 'Bangumi rating';

  @override
  String get bangumiSyncSettings => 'Sync settings';

  @override
  String get bangumiBindToViewRating =>
      'Bind a subject to view its Bangumi rating and reviews';

  @override
  String bangumiRatingUsers(int count) {
    return '$count ratings';
  }

  @override
  String bangumiRank(int rank) {
    return 'Rank #$rank';
  }

  @override
  String get bangumiSummary => 'Summary';

  @override
  String get bangumiTags => 'Tags';

  @override
  String get bangumiNoRating => 'No rating yet';

  @override
  String get bangumiLoadFailed => 'Failed to load';

  @override
  String get bangumiViewOnWeb => 'Open on Bangumi';

  @override
  String get bangumiBrowseCollection => 'Browse Bangumi collection';

  @override
  String get bangumiCollectionEmpty => 'No items in this state';

  @override
  String get bangumiSubjectTypeAnime => 'Anime';

  @override
  String get bangumiSubjectTypeBook => 'Book';

  @override
  String get bangumiSubjectTypeReal => 'Real';

  @override
  String get bangumiLoginWithOAuth => 'Sign in with Bangumi';

  @override
  String get bangumiOauthHint =>
      'Safer: authorize in your browser and return to the app automatically.';

  @override
  String get bangumiOauthNotConfigured =>
      'OAuth not configured: create an app on the Bangumi developer console and fill in Client ID / Secret.';

  @override
  String get bangumiOauthFailed =>
      'Bangumi authorization failed. Please try again.';

  @override
  String get networkSettingsTitle => 'Network Settings';

  @override
  String get networkSettingsDesc => 'Proxy, DNS, DoH/DoT, SNI, ECH and Hosts';

  @override
  String get networkInfoTitle => 'About network settings';

  @override
  String get networkInfoBody =>
      'Global settings apply to all in-app HTTP traffic (covers, downloads, sync, scraping). Native components (webview, media player, cast) use the native stack and are not affected. Per-source overrides only affect that source\'s scraping.';

  @override
  String get networkHelpDoc => 'Help & documentation';

  @override
  String get networkExperimentalNote =>
      'Experimental: limited by the Dart TLS stack; may not take effect on all paths.';

  @override
  String get networkProxyTitle => 'Proxy';

  @override
  String get networkProxyModeDirect => 'Direct';

  @override
  String get networkProxyModeSystem => 'System';

  @override
  String get networkProxyModeManual => 'Manual';

  @override
  String get networkProxyProtocolHttp => 'HTTP';

  @override
  String get networkProxyProtocolSocks5 => 'SOCKS5';

  @override
  String get networkProxyHost => 'Host';

  @override
  String get networkProxyPort => 'Port';

  @override
  String get networkProxyUsername => 'Username';

  @override
  String get networkProxyPassword => 'Password';

  @override
  String get networkTestProxy => 'Test proxy';

  @override
  String networkTestSuccess(int ms) {
    return 'OK ($ms ms)';
  }

  @override
  String get networkTestFailed => 'Test failed';

  @override
  String get networkDnsTitle => 'DNS';

  @override
  String get networkDnsModeSystem => 'System';

  @override
  String get networkDnsModeCustom => 'Custom';

  @override
  String get networkDnsModeDoh => 'DoH';

  @override
  String get networkDnsModeDot => 'DoT';

  @override
  String get networkDnsServers => 'DNS servers';

  @override
  String get networkDnsServersEmpty => 'No servers configured';

  @override
  String get networkAddServer => 'Add server';

  @override
  String get networkDnsCacheEnabled => 'Enable DNS cache';

  @override
  String networkDnsCacheStatus(int count) {
    return 'Cached entries: $count';
  }

  @override
  String get networkClearCache => 'Clear cache';

  @override
  String get networkTestDns => 'Test DNS resolution';

  @override
  String get networkDnsTestHost => 'Host to resolve';

  @override
  String networkDnsTestResult(Object ips, int ms) {
    return '$ips ($ms ms)';
  }

  @override
  String get networkDohTitle => 'DNS over HTTPS (DoH)';

  @override
  String get networkDohPreset => 'Preset';

  @override
  String get networkDohUrl => 'DoH URL';

  @override
  String get networkTestDoh => 'Test DoH';

  @override
  String get networkDotTitle => 'DNS over TLS (DoT)';

  @override
  String get networkDotHost => 'DoT host';

  @override
  String get networkDotPort => 'DoT port';

  @override
  String get networkHostsTitle => 'Custom Hosts';

  @override
  String get networkHostsEmpty => 'No host entries';

  @override
  String get networkAddHost => 'Add host entry';

  @override
  String get networkHostsIp => 'IP address';

  @override
  String get networkHostsHost => 'Hostname';

  @override
  String get networkSniTitle => 'SNI';

  @override
  String get networkSniEnabled => 'Enable custom SNI';

  @override
  String get networkSniDefault => 'Default SNI value';

  @override
  String get networkSniRuntimeNote =>
      'Applies to direct HTTPS connections: the default SNI applies to all hosts, and `-` suppresses SNI entirely (the handshake omits server_name, bypassing SNI-based blocking; pair with custom hosts pinning a reachable IP). Per-host mappings below override the default. Not applied through a proxy.';

  @override
  String get networkSniDomainTitle => 'Host → SNI mappings';

  @override
  String get networkSniDomainEmpty => 'No mappings';

  @override
  String get networkSniAddDomain => 'Add SNI mapping';

  @override
  String get networkSniDomainHost =>
      'Host pattern (.example.com for suffix match)';

  @override
  String get networkSniDomainValue => 'SNI value (- for none)';

  @override
  String get networkSniTestHost => 'Host to test';

  @override
  String get networkTestSni => 'Test SNI handshake';

  @override
  String networkSniTestResult(String name, int ms) {
    return '$name ($ms ms)';
  }

  @override
  String get networkEchTitle => 'ECH (Encrypted Client Hello)';

  @override
  String get networkEchEnabled => 'Enable ECH';

  @override
  String get networkEchConfigList => 'ECH config list (base64)';

  @override
  String get networkEchRuntimeNote =>
      'The in-app direct path uses the Dart TLS stack, which cannot do ECH. With this enabled, requests are routed through the built-in ECH proxy and the native TLS stack performs the ECH handshake; hosts that do not support ECH fall back to a direct connection automatically, so normal access is unaffected. If you provide an ECH config list it is used as-is; when left empty the proxy obtains one automatically.';

  @override
  String get networkReset => 'Reset network settings';

  @override
  String get networkResetTitle => 'Reset network settings';

  @override
  String get networkResetConfirm => 'Restore all network settings to defaults?';

  @override
  String get networkResetDone => 'Network settings restored to defaults';

  @override
  String get networkSaved => 'Network settings saved';

  @override
  String get networkCacheCleared => 'DNS cache cleared';

  @override
  String get networkErrorInvalidHost => 'Invalid host';

  @override
  String get networkErrorInvalidPort => 'Invalid port (1-65535)';

  @override
  String get networkErrorInvalidIp => 'Invalid IP address';

  @override
  String get networkErrorInvalidDomain => 'Invalid domain';

  @override
  String get networkErrorInvalidDohUrl => 'Invalid DoH URL (must be https)';

  @override
  String get sourceNetworkOverride => 'Network override';

  @override
  String get sourceNetworkScopeNote =>
      'These settings only affect this source\'s scraping. They override the global network settings per aspect; aspects left off inherit the global configuration.';

  @override
  String get sourceNetworkFromSourceNote =>
      'This source ships its own network configuration, which is applied automatically — no manual setup required. Edit the values below and save to keep a custom override.';

  @override
  String get networkOverrideEnable => 'Override global';

  @override
  String get networkInheritGlobal => 'Inherit global';

  @override
  String get sourceNetworkSaved => 'Source network override saved';

  @override
  String get sourceNetworkClear => 'Clear override';

  @override
  String get sourceNetworkClearConfirm =>
      'Remove this source\'s network override and inherit global settings?';

  @override
  String get sourceNetworkClearConfirmFromSource =>
      'This source ships its own network configuration. Clearing the custom override restores the source\'s built-in configuration (not global settings). Continue?';

  @override
  String get sourceNetworkCleared => 'Source network override cleared';

  @override
  String get sourceNetworkClearedToSource =>
      'Custom override cleared; this source now uses its built-in network configuration';

  @override
  String get bangumiNoMatch => 'No matching Bangumi subject found';

  @override
  String get bangumiManualBind => 'Search & bind manually';

  @override
  String get bangumiConfirmBind => 'Confirm binding to one of these';

  @override
  String get bangumiFromBangumi => 'Data from Bangumi';

  @override
  String get bangumiHideCollection => 'Hide collection';

  @override
  String get bangumiProgress => 'Progress (episodes/chapters watched)';

  @override
  String get bangumiSaveSync => 'Save & sync';

  @override
  String get bangumiSavedLocal => 'Not signed in: saved locally';

  @override
  String get websiteComments => 'Site comments';

  @override
  String get bangumiComments => 'Bangumi comments';

  @override
  String get bangumiCommentsEmpty => 'No comments yet';

  @override
  String get bangumiCommentsLoadFailed => 'Failed to load comments';

  @override
  String bangumiGuessMatch(Object name) {
    return 'Best-guess match: $name';
  }

  @override
  String bangumiEps(int count) {
    return '$count eps';
  }

  @override
  String bangumiAirDate(String date) {
    return 'Aired: $date';
  }

  @override
  String bangumiCollectionWish(int count) {
    return '$count wish';
  }

  @override
  String bangumiCollectionDoing(int count) {
    return '$count watching';
  }

  @override
  String bangumiCollectionCollect(int count) {
    return '$count watched';
  }

  @override
  String get bangumiCharacters => 'Characters';

  @override
  String get bangumiRelated => 'Related';

  @override
  String get bangumiCollectionStat => 'Collection Stats';

  @override
  String get bangumiProxyTitle => 'Connection Mode';

  @override
  String get bangumiProxyDirect => 'Direct';

  @override
  String get bangumiProxyMirror => 'Mirror';

  @override
  String get bangumiProxyEch => 'ECH';

  @override
  String get bangumiProxyMainSite => 'Main site domain';

  @override
  String get bangumiProxyApi => 'API domain';

  @override
  String get bangumiProxyImage => 'Image domain';

  @override
  String get bangumiProxyHint =>
      'In mirror/reverse-proxy mode, enter your self-hosted domain (no path). Leave blank to use Bangumi\'s default domain for that category.';

  @override
  String get bangumiProxySaved => 'Proxy settings saved';

  @override
  String get bangumiEchProxyHint =>
      'Connects to the official domains, but requests to Bangumi-related domains are transparently routed through a local ECH (Encrypted Client Hello) proxy that hides the SNI. No configuration needed. If this mode works, there is no need to consider \"Mirror / Reverse Proxy\". Requires a build that bundles the native ECH engine; without it this mode cannot be enabled.';

  @override
  String get bangumiEchStatus => 'ECH proxy status';

  @override
  String get bangumiEchUnavailable =>
      'Failed to start the local ECH proxy. The native engine may not be bundled for this platform.';

  @override
  String bangumiEchProxyRunning(int port) {
    return 'Running (port $port)';
  }

  @override
  String get bangumiEchProxyIdle => 'Not running';

  @override
  String get bangumiDetail => 'Details';

  @override
  String get bangumiStaff => 'Staff';

  @override
  String get bangumiTapToExpand => 'Tap to expand';

  @override
  String get bangumiSyncRating => 'Rating';

  @override
  String get bangumiSyncComment => 'Comment';

  @override
  String get bangumiSync => 'Sync';

  @override
  String get bangumiPublic => 'Public';

  @override
  String get bangumiPrivate => 'Private';

  @override
  String get bangumiSyncLoginHint => 'Sign in to Bangumi in Settings first';

  @override
  String get bangumiSyncSaved => 'Saved';

  @override
  String get bangumiSyncWatchedEpisodes => 'Watched episodes';

  @override
  String get bangumiSyncWatchedChapters => 'Read chapters';

  @override
  String get bangumiSyncProgressHint =>
      'Leave empty to auto-sync local progress';

  @override
  String get bangumiSyncExpandList => 'Pick specific episodes / chapters';

  @override
  String get bangumiSyncCollapseList => 'Collapse';

  @override
  String bangumiSyncChaptersTotal(Object count, Object unit) {
    return '$count $unit total';
  }

  @override
  String bangumiSyncChaptersLoadedHint(Object count, Object unit) {
    return '$count $unit loaded — pick individually';
  }

  @override
  String bangumiSyncNoEpisodeList(Object eps) {
    return 'Bangumi has no episode list for this subject ($eps), cannot pick individually';
  }

  @override
  String bangumiSyncLoadEpisodesFailed(Object error) {
    return 'Failed to load episode list: $error';
  }

  @override
  String get bangumiSyncUnitEp => 'ep';

  @override
  String get bangumiSyncUnitVolume => 'vol';

  @override
  String get bangumiSyncUnitChapter => 'ch';

  @override
  String get bangumiSyncMyCompletion => 'My Completion';

  @override
  String get bangumiSyncUpdate => 'Update';

  @override
  String get bangumiSyncAdvancedOptions => 'Advanced';

  @override
  String get bangumiSyncAdvancedHint => 'Rating / Comment / Status / Privacy';

  @override
  String get bangumiSyncChapLabel => 'Chap.';

  @override
  String get bangumiSyncVolLabel => 'Vol.';

  @override
  String get bangumiSyncIncrement => '+';

  @override
  String get bangumiSyncAnimeGridTitle => 'Episodes';

  @override
  String get bangumiSyncAnimeGridHint =>
      'Tap a cell to toggle watched / unwatched';

  @override
  String get bangumiSyncScheduleWeek => 'W';

  @override
  String get bangumiSyncScheduleHour => 'H';

  @override
  String get bangumiSyncScheduleMinute => 'M';

  @override
  String get bangumiSyncScheduleTitle => 'Air time';

  @override
  String bangumiSyncPageOf(int current, int total) {
    return 'Page $current / $total';
  }

  @override
  String get bangumiSyncUnknown => '??';

  @override
  String bangumiRatingValue(int count) {
    return '$count / 10';
  }

  @override
  String get clear => 'Clear';

  @override
  String get mirrorAddCustom => 'Add custom mirror';

  @override
  String get mirrorName => 'Mirror name';

  @override
  String get mirrorDomain => 'Domain';

  @override
  String get mirrorBaseUrl => 'Base URL';

  @override
  String get mirrorCustom => 'Custom';

  @override
  String get mirrorDelete => 'Delete';

  @override
  String get mirrorExtractFromPublish => 'Extract mirrors from publish page';

  @override
  String get mirrorExtracting => 'Extracting…';

  @override
  String get mirrorNoMirrorsExtracted => 'No mirrors found';

  @override
  String get mirrorImportSelected => 'Import selected';

  @override
  String get mirrorExtractFailed => 'Extraction failed';

  @override
  String get mirrorAddInvalid => 'Base URL must start with http:// or https://';

  @override
  String get importLibraryTab => 'Library import';

  @override
  String get libraryUrlHint => 'Enter source library URL';

  @override
  String get fetchLibrary => 'Fetch';

  @override
  String get saveLibrary => 'Save bookmark';

  @override
  String get libraryBookmarks => 'Library';

  @override
  String get sourceNotLoggedIn => 'Not logged in';

  @override
  String get novelThemeFollowApp => 'Follow app';

  @override
  String get novelThemeFollowDark => 'Always night';

  @override
  String get novelThemeFollowLight => 'Always day';

  @override
  String get libraryEmpty => 'No saved library URLs';

  @override
  String get addLibraryTitle => 'Add source library';

  @override
  String get libraryNameHint => 'Name (optional)';

  @override
  String get subscribeLibrary => 'Subscribe';

  @override
  String get fetchLibraryAndImport => 'Update & Import';

  @override
  String get openHomepage => 'Open homepage';

  @override
  String get unsubscribeLibrary => 'Unsubscribe';

  @override
  String unsubscribeLibraryConfirm(String name) {
    return 'Unsubscribe from \"$name\"?';
  }

  @override
  String get viewLibrarySources => 'View sources';

  @override
  String get librarySubscribeFailed =>
      'Subscribe failed. Please check the URL.';

  @override
  String libraryImportResult(int success, int total, int failed) {
    return 'Imported $success/$total sources ($failed failed)';
  }

  @override
  String libraryVersion(int lib, int installed) {
    return 'Lib v$lib · Installed v$installed';
  }

  @override
  String get libraryNotInstalled => 'Not installed';

  @override
  String get libraryUpdate => 'Update';

  @override
  String get libraryUpdateAll => 'Update all';

  @override
  String get libraryUpdateAvailable => 'Update available';

  @override
  String get libraryUpdating => 'Updating…';

  @override
  String get libraryUpdated => 'Updated';

  @override
  String get libraryUpdateFailed => 'Update failed';

  @override
  String get libraryAllUpToDate => 'All up to date';

  @override
  String libraryAlreadyLatestCount(int count) {
    return '$count already latest';
  }

  @override
  String get sourcePin => 'Pin';

  @override
  String get sourceUnpin => 'Unpin';

  @override
  String get mirrorTestAll => 'Test all';

  @override
  String get sourceTypeOther => 'Other';

  @override
  String get official => 'Official';

  @override
  String get loginStatusLoggedIn => 'Logged in';

  @override
  String get loginStatusLoggedOut => 'Logged out';

  @override
  String get cookieInputHint => 'Paste the cookie string for this source';

  @override
  String get incognitoMode => 'Incognito mode';

  @override
  String get incognitoModeHint =>
      'Don\'t record history or search for this source';

  @override
  String get incognitoModeOn => 'Incognito on';

  @override
  String get incognitoOnToast =>
      'Incognito on: history and search won\'t be recorded for this source';

  @override
  String get incognitoOffToast =>
      'Incognito off: history recording resumed for this source';

  @override
  String get globalIncognito => 'Global incognito';

  @override
  String get globalIncognitoHint =>
      'When on, no source records history or search. Per-source toggle in source management still overrides individually.';

  @override
  String get rememberPosition => 'Remember playback/reading position';

  @override
  String get rememberPositionHint =>
      'When on, reopening anime/comic/novel resumes from the last position; when off, always starts from the beginning';

  @override
  String mirrorAutoAdded(Object count) {
    return 'Auto-added $count mirror(s) from the publish page';
  }

  @override
  String get sourceAnnouncementView => 'View details';

  @override
  String get announcementDontShowAgain => 'Don\'t show again';

  @override
  String get appAnnouncement => 'App announcement';

  @override
  String get appAnnouncementGotIt => 'Got it';

  @override
  String get watchedThreshold => 'Watched threshold';

  @override
  String get watchedThresholdHint =>
      'Progress reaching this percentage is considered watched';

  @override
  String get watchedThresholdUnit => '%';

  @override
  String get onlineTabWebFavorite => 'Web favorites';

  @override
  String get favoriteLocal => 'Local favorite';

  @override
  String get favoriteLocalHint => 'Save to this device';

  @override
  String get favoriteWeb => 'Add to web favorites';

  @override
  String get favoriteWebHint =>
      'Save to your source-site account (needs network)';

  @override
  String get favoriteWebRequiresLogin => 'Requires source-site login first';

  @override
  String get webFavoriteDefaultFolder => 'Default folder';

  @override
  String get webFavoriteAdded => 'Added to web favorites';

  @override
  String get webFavoriteAddFailed => 'Failed to add to web favorites';

  @override
  String get ageRatingGeneral => 'General';

  @override
  String get ageRatingTeen => 'Teen (16+)';

  @override
  String get ageRatingMature => 'Mature (18+)';

  @override
  String get ageRatingLabel => 'Age rating';

  @override
  String get ageRestrictionImportMatureBlocked =>
      'Age restriction is on; 18+ sources cannot be imported (turn it off in settings)';

  @override
  String ageBlockedManageHint(int count) {
    return 'Hid $count 18+ source(s) (visible after turning off age restriction)';
  }

  @override
  String ageBlockedImportHint(int count) {
    return 'Due to age restriction, $count 18+ source(s) were not imported';
  }

  @override
  String get ageRestriction => 'Age restriction';

  @override
  String get ageRestrictionHint => 'When on, hides sources rated Mature (18+)';

  @override
  String get ageRestrictionDisclaimerTitle => 'Disclaimer';

  @override
  String get ageRestrictionDisclaimerBody =>
      'By disabling age restriction you acknowledge that this app may display content rated Mature (18+), including explicit adult material. You confirm that you are of legal age in your jurisdiction to view such content, and you accept full responsibility for any content accessed. The developer is not responsible for any content provided by third-party sources. Please comply with local laws and regulations.';

  @override
  String get ageRestrictionDisclaimerConfirm =>
      'I have read and understand, continue';

  @override
  String get ageRestrictionDisclaimerScrollHint =>
      'Scroll to the bottom to read the full disclaimer before confirming';

  @override
  String ageRestrictionDisclaimerCounting(Object seconds) {
    return 'Wait ${seconds}s to confirm';
  }

  @override
  String ageRestrictionDisclaimerWait(Object seconds) {
    return 'Confirm (wait ${seconds}s)';
  }

  @override
  String get comicSectionTapPage => 'Page Turning & Tap';

  @override
  String get comicSectionVisualFilter => 'Visual & Filters';

  @override
  String get comicSectionProgress => 'Progress & Display';

  @override
  String get comicSectionFlash => 'Flash Effects';

  @override
  String get comicSectionMouseWheel => 'Mouse Wheel';

  @override
  String get comicReaderAutoSection => 'Auto (download / chapter skip)';

  @override
  String get comicReaderOverlaySection => 'Overlay (clock / battery)';

  @override
  String get comicReaderMultiImageSection => 'Multi-image / spacing';

  @override
  String get statsOverviewTitle => 'Statistics';

  @override
  String get statsSearchHint => 'Search records';

  @override
  String get statsHeatmap => 'Heatmap';

  @override
  String get statsSectionTrend => 'Trend';

  @override
  String get statsTrend7d => '7 days';

  @override
  String get statsTrend30d => '30 days';

  @override
  String get statsTotalDuration => 'Total duration';

  @override
  String get statsWorkCount => 'Works';

  @override
  String get statsSessionCount => 'Sessions';

  @override
  String get statsLastRead => 'Last read';

  @override
  String get statsNoRecords => 'No records yet, go read something';

  @override
  String statsDurSec(int s) {
    return '$s s';
  }

  @override
  String statsDurHours(int h) {
    return '$h hours';
  }

  @override
  String statsDurHm(int h, int m) {
    return '$h h $m m';
  }

  @override
  String statsDurMs(int m, int s) {
    return '$m m $s s';
  }

  @override
  String get statsClearTitle => 'Clear stats';

  @override
  String statsClearBody(String name) {
    return 'Clear all stats for \"$name\"?';
  }

  @override
  String get statsClearConfirm => 'Clear';

  @override
  String get statsPrevMonth => 'Previous month';

  @override
  String get statsNextMonth => 'Next month';

  @override
  String statsHeatmapMonthYear(String y, String m) {
    return '$y/$m';
  }

  @override
  String get statsAll => 'All';

  @override
  String get statsHeatmapLess => 'Less';

  @override
  String get statsHeatmapMore => 'More';

  @override
  String get statsHeatmapTotal => 'This month';

  @override
  String get stats7dActive => 'Active (7d)';

  @override
  String get stats30dActive => 'Active (30d)';

  @override
  String get statsActiveDays => 'Active days';

  @override
  String get statsAvgSession => 'Avg per session';

  @override
  String get statsMaxDaily => 'Best day';

  @override
  String get statsStreak => 'Current streak';

  @override
  String get statsSectionOverview => 'Overview';

  @override
  String get statsSectionActivity => 'Activity';

  @override
  String get statsSectionPace => 'Pace';

  @override
  String get heatmapActiveDays => 'Active days';

  @override
  String get heatmapMaxDaily => 'Best day';

  @override
  String get heatmapStreak => 'Current streak';

  @override
  String get downloadAutoDelete => 'Auto-delete after finishing';

  @override
  String get downloadAutoDeleteHint =>
      'Remove downloaded files once you finish this item';

  @override
  String get downloadAutoDeleteExclude => 'Excluded categories';

  @override
  String get downloadAutoDeleteExcludeNone => 'Auto-delete all categories';

  @override
  String get downloadPreDownload => 'Pre-download next content';

  @override
  String get downloadPreDownloadOff => 'Off';

  @override
  String downloadEpisodesCount(int count) {
    return '$count items';
  }

  @override
  String get categoriesManageTitle => 'Categories';

  @override
  String get categoriesManageDesc =>
      'Manage collection categories for anime, comics and novels';

  @override
  String get settingsGroupPrivacy => 'Privacy';

  @override
  String get onboardingWelcomeTitle => 'Welcome to NexHub';

  @override
  String get onboardingWelcomeBody =>
      'An all-in-one media client: anime, manga, novel, and video. The app ships no built-in sites; content comes from the sources you import.';

  @override
  String get onboardingSourcesTitle => 'Add your sources';

  @override
  String get onboardingSourcesBody =>
      'Go to Source Management and import community-maintained sources to start browsing and searching.';

  @override
  String get onboardingBangumiTitle => 'Connect Bangumi';

  @override
  String get onboardingBangumiBody =>
      'Sign in to sync your \'watching / want-to-watch\' to Bangumi and view ratings and comments on detail pages.';

  @override
  String get onboardingBangumiLogin => 'Sign in now';

  @override
  String get onboardingDandanplayTitle => 'Connect DanDanPlay';

  @override
  String get onboardingDandanplayBody =>
      'Sign in to post and sync danmaku to DanDanPlay and share comment libraries across devices.';

  @override
  String get onboardingDandanplayLogin => 'Sign in';

  @override
  String get onboardingPrivacyTitle => 'Privacy & compliance';

  @override
  String get onboardingPrivacyBody =>
      'Your sources, credentials, and browsing history are stored only on this device and never uploaded. The app hardcodes no secrets.';

  @override
  String get onboardingSkip => 'Skip';

  @override
  String get onboardingNext => 'Next';

  @override
  String get onboardingGetStarted => 'Get started';

  @override
  String get onboardingSettingsTitle => 'Basic settings';

  @override
  String get onboardingSettingsBody =>
      'Choose your theme and interface language. You can change these later in Settings.';

  @override
  String get onboardingThemeLabel => 'Theme';

  @override
  String get onboardingLanguageLabel => 'Language';

  @override
  String get onboardingPermissionTitle => 'Grant permissions';

  @override
  String get onboardingPermissionBody =>
      'To import local files, save downloads and screenshots, we recommend granting these permissions. You can also do it later in Settings.';

  @override
  String get onboardingGrantPermission => 'Grant permissions';

  @override
  String get onboardingPermissionGranted => 'Required permissions granted';

  @override
  String get onboardingPermissionNotNeeded =>
      'No runtime permission needed on this platform';

  @override
  String get onboardingPermissionStorage => 'Storage';

  @override
  String get onboardingPermissionStorageDesc =>
      'Access local files (legacy Android versions)';

  @override
  String get onboardingPermissionPhotos => 'Photos';

  @override
  String get onboardingPermissionPhotosDesc => 'Read images from your gallery';

  @override
  String get onboardingPermissionVideos => 'Videos';

  @override
  String get onboardingPermissionVideosDesc => 'Read videos from your gallery';

  @override
  String get onboardingPermissionAudio => 'Audio';

  @override
  String get onboardingPermissionAudioDesc => 'Read local audio files';

  @override
  String get onboardingPermissionItemGranted => 'Granted';

  @override
  String get onboardingPermissionItemDenied => 'Not granted';

  @override
  String get onboardingDownloadTitle => 'Download location';

  @override
  String get onboardingDownloadBody =>
      'Choose where downloaded anime / manga / novel / video content is saved. You can change it later under Settings → Downloads.';

  @override
  String get onboardingChooseDownloadPath => 'Choose download folder';

  @override
  String get onboardingThemeColorLabel => 'Accent color';

  @override
  String get onboardingThemePreviewLabel => 'Style preview';

  @override
  String get privacySettingsTitle => 'Privacy Settings';

  @override
  String get privacySettingsDesc =>
      'Notification masking and incognito options';

  @override
  String get privacyNotificationsGroup => 'Notifications';

  @override
  String get hideNotificationContent => 'Hide Notification Content';

  @override
  String get hideNotificationContentHint =>
      'When on, notifications only show \"New content\" without specific counts, preventing shoulder surfing';

  @override
  String get privacyNetworkGroup => 'Network';

  @override
  String get privacyPageHint =>
      'Global incognito randomizes request delays and rotates browser fingerprints to reduce the chance of being detected as a script';

  @override
  String get settingsGroupAdvanced => 'Advanced & Cache';

  @override
  String get advancedSettingsTitle => 'Advanced Settings';

  @override
  String get advancedSettingsDesc =>
      'Crash logs, detailed logs, data cleanup and request fingerprint';

  @override
  String get advancedLogGroup => 'Logs';

  @override
  String get detailedLogging => 'Detailed Logging';

  @override
  String get detailedLoggingHint =>
      'Log each network request and response to help debug scraping issues';

  @override
  String get crashLog => 'Crash Log';

  @override
  String get crashLogDesc => 'View runtime errors and uncaught exceptions';

  @override
  String get crashLogTitle => 'Crash Log';

  @override
  String get crashLogEmpty =>
      'No crash records yet. If you hit a problem, reproduce it and check back';

  @override
  String get crashLogCopied => 'Copied to clipboard';

  @override
  String get crashLogClear => 'Clear Crash Log';

  @override
  String get crashLogCleared => 'Cleared';

  @override
  String get crashLogCopyAll => 'Copy All';

  @override
  String get runtimeLog => 'Runtime Log';

  @override
  String get runtimeLogDesc =>
      'In-memory log of this session\'s network requests, responses and errors (detailed logging toggle controls verbosity)';

  @override
  String get logEmpty =>
      'No logs yet. Enable \"Detailed Logging\", reproduce the issue, then come back.';

  @override
  String get logCopied => 'Log copied to clipboard';

  @override
  String get advancedCleanGroup => 'Data Cleanup';

  @override
  String get clearCookies => 'Clear Cookies';

  @override
  String get clearCookiesDesc => 'Clear session cookies of crawler and WebView';

  @override
  String get cookiesCleared => 'Cookies cleared';

  @override
  String get cloudSyncAutoUploadNovelExports => 'Auto-upload novel exports';

  @override
  String get cloudSyncAutoUploadNovelExportsDesc =>
      'Upload exported EPUB files to WebDAV nexhub/exports after download completes';

  @override
  String get uploadToWebdav => 'Upload exports to WebDAV';

  @override
  String get uploadToWebdavDone => 'export file(s) uploaded to WebDAV';

  @override
  String get uploadToWebdavNoFiles =>
      'No downloaded EPUB exports for this title yet';

  @override
  String get uploadToWebdavFailed =>
      'Export upload failed, check WebDAV config';

  @override
  String get novelExportTemplate => 'Export template (EPUB)';

  @override
  String get novelExportTemplateDesc =>
      'Custom stylesheet, cover page and intro page embedded in the EPUB export';

  @override
  String get novelExportCss => 'Custom CSS (style.css)';

  @override
  String get novelExportCssHint =>
      'Plain CSS rules applied to every chapter (font family, line height…)';

  @override
  String get novelExportIntro => 'Book intro page';

  @override
  String get novelExportIntroHint =>
      'Blank line separates paragraphs; title and author placeholders are auto-substituted';

  @override
  String get novelExportIncludeCover =>
      'Embed network cover as first cover page';

  @override
  String get novelExportIncludeIntro => 'Append intro page after cover';

  @override
  String get novelExportSaved => 'Export template saved';

  @override
  String get advancedImageCache => 'Image cache';

  @override
  String get advancedImageCacheDesc =>
      'Disk usage of downloaded images; tap to clear';

  @override
  String get imageCacheCleared => 'Image cache cleared';

  @override
  String get imageCacheClearConfirm => 'Clear image cache?';

  @override
  String get imageCacheCalculating => 'Calculating…';

  @override
  String get cacheManagerTitle => 'Cache manager';

  @override
  String get cacheManagerTotal => 'Total cache usage';

  @override
  String cacheManagerTotalDesc(String size) {
    return '$size in total; clear per category below';
  }

  @override
  String get cacheManagerHint =>
      'Clearing the cache never removes favorites, downloads or sources; images saved in the image-favorites gallery live in the favorites folder and are unaffected.';

  @override
  String get cacheCategoryGroup => 'Cache categories';

  @override
  String get cacheCatImages => 'Image cache';

  @override
  String get cacheCatImagesDesc => 'Covers, comic pages and RSS inline images';

  @override
  String get cacheCatDanmaku => 'Danmaku cache';

  @override
  String get cacheCatDanmakuDesc =>
      'Cached video danmaku (expired entries auto-evicted)';

  @override
  String get cacheCatTranslations => 'Translation cache';

  @override
  String get cacheCatTranslationsDesc =>
      'AI translations for novels / comics / subtitles';

  @override
  String get cacheCatWebview => 'WebView data';

  @override
  String get cacheCatWebviewDesc => 'Embedded browser cache and local storage';

  @override
  String get cacheCatTemp => 'Temporary files';

  @override
  String get cacheCatTempDesc =>
      'Derived files such as PDF renders and archive extraction';

  @override
  String get cacheCatUpdates => 'Update package leftovers';

  @override
  String get cacheCatUpdatesDesc =>
      'Downloaded installers and stale version folders';

  @override
  String get cacheSizeUnknown => 'Not measurable';

  @override
  String get cacheClearCategory => 'Clear this category';

  @override
  String cacheClearCategoryConfirm(String name) {
    return 'Clear \"$name\"?';
  }

  @override
  String get cacheClearAll => 'Clear all';

  @override
  String get cacheClearAllConfirm => 'Clear every cache category?';

  @override
  String get cacheCategoryCleared => 'Cleared';

  @override
  String get cacheClearFailed => 'Cleanup failed, please retry later';

  @override
  String get cacheAutoCleanGroup => 'Automatic cache cleanup';

  @override
  String get cacheAutoCleanGroupDesc =>
      'Runs in the background on launch using age + size limits';

  @override
  String get cacheAutoClean => 'Auto-clean cache';

  @override
  String get cacheAutoCleanDesc =>
      'When off, caches are only cleared manually here';

  @override
  String get cacheMaxAge => 'Keep cache for';

  @override
  String cacheMaxAgeValue(int days) {
    return '$days days';
  }

  @override
  String get cacheMaxTotal => 'Total cache size limit';

  @override
  String get cacheAutoCleanNow => 'Run cleanup policy';

  @override
  String cacheAutoCleanDone(String size) {
    return 'Freed $size';
  }

  @override
  String get cacheAutoCleanNothing => 'Nothing to clean up';

  @override
  String get readerUpscale => 'Image super-resolution';

  @override
  String get readerUpscaleMode => 'Super-resolution mode';

  @override
  String get readerUpscaleOff => 'Off';

  @override
  String get readerUpscaleResample => 'High-quality resample';

  @override
  String get readerUpscaleSharpen => 'Super-resolution (sharpen)';

  @override
  String get readerUpscaleDesc =>
      'Paged (single-page) mode only: the GPU resamples and sharpens lines when an image is upscaled (webtoon strips and oversized single images keep plain rendering); turn off on low-end devices';

  @override
  String get confirmActionHint => 'This action cannot be undone. Continue?';

  @override
  String get advancedRequestGroup => 'Request Fingerprint';

  @override
  String get defaultUserAgent => 'Default User-Agent';

  @override
  String get userAgentAuto => 'Auto (built-in fingerprint rotation)';

  @override
  String get userAgentAutoHint =>
      'Different sites automatically use different browser fingerprints';

  @override
  String get userAgentCustom => 'Custom User-Agent';

  @override
  String get advancedPageHint =>
      'The default UA takes effect immediately; some sites may be more sensitive to a fixed fingerprint';

  @override
  String get refresh => 'Refresh';

  @override
  String get rssNewContentGeneric => 'New content available';

  @override
  String get readerClockPosTopLeft => 'Top Left';

  @override
  String get readerClockPosTopRight => 'Top Right';

  @override
  String get readerClockPosBottomLeft => 'Bottom Left';

  @override
  String get readerClockPosBottomRight => 'Bottom Right';

  @override
  String get cacheBook => 'Cache';

  @override
  String get cacheChaptersTitle => 'Select chapters to cache';

  @override
  String get cacheSelected => 'Cache selected';

  @override
  String cacheSelectedCount(int count) {
    return 'Selected $count chapters';
  }

  @override
  String get searchPause => 'Pause';

  @override
  String get searchResume => 'Resume';

  @override
  String get searchScope => 'Scope';

  @override
  String get searchScopeAll => 'Whole book';

  @override
  String get searchScopeFromHere => 'From current';

  @override
  String get searchScopeRange => 'Range';

  @override
  String get searchUseRegex => 'Regex';

  @override
  String get searchRegexInvalid => 'Invalid regex';

  @override
  String get searchRangeStart => 'Start';

  @override
  String get searchRangeEnd => 'End';

  @override
  String get overviewChapterSummary => 'Chapter overview';

  @override
  String get overviewMode => 'Summary mode';

  @override
  String get overviewModeLocal => 'Offline';

  @override
  String get overviewModeApi => 'Cloud AI';

  @override
  String get overviewGenerate => 'Generate';

  @override
  String get overviewGenerating => 'Generating…';

  @override
  String get overviewEmpty => 'No content to summarize';

  @override
  String get overviewApiSettings => 'Summary API';

  @override
  String get overviewApiBaseUrl => 'API base URL';

  @override
  String get overviewApiKey => 'API key';

  @override
  String get overviewApiModel => 'Model';

  @override
  String get overviewApiError => 'Request failed';

  @override
  String get overviewApiMissing => 'API not configured';

  @override
  String get overviewRetry => 'Retry';

  @override
  String get overviewCopy => 'Copy';

  @override
  String get importLegadoSource => 'Import legado sources';

  @override
  String get legadoImportTitle => 'legado source import';

  @override
  String get legadoImportHint => 'Select legado source JSON';

  @override
  String get legadoImportedCount => 'Imported \$count sources';

  @override
  String get legadoParseError => 'Failed to parse source';

  @override
  String get legadoGroupDefault => 'legado';

  @override
  String get searchPaused => 'Paused';

  @override
  String get selectionCopy => 'Copy';

  @override
  String get selectionCopied => 'Copied';

  @override
  String get selectionHighlight => 'Highlight';

  @override
  String get selectionUnderline => 'Underline';

  @override
  String get underlineStyle => 'Underline Style';

  @override
  String get underlineColor => 'Underline Color';

  @override
  String get underlineStyleSolid => 'Solid';

  @override
  String get underlineStyleWavy => 'Wavy';

  @override
  String get underlineStyleDotted => 'Dotted';

  @override
  String get customColorApply => 'Apply Custom Color';

  @override
  String get selectionNote => 'Note';

  @override
  String get selectionShare => 'Share';

  @override
  String get selectionTranslate => 'Translate';

  @override
  String get selectionAskAi => 'Ask AI';

  @override
  String get selTranslateTitle => 'Translate selection';

  @override
  String get selTranslateSource => 'Source';

  @override
  String get selTranslateResult => 'Translation';

  @override
  String get selTranslateRetry => 'Retry';

  @override
  String get selTranslateFailed => 'Translation failed';

  @override
  String get askAiTitle => 'Ask AI';

  @override
  String get askAiHint => 'Ask about the selection or this chapter…';

  @override
  String get askAiSend => 'Send';

  @override
  String get askAiThinking => 'Thinking…';

  @override
  String get askAiFailed => 'Request failed, please retry';

  @override
  String get askAiNoEndpoints =>
      'No AI endpoint configured. Configure one in \"Settings → AI\" first';

  @override
  String askAiContextTag(String book, String chapter) {
    return 'Context: $book · $chapter';
  }

  @override
  String get notesSheetTitle => 'Notes';

  @override
  String get notesExport => 'Export Markdown';

  @override
  String notesExported(int count) {
    return 'Generated Markdown with $count items';
  }

  @override
  String get shareChangeCover => 'Change Cover';

  @override
  String get selectionCancel => 'Cancel';

  @override
  String get selectionParagraph => 'Paragraph';

  @override
  String get highlightList => 'Highlights';

  @override
  String get highlightEmpty => 'No highlights';

  @override
  String get highlightDelete => 'Delete highlight';

  @override
  String get highlightEditNote => 'Edit note';

  @override
  String get highlightNoteHint => 'Write your thought…';

  @override
  String get highlightSave => 'Save';

  @override
  String get highlightJump => 'Go to';

  @override
  String get highlightColor => 'Color';

  @override
  String get comicTranslateSettingLabel => 'Manga translation';

  @override
  String get comicTranslateTurnOn => 'Translate this page';

  @override
  String get comicTranslateTurnOff => 'Turn off translation';

  @override
  String get comicTranslateLoading => 'Translating…';

  @override
  String get comicTranslateFailed => 'Translation failed';

  @override
  String get comicTranslatePartial => 'Partially translated';

  @override
  String get subTransSectionTitle => 'Live translation';

  @override
  String get subTransToggle => 'Translate subtitles in real time';

  @override
  String get subTransToggleDesc =>
      'Detect the current subtitle line and show the translation on screen';

  @override
  String get subTransShowOriginal => 'Show original text';

  @override
  String get subTransOcrFallback => 'Recognize screen when no subtitles';

  @override
  String get subTransOcrFallbackDesc =>
      'Capture frames periodically and recognize dialogue (uses more data)';

  @override
  String get aiComicTranslationSection => 'Manga translation';

  @override
  String get aiComicTranslationDesc =>
      'Vision endpoint for manga page OCR + translation; falls back to common API when empty';

  @override
  String get aiComicModelHint => 'A vision-capable model, e.g. gpt-4o-mini';

  @override
  String get aiMediaTranslationSection => 'Video subtitle translation';

  @override
  String get aiMediaTranslationDesc =>
      'Endpoint for real-time subtitle translation in the player; falls back to common API when empty';

  @override
  String get translationCacheTitle => 'Translation cache';

  @override
  String get translationCacheDesc =>
      'Per-item AI translation results cached locally; clearing them means re-translating (and re-charging)';

  @override
  String get translationCacheNovel => 'Novel paragraph translation';

  @override
  String get translationCacheComic => 'Manga page translation';

  @override
  String get translationCacheSubtitle => 'Video subtitle translation';

  @override
  String translationCacheEntries(Object count) {
    return '$count entries';
  }

  @override
  String get translationCacheClear => 'Clear all translation caches';

  @override
  String get translationCacheClearConfirm =>
      'Clear all translation caches? Translated content will be re-translated with additional API cost.';

  @override
  String get translationCacheCleared => 'Translation caches cleared';

  @override
  String get glossaryTitle => 'Translation glossary';

  @override
  String glossaryTargetLang(String lang) {
    return 'Target language: $lang';
  }

  @override
  String get glossaryEmpty =>
      'No glossary entries yet. Add character names and proper nouns so translations stay consistent across chapters.';

  @override
  String get glossaryAdd => 'Add term';

  @override
  String get glossaryEdit => 'Edit term';

  @override
  String get glossaryTerm => 'Source term';

  @override
  String get glossaryPreferred => 'Preferred translation';

  @override
  String get glossaryAliases =>
      'Accepted aliases (separated by 、 or comma, optional)';

  @override
  String get glossaryNote => 'Note (optional)';

  @override
  String get glossaryImport => 'Import from JSON';

  @override
  String get glossaryExport => 'Export as JSON';

  @override
  String glossaryImportOk(int count) {
    return 'Imported $count entries';
  }

  @override
  String get glossaryImportFail => 'Import failed: invalid glossary file';

  @override
  String glossaryDeleteConfirm(String term) {
    return 'Delete term “$term”?';
  }

  @override
  String glossaryAliasesPreview(String aliases) {
    return 'Aliases: $aliases';
  }

  @override
  String get glossaryOpen => 'Glossary editor';

  @override
  String get glossaryWorkTitle => 'Work glossary';

  @override
  String get glossaryScopeGlobal => 'Global glossary · applies to all works';

  @override
  String get glossaryScopeWork => 'This work + global glossary';

  @override
  String glossaryConflictsTitle(int count) {
    return 'Glossary conflicts to resolve ($count)';
  }

  @override
  String get glossaryConflictExisting => 'Current translation';

  @override
  String get glossaryConflictProposed => 'Translation seen this batch';

  @override
  String glossaryConflictChapter(String chapter) {
    return 'From: $chapter';
  }

  @override
  String get glossaryConflictAdopt => 'Use new translation';

  @override
  String get glossaryConflictKeep => 'Keep current translation';

  @override
  String get glossaryConflictResolved => 'Conflict resolved';

  @override
  String get glossaryConflictBadge => 'Needs review';

  @override
  String get glossaryGlobalEntryHint =>
      'Global entry; edit or delete it in the global glossary';

  @override
  String get glossaryTypeTerm => 'Term';

  @override
  String get glossaryTypePerson => 'Person';

  @override
  String get glossaryTypePlace => 'Place';

  @override
  String get glossaryTypeOrg => 'Organization';

  @override
  String get glossaryTypeAppellation => 'Title';

  @override
  String get glossaryTypeHonorific => 'Honorific';

  @override
  String get glossaryTypeSpeech => 'Verbal tic';

  @override
  String get glossaryTypeFixed => 'Fixed expression';

  @override
  String glossaryExtractedNotice(int terms, int conflicts) {
    return '$terms terms added, $conflicts conflicts to resolve';
  }

  @override
  String get glossaryExtractedOpen => 'View';

  @override
  String get translationStyle => 'Translation style';

  @override
  String get translationStyleStandard => 'Standard';

  @override
  String get translationStyleColloquial => 'Colloquial';

  @override
  String get translationStyleElegant => 'Elegant';

  @override
  String get translationStyleInternet => 'Internet slang';

  @override
  String get translationCot => 'Deliberate translation (chain of thought)';

  @override
  String get translationCotHint =>
      'Let the model reason about context and terminology before translating. Higher quality but slower and more costly; best for short passages.';

  @override
  String get translationSubtitleLightweight => 'Lightweight subtitle output';

  @override
  String get translationSubtitleLightweightHint =>
      'Subtitles are output line-by-line without numbering to save tokens; falls back to numbered protocol automatically when alignment fails.';

  @override
  String get translationAutoExtract => 'Auto-extract glossary';

  @override
  String get translationAutoExtractHint =>
      'After each batch, collect character names, places and fixed renderings; differing renderings become conflicts to resolve. Turn off to reduce requests.';

  @override
  String get translationExportLayout => 'Novel translation appendix layout';

  @override
  String get translationLayoutTranslationFirst => 'Translation first';

  @override
  String get translationLayoutSourceFirst => 'Source first';

  @override
  String get translationLayoutBilingual => 'Bilingual';

  @override
  String get novelTranslateResume => 'Resume translation';

  @override
  String novelTranslateResumable(Object done, Object total) {
    return '$done of $total paragraphs translated - resume from where it stopped';
  }

  @override
  String get prescanStart => 'Prescan whole book';

  @override
  String prescanProgress(Object done, Object total) {
    return 'Prescanning: $done of $total chapters';
  }

  @override
  String get prescanReady => 'Book overview injected into translation context';

  @override
  String get translationPolish => 'Translation polish (second pass)';

  @override
  String get translationPolishHint =>
      'After a chapter is translated, polish it once more for natural phrasing and consistent terminology. Off by default; each polished chapter costs one extra request.';

  @override
  String get polishAction => 'Polish this chapter';

  @override
  String get translationVariantOriginal => 'First pass';

  @override
  String get translationVariantPolished => 'Polished';

  @override
  String get reviewOpen => 'Translation review reports';

  @override
  String get reviewTitle => 'Translation review';

  @override
  String get reviewBooksEmpty =>
      'No translated chapters cached yet. Translate some chapters first, then run a review here.';

  @override
  String reviewBookChapters(Object count) {
    return '$count chapters translated';
  }

  @override
  String reviewBookFindings(Object count) {
    return '$count findings in the latest report';
  }

  @override
  String get reviewRunFailed => 'Review failed';

  @override
  String reviewFindingCount(Object count) {
    return '$count findings';
  }

  @override
  String get reviewNoFindings => 'No issues found. All checks passed.';

  @override
  String get reviewTruncated =>
      'Summary version: showing the first 100 findings. The full report was saved as a JSON file.';

  @override
  String get reviewTypeGlossary => 'Glossary';

  @override
  String get reviewTypeMissing => 'Missing';

  @override
  String get reviewTypeLiteral => 'Literal';

  @override
  String get reviewTypeAdded => 'Over-translation';

  @override
  String get reviewTypeMistranslation => 'Mistranslation';

  @override
  String get reviewTypeTerminology => 'Terminology';

  @override
  String get reviewTypePronoun => 'Pronoun';

  @override
  String get reviewAiAction => 'AI review';

  @override
  String reviewAiProgress(Object done, Object total) {
    return 'AI reviewing $done/$total';
  }

  @override
  String get reviewAiPartial =>
      'Some chunks were skipped. The report may be incomplete.';

  @override
  String get reviewRevision => 'Revision';

  @override
  String get reviewAccept => 'Accept';

  @override
  String get reviewIgnore => 'Ignore';

  @override
  String get reviewApplyAll => 'Apply all';

  @override
  String reviewAppliedCount(Object count) {
    return 'Applied $count revisions';
  }

  @override
  String get offlineTranslateTitle => 'Offline whole-video translation';

  @override
  String get offlineHint =>
      'Pick an external subtitle file (SRT / VTT / ASS); all sentences are translated in batches and can be exported as bilingual subtitles. Interrupted jobs resume automatically.';

  @override
  String get offlinePickSubtitle => 'Pick subtitle file to translate';

  @override
  String offlineJobProgress(Object done, Object total) {
    return 'Translated $done of $total cues';
  }

  @override
  String get offlineJobDone => 'Translation complete - export below';

  @override
  String get offlineJobFailed => 'Translation failed';

  @override
  String get offlineResume => 'Resume';

  @override
  String get offlineCancel => 'Cancel job';

  @override
  String get offlineRetranslate => 'Translate again / fill gaps';

  @override
  String get offlineExportSrt => 'Export bilingual SRT';

  @override
  String get offlineExportAss => 'Export bilingual ASS';

  @override
  String get offlineUpload => 'Upload to WebDAV';

  @override
  String offlineUploaded(Object url) {
    return 'Uploaded: $url';
  }

  @override
  String get comicTranslateBackfillLabel => 'Bubble backfill layout';

  @override
  String get comicTranslateBackfillDesc =>
      'Render translations inside speech bubbles with stroked text, bubble-width wrapping and adaptive font size. Vertical text pages degrade to horizontal centered layout.';

  @override
  String get aiBackupSection => 'Backup endpoint (auto failover)';

  @override
  String get comicTranslationExport => 'Export translations (JSON)';

  @override
  String get comicTranslationImport => 'Import translations';

  @override
  String comicTranslationImportOk(Object imported, Object skipped) {
    return 'Imported $imported pages, skipped $skipped existing';
  }

  @override
  String get comicTranslationImportFail =>
      'Import failed: invalid translations file';

  @override
  String get offlineExportAll => 'Export all completed (bilingual SRT)';

  @override
  String get networkRssAppliesNote =>
      'RSS subscriptions also apply this page\'s proxy, DNS, SNI and Hosts settings: global network configured here takes effect for both RSS fetching and RSSHub speed tests.';

  @override
  String get rssGlobalSubscriptionDesc =>
      'Global RSS subscriptions shared with the Browse tab';

  @override
  String get rssBindModuleTitle => 'Bind to module';

  @override
  String get rssBindToNovel => 'Bind to novel';

  @override
  String get rssBindToAnime => 'Bind to video';

  @override
  String get rssBindToManga => 'Bind to manga';

  @override
  String get rssUnbindGlobal => 'Unbind to global';

  @override
  String get rssArticleFavorited => 'Added to favorites';

  @override
  String get rssArticleUnfavorited => 'Removed from favorites';

  @override
  String get rssFavorites => 'RSS Favorites';

  @override
  String get rssFavoritesDesc => 'Favorited RSS articles';

  @override
  String get rssFavoritesEmpty => 'No favorites yet';

  @override
  String get rssMarkAllRead => 'Mark all as read';

  @override
  String get rssMarkedAllRead => 'Marked all as read';

  @override
  String get rssOfflineCached => 'Offline cache (last fetched)';

  @override
  String get rssShowAll => 'All';

  @override
  String get rssShowUnread => 'Unread';

  @override
  String get rssStarAdd => 'Add to favorites';

  @override
  String get rssStarRemove => 'Remove from favorites';

  @override
  String rssDiscoverAddSelected(Object count) {
    return 'Add selected ($count)';
  }

  @override
  String rssDiscoverAdded(Object count) {
    return 'Added $count feeds';
  }

  @override
  String get rssDiscoverButton => 'Find feeds';

  @override
  String get rssDiscoverDesc =>
      'Enter a site address to find its RSS / Atom feeds';

  @override
  String rssDiscoverFailed(Object error) {
    return 'Discovery failed: $error';
  }

  @override
  String rssDiscoverFound(Object count) {
    return 'Found $count feeds';
  }

  @override
  String get rssDiscoverFromLink => 'Declared by page';

  @override
  String get rssDiscoverFromProbe => 'Common path';

  @override
  String get rssDiscoverInputHint => 'https://example.com';

  @override
  String get rssDiscoverInvalidUrl => 'Enter a valid URL';

  @override
  String get rssDiscoverNone => 'No feeds found';

  @override
  String get rssDiscoverProbing => 'Probing common paths…';

  @override
  String get rssDiscoverTitle => 'Discover feeds from a site';

  @override
  String get rssExportOpml => 'Export as OPML';

  @override
  String get rssGroupAdd => 'New group';

  @override
  String rssGroupAddExists(Object name) {
    return 'Group \"$name\" already exists';
  }

  @override
  String get rssAudioFailed => 'Audio failed to load';

  @override
  String get rssOpenExternally => 'Open in external app';

  @override
  String get rssVideoFailed => 'Video failed to load';

  @override
  String get rssVideoPlay => 'Play video';

  @override
  String get rssFetchWebsite => 'Fetch from website';

  @override
  String get rssFetchSucceeded => 'Article updated from website';

  @override
  String get rssListLayout => 'List layout';

  @override
  String get rssLayoutList => 'List';

  @override
  String get rssLayoutCard => 'Cards';

  @override
  String get rssLayoutCompact => 'Compact';

  @override
  String get rssLayoutMagazine => 'Magazine';

  @override
  String get rssSort => 'Sort';

  @override
  String get rssSortNewest => 'Newest first';

  @override
  String get rssSortOldest => 'Oldest first';

  @override
  String get rssSortUnreadFirst => 'Unread first';

  @override
  String get rssPrevArticle => 'Previous';

  @override
  String get rssNextArticle => 'Next';

  @override
  String get rssAutoReadTitle => 'Auto-read keywords';

  @override
  String get rssAutoReadDesc =>
      'New articles whose title matches a keyword are marked as read and excluded from the unread count';

  @override
  String get rssAutoReadAdd => 'Add keyword';

  @override
  String get rssAutoReadEmpty => 'No keywords yet';

  @override
  String get rssAutoReadHint => 'Keyword contained in the article title';

  @override
  String get rssOpenInBrowser => 'Open in browser';

  @override
  String get rssAutoFetchFullText => 'Auto-fetch full text';

  @override
  String get rssIframeOpen => 'Open in built-in browser';

  @override
  String get rssFetchFullText => 'Fetch full page';

  @override
  String get rssFetching => 'Fetching…';

  @override
  String get rssFetchFullTextFailed => 'Fetch failed';

  @override
  String get rssFetchFullTextEmpty => 'Could not extract content';

  @override
  String get rssImageSaved => 'Image saved';

  @override
  String get rssImageSaveFailed => 'Save failed';

  @override
  String get rssLinkUnsupported => 'This link is not supported';

  @override
  String get rssGroupAll => 'All';

  @override
  String get rssGroupDelete => 'Delete group';

  @override
  String rssGroupDeleteConfirm(Object name) {
    return 'Delete group \"$name\"? Subscriptions stay; only the tag is removed.';
  }

  @override
  String get rssGroupEmpty => 'No groups yet';

  @override
  String rssGroupFeedCount(Object count) {
    return '$count feeds';
  }

  @override
  String get rssGroupManage => 'Manage groups';

  @override
  String get rssGroupRename => 'Rename group';

  @override
  String get rssGroupSetDone => 'Groups updated';

  @override
  String get rssGroupUngrouped => 'Ungrouped';

  @override
  String get rssImportOpml => 'Import OPML';

  @override
  String rssOpmlCategory(Object name) {
    return 'Group: $name';
  }

  @override
  String get rssOpmlConfirmImport => 'Import selected';

  @override
  String get rssOpmlEmpty => 'No subscriptions to import';

  @override
  String get rssOpmlExportDesc => 'Export all subscriptions to standard OPML';

  @override
  String get rssOpmlExportDesc2 => 'Create an OPML backup and share it';

  @override
  String get rssOpmlExportTitle => 'Export';

  @override
  String get rssOpmlImportDesc =>
      'Import subscriptions from a file or pasted text';

  @override
  String get rssOpmlImportFile => 'Import from file';

  @override
  String get rssOpmlImportFileDesc => 'Pick a local .opml / .xml file';

  @override
  String get rssOpmlImportPreviewTitle => 'Import preview';

  @override
  String get rssOpmlImportText => 'Import from pasted text';

  @override
  String get rssOpmlImportTextDesc => 'Paste OPML content directly';

  @override
  String get rssOpmlImportTitle => 'Import';

  @override
  String rssOpmlParseFailed(Object error) {
    return 'Failed to parse OPML: $error';
  }

  @override
  String rssOpmlPreviewSummary(Object selected, Object total) {
    return 'Selected $selected / $total total';
  }

  @override
  String rssOpmlPreviewSummarySkipped(
      Object selected, Object skipped, Object total) {
    return 'Selected $selected / $total total (skipped $skipped invalid nodes)';
  }

  @override
  String get rssSetGroups => 'Set groups';

  @override
  String get rssOpmlTitle => 'OPML Import & Export';

  @override
  String get rssOpmlExport => 'Export as OPML';

  @override
  String get rssOpmlPasteHint => 'Paste OPML content here';

  @override
  String rssOpmlImported(Object count) {
    return 'Imported $count subscriptions';
  }

  @override
  String get rssGroupName => 'Group name';

  @override
  String get rssSearchTitle => 'RSS Search';

  @override
  String get rssSearchHint => 'Search articles in your subscriptions';

  @override
  String get rssSearchNoResult => 'No matching articles';

  @override
  String get rssSearchBuilding => 'Building index…';

  @override
  String get rssSearchEmpty => 'No cached articles yet. Open a feed first.';

  @override
  String rssSearchCount(Object shown, Object total) {
    return 'Matched $shown of $total';
  }

  @override
  String get rssAttachments => 'Attachments';

  @override
  String get rssSystemNotification => 'System notification';

  @override
  String get rssSystemNotificationSubtitle =>
      'Send OS notification on new articles (Android/iOS/Linux/macOS)';

  @override
  String get articleMargin => 'Margin';

  @override
  String get articleFontUnderline => 'Underline';

  @override
  String get articleUnderlineDashed => 'Dashed underline';

  @override
  String get articleUnderlineThickness => 'Underline width';

  @override
  String get articleUnderlineColor => 'Underline color';

  @override
  String get articleBackground => 'Background';

  @override
  String get articleTextColor => 'Text color';

  @override
  String get articleEmphasisColor => 'Accent color';

  @override
  String get articleShadow => 'Text shadow';

  @override
  String get articleShadowBlur => 'Shadow blur';

  @override
  String get articleShadowOffsetX => 'Shadow X offset';

  @override
  String get articleShadowOffsetY => 'Shadow Y offset';

  @override
  String get articleChooseFont => 'Choose font file';

  @override
  String get articleClearFont => 'Clear font';

  @override
  String articleFontCurrent(Object file) {
    return 'Current: $file';
  }

  @override
  String get articleTitleScale => 'Title size';

  @override
  String get articleTitleBold => 'Bold title';

  @override
  String get articleTitleColor => 'Title color';

  @override
  String get articleTitleAlign => 'Title alignment';

  @override
  String get alignLeft => 'Left';

  @override
  String get alignCenter => 'Center';

  @override
  String get alignRight => 'Right';

  @override
  String get colorFollowDefault => 'Follow default';

  @override
  String get rssChargeCheck => 'Check on charging';

  @override
  String get rssChargeCheckSubtitle =>
      'Auto-check for new content once the charger is connected (trigger: charging)';

  @override
  String get articleSecTypography => 'Typography';

  @override
  String get articleSecTextStyle => 'Text style';

  @override
  String get articleSecColor => 'Color & background';

  @override
  String get articleSecShadow => 'Shadow';

  @override
  String get articleSecFont => 'Font';

  @override
  String get articleSecTitle => 'Title';

  @override
  String get mediaServerSettings => 'Media servers';

  @override
  String get mediaServerSettingsDesc =>
      'Manage Emby / Jellyfin server connections and sign-in';

  @override
  String get mediaServerSettingsSubtitle =>
      'Connect Emby / Jellyfin with two-way watch progress sync';

  @override
  String mediaServerTileConnected(Object n) {
    return '$n connected';
  }

  @override
  String get mediaServerAddServer => 'Add server';

  @override
  String get mediaServerAddressLabel => 'Server address';

  @override
  String get mediaServerAddressHint => 'e.g. http://192.168.1.10:8096';

  @override
  String get mediaServerDetect => 'Detect';

  @override
  String get mediaServerDetecting => 'Detecting…';

  @override
  String get mediaServerTypeLabel => 'Type';

  @override
  String mediaServerDetectedAs(Object name) {
    return 'Detected: $name';
  }

  @override
  String get mediaServerManualTypeHint =>
      'Detection failed? Pick the type manually and sign in.';

  @override
  String get mediaServerUsernameLabel => 'Username';

  @override
  String get mediaServerPasswordLabel => 'Password';

  @override
  String get mediaServerLogin => 'Sign in';

  @override
  String get mediaServerLoggingIn => 'Signing in…';

  @override
  String get mediaServerNotLoggedIn => 'Not signed in';

  @override
  String mediaServerLoggedInAs(Object user) {
    return 'Account: $user';
  }

  @override
  String get mediaServerStatusOnline => 'Online';

  @override
  String get mediaServerStatusOffline => 'Offline';

  @override
  String get mediaServerStatusNeedRelogin => 'Re-login required';

  @override
  String get mediaServerStatusChecking => 'Checking…';

  @override
  String get mediaServerRename => 'Rename';

  @override
  String get mediaServerRenameTitle => 'Rename server';

  @override
  String get mediaServerRelogin => 'Re-login';

  @override
  String mediaServerReloginTitle(Object name) {
    return 'Re-login to \"$name\"';
  }

  @override
  String get mediaServerDelete => 'Delete';

  @override
  String get mediaServerDeleteTitle => 'Delete server';

  @override
  String mediaServerDeleteBody(Object name) {
    return 'This removes the local configuration and credentials for \"$name\". Your server\'s libraries and watch progress are not affected.';
  }

  @override
  String get mediaServerEmptyTitle => 'No servers yet';

  @override
  String get mediaServerEmptyHint =>
      'Supports Emby and Jellyfin. Enter a LAN or reverse-proxy address, sign in, then browse and play.';

  @override
  String mediaServerOperationFailed(Object error) {
    return 'Operation failed: $error';
  }

  @override
  String get mediaServerAddressRequired => 'Enter a server address first';

  @override
  String get mediaServerCredentialsRequired => 'Enter a username and password';

  @override
  String get mediaServerHomeResume => 'Continue watching';

  @override
  String get mediaServerHomeLatest => 'Latest additions';

  @override
  String get mediaServerHomeLibraries => 'Libraries';

  @override
  String get mediaServerUnsupportedLibraries =>
      'Music / photo and other library types are not supported yet and are hidden.';

  @override
  String get mediaServerRetry => 'Retry';

  @override
  String mediaServerLoadFailed(Object error) {
    return 'Failed to load: $error';
  }

  @override
  String get mediaServerSearchHint => 'Search within server';

  @override
  String get mediaServerNoResults => 'No results';

  @override
  String get mediaServerPlay => 'Play';

  @override
  String get mediaServerResumePlay => 'Resume';

  @override
  String get mediaServerPlayFromStart => 'Play from start';

  @override
  String get mediaServerTypeSeries => 'Series';

  @override
  String get mediaServerPgsSubtitleWarn =>
      'Graphical subtitles in this episode require transcoding (unsupported).';

  @override
  String get mediaServerTranscodeRequired =>
      'This format requires transcoding (unsupported).';

  @override
  String mediaServerRuntimeMinutes(Object m) {
    return '$m min';
  }

  @override
  String mediaServerRuntimeHoursMinutes(Object h, Object m) {
    return '$h h $m min';
  }

  @override
  String get mediaServerGoAdd => 'Add a server';

  @override
  String get mediaServerCredentialsWrong =>
      'Incorrect username or password. Please check and try again.';

  @override
  String get mediaServerManageAction => 'Add or manage media servers';

  @override
  String get mediaServerConnecting => 'Connecting to server…';

  @override
  String get mediaServerBlockedByChallenge =>
      'Blocked by the server\'s protection (Cloudflare challenge). Open the server address in a browser to verify once, or ask the admin to exempt API paths';

  @override
  String get mediaServerUnreachable =>
      'Cannot reach the media server (network error or temporary rate limit). Try again later';

  @override
  String get mediaServerBitrateTier => 'Bitrate tier';

  @override
  String get mediaServerBitrateAuto => 'Auto (server decides)';

  @override
  String get mediaServerBitrateOriginal => 'Original (direct play only)';

  @override
  String get mediaServerBitrate720p => '720p cap';

  @override
  String get mediaServerTranscodingNotice =>
      'Direct play not supported for this format, transcoding instead';

  @override
  String get mediaServerOriginalNeedsDirect =>
      'Original tier requires direct play, which this format does not support; pick another bitrate tier';

  @override
  String get mediaServerAudioTrack => 'Audio track';

  @override
  String get mediaServerFavorites => 'My favorites';

  @override
  String get mediaServerNextUp => 'Next up';

  @override
  String get mediaServerFavorite => 'Favorite';

  @override
  String get mediaServerFavoriteAdded => 'Added to favorites';

  @override
  String get mediaServerFavoriteRemoved => 'Removed from favorites';

  @override
  String get mediaServerMarkWatched => 'Mark watched';

  @override
  String get mediaServerMarkUnwatched => 'Mark unwatched';

  @override
  String get mediaServerMarkAllWatched => 'Mark all watched';

  @override
  String mediaServerRemaining(Object m) {
    return '$m min left';
  }

  @override
  String get mediaServerFilterAll => 'All';

  @override
  String get mediaServerFilterUnwatched => 'Unwatched';

  @override
  String get mediaServerFilterWatched => 'Watched';

  @override
  String get mediaServerFilterGenre => 'Genre';

  @override
  String get mediaServerFilterYear => 'Year';

  @override
  String get mediaServerSort => 'Sort';

  @override
  String get mediaServerSortByName => 'Name';

  @override
  String get mediaServerSortByYear => 'Year';

  @override
  String get mediaServerSortByAdded => 'Date added';

  @override
  String get mediaServerAddresses => 'Server addresses';

  @override
  String get mediaServerAddressesHint =>
      'One address per line; the first reachable one becomes active (LAN & WAN can coexist)';

  @override
  String get mediaServerAddressSaved => 'Addresses updated';

  @override
  String get mediaServerTypeBoxSet => 'Collection';

  @override
  String get mediaServerStatsPlayMethod => 'Play method';

  @override
  String get mediaServerPlayMethodDirect => 'Direct play';

  @override
  String get mediaServerPlayMethodDirectStream => 'Direct stream';

  @override
  String get mediaServerPlayMethodTranscode => 'Transcoding';

  @override
  String get mediaServerSearchHistory => 'Search history';

  @override
  String get mediaServerSearchHistoryClear => 'Clear search history';

  @override
  String get bingTranslationTitle => 'Bing free translation';

  @override
  String get bingTranslationDesc =>
      'No API key required; also powers titles, tags, summaries and comments';

  @override
  String get bingTranslationEnable => 'Enable Bing free translation';

  @override
  String get bingTranslationEnableHint =>
      'When off, novels and subtitles use AI only; auto translation on detail pages is disabled';

  @override
  String get bingTranslationPriority => 'Engine priority';

  @override
  String get bingTranslationBingFirst => 'Bing first';

  @override
  String get bingTranslationAiFirst => 'AI first';

  @override
  String get bingTranslationAutoTitle => 'Auto-translate titles';

  @override
  String get bingTranslationAutoTags => 'Auto-translate tags';

  @override
  String get bingTranslationAutoSummary => 'Auto-translate summaries';

  @override
  String get bingTranslationAutoComments => 'Auto-translate comments';

  @override
  String get bingTranslationTest => 'Test Bing connection';

  @override
  String get bingTranslationTesting => 'Testing...';

  @override
  String get bingTranslationTestOk => 'Bing translation is available';

  @override
  String get bingTranslationTestFail =>
      'Bing is unavailable right now; AI fallback will be used';

  @override
  String get translationNotNeeded =>
      'Already in the target language; no translation needed';

  @override
  String get bingTranslationPrivacy =>
      'Text is sent to Microsoft\'s translation service. This is an unofficial endpoint and may change or stop working at any time.';

  @override
  String get translationCacheUiText => 'Detail page & comment translation';

  @override
  String get storageLocationAppPrivate => 'App private folder';

  @override
  String get storageLocationAppPrivateHint =>
      'Inside the app; deleted with the app';

  @override
  String get storageLocationSystemDownloads => 'System Downloads folder';

  @override
  String get storageLocationSystemDownloadsHint =>
      'Visible in Files and kept after uninstall';

  @override
  String get storageLocationSystemScreenshots =>
      'System Downloads / Screenshots';

  @override
  String get storageLocationSystemScreenshotsHint =>
      'Visible in Files and kept after uninstall';

  @override
  String get ttsAutoNext => 'Auto-continue chapters';

  @override
  String get ttsAutoNextDesc =>
      'Load and read the next chapter automatically when one finishes';

  @override
  String get ttsCastTitle => 'Characters & voices';

  @override
  String get ttsCastSubtitle =>
      'Assign different voices per character; unassigned roles fall back to narrator/gender slots';

  @override
  String get ttsCastHttpSlots => 'Online voice fallback (HTTP TTS)';

  @override
  String get ttsCastSystemSlots => 'System voices (device engine)';

  @override
  String get ttsCastNarratorVoice => 'Narrator voice';

  @override
  String get ttsCastMaleVoice => 'Male fallback voice';

  @override
  String get ttsCastFemaleVoice => 'Female fallback voice';

  @override
  String get ttsCastHttpVoice => 'Online voice ID (HTTP TTS)';

  @override
  String get ttsCastSystemVoice => 'System voice';

  @override
  String get ttsCastEngineDefault => 'Engine default';

  @override
  String get ttsCastCharacters => 'Characters in this book';

  @override
  String get ttsCastEmpty =>
      'No character cards yet. AI identifies speakers while reading; you can also add manually.';

  @override
  String get ttsCastAddRole => 'Add character';

  @override
  String get ttsCastEditRole => 'Edit character';

  @override
  String get ttsCastRoleName => 'Name';

  @override
  String get ttsCastAliases => 'Aliases (optional)';

  @override
  String get ttsCastAliasesHint => 'Separate multiple aliases with commas';

  @override
  String get ttsCastMale => 'Male';

  @override
  String get ttsCastFemale => 'Female';

  @override
  String get ttsCastGenderUnknown => 'Unknown';

  @override
  String get ttsCastEnable => 'Enable';

  @override
  String get ttsCastDisable => 'Disable';

  @override
  String get ttsCastDelete => 'Delete';

  @override
  String get ttsCastAiRelabel => 'AI attribution for this chapter';

  @override
  String get ttsCastAiRunning => 'AI attributing…';

  @override
  String ttsCastAiDone(int count) {
    return 'AI attribution done: $count lines labeled';
  }

  @override
  String get ttsCastAiNoConfig =>
      'No AI endpoint configured. Set the novel-overview or default endpoint in Settings → AI first.';

  @override
  String get ttsCastAiFailed => 'AI attribution failed; local results kept';

  @override
  String get ttsCastVoiceMapHint =>
      'Global fallback map (name=voiceId, one per line); per-book setup lives in the reader\'s Characters & voices panel';

  @override
  String get ttsCacheClear => 'Clear TTS audio cache';

  @override
  String get ttsCacheEmpty => 'No cached audio';

  @override
  String ttsCacheCount(int count) {
    return '$count audio clips cached';
  }

  @override
  String ttsCacheCleared(int count) {
    return 'Cleared $count TTS audio clips';
  }

  @override
  String homeWidgetUpdates(int count) {
    return 'Updates · $count saved';
  }

  @override
  String get homeWidgetUpdatesIdle => 'Updates · nothing saved';

  @override
  String homeWidgetDownloads(int count, int percent) {
    return 'Downloads · $count at $percent%';
  }

  @override
  String get homeWidgetDownloadsIdle => 'Downloads · idle';

  @override
  String homeWidgetWeek(int minutes) {
    return 'This week · $minutes min';
  }

  @override
  String get homeWidgetWeekIdle => 'This week · not started';

  @override
  String get homeWidgetEmptyTitle => 'Nothing watched yet';

  @override
  String get homeWidgetEmptyHint => 'Open NexHub and pick something';

  @override
  String get homeWidgetContinueLabel => 'Continue';

  @override
  String get homeWidgetUpdatesLabel => 'Updates';

  @override
  String get homeWidgetDownloadsLabel => 'Downloads';

  @override
  String get homeWidgetStatsLabel => 'Stats';

  @override
  String homeWidgetChapterProgress(int index, int total) {
    return 'Ch. $index of $total';
  }

  @override
  String homeWidgetChapterProgressOpen(int index) {
    return 'Ch. $index';
  }

  @override
  String homeWidgetEpisodeProgress(int index, int minutes) {
    return 'Ep. $index · $minutes min watched';
  }

  @override
  String homeWidgetEpisodeWatched(int index) {
    return 'Ep. $index';
  }

  @override
  String homeWidgetToday(int minutes) {
    return 'Today · $minutes min';
  }

  @override
  String get homeWidgetTodayIdle => 'Today · not started';

  @override
  String homeWidgetStreak(int active, int streak) {
    return '$active days active · $streak streak';
  }

  @override
  String get settingsCatWidget => 'Home widgets';

  @override
  String get settingsCatWidgetDesc => 'Background, blur and record count';

  @override
  String get widgetBackgroundSection => 'Background';

  @override
  String get widgetBgCover => 'Cover art';

  @override
  String get widgetBgCoverDesc => 'Blur the cover of what you last watched';

  @override
  String get widgetBgTheme => 'Theme color';

  @override
  String get widgetBgThemeDesc => 'Gradient based on the current theme color';

  @override
  String get widgetBgNone => 'None';

  @override
  String get widgetBgNoneDesc => 'Keep only the card base color';

  @override
  String get widgetTuningSection => 'Appearance';

  @override
  String get widgetBlurStrength => 'Blur strength';

  @override
  String get widgetOpacity => 'Opacity';

  @override
  String get widgetRecordsSection => 'Records';

  @override
  String get widgetContinueLimit => 'Continue-watching items';

  @override
  String widgetContinueLimitDesc(int count) {
    return 'Show $count items';
  }

  @override
  String get widgetLimitNote => 'Platform limit';

  @override
  String get widgetLimitNoteDesc =>
      'Widgets show 4–5 items depending on platform';

  @override
  String get widgetHeatmapCaption => 'This month';

  @override
  String get widgetMinuteUnit => 'min';

  @override
  String get widgetStreakCaption => 'Streak';

  @override
  String widgetLifetimeHours(int hours) {
    return '$hours h total';
  }

  @override
  String widgetWeekSessions(int count) {
    return '$count sessions this week';
  }

  @override
  String widgetTrendUp(int percent) {
    return '+$percent%';
  }

  @override
  String widgetTrendDown(int percent) {
    return '-$percent%';
  }

  @override
  String get widgetTrendFlat => 'flat';

  @override
  String get widgetTrendNew => 'new';
}
