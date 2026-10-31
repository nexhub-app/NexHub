// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'NexHub';

  @override
  String get navBrowse => '浏览';

  @override
  String get navNovel => '小说';

  @override
  String get navMedia => '媒体';

  @override
  String get navComic => '漫画';

  @override
  String get navSettings => '设置';

  @override
  String get homeTitle => '浏览';

  @override
  String get settingsTitle => '设置';

  @override
  String get settingsTagline => '打造专属你的媒体空间';

  @override
  String get sourceManagementTitle => '源管理';

  @override
  String get sourceManagementDesc => '导入、启用与排序内容源';

  @override
  String get downloadSettingsTitle => '下载';

  @override
  String get downloadManagementTitle => '下载管理';

  @override
  String get aboutTitle => '关于';

  @override
  String get themeTitle => '外观';

  @override
  String get tabLibrary => '书架';

  @override
  String get tabMediaLibrary => '媒体库';

  @override
  String get tabOnline => '在线';

  @override
  String get tabSubscribe => '订阅';

  @override
  String get tabSources => '源管理';

  @override
  String get browseLocalFiles => '本地文件';

  @override
  String get browseLocalFilesSubtitle => '浏览本机小说、视频和漫画';

  @override
  String get browseNetworkFiles => '网络文件';

  @override
  String get browseNetworkFilesSubtitle => '浏览 HTTP 文件服务器';

  @override
  String get browseWebScrape => '网页爬取';

  @override
  String get browseWebScrapeSubtitle => '从网页提取小说、漫画、视频或文章';

  @override
  String get browseRss => 'RSS 订阅';

  @override
  String get browseRssSubtitle => '管理和浏览 RSS 订阅源';

  @override
  String get browseSniff => '嗅探';

  @override
  String get browseSniffSubtitle => '嗅探网页视频并在应用内播放';

  @override
  String get subTabLocal => '本地';

  @override
  String get subTabHistory => '历史记录';

  @override
  String get subTabFavorite => '收藏';

  @override
  String get filter => '筛选';

  @override
  String get filterTitle => '筛选';

  @override
  String get sortBy => '排序';

  @override
  String get sortRecent => '最近';

  @override
  String get sortTitle => '标题';

  @override
  String get sortAuthor => '作者';

  @override
  String get sortLatestChapter => '最新章';

  @override
  String get sortTitleZh => '中文书名';

  @override
  String get sortManual => '手动';

  @override
  String get sortDirector => '导演';

  @override
  String get sortActors => '主演';

  @override
  String get sortLatestUpdate => '最新';

  @override
  String get sortLatestMangaChapter => '最新话';

  @override
  String get filterByStatus => '状态';

  @override
  String get filterByCategory => '分类';

  @override
  String get filterByProgress => '进度';

  @override
  String get allLabel => '全部';

  @override
  String get progressReading => '在看';

  @override
  String get progressNotStarted => '未看';

  @override
  String get filterReset => '重置';

  @override
  String get filterApply => '应用';

  @override
  String get filterSelectedPrefix => '已选';

  @override
  String get play => '播放';

  @override
  String get readChapter => '阅读';

  @override
  String episodesWithLine(Object line) {
    return '剧集 · $line';
  }

  @override
  String get recommendations => '猜你喜欢';

  @override
  String episodeN(Object n) {
    return '第 $n 集';
  }

  @override
  String get cancel => '取消';

  @override
  String get confirm => '确认';

  @override
  String get delete => '删除';

  @override
  String get save => '保存';

  @override
  String get import => '导入';

  @override
  String get export => '导出';

  @override
  String get close => '关闭';

  @override
  String get search => '搜索';

  @override
  String get retry => '重试';

  @override
  String get ok => '确定';

  @override
  String get next => '下一集';

  @override
  String get previous => '上一集';

  @override
  String get emptyLibrary => '书架还是空的';

  @override
  String get emptySearch => '没有找到结果';

  @override
  String get emptyDownloads => '还没有下载';

  @override
  String get emptySources => '还没有添加源';

  @override
  String get emptyBrowse => '这里什么都没有';

  @override
  String get emptyLocalNovel => '暂无本地小说';

  @override
  String get emptyLocalMedia => '暂无本地媒体';

  @override
  String get emptyLocalComic => '暂无本地漫画';

  @override
  String get emptyLocalNovelAction => '导入小说';

  @override
  String get emptyLocalMediaAction => '导入媒体';

  @override
  String get emptyLocalComicAction => '导入漫画';

  @override
  String get loading => '加载中…';

  @override
  String get noResults => '暂无结果';

  @override
  String get loadFailed => '加载失败';

  @override
  String chapterLoadPartial(Object count) {
    return '目录加载未完成，当前显示 $count 章（网络可能不稳定）';
  }

  @override
  String get noMoreResults => '没有更多了';

  @override
  String get authorColon => '作者：';

  @override
  String get tagColon => '标签：';

  @override
  String get searchFailed => '搜索失败，请重试';

  @override
  String get searching => '搜索中…';

  @override
  String updatedAt(Object time) {
    return '更新于 $time';
  }

  @override
  String get statusOngoing => '连载中';

  @override
  String get statusCompleted => '已完成';

  @override
  String get deprecated => '已弃用';

  @override
  String get mirrorSettings => '镜像与隐藏设置';

  @override
  String get stealthMode => '隐身模式';

  @override
  String get gridView => '网格视图';

  @override
  String get listView => '列表视图';

  @override
  String get toggleLayout => '切换视图';

  @override
  String get all => '全部';

  @override
  String get emptyCategory => '该分类暂无内容';

  @override
  String get emptyContent => '暂无内容';

  @override
  String get contentExpired => '内容已过期，请重新搜索';

  @override
  String get sourceNotFound => '内容源不可用，请更换源或重新搜索';

  @override
  String get onlineBrowse => '在线浏览';

  @override
  String get switchSource => '切换源';

  @override
  String get searchSourceHint => '搜索源名称';

  @override
  String get refreshList => '刷新列表';

  @override
  String get goToVerification => '去验证';

  @override
  String get openSourceWebsite => '打开源站';

  @override
  String get errorGeneric => '出了点问题';

  @override
  String get errorNetwork => '网络错误，请重试';

  @override
  String get errorParse => '解析内容失败';

  @override
  String get errorVerification => '需要验证，请完成验证';

  @override
  String get verificationFailed => '验证失败，请稍后重试';

  @override
  String get errorVideoExpired => '视频链接已失效，请重试';

  @override
  String get danmaku => '弹幕';

  @override
  String get danmakuSend => '发送弹幕';

  @override
  String get danmakuSendHint => '输入弹幕内容';

  @override
  String get danmakuUploadSuccess => '弹幕已上传';

  @override
  String danmakuUploadFailed(String error) {
    return '弹幕上传失败：$error';
  }

  @override
  String get danmakuSendNoEpisode => '弹幕未匹配到剧集，仅本地显示';

  @override
  String get danmakuSendTimeInvalid => '发送位置超出视频时长，仅本地显示';

  @override
  String get danmakuLoginTitle => '登录弹弹play';

  @override
  String get danmakuLoginRequiredHint => '发送弹幕需要登录弹弹play 账号';

  @override
  String get danmakuUsername => '用户名';

  @override
  String get danmakuPassword => '密码';

  @override
  String get danmakuLoginAction => '登录';

  @override
  String get danmakuLoginEmptyFields => '请填写用户名与密码';

  @override
  String get danmakuAccountSection => '弹弹play 账号';

  @override
  String danmakuAccountLoggedInAs(String name) {
    return '已登录：$name';
  }

  @override
  String get dandanplayLoggedOut => '已退出弹弹play 账号';

  @override
  String get dandanplayAppNotConfigured => '弹弹play 应用未配置，当前无法登录';

  @override
  String get dandanplayLoginTab => '登录';

  @override
  String get dandanplayRegisterTab => '注册';

  @override
  String get dandanplayEmail => '邮箱';

  @override
  String get dandanplayNickname => '昵称';

  @override
  String get dandanplayRegisterAction => '注册并登录';

  @override
  String get dandanplayRegisterSuccess => '注册成功，已自动登录';

  @override
  String get dandanplayRegisterEmptyFields => '请填写用户名、密码与邮箱';

  @override
  String get dandanplayRegisterEmailInvalid => '邮箱格式不正确';

  @override
  String get danmakuStyle => '弹幕样式';

  @override
  String get danmakuStyleScroll => '滚动';

  @override
  String get danmakuStyleTop => '顶部';

  @override
  String get danmakuStyleBottom => '底部';

  @override
  String get themeLight => '浅色';

  @override
  String get themeDark => '深色';

  @override
  String get themeSystem => '跟随系统';

  @override
  String get useMonet => '使用动态取色（莫奈）';

  @override
  String get glassEffectTitle => '界面毛玻璃效果';

  @override
  String get glassEffectDesc => '侧栏/底栏半透明模糊，内容从栏后滚过；低端设备可关闭';

  @override
  String get sourceDragSplitTitle => '拖动排序断开动效';

  @override
  String get sourceDragSplitDesc => '拖动源排序时卡片断开、圆角实时跟随；关闭后为简化效果，卡片保持完整';

  @override
  String get statusBarTapToTopTitle => '轻点状态栏回到顶部';

  @override
  String get statusBarTapToTopDesc => '鸿蒙设备上轻点系统状态栏，当前页面快速滚动回顶部';

  @override
  String get glassBlurStrength => '模糊强度';

  @override
  String get glassBarOpacity => '栏位不透明度';

  @override
  String get customColor => '自定义颜色';

  @override
  String get presetColor => '预设颜色';

  @override
  String get paletteStyleTitle => '调色板风格';

  @override
  String get paletteStyleDesc => '同一主色下的配色算法变体';

  @override
  String get paletteStyleTonalSpot => '标准';

  @override
  String get paletteStyleFidelity => '保真';

  @override
  String get paletteStyleContent => '内容';

  @override
  String get paletteStyleNeutral => '中性';

  @override
  String get paletteStyleMonochrome => '单色';

  @override
  String get paletteStyleVibrant => '鲜艳';

  @override
  String get paletteStyleExpressive => '表现力';

  @override
  String get paletteStyleRainbow => '彩虹';

  @override
  String get paletteStyleFruitSalad => '水果沙拉';

  @override
  String get appearanceThemeMode => '主题模式';

  @override
  String get appearanceThemeSection => '主题';

  @override
  String get appearanceColorsSection => '配色';

  @override
  String get appearanceFontSection => '字体';

  @override
  String get appearanceFont => '界面字体';

  @override
  String get appFontFollowSystem => '跟随系统';

  @override
  String get appFontFollowSystemDesc => '使用系统默认字体';

  @override
  String get appFontPreviewSample => '预览：永东国爱，123 Aa';

  @override
  String get appFontCustomDesc => '自定义字体';

  @override
  String get appFontCustomImport => '导入字体文件（.ttf / .otf）';

  @override
  String get appFontClearCustom => '清除自定义字体';

  @override
  String get appFontLoadFailed => '字体加载失败，请换一个 .ttf / .otf 文件试试';

  @override
  String get appearanceStartupSection => '启动与显示';

  @override
  String get heroSettingsTitle => 'Hero 图片设置';

  @override
  String get appearanceHeroSection => '背景图';

  @override
  String get heroEmptyHint => '添加几张图片，在设置主页顶部循环展示';

  @override
  String get heroAddFromUrl => '从网络添加';

  @override
  String get heroAddFromDevice => '从本机选择';

  @override
  String get heroUrlDialogTitle => '添加图片 URL';

  @override
  String get heroUrlFieldHint => '图片地址（https://... 或 file://...）';

  @override
  String get heroRemoveTooltip => '删除';

  @override
  String get deleteConfirmTitle => '删除确认';

  @override
  String deleteConfirmContent(String name) {
    return '确定删除「$name」吗？此操作不可撤销。';
  }

  @override
  String get deleteRecordOnly => '仅删除记录';

  @override
  String get deleteRecordAndFile => '删除记录和文件';

  @override
  String get addSource => '添加源';

  @override
  String get importSource => '导入源';

  @override
  String get exportSource => '导出源';

  @override
  String get aboutDescription => 'NexHub —— 四合一媒体聚合客户端（动漫 / 漫画 / 小说 / 影视）。';

  @override
  String get videoSourceLine => '线路';

  @override
  String get defaultLine => '默认线路';

  @override
  String get errorWebView => '需要网页验证';

  @override
  String get verifying => '验证中…';

  @override
  String get mirrorTest => '测速';

  @override
  String get sourceHealthy => '正常';

  @override
  String get resolveTimeout => '解析超时';

  @override
  String resolveFailed(Object message) {
    return '解析失败：$message';
  }

  @override
  String get categories => '分类';

  @override
  String chapterN(Object n) {
    return '第 $n 话';
  }

  @override
  String pageIndicator(Object cur, Object total) {
    return '第 $cur / $total 页';
  }

  @override
  String readerDoublePageIndicator(Object first, Object last, Object total) {
    return '$first-$last / $total';
  }

  @override
  String get prevChapter => '上一章';

  @override
  String get nextChapter => '下一章';

  @override
  String get readerLastChapterReached => '已经是最后一章了';

  @override
  String get readerFirstChapterReached => '已经是第一章了';

  @override
  String readerNextChapterSkipped(Object title) {
    return '下一章：$title';
  }

  @override
  String get readerNextChapterSkippedHint => '点击立即跳转';

  @override
  String get readerSettings => '阅读设置';

  @override
  String get readerMode => '阅读模式';

  @override
  String get readerBackground => '背景';

  @override
  String get readerOrientation => '屏幕方向';

  @override
  String get readerTapZone => '点击区域';

  @override
  String get readerZoom => '双击缩放';

  @override
  String get noImages => '本章暂无可读图片';

  @override
  String get preloading => '预加载下一章…';

  @override
  String get readerModeSingleLTR => '单页（左→右）';

  @override
  String get readerModeSingleRTL => '单页（右→左）';

  @override
  String get readerModeSingleVertical => '单页（竖向）';

  @override
  String get readerModeWebtoon => '条漫';

  @override
  String get readerModeWebtoonWithGap => '条漫（带间距）';

  @override
  String get readerOrientationDefault => '默认';

  @override
  String get readerOrientationSystem => '跟随系统';

  @override
  String get readerOrientationPortrait => '竖屏';

  @override
  String get readerOrientationLandscape => '横屏';

  @override
  String get readerOrientationLockPortrait => '锁定竖屏';

  @override
  String get readerOrientationLockLandscape => '锁定横屏';

  @override
  String get readerOrientationReversePortrait => '反向竖屏';

  @override
  String get readerBgBlack => '黑色';

  @override
  String get readerBgGray => '灰色';

  @override
  String get readerBgDarkGray => '深灰';

  @override
  String get readerBgEyeCare => '护眼绿';

  @override
  String get readerBgParchment => '羊皮纸';

  @override
  String get readerBgWarmLinen => '暖黄';

  @override
  String get readerBgLightBrown => '浅褐';

  @override
  String get readerBgBeanGreen => '豆沙绿';

  @override
  String get readerBgMint => '淡青';

  @override
  String get readerBgApricot => '暖杏';

  @override
  String get readerBgGrayBlue => '浅灰蓝';

  @override
  String get readerBgEInk => '墨水屏纸感';

  @override
  String get readerBgWhite => '白色';

  @override
  String get readerBgAuto => '自动';

  @override
  String get readerTapLeftRight => '左右';

  @override
  String get readerTapLShape => 'L 形';

  @override
  String get readerTapKindle => 'Kindle';

  @override
  String get readerTapBothSides => '两侧';

  @override
  String get readerTapOff => '关闭';

  @override
  String get readerTapInvert => '点击翻转';

  @override
  String get readerTapInvertNone => '不反转';

  @override
  String get readerTapInvertLeftRight => '左右反转';

  @override
  String get readerTapInvertUpDown => '上下反转';

  @override
  String get readerTapInvertAll => '全反转';

  @override
  String get readerSideMargin => '左右留白';

  @override
  String get readerFlashEnabled => '翻页闪光';

  @override
  String get readerFlashTime => '闪光时长';

  @override
  String get readerFlashInterval => '闪光延迟';

  @override
  String get readerFlashColor => '闪光颜色';

  @override
  String get readerFlashBlack => '黑';

  @override
  String get readerFlashWhite => '白';

  @override
  String get readerFlashBlackWhite => '黑→白';

  @override
  String get readerTapPreviewHint => '点击区域预览（实时）';

  @override
  String get tapPreviewPrev => '上一页';

  @override
  String get tapPreviewNext => '下一页';

  @override
  String get tapPreviewToggle => '切换';

  @override
  String get filterInverted => '反色';

  @override
  String get favorite => '收藏';

  @override
  String get moreActions => '更多操作';

  @override
  String get demoNormal => '默认视图';

  @override
  String get demoEmpty => '显示空状态';

  @override
  String get demoError => '显示错误状态';

  @override
  String get noContent => '本章暂无内容';

  @override
  String get novelFontSize => '字号';

  @override
  String get novelLineHeight => '行距';

  @override
  String get novelParagraphSpacing => '段距';

  @override
  String get novelMargin => '边距';

  @override
  String get novelPageAnimation => '翻页动画';

  @override
  String get novelTextShadow => '文字阴影';

  @override
  String get novelAnimNone => '无动画';

  @override
  String get novelAnimSlide => '滑动';

  @override
  String get novelAnimScroll => '滚动';

  @override
  String get novelAnimFade => '淡入';

  @override
  String get novelAnimCover => '覆盖';

  @override
  String get novelAnimSimulation => '仿真';

  @override
  String get novelHfNone => '无';

  @override
  String get novelHfTime => '时间';

  @override
  String get novelHfBattery => '电量';

  @override
  String get novelHfChapterTitle => '章节标题';

  @override
  String get novelHfBookName => '书名';

  @override
  String get novelHfPageNumber => '页码';

  @override
  String get novelHfProgressPercent => '进度百分比';

  @override
  String novelChapterN(Object n) {
    return '第 $n 章';
  }

  @override
  String get download => '下载';

  @override
  String get downloads => '下载';

  @override
  String get downloadListTitle => '下载列表';

  @override
  String get downloadedContent => '已下载';

  @override
  String get downloadSettings => '下载设置';

  @override
  String get emptyDownloadList => '暂无下载任务';

  @override
  String get emptyDownloaded => '暂无已下载内容';

  @override
  String get clearAll => '清除全部';

  @override
  String get clearAllConfirm =>
      '将清除所有筛选下全部下载中/已暂停/失败的任务记录，已下载完成的内容将保留、可直接阅读。确定继续吗？';

  @override
  String get clearHistory => '清除历史';

  @override
  String get recentSearches => '最近搜索';

  @override
  String get clearHistoryConfirm => '确定清除本模块的全部浏览历史吗？阅读进度将保留，重新进入该作品后自动恢复。';

  @override
  String get historyCleared => '历史已清除';

  @override
  String get batchPause => '批量暂停';

  @override
  String get batchResume => '批量继续';

  @override
  String get deleteSelected => '批量删除';

  @override
  String deleteSelectedConfirm(Object count) {
    return '确定删除选中的 $count 项下载记录吗？';
  }

  @override
  String get pause => '暂停';

  @override
  String get selectAll => '全选';

  @override
  String get select => '选择';

  @override
  String get deleteConfirm => '确定删除选中的下载吗？';

  @override
  String get statusPending => '等待中';

  @override
  String get statusDownloading => '下载中';

  @override
  String get statusPaused => '已暂停';

  @override
  String get statusFailed => '失败';

  @override
  String get statusWaitingForWifi => '等待 WiFi';

  @override
  String get statusCancelled => '已取消';

  @override
  String get downloadWifiOnly => '仅 WiFi 下载';

  @override
  String get downloadWifiOnlyHint => '仅在连接到 WiFi 时启动下载';

  @override
  String get comicDownloadFormat => '漫画下载格式';

  @override
  String get novelDownloadFormat => '小说下载格式';

  @override
  String get formatCbz => 'CBZ 压缩包';

  @override
  String get formatCbzSubtitle => '所有图片打包为单个 .cbz 文件';

  @override
  String get formatFolder => '散图文件夹';

  @override
  String get formatFolderSubtitle => '每章一个文件夹，散图存放';

  @override
  String get formatEpub => 'EPUB 电子书';

  @override
  String get formatEpubSubtitle => '标准电子书格式，支持目录';

  @override
  String get formatTxt => 'TXT 纯文本';

  @override
  String get formatTxtSubtitle => '纯文本格式，兼容性最广';

  @override
  String get emptyHistory => '暂无浏览记录';

  @override
  String get emptyFavorites => '暂无收藏';

  @override
  String get emptyRssFeeds => '暂无订阅源';

  @override
  String get emptyRssItems => '暂无文章';

  @override
  String get addRssFeed => '添加订阅源';

  @override
  String get rssFeedTitle => '标题';

  @override
  String get rssFeedTitleHint => '自定义标题（可选）';

  @override
  String get opening => '正在打开';

  @override
  String get verificationRequired => '需要验证';

  @override
  String get verificationHint => '此内容需要完成网页验证后才能访问。请点击下方按钮在浏览器中完成验证，然后返回重试。';

  @override
  String get openInBrowser => '外部打开';

  @override
  String get verificationDone => '已完成验证，重试';

  @override
  String get webViewNotAvailable => '当前平台不支持内嵌浏览器，请使用外部浏览器完成验证。';

  @override
  String get extractFromPage => '用此页抽取';

  @override
  String get extractHint => '在页面中完成验证后，点击「用此页抽取」自动提取内容地址；失败时回退到浏览器手动验证。';

  @override
  String get extracting => '抽取中…';

  @override
  String get extractSuccess => '抽取成功';

  @override
  String get extractNoResult => '未抽取到内容，请重试或手动验证';

  @override
  String get extractFailed => '抽取失败';

  @override
  String get captureFromPage => '抓取本页渲染内容';

  @override
  String get captureHint => '页面渲染完成后，点击「抓取本页渲染内容」即可用既有选择器解析列表/详情，无需手动编写脚本。';

  @override
  String get capturing => '抓取中…';

  @override
  String get snifferTitle => '视频嗅探';

  @override
  String get snifferAddressHint => '打开视频页面以嗅探';

  @override
  String get snifferHint => '打开视频页面后，动态加载的 m3u8/mp4 串流会自动在下方列出。';

  @override
  String get snifferNoResult => '尚未嗅探到视频串流';

  @override
  String get snifferCopy => '复制';

  @override
  String get snifferPlay => '播放';

  @override
  String get snifferInPagePlaying => '正在页内播放';

  @override
  String get snifferInPageHint => '该串流为 blob/MSE 格式，无法在外部播放器打开，已在当前页面内播放。';

  @override
  String get snifferCopyPageLink => '复制页面链接';

  @override
  String get snifferClear => '清空列表';

  @override
  String get snifferGo => '前往';

  @override
  String get snifferDeep => '深度嗅探';

  @override
  String get snifferSave => '保存';

  @override
  String get snifferFilterAll => '全部';

  @override
  String get snifferFilterVideo => '视频';

  @override
  String get snifferFilterAudio => '音频';

  @override
  String get snifferFilterOther => '其他';

  @override
  String get snifferSizeUnknown => '大小未知';

  @override
  String snifferResultCount(int count) {
    return '$count 条结果';
  }

  @override
  String get snifferPanelHandle => '嗅探结果面板，上下拖动调整高度，点按折叠或展开';

  @override
  String get snifferResolveTitle => '嗅探解析';

  @override
  String get snifferResolving => '正在嗅探视频地址…';

  @override
  String get snifferResolveTimeout => '未捕获到直链，可继续等待或取消';

  @override
  String get failed => '失败';

  @override
  String get share => '分享';

  @override
  String get shareCopied => '已复制到剪贴板';

  @override
  String get browserTitle => '浏览器';

  @override
  String get browserAddressHint => '输入网址或搜索';

  @override
  String get browserBack => '后退';

  @override
  String get browserForward => '前进';

  @override
  String get browserRefresh => '刷新';

  @override
  String get browserCopyLink => '复制链接';

  @override
  String get browserShare => '分享';

  @override
  String get browserLinkCopied => '链接已复制';

  @override
  String get browserUseAsVerification => '用此页完成验证';

  @override
  String get browserOpenSniffer => '视频嗅探模式';

  @override
  String get browserUseAsVerificationDone => '已用此页 Cookie 完成验证';

  @override
  String get browserNotAvailable => '当前平台不支持内置浏览器，请使用外部浏览器。';

  @override
  String get openInternalBrowser => '打开内置浏览器';

  @override
  String get downloadStarted => '下载已开始';

  @override
  String get downloadEpisodes => '选集下载';

  @override
  String get episodeRange => '选集范围';

  @override
  String get addToDownload => '加入下载';

  @override
  String get deselectAll => '全不选';

  @override
  String selectedCount(Object selected, Object total) {
    return '已选 $selected/$total';
  }

  @override
  String get rangeStart => '起始集';

  @override
  String get rangeEnd => '结束集';

  @override
  String get applyRange => '应用';

  @override
  String get alreadyDownloaded => '已下载';

  @override
  String get favoriteAdded => '已收藏';

  @override
  String get favoriteRemoved => '已取消收藏';

  @override
  String get aboutApp => '关于应用';

  @override
  String get appVersion => '版本';

  @override
  String get privacySettings => '隐私设置';

  @override
  String get stealthSettings => '隐身设置';

  @override
  String get browseLocalTitle => '本地文件';

  @override
  String get browseLocalEmpty => '未找到可读的本地文件';

  @override
  String get browseLocalScan => '扫描文件';

  @override
  String get browseLocalFileTypeAll => '全部';

  @override
  String get browseLocalFileTypeNovel => '小说';

  @override
  String get browseLocalFileTypeComic => '漫画';

  @override
  String get browseLocalFileTypeVideo => '视频';

  @override
  String get browseLocalSelectFolder => '选择文件夹';

  @override
  String get browseNetworkTitle => '网络文件';

  @override
  String get browseNetworkUrlHint => '输入 HTTP 文件服务器地址';

  @override
  String get browseNetworkConnect => '连接';

  @override
  String get browseNetworkEmpty => '未找到文件';

  @override
  String get browseNetworkHistory => '历史地址';

  @override
  String get browseNetworkParentDir => '上级目录';

  @override
  String get browseNetworkFileSize => '大小';

  @override
  String get scrapeModeGeneral => '通用';

  @override
  String get scrapeModeNovel => '小说';

  @override
  String get scrapeModeComic => '漫画';

  @override
  String get scrapeModeVideo => '视频';

  @override
  String get scrapeModeArticle => '文章';

  @override
  String get scrapeUrlHint => '输入要爬取的网页 URL';

  @override
  String get scrapeStart => '开始爬取';

  @override
  String get scrapeResultTitle => '页面标题';

  @override
  String get scrapeResultLinks => '所有链接';

  @override
  String get scrapeResultText => '正文内容';

  @override
  String get scrapeResultImages => '图片列表';

  @override
  String get scrapeResultVideos => '视频列表';

  @override
  String get scrapeOpenInReader => '在阅读器中打开';

  @override
  String get scrapeOpenInPlayer => '在播放器中打开';

  @override
  String get scrapeNoResults => '未提取到内容';

  @override
  String get scrapeSelectorHint => 'CSS 选择器（可选）';

  @override
  String get scrapeAdvanced => '高级选项';

  @override
  String get rssFeedUrl => '订阅地址';

  @override
  String get rssFeedUrlHint => 'https://example.com/feed.xml';

  @override
  String get rssFeedDescription => '描述';

  @override
  String get rssFeedModule => '绑定模块';

  @override
  String get rssFeedModuleNone => '全局（浏览页）';

  @override
  String get rssFeedTestConnection => '测试连接';

  @override
  String get rssFeedTesting => '测试中…';

  @override
  String get rssFeedTestSuccess => '连接成功';

  @override
  String get rssFeedTestFailed => '连接失败';

  @override
  String get rssFeedPreview => '预览';

  @override
  String get rssFeedSaved => '订阅源已保存';

  @override
  String get articleDetailAuthor => '作者';

  @override
  String get articleDetailPublishedAt => '发布时间';

  @override
  String get articleDetailReadFull => '阅读全文';

  @override
  String get articleDetailSource => '来源';

  @override
  String get articleDetailEmpty => '文章无内容';

  @override
  String get articleReadingSettings => '阅读设置';

  @override
  String get articleFontSize => '字号';

  @override
  String get articleLineHeight => '行距';

  @override
  String get articleNightMode => '夜间模式';

  @override
  String get articleContentWidth => '内容宽度';

  @override
  String get articleJustify => '两端对齐';

  @override
  String get articleParagraphSpacing => '段间距';

  @override
  String get articleWidthNarrow => '窄';

  @override
  String get articleWidthNormal => '标准';

  @override
  String get articleWidthWide => '宽';

  @override
  String get articleFontFamily => '字体族';

  @override
  String get fontSystem => '系统';

  @override
  String get fontSerif => '衬线';

  @override
  String get fontMono => '等宽';

  @override
  String get articleLetterSpacing => '字间距';

  @override
  String get mirrorListTitle => '镜像列表';

  @override
  String get mirrorTesting => '测速中…';

  @override
  String mirrorTestResultMs(Object ms) {
    return '$ms ms';
  }

  @override
  String get mirrorTestFailed => '失败';

  @override
  String get mirrorCurrent => '当前';

  @override
  String get mirrorSwitched => '镜像已切换';

  @override
  String get mirrorStealthLocked => '隐身模式已强制开启';

  @override
  String get mirrorNoMirrors => '此源无镜像配置';

  @override
  String get collectApiImportTitle => '采集 API 导入';

  @override
  String get collectApiUrlHint => 'https://example.com/api.php/provide/vod/';

  @override
  String get collectApiDetect => '识别';

  @override
  String get collectApiDetecting => '识别中…';

  @override
  String get collectApiDetectSuccess => '识别成功';

  @override
  String get collectApiDetectFailed => '识别失败';

  @override
  String get collectApiSiteName => '站点名称';

  @override
  String get collectApiCategories => '分类';

  @override
  String get collectApiPreview => '内容预览';

  @override
  String get collectApiSourceName => '源名称';

  @override
  String get collectApiSourceId => '源 ID';

  @override
  String get collectApiSave => '保存源';

  @override
  String get collectApiSaved => '源已保存';

  @override
  String get collectApiInvalidUrl => '无效的 URL';

  @override
  String get sourceImportFromUrl => '从 URL 导入';

  @override
  String get sourceImportFromFile => '从文件导入';

  @override
  String get sourceImportFromJson => '手动输入 JSON';

  @override
  String get sourceImportUrlHint => '源 JSON 的 URL';

  @override
  String get sourceImportFilePicker => '选择 JSON 文件';

  @override
  String get sourceImportJsonHint => '粘贴源 JSON 配置';

  @override
  String get sourceImportValidate => '校验';

  @override
  String get sourceImportValid => '校验通过';

  @override
  String get sourceImportInvalid => '校验失败';

  @override
  String get sourceImportErrors => '错误信息';

  @override
  String get sourceImportCollectApiDetected => '检测到 MacCMS 采集 API';

  @override
  String get sourceImportCollectApiRedirect => '使用采集 API 导入';

  @override
  String get sourceImportSaved => '源已导入';

  @override
  String get contentImportTitle => '导入内容';

  @override
  String get contentImportSelectFile => '选择文件';

  @override
  String get contentImportSupportedFormats => '支持的格式';

  @override
  String get contentImportHistory => '导入历史';

  @override
  String get contentImportEmpty => '暂无导入记录';

  @override
  String get contentImportOpened => '已打开';

  @override
  String comicDirImported(Object name) {
    return '已导入漫画：$name';
  }

  @override
  String novelDirImported(String name, int count) {
    return '已导入小说：$name（共 $count 章）';
  }

  @override
  String get contentImportNovelFormats => '.txt, .epub';

  @override
  String get contentImportComicFormats => '.cbz, 图片文件夹';

  @override
  String get contentImportMediaFormats => '.mp4, .mkv, .avi';

  @override
  String get downloadedGroupChapters => '章节列表';

  @override
  String get downloadedGroupFormat => '格式';

  @override
  String get downloadedGroupOpen => '打开';

  @override
  String get downloadedGroupFileMissing => '文件不存在';

  @override
  String get downloadedGroupDeleteConfirm => '确定删除此下载项吗？';

  @override
  String downloadBatches(Object count) {
    return '$count 个批次';
  }

  @override
  String downloadBatchLabel(Object index) {
    return '第 $index 批';
  }

  @override
  String get browsePageTitle => '浏览';

  @override
  String get rssSubscribeTitle => 'RSS 订阅';

  @override
  String get emptyRssSubscribe => '还没有 RSS 订阅';

  @override
  String get addSubscription => '添加订阅';

  @override
  String get subscribeAddressLabel => '订阅地址';

  @override
  String get rsshubRoutesTitle => 'RSSHub 路由';

  @override
  String get rsshubRouteRecommend => 'RSSHub 路由推荐';

  @override
  String get rsshubRouteHint => '点击路由自动填入 RSSHub 实例地址';

  @override
  String get novelLibraryName => '小说库';

  @override
  String get mediaLibraryName => '媒体库';

  @override
  String get comicLibraryName => '漫画库';

  @override
  String get emptySubscribe => '暂无订阅源';

  @override
  String get sourceListTab => '源列表';

  @override
  String get networkImportTab => '网络导入';

  @override
  String get localImportTab => '本地导入';

  @override
  String get sourceListEmpty => '暂无源';

  @override
  String get networkImportHint => '粘贴源地址（.json/.txt）';

  @override
  String get networkImportPasteHint => '粘贴地址并点击获取';

  @override
  String get localImportTitle => '从本地文件导入';

  @override
  String get localImportFormats => '支持 .json、.txt、.xml';

  @override
  String get selectFile => '选择文件';

  @override
  String get selectFolder => '选择文件夹';

  @override
  String get noLocalSource => '未找到源文件';

  @override
  String get localImportHint => '选择单个文件或文件夹，扫描其中的源文件（.json/.txt/.xml）';

  @override
  String importPreviewTitle(Object count) {
    return '找到 $count 个文件';
  }

  @override
  String get confirmImport => '确认导入';

  @override
  String importSelectedCount(Object count) {
    return '已选 $count 项';
  }

  @override
  String importTypeOnly(Object type) {
    return '仅导入【$type】类型源';
  }

  @override
  String importTypeFiltered(int count) {
    return '已跳过 $count 个其他类型源';
  }

  @override
  String importNoMatchingType(Object type, int count) {
    return '所选内容中无【$type】类型源（已跳过 $count 个其他类型）';
  }

  @override
  String sourceImportResult(int success, int total) {
    return '成功导入 $success/$total 个源';
  }

  @override
  String batchImportHint(int count) {
    return '已识别 $count 个源，勾选后批量导入（含小说 / 媒体 / 漫画）';
  }

  @override
  String get sourceUnrecognized => '无法识别为有效源（小说 / 媒体 / 漫画）';

  @override
  String importDistributedHint(int count) {
    return '将按类型自动归入对应模块（含 $count 个其他模块源）';
  }

  @override
  String get settingsGroupDownload => '下载管理';

  @override
  String get settingsGroupTools => '工具';

  @override
  String get settingsGroupPlugins => '插件';

  @override
  String get settingsGroupData => '数据';

  @override
  String get settingsGroupPlayback => '播放与阅读';

  @override
  String get settingsGroupContentSources => '内容源';

  @override
  String get settingsGroupNetwork => '网络';

  @override
  String get settingsGroupSubscriptions => '订阅与通知';

  @override
  String get settingsGroupDownloadsData => '下载与数据';

  @override
  String get webScrapeSetting => '网页爬取';

  @override
  String get webScrapeSettingSameAsBrowse => '与浏览页网页爬取一样';

  @override
  String get subscriptionManagement => '订阅管理';

  @override
  String get subscriptionManagementDesc => '分类型统一管理，可以设置 RSS 订阅';

  @override
  String get rsshubInstance => 'RSSHub Instance';

  @override
  String get rsshubInstanceDesc => '自部署 RSSHub 地址';

  @override
  String get rsshubSettingsTitle => 'RSSHub 设置';

  @override
  String get rsshubSettingsDesc => '选择预置实例或自建实例地址';

  @override
  String get rssNotifications => 'RSS 更新通知';

  @override
  String get rssNotificationsDesc => '检测订阅源新条目';

  @override
  String get rssNotificationsTitle => 'RSS 更新通知';

  @override
  String get rssNotificationEnabled => '启用更新检测';

  @override
  String get rssNotificationEnabledSubtitle => '前台定期轮询已订阅源';

  @override
  String get rssUpdateInterval => '检测间隔';

  @override
  String get interval15m => '15 分钟';

  @override
  String get interval30m => '30 分钟';

  @override
  String get interval1h => '1 小时';

  @override
  String get interval2h => '2 小时';

  @override
  String get interval4h => '4 小时';

  @override
  String get rssCheckNow => '立即检测';

  @override
  String rssTotalNewCount(int count) {
    return '当前未读：$count';
  }

  @override
  String get rssCheckDone => '检测完成';

  @override
  String get rssNotificationHint => '仅应用在前台时轮询；检测到新条目会在订阅源卡片显示未读数。';

  @override
  String get currentInstance => '当前实例';

  @override
  String get presetInstances => '预置实例';

  @override
  String get presetInstanceOfficial => '官方';

  @override
  String get customInstance => '自定义实例';

  @override
  String get restoreDefault => '恢复默认';

  @override
  String get rsshubTestAll => '一键测速';

  @override
  String get rsshubTestingAll => '正在测速全部实例…';

  @override
  String rsshubTestAllDone(Object count) {
    return '已测速 $count 个实例';
  }

  @override
  String get saveCustomInstance => '保存自定义';

  @override
  String get instanceTestFail => '测试失败';

  @override
  String get instanceTestSuccess => '连接成功';

  @override
  String get rsshubTroubleshoot => '故障排除';

  @override
  String get rsshubTroubleshootHint =>
      '如果遇到问题：\n• 确保地址可访问且无防火墙限制\n• 尝试更换预置实例\n• 自建 RSSHub 用户请检查服务是否正常运行';

  @override
  String get danmakuSettings => '弹弹play 弹幕';

  @override
  String get danmakuSettingsDesc => '弹幕配置';

  @override
  String get danmakuConfigTitle => '弹弹play 弹幕配置';

  @override
  String get unconfigured => '未配置';

  @override
  String get configured => '已配置';

  @override
  String get appIdLabel => 'AppId';

  @override
  String get appIdHint => '请输入 AppId';

  @override
  String get appSecretLabel => 'AppSecret';

  @override
  String get appSecretHint => '请输入 AppSecret';

  @override
  String get saveDanmaku => '保存';

  @override
  String get danmakuDesc =>
      '在 https://daplay.danmaku.net 获取您的配置 AppId 和 AppSecret。配置后可在播放器中看到弹弹play弹幕。';

  @override
  String get pluginManagement => '管理插件';

  @override
  String get dataImportExport => '导入/导出';

  @override
  String get dataImportExportTitle => '导入/导出';

  @override
  String get importData => '导入数据';

  @override
  String get importDataDesc => '导入订阅、插件和进度';

  @override
  String get exportData => '导出数据';

  @override
  String get exportDataDesc => '导出所有数据到文件';

  @override
  String get exportSubscription => '导出订阅';

  @override
  String get exportSubscriptionDesc => '仅导出 RSS 订阅';

  @override
  String get exportPlugins => '导出插件';

  @override
  String get exportPluginsDesc => '导出插件配置';

  @override
  String get selectExportFolder => '选择导出文件夹';

  @override
  String get exportFolderCustom => '可以自定义导出文件夹';

  @override
  String get downloadListTab => '下载列表';

  @override
  String get downloadedListTab => '已下载内容';

  @override
  String get maxConcurrentDownloads => '最大同时下载数';

  @override
  String get maxConcurrentDownloadsDesc => '同时进行的下载数量';

  @override
  String get downloadPath => '下载路径';

  @override
  String get folderImportOhosUnsupported => '鸿蒙版暂不支持文件夹导入，请改用「选择文件」导入';

  @override
  String get folderImportCopyProgress => '正在导入目录';

  @override
  String get folderImportCopyProgressHint => '正在复制到应用空间，请勿关闭应用';

  @override
  String get folderImportCopyFailed => '目录复制失败，请重试';

  @override
  String get downloadPathSet => '下载路径已更新';

  @override
  String get contentImportActions => '操作';

  @override
  String get downloaderType => '下载器';

  @override
  String get downloaderInternal => '内置下载器';

  @override
  String get downloaderExternal => '外置下载器';

  @override
  String get threadCount => '线程数';

  @override
  String get threadCountDesc => '下载线程数量';

  @override
  String get comicFormatSetting => '漫画格式';

  @override
  String get novelFormatSetting => '小说格式';

  @override
  String get downloadTabsAll => '全部';

  @override
  String get downloadTabsNovel => '小说';

  @override
  String get downloadTabsMedia => '媒体';

  @override
  String get downloadTabsComic => '漫画';

  @override
  String get downloadedTabsAll => '全部';

  @override
  String get downloadedTabsNovel => '小说';

  @override
  String get downloadedTabsMedia => '媒体';

  @override
  String get downloadedTabsComic => '漫画';

  @override
  String get downloadedTabsArchived => '已删除下载';

  @override
  String get noDownloads => '暂无下载';

  @override
  String get downloadPause => '暂停';

  @override
  String get downloadResume => '继续';

  @override
  String get sourceCategoryNovel => '小说';

  @override
  String get sourceCategoryMedia => '媒体';

  @override
  String get sourceCategoryComic => '漫画';

  @override
  String sourceCategoryEmpty(Object category) {
    return '暂无$category源';
  }

  @override
  String rsshubLatencyMs(Object ms) {
    return '${ms}ms';
  }

  @override
  String get rsshubLatencyFailed => '失败';

  @override
  String get downloaderSelectTitle => '下载器选择';

  @override
  String get comicFormatSelectTitle => '漫画格式';

  @override
  String get comicFormatJpg => '单页 JPG';

  @override
  String get comicFormatPng => '单页 PNG';

  @override
  String get comicFormatCbz => 'CBZ 打包';

  @override
  String get novelFormatSelectTitle => '小说格式';

  @override
  String get novelFormatTxt => 'TXT';

  @override
  String get novelFormatEpub => 'EPUB';

  @override
  String get rsshubRouteBilibiliBangumi => 'B站番剧';

  @override
  String get rsshubRouteBilibiliBangumiPath =>
      '/bilibili/bangumi/media/:mediaid';

  @override
  String get rsshubRouteBilibiliMangaUpdate => 'B站漫画更新';

  @override
  String get rsshubRouteBilibiliMangaUpdatePath =>
      '/bilibili/manga/update/:comicid';

  @override
  String get rsshubRouteBilibiliUserVideo => 'B站UP主投稿';

  @override
  String get rsshubRouteBilibiliUserVideoPath => '/bilibili/user/video/:uid';

  @override
  String get rsshubRouteBilibiliRanking => 'B站排行榜';

  @override
  String get rsshubRouteBilibiliRankingPath =>
      '/bilibili/partion/ranking/:tid/:days?';

  @override
  String get rsshubRouteYoutubeChannel => 'YouTube频道';

  @override
  String get rsshubRouteYoutubeChannelPath => '/youtube/channel/:id';

  @override
  String get rsshubRouteTwitterUser => 'Twitter 用户';

  @override
  String get rsshubRouteLinovelib => '轻小说文库';

  @override
  String get rsshubRouteSfacg => 'SF轻小说';

  @override
  String get importMediaTitle => '导入媒体';

  @override
  String get importMediaFormatsHint => '支持 mp4、mkv、avi、mov 等常见视频格式';

  @override
  String get importMediaPickFile => '选择视频文件';

  @override
  String get importMediaPickFolder => '选择视频目录';

  @override
  String get importNovelTitle => '导入小说';

  @override
  String get importNovelFormatsHint =>
      '支持 .txt / .epub 文件，以及包含它们的压缩包（.zip / .cbz / .rar / .7z）';

  @override
  String get novelArchiveImported => '个压缩包已解包导入';

  @override
  String get importNovelPickFile => '选择文件';

  @override
  String get importNovelPickFolder => '选择目录';

  @override
  String get importComicTitle => '导入漫画';

  @override
  String get importComicFormatsHint => '支持 cbz、cbr、cbt 等常见漫画压缩格式';

  @override
  String get importComicPickFile => '选择漫画文件';

  @override
  String get importComicPickFolder => '选择漫画目录';

  @override
  String get novelBrightness => '亮度';

  @override
  String get playerLock => '锁定';

  @override
  String get playerUnlock => '解锁';

  @override
  String get playerAutoPlayNext => '自动连播';

  @override
  String get playerAddToQueue => '加入播放队列';

  @override
  String get playerPlayNext => '下一部播放';

  @override
  String get playerQueue => '播放队列';

  @override
  String get playerQueueEmpty => '队列为空';

  @override
  String get playerQueueAdded => '已加入播放队列';

  @override
  String get playerQueuePlayNextAdded => '已设为下一部播放';

  @override
  String get playerQueueCleared => '已清空队列';

  @override
  String get playerQueueRemoved => '已从队列移除';

  @override
  String get playerQueueNoEpisodes => '该作品无可用剧集';

  @override
  String get playerQueueLoadFailed => '加载下一部失败，已停止连播';

  @override
  String playerQueueLoading(String title) {
    return '正在加载：$title';
  }

  @override
  String playerQueueResumeLast(String title) {
    return '继续播放：$title';
  }

  @override
  String playerAutoNextWork(String title) {
    return '即将播放：$title';
  }

  @override
  String get playerQueueMoveUp => '上移';

  @override
  String get playerQueueMoveDown => '下移';

  @override
  String get playerQueueRemove => '移除';

  @override
  String get playerDecodeMode => '解码模式';

  @override
  String get playerDecodeAuto => '自动';

  @override
  String get playerDecodeSw => '软件解码';

  @override
  String get playerDecodeHw => '硬件解码';

  @override
  String get playerDecodeHwPlus => '硬件解码+';

  @override
  String get playerDecodeHwPlusHint => '花屏时推荐';

  @override
  String get playerUpscaleShader => '超分辨率';

  @override
  String get playerUpscaleShaderOff => '关闭';

  @override
  String get playerUpscaleShaderPerformance => '效率';

  @override
  String get playerUpscaleShaderQuality => '质量';

  @override
  String get playerUpscaleShaderHint => '低清晰度源实时修复放大；卡顿时选效率或关闭';

  @override
  String playerDecodeFallback(String mode) {
    return '检测到解码异常，已切换为$mode';
  }

  @override
  String get playerStats => '播放统计';

  @override
  String get playerStatsDecoder => '解码器';

  @override
  String get playerStatsHardware => '硬件解码';

  @override
  String get playerStatsSoftware => '软件解码';

  @override
  String get playerStatsVideoCodec => '视频编码';

  @override
  String get playerStatsPixelFormat => '像素格式';

  @override
  String get playerStatsResolution => '分辨率';

  @override
  String get playerStatsDroppedFrames => '掉帧（渲染 / 解码）';

  @override
  String get playerStatsBitrate => '视频码率';

  @override
  String get playerStatsBuffering => '缓冲进度';

  @override
  String get playerStatsUnavailable => '当前无法获取播放统计';

  @override
  String get playerAudioChannel => '音频通道';

  @override
  String get playerAudioStereo => '立体声';

  @override
  String get playerAudioMono => '单声道';

  @override
  String get playerAudioAutoProtect => '自动保护';

  @override
  String get playerAudioReverseStereo => '翻转立体声';

  @override
  String get playerAspectRatio => '画面比例';

  @override
  String get playerAspectDefault => '默认';

  @override
  String get playerAspectFill => '填充';

  @override
  String get playerAspect43 => '4:3';

  @override
  String get playerAspect169 => '16:9';

  @override
  String get playerPlaybackSpeed => '播放速度';

  @override
  String get playerLongPressSpeed => '长按播放速度';

  @override
  String get playerSubtitle => '字幕';

  @override
  String get playerSubtitleSettings => '字幕设置';

  @override
  String get playerSubtitleDelay => '字幕延迟(ms)';

  @override
  String get playerFontSize => '字体大小';

  @override
  String get playerSubtitleOutline => '字幕边框';

  @override
  String get playerTimer => '定时关闭';

  @override
  String get playerPlayInfo => '播放信息';

  @override
  String get playerExternalPlay => '外部播放';

  @override
  String get playerVideoExpired => '视频链接已失效，请重试';

  @override
  String get playerOhosUnsupported => '鸿蒙版暂不支持视频播放，该功能正在适配中';

  @override
  String get playerEpisodeSwitchFailed => '切换该剧集失败，请重试';

  @override
  String get playerStallDetected => '播放卡顿，正在重连…';

  @override
  String get playerRetry => '重试';

  @override
  String get playerNextEpisode => '下一集';

  @override
  String get playerPreviousEpisode => '上一集';

  @override
  String get playerNextFrame => '下一帧';

  @override
  String get playerPreviousFrame => '上一帧';

  @override
  String get playerShare => '分享';

  @override
  String get danmakuFilterKeywords => '关键词过滤';

  @override
  String get danmakuTimeOffset => '时间偏移(秒)';

  @override
  String get danmakuArea => '显示区域';

  @override
  String get danmakuDuration => '持续时间(秒)';

  @override
  String get danmakuLineHeight => '行高';

  @override
  String get danmakuHideTop => '隐藏顶部';

  @override
  String get danmakuHideBottom => '隐藏底部';

  @override
  String get danmakuHideScroll => '隐藏滚动';

  @override
  String get danmakuFollowSpeed => '跟随倍速';

  @override
  String get danmakuAddKeyword => '添加关键词';

  @override
  String get danmakuKeywordHint => '输入关键词或正则表达式';

  @override
  String get danmakuSearch => '搜索弹幕';

  @override
  String get danmakuSearchHint => '输入动漫名称搜索';

  @override
  String get danmakuMatchEpisode => '匹配剧集';

  @override
  String get danmakuNoResult => '无搜索结果';

  @override
  String get danmakuLoadFailed => '弹幕加载失败';

  @override
  String get danmakuLoaded => '弹幕已加载';

  @override
  String get danmakuCacheHit => '弹幕已缓存';

  @override
  String get danmakuSourceTitle => '弹幕源';

  @override
  String get danmakuSourceHint => '选择弹幕来源';

  @override
  String get danmakuSourceDandanplay => '弹弹play';

  @override
  String get danmakuSourceBilibili => 'bilibili';

  @override
  String get danmakuSourceOff => '关闭';

  @override
  String get danmakuSourceDandanplayDesc => '自动按番剧名匹配';

  @override
  String get danmakuSourceBilibiliDesc => '按视频 av/BV 号匹配';

  @override
  String get danmakuSourceOffDesc => '不加载弹幕';

  @override
  String get danmakuDisplaySettingsTitle => '弹幕显示设置';

  @override
  String get danmakuDisplaySettingsDesc => '字体大小、不透明度、时间偏移等';

  @override
  String get danmakuFontSize => '字体大小';

  @override
  String get danmakuOpacity => '不透明度';

  @override
  String get playerSettingsTitle => '播放器设置';

  @override
  String get playerSettingsDesc => '解码模式、画面比例、播放速度等';

  @override
  String get playerDefaultDecodeMode => '默认解码模式';

  @override
  String get playerDefaultAudioChannel => '默认音频通道';

  @override
  String get playerDefaultAspectRatio => '默认画面比例';

  @override
  String get playerDefaultSpeed => '默认播放速度';

  @override
  String get playerDefaultAutoPlay => '默认自动连播';

  @override
  String get playerSubtitleFontSize => '字幕字体大小';

  @override
  String get subtitleTitle => '字幕';

  @override
  String get subtitleOffset => '偏移';

  @override
  String get subtitlePosTop => '顶部';

  @override
  String get subtitlePosCenter => '居中';

  @override
  String get subtitlePosBottom => '底部';

  @override
  String get subtitleAssYes => '是';

  @override
  String get subtitleAssNo => '否';

  @override
  String get subtitleAssStrip => '剥离';

  @override
  String get subtitleAssForce => '强制';

  @override
  String get subtitleShow => '显示字幕';

  @override
  String get subtitleNone => '无字幕';

  @override
  String get subtitleNoTracks => '无可用字幕轨道';

  @override
  String get subtitleStyleTitle => '字幕样式';

  @override
  String get subtitleFontSize => '字号';

  @override
  String get subtitleScale => '缩放';

  @override
  String get subtitleBorderSize => '边框宽度';

  @override
  String get subtitleShadowOffset => '阴影偏移';

  @override
  String get subtitleTextColor => '文字颜色';

  @override
  String get subtitleBorderColorLabel => '边框颜色';

  @override
  String get subtitleShadowColorLabel => '阴影颜色';

  @override
  String get subtitlePosition => '位置';

  @override
  String get subtitleAssOverride => '覆盖 ASS/SSA 样式';

  @override
  String subtitleTrackN(Object n) {
    return '轨道 $n';
  }

  @override
  String get readerSettingsTitle => '阅读器设置';

  @override
  String get readerSettingsDesc => '阅读模式、背景、方向等';

  @override
  String get readerGeneralGroup => '通用阅读偏好';

  @override
  String get novelReaderSettingsTitle => '小说阅读器设置';

  @override
  String get novelReaderSettingsDesc => '小说阅读全局默认设置';

  @override
  String get comicReaderSettingsTitle => '漫画阅读器设置';

  @override
  String get comicReaderSettingsDesc => '方向、点击区、滤镜、缩放手势等';

  @override
  String get novelTypographyGroup => '小说排版';

  @override
  String get novelShadow => '阴影开关';

  @override
  String get novelBackgroundPreset => '背景预设';

  @override
  String get novelTapZoneInvert => '点击区域翻转';

  @override
  String get comicFilterGroup => '图片滤镜';

  @override
  String get comicFilterBrightness => '亮度';

  @override
  String get comicFilterContrast => '对比度';

  @override
  String get comicFilterColorTemp => '色温';

  @override
  String get comicFilterInverted => '反色滤镜';

  @override
  String get comicTapZoneInvert => '点击区反转';

  @override
  String get novelZoomGroup => '缩放与排版';

  @override
  String get comicZoomGroup => '缩放与手势';

  @override
  String get readerDefaultMode => '默认阅读模式';

  @override
  String get readerDefaultBackground => '默认背景色';

  @override
  String get readerBackgroundWhite => '白色';

  @override
  String get readerBackgroundBeige => '米色';

  @override
  String get readerBackgroundDark => '深色';

  @override
  String get readerDefaultOrientation => '默认方向';

  @override
  String get readerOrientationHorizontal => '水平';

  @override
  String get readerOrientationVertical => '垂直';

  @override
  String get readerDoubleTapZoom => '双击缩放';

  @override
  String get readerOrientationLock => '方向锁定';

  @override
  String get layoutSettings => '布局设置';

  @override
  String get layoutSettingsDesc => '书架网格/列表、密度';

  @override
  String get bookshelfLayoutMode => '书架布局模式';

  @override
  String get bookshelfLayoutGrid => '网格';

  @override
  String get bookshelfLayoutList => '列表';

  @override
  String get bookshelfLayoutDensity => '网格密度';

  @override
  String get bookshelfDensityCompact => '紧凑';

  @override
  String get bookshelfDensityStandard => '标准';

  @override
  String get bookshelfDensityComfortable => '舒适';

  @override
  String get sourceHide => '隐藏';

  @override
  String get sourceShowHidden => '显示隐藏源';

  @override
  String get sourceEdit => '编辑源';

  @override
  String get sourceDelete => '删除源';

  @override
  String get sourceMigrate => '查看迁移说明';

  @override
  String get sourceEditBuiltinNotAllowed => '内置源不可编辑';

  @override
  String get sourceEditSaved => '源已更新';

  @override
  String get sourceEditFailed => '源更新失败';

  @override
  String get sourceEditJsonHint =>
      '按模块折叠编辑该源的全部字段（JSON），点模块标题展开/收起，折叠模块的内容展开时才加载。清空某模块内容并保存即删除该字段；id 已锁定，不可修改。';

  @override
  String get sourceEditInvalidJson => 'JSON 格式或字段校验未通过，请检查后重试。';

  @override
  String sourceEditSectionItems(int count) {
    return '$count 项';
  }

  @override
  String get sourceEditAddField => '添加字段';

  @override
  String get sourceEditFieldName => '字段名';

  @override
  String get sourceEditFieldExists => '该字段已存在';

  @override
  String get sourceEditIdLocked => 'id 已锁定，保存时保持不变';

  @override
  String get sourceEditTabBasic => '基础字段';

  @override
  String get sourceEditTabParse => '站点解析';

  @override
  String get sourceEditTabRoutes => '路由';

  @override
  String get sourceEditTabBrowse => '分类筛选';

  @override
  String get sourceEditTabAdvanced => '网络与其他';

  @override
  String get sourceDeleteBuiltinNotAllowed => '内置源不可删除';

  @override
  String get sourceDeleted => '源已删除';

  @override
  String get sourceDeleteFailed => '源删除失败';

  @override
  String get sourceDeprecatedHint => '此源已弃用，请使用替代源。';

  @override
  String get sourceNameLabel => '源名称';

  @override
  String get sourceUrlLabel => '源地址';

  @override
  String get back => '返回';

  @override
  String get sourceType => '类型';

  @override
  String get sourceTypeAnime => '动漫';

  @override
  String get sourceTypeManga => '漫画';

  @override
  String get sourceTypeNovel => '小说';

  @override
  String get playerTimerOff => '关闭定时';

  @override
  String playerTimerMinutes(int minutes) {
    return '$minutes 分钟';
  }

  @override
  String get playerTimerCustom => '自定义';

  @override
  String get playerTimerCanceled => '已取消定时关闭';

  @override
  String get playerTimerFired => '定时关闭已触发，播放已暂停';

  @override
  String playerTimerEpisodes(int count) {
    return '再播 $count 集后暂停';
  }

  @override
  String get playerTimerEpisodesFired => '已按集数定时暂停播放';

  @override
  String get noDescription => '暂无简介';

  @override
  String get aboutAppTitle => '关于';

  @override
  String get openSourceLicenses => '开源协议';

  @override
  String get thirdPartyLibraries => '第三方库';

  @override
  String get acknowledgements => '致谢';

  @override
  String get acknowledgementsLegado =>
      'NexHub 小说分页器以独立 Dart 实现借鉴了其 ChapterProvider 分页算法（未复制源码）。上游仓库未附带明确开源许可证，本致谢仅作启发署名。';

  @override
  String get acknowledgementsMihon =>
      '扩展源架构与漫画阅读器交互为 NexHub 的漫画解析与阅读体验提供了重要参考。以 Apache License 2.0 发布（© Mihon contributors）。';

  @override
  String get acknowledgementsRssHub =>
      '为 NexHub 的订阅功能提供 RSS 聚合服务。以 AGPL-3.0 发布（© DIYgod），NexHub 仅作客户端调用，未修改或再分发其源码。';

  @override
  String get acknowledgementsWenyi =>
      '其小说 AI 翻译管线设计（上下文增强、术语闭环、审查与精译）为 NexHub 内置小说翻译的深度优化提供了重要参考。以 MIT License 发布（© BigDawnGhost），NexHub 未复制其源码，仅借鉴设计思想独立实现。';

  @override
  String get acknowledgementsAnime4K =>
      '播放器「超分辨率」内置其 GLSL shader 预设（Mode A 效率/质量档），随应用分发。以 MIT License 发布（© 2019-2021 bloc97）。';

  @override
  String get acknowledgementsViewProject => '查看项目';

  @override
  String get acknowledgementsMoreLibs => '其余第三方库见「开源许可」列表。';

  @override
  String get projectRepository => '项目仓库';

  @override
  String get aboutContactSection => '联系我们';

  @override
  String get aboutGithubDesc => '代码仓库与问题反馈';

  @override
  String get aboutQqGroup => 'QQ 群';

  @override
  String aboutQqGroupDesc(String number) {
    return '开发交流群：$number';
  }

  @override
  String get checkUpdate => '检查更新';

  @override
  String get updateChecking => '正在检查更新…';

  @override
  String get updateLatest => '已是最新版本';

  @override
  String updateAvailable(Object version) {
    return '发现新版本 $version';
  }

  @override
  String get updateAvailableHint => '是否前往发布页下载？';

  @override
  String get updateGoToDownload => '前往下载';

  @override
  String get updateCheckFailed => '检查更新失败，请稍后重试';

  @override
  String get updateMirrorSettings => '更新镜像设置';

  @override
  String get updateMirror => '镜像';

  @override
  String get updateSilentDownload => '静默下载';

  @override
  String get updateDownloadAndInstall => '下载并安装';

  @override
  String get updateDownloaded => '下载完成，可开始安装';

  @override
  String get updateInstallNow => '立即安装';

  @override
  String get updateAutoSwitchMirror => '自动切换高速镜像';

  @override
  String get updateAutoSwitchMirrorDesc => '下载时自动测试各镜像延迟，选择最快的一个';

  @override
  String get updateMirrorSelection => '镜像选择';

  @override
  String get updateCustomMirrors => '自定义镜像';

  @override
  String get updateNoCustomMirrors => '暂无自定义镜像';

  @override
  String get updateAddMirror => '添加镜像';

  @override
  String get updateMirrorName => '镜像名称';

  @override
  String get updateMirrorUrl => '镜像地址';

  @override
  String get updateMirrorUrlInvalid => '镜像地址无效，需为 http/https 开头的完整网址';

  @override
  String get updateTestMirrors => '测试所有镜像';

  @override
  String get updateMirrorTimeout => '超时';

  @override
  String get updateSettings => '更新设置';

  @override
  String get updateSettingsDesc => '检查更新、升级通道与下载方式';

  @override
  String get updateChannelSection => '升级通道';

  @override
  String get updateChannelStable => '稳定版';

  @override
  String get updateChannelStableDesc => '仅接收正式发布版本，最稳定';

  @override
  String get updateChannelBeta => '测试版';

  @override
  String get updateChannelBetaDesc => '提前体验 alpha / beta / rc 测试版本，可能不稳定';

  @override
  String get updateAutoCheck => '自动检查更新';

  @override
  String get updateAutoCheckDesc => '启动时在后台检查是否有新版本';

  @override
  String get updateAutoDownload => '自动下载更新';

  @override
  String get updateAutoDownloadDesc => '发现新版本后自动下载安装包';

  @override
  String get updateWifiOnlyAutoDownload => '仅 WiFi 下自动下载';

  @override
  String get updateWifiOnlyAutoDownloadDesc => '移动网络下暂不下载，连接 WiFi 后自动继续';

  @override
  String get updateInAppDownload => '应用内下载';

  @override
  String get updateInAppDownloadDesc => '在应用内直接下载安装包；关闭后跳转浏览器';

  @override
  String get updateMirrorSection => '下载镜像';

  @override
  String get updateMirrorCommunityThanks =>
      '镜像由社区热心网友公益贡献，无法保障稳定性与可用性，由衷感谢每一位无私分享的贡献者 🙏';

  @override
  String updateMirrorShowAll(Object count) {
    return '展开全部（$count 个）';
  }

  @override
  String get updateMirrorCollapse => '收起';

  @override
  String get updateMirrorAllUnreachable =>
      '当前网络下所有镜像均不可达，下载将使用 GitHub 官方直连；可稍后重试或添加自定义镜像。';

  @override
  String get updateOpenedBrowser => '已打开浏览器前往下载';

  @override
  String get updateCannotOpenBrowser => '无法打开浏览器';

  @override
  String get settingsGroupLanguage => '语言';

  @override
  String get languageTitle => '界面语言';

  @override
  String get languageFollowSystem => '跟随系统';

  @override
  String get languageChinese => '简体中文';

  @override
  String get languageEnglish => 'English';

  @override
  String get chapterList => '章节目录';

  @override
  String get currentChapter => '当前章';

  @override
  String get searchByAuthor => '按作者搜索';

  @override
  String get noRecommendation => '暂无推荐';

  @override
  String get restore => '恢复';

  @override
  String get archive => '归档';

  @override
  String get archivedEmpty => '没有已归档的内容';

  @override
  String get archivedHint => '归档后文件保留在磁盘，可随时恢复';

  @override
  String get deletePermanently => '彻底删除';

  @override
  String get restoreSuccess => '已恢复';

  @override
  String get statusArchived => '已归档';

  @override
  String get searchHistoryTitle => '搜索历史';

  @override
  String get clearSearchHistory => '清空历史';

  @override
  String get clearSearchHistoryConfirm => '确定清空所有搜索历史？';

  @override
  String get noSearchHistory => '暂无搜索历史';

  @override
  String get deleteSearchHistoryConfirm => '删除这条搜索历史？';

  @override
  String get hotSearch => '热门搜索';

  @override
  String get noHotSearch => '暂无热词';

  @override
  String get importDataParsing => '正在解析…';

  @override
  String get importDataSuccess => '导入成功';

  @override
  String get importDataFailed => '导入失败';

  @override
  String get importDataInvalidFormat => '文件格式无效';

  @override
  String importDataSummary(int plugins, int favorites, int history) {
    return '已导入 $plugins 个插件 / $favorites 个收藏 / $history 条历史';
  }

  @override
  String get exportFolderDefault => '默认路径（文档）';

  @override
  String get exportDataSuccess => '导出成功';

  @override
  String get exportDataFailed => '导出失败';

  @override
  String get exportDataInProgress => '正在导出…';

  @override
  String exportDataFileSaved(String path) {
    return '已保存到 $path';
  }

  @override
  String get exportNothingToExport => '无数据可导出';

  @override
  String get notImplemented => '功能暂未实现';

  @override
  String get cast => '投屏';

  @override
  String get castNotSupportedYet => '投屏功能即将推出';

  @override
  String get cloudSync => '云同步';

  @override
  String get cloudSyncNotSupportedYet => '即将推出';

  @override
  String get cloudSyncNotConfigured => '未配置，点击设置';

  @override
  String get cloudSyncFeatureWebdav => 'WebDAV 备份';

  @override
  String get cloudSyncFeatureSync => '多端同步收藏与进度';

  @override
  String get enableRecommendedSources => '启用推荐源';

  @override
  String get enableRecommendedSourcesHint => '一键开启所有可用的推荐源';

  @override
  String recommendedSourcesEnabled(int count) {
    return '已启用 $count 个推荐源';
  }

  @override
  String get castToDevice => '投屏到设备';

  @override
  String castingTo(Object device) {
    return '正在投屏到 $device';
  }

  @override
  String get castNoDevices => '未找到投屏设备';

  @override
  String get castNotSupportedOnDevice => '当前设备不支持投屏';

  @override
  String get castDisconnect => '断开投屏';

  @override
  String get castDisconnected => '投屏已断开';

  @override
  String get pip => '画中画';

  @override
  String get pipNotSupportedOnDevice => '当前设备不支持画中画';

  @override
  String get pipNotWhileCasting => '投屏中无法进入画中画';

  @override
  String get pipNotReady => '媒体加载完成后才能进入画中画';

  @override
  String get pipActionPlay => '播放';

  @override
  String get pipActionPause => '暂停';

  @override
  String get pipActionDanmaku => '弹幕';

  @override
  String get pipActionRewind => '快退 10 秒';

  @override
  String get pipActionForward => '快进 30 秒';

  @override
  String get screenshot => '截图';

  @override
  String get screenshotSaved => '截图已保存';

  @override
  String get screenshotFailed => '截图失败';

  @override
  String get screenshotPathSetting => '截图保存路径';

  @override
  String get screenshotPathDefault => '默认路径（Documents/screenshots）';

  @override
  String get imageLoadFailed => '图片加载失败';

  @override
  String get imageFavoriteGalleryTitle => '图片收藏';

  @override
  String get imageFavoriteEmpty => '暂无收藏图片';

  @override
  String get imageFavoriteDeleteConfirm => '确定删除这张收藏图片吗？';

  @override
  String get imageFavoriteDeleted => '已删除收藏图片';

  @override
  String get seriesTitle => '系列';

  @override
  String get seasonsTitle => '季';

  @override
  String episodeCount(int count) {
    return '$count 集';
  }

  @override
  String seasonCount(int count) {
    return '$count 季';
  }

  @override
  String get imageFilter => '图片滤镜';

  @override
  String get brightness => '亮度';

  @override
  String get contrast => '对比度';

  @override
  String get colorTemperature => '色温';

  @override
  String get saturation => '饱和度';

  @override
  String get hue => '色相';

  @override
  String get resetFilter => '重置滤镜';

  @override
  String get saveImage => '保存图片';

  @override
  String get shareImage => '分享图片';

  @override
  String imageSavedTo(String path) {
    return '图片已保存到 $path';
  }

  @override
  String get imageSaveFailed => '图片保存失败';

  @override
  String get imagePathCopied => '图片路径已复制到剪贴板';

  @override
  String get chineseConverter => '繁简转换';

  @override
  String get noConvert => '不转换';

  @override
  String get traditionalToSimplified => '繁转简';

  @override
  String get simplifiedToTraditional => '简转繁';

  @override
  String get autoPageInterval => '自动翻页间隔';

  @override
  String get autoPageSmooth => '平滑自动翻页';

  @override
  String get autoPageOff => '关闭';

  @override
  String get pauseAutoPage => '暂停自动翻页';

  @override
  String get resumeAutoPage => '恢复自动翻页';

  @override
  String get customFont => '自定义字体';

  @override
  String get fontMonospace => '等宽';

  @override
  String get addBookmark => '添加书签';

  @override
  String get bookmarkList => '书签列表';

  @override
  String get bookmarkAdded => '书签已添加';

  @override
  String get novelSwipeKeepGoing => '继续下滑添加书签';

  @override
  String get novelSwipeRelease => '松开添加书签';

  @override
  String get novelSwipeReleaseRemove => '松开取消书签';

  @override
  String get novelBookmarkRemoved => '书签已取消';

  @override
  String get deleteBookmark => '删除书签';

  @override
  String get bookmarkBadgeCustom => '自定义角标图';

  @override
  String get bookmarkBadgeReset => '恢复默认图标';

  @override
  String get noBookmarks => '暂无书签';

  @override
  String get bookmarkNoteHint => '备注（可选）';

  @override
  String novelChapterProgress(int current, int total) {
    return '第 $current 章 / 共 $total 章';
  }

  @override
  String get novelLetterSpacing => '字距';

  @override
  String get novelFontStyle => '字体样式';

  @override
  String get fontBold => '加粗';

  @override
  String get fontItalic => '斜体';

  @override
  String get fontUnderline => '下划线';

  @override
  String get novelTextColor => '正文颜色';

  @override
  String get novelTextColorFollowBg => '跟随背景自动配色';

  @override
  String get novelShadowColor => '阴影颜色';

  @override
  String get novelShadowColorAuto => '自动（正文色半透明）';

  @override
  String get novelSectionText => '阅读基础';

  @override
  String get novelSectionTitle => '章节标题';

  @override
  String get novelSectionColor => '颜色与背景';

  @override
  String get novelSectionPage => '翻页与手势';

  @override
  String get novelWheelInverted => '鼠标滚轮翻页方向反转';

  @override
  String get novelSectionMisc => '其他';

  @override
  String get novelSectionPreDownload => '预下载';

  @override
  String get preDownloadEnabled => '阅读中预下载后续章节';

  @override
  String get preDownloadThreshold => '触发阈值（当前章进度）';

  @override
  String get preDownloadCount => '预下载章节数';

  @override
  String preDownloadStarted(Object count) {
    return '正在后台预下载后续 $count 章';
  }

  @override
  String preDownloadDone(Object count) {
    return '已预下载 $count 章';
  }

  @override
  String get preDownloadFailedHint => '预下载失败（可能需要验证或网络超时）';

  @override
  String get localReadContinueOnline => '本地内容已读完，正在接入在线继续阅读…';

  @override
  String get localContinueOnlineFailed => '无法接入在线内容';

  @override
  String get localContinueOnlineUpToDate => '已读完最新内容';

  @override
  String get novelShowChapterTitle => '正文显示章节标题';

  @override
  String get novelTitleFontScale => '标题字号倍数';

  @override
  String get novelTitleBold => '标题加粗';

  @override
  String get novelTitleColor => '标题颜色';

  @override
  String get novelTitleColorAuto => '跟随强调色';

  @override
  String get importShuyuan => '导入书源';

  @override
  String get shuyuanImportTitle => '导入书源';

  @override
  String get shuyuanImportHint => '支持书源规则（@css/@xpath/@json/@js + ## 正则）';

  @override
  String get shuyuanImportFromUrl => 'URL';

  @override
  String get shuyuanImportFromFile => '文件';

  @override
  String get shuyuanImportFromJson => 'JSON';

  @override
  String get shuyuanImportUrlHint => '书源 JSON 的 URL';

  @override
  String get shuyuanImportJsonHint => '粘贴书源 JSON 配置';

  @override
  String get shuyuanImportFilePicker => '选择书源文件';

  @override
  String get shuyuanImportParse => '解析';

  @override
  String get shuyuanImportParsing => '解析中…';

  @override
  String get shuyuanImportParseFailed => '解析失败，未识别到有效书源';

  @override
  String shuyuanImportPreview(int count) {
    return '预览（$count）';
  }

  @override
  String get shuyuanImportSaveAll => '全部导入';

  @override
  String get shuyuanImportEmpty => '暂无解析结果';

  @override
  String get shuyuanImportValid => '有效';

  @override
  String get shuyuanImportInvalid => '无效';

  @override
  String get shuyuanImportTypeUnsupported => '类型不支持（仅文本书源）';

  @override
  String shuyuanImportSuccess(int count) {
    return '已导入 $count 个书源';
  }

  @override
  String shuyuanImportSelected(int count) {
    return '导入选中 $count 项';
  }

  @override
  String get shuyuanImportFailed => '导入失败';

  @override
  String get shareFailed => '分享失败';

  @override
  String get openInBrowserFailed => '无法打开浏览器';

  @override
  String get updatedAtLabel => '更新时间：';

  @override
  String get searchChapter => '搜索章节';

  @override
  String get noChaptersFound => '未找到匹配章节';

  @override
  String expandRemainingChapters(int count) {
    return '展开剩余 $count 章';
  }

  @override
  String get sortAscending => '升序';

  @override
  String get sortDescending => '降序';

  @override
  String get downloadSingleChapter => '下载单章';

  @override
  String get chapterBookmark => '章节书签';

  @override
  String get chapterRead => '已读标记';

  @override
  String get chapterSortMode => '章节排序';

  @override
  String get aggModeFileExpanded => '按文件顺序（EPUB 章节就地展开）';

  @override
  String get aggModeEpubLast => 'EPUB 章节排在最后';

  @override
  String get aggModeCollapsed => '每文件一章（不展开 EPUB）';

  @override
  String get continueReading => '继续阅读';

  @override
  String get continueWatching => '继续观看';

  @override
  String get startFromBeginning => '从头开始';

  @override
  String get openInAppBrowser => '应用内打开';

  @override
  String get refreshMetadata => '刷新信息';

  @override
  String get removeFromFavorites => '从收藏移除';

  @override
  String get coverViewer => '封面';

  @override
  String get downloadPreset1 => '下载最新1集';

  @override
  String get downloadPreset5 => '下载最新5集';

  @override
  String get downloadPreset10 => '下载最新10集';

  @override
  String get downloadUnread => '下载未读';

  @override
  String get downloadFavorited => '下载已收藏';

  @override
  String get tagLabel => '标签';

  @override
  String get sourceLabel => '来源';

  @override
  String get reloadChapter => '重载本章';

  @override
  String get clearReadingProgress => '清除阅读进度';

  @override
  String get readingProgressCleared => '阅读进度已清除';

  @override
  String get novelMenuBookmarkList => '书签列表';

  @override
  String get novelMenuConfigureToolbar => '配置底部工具栏';

  @override
  String get novelTtsBackground => '后台朗读';

  @override
  String get httpTtsEnable => '在线 TTS 引擎';

  @override
  String get httpTtsEnableDesc => '在线合成语音（内置 Edge 语音，或自建/第三方 HTTP 端点）';

  @override
  String get httpTtsProvider => '在线语音来源';

  @override
  String get httpTtsProviderEdge => 'Edge 语音';

  @override
  String get httpTtsProviderCustom => '自定义端点';

  @override
  String get httpTtsEdgeHint => '微软 Edge 朗读接口，免费在线合成、无需配置服务；音质通常优于系统 TTS，需联网';

  @override
  String get httpTtsUrlTemplate => 'URL 模板';

  @override
  String get httpTtsDefaultVoice => '默认音色';

  @override
  String get httpTtsVoiceFollowDefault => '跟随默认音色';

  @override
  String get httpTtsVoicePreview => '试听';

  @override
  String get httpTtsVoicePreviewSample => '你好，这是音色试听。';

  @override
  String get httpTtsVoicePreviewFail => '试听失败，请检查网络';

  @override
  String get highlightsSyncNow => '同步划线笔记';

  @override
  String highlightsSyncResult(int uploaded, int applied) {
    return '上传 $uploaded 本 · 云端并入 $applied 条';
  }

  @override
  String get highlightsSyncedNone => '划线已是最新';

  @override
  String get highlightsSyncStatusTitle => '划线笔记同步';

  @override
  String highlightsSyncLocal(int total, int books) {
    return '本机划线 $total 条 · $books 本书';
  }

  @override
  String get highlightsSyncLastNone => '尚未同步';

  @override
  String get highlightsSyncFailed => '划线同步失败，请检查网络与 WebDAV 配置';

  @override
  String get aiAskSection => '问 AI';

  @override
  String get aiAskDesc => '阅读器选区「问AI」使用的接口，留空回落通用接口';

  @override
  String get aiGroupGeneration => '内容生成';

  @override
  String get aiGroupTranslation => '翻译';

  @override
  String get httpTtsVoiceMap => '角色 → 音色（每行「角色=音色」）';

  @override
  String get httpTtsConcurrency => '预下载并发（1-8）';

  @override
  String get httpTtsMaxFailures => '连续失败停止阈值';

  @override
  String get httpTtsSilentPlaceholder => '失败静音占位降级';

  @override
  String get httpTtsSilentPlaceholderDesc => '单句合成失败时静音跳过继续朗读；关闭则立即停止';

  @override
  String get novelSectionFont => '字体样式';

  @override
  String get searchInBook => '书内搜索';

  @override
  String get wholeBook => '全书';

  @override
  String get noSearchResults => '无搜索结果';

  @override
  String searchProgress(int searched, int total) {
    return '已搜索 $searched/$total 章';
  }

  @override
  String get customBgColor => '自定义背景色';

  @override
  String get tapZoneInvert => '点击反转';

  @override
  String get tapInvertNone => '不反转';

  @override
  String get tapInvertLeftRight => '左右反转';

  @override
  String get tapInvertAll => '全反转';

  @override
  String get tapZonePreview => '预览点按区域';

  @override
  String get tapZonePrev => '上一页';

  @override
  String get tapZoneNext => '下一页';

  @override
  String get tapZoneToggle => '切换界面';

  @override
  String get startReading => '开始朗读';

  @override
  String get stopReading => '停止朗读';

  @override
  String get noteList => '笔记列表';

  @override
  String get noNotes => '暂无笔记';

  @override
  String get noteEditUnsupported => '独立笔记暂不支持编辑，可删除后重建';

  @override
  String get add => '添加';

  @override
  String get testConnection => '测试连接';

  @override
  String get noCustomInstances => '暂无自定义实例';

  @override
  String get searchByDirector => '按导演搜索';

  @override
  String get searchByActor => '按演员搜索';

  @override
  String get searchByTag => '按标签搜索';

  @override
  String get searchAggregate => '聚合全部源';

  @override
  String get searchSingle => '单源';

  @override
  String get searchSelectSource => '选择一个源';

  @override
  String get searchByWork => '按作品名搜索';

  @override
  String get searchFieldAuthor => '作者';

  @override
  String get searchFieldDirector => '导演';

  @override
  String get searchFieldActor => '主演';

  @override
  String get searchFieldWork => '作品';

  @override
  String get rsshubRouteQidian => '起点';

  @override
  String get rsshubRouteJjwxc => '晋江文学城';

  @override
  String get rsshubRouteDoubanBooks => '豆瓣图书';

  @override
  String get rsshubRouteDmzj => '动漫之家';

  @override
  String get rsshubRouteJmcomic => '禁漫天堂';

  @override
  String browseNetworkSelectedCount(int count) {
    return '已选 $count 项';
  }

  @override
  String get browseNetworkOpenSelected => '打开';

  @override
  String get browseNetworkDownloadSelected => '下载';

  @override
  String browseNetworkDownloadStarted(int count) {
    return '开始下载 $count 个文件';
  }

  @override
  String browseNetworkDownloadDone(int count) {
    return '已下载 $count 项';
  }

  @override
  String get browseNetworkDownloadFailed => '下载失败';

  @override
  String get browseNetworkDownloadPathMissing => '下载路径不可用';

  @override
  String get unknown => '未知';

  @override
  String get rssFeedListTitle => 'RSS 订阅';

  @override
  String get rssTestAllSpeed => '一键测速';

  @override
  String get rssTestSpeed => '测速';

  @override
  String get rssSpeedFailed => '测速失败';

  @override
  String rssSpeedMs(int ms) {
    return '${ms}ms';
  }

  @override
  String unrecognizedFile(String fileName) {
    return '未识别的文件：$fileName';
  }

  @override
  String importFailed(String reason) {
    return '导入失败：$reason';
  }

  @override
  String get folderScanFailed => '文件夹扫描失败，请检查权限或路径';

  @override
  String get emptyFolder => '文件夹为空或无可用文件';

  @override
  String get storagePermissionDenied => '存储权限被拒绝，无法选择文件';

  @override
  String get pickFileNoPath => '无法获取所选文件路径（可能是系统限制），请尝试其他文件';

  @override
  String get folderPickUnsupportedSaf =>
      '当前系统不支持选择文件夹导入（Android SAF 限制），请改用「选择文件」逐个添加';

  @override
  String folderImportChoiceTitle(Object name) {
    return '导入文件夹「$name」';
  }

  @override
  String folderImportChoiceHint(Object type) {
    return '检测到多个$type文件。合并后整个文件夹作为一部作品，内部每个文件是一章/一话；或每个文件单独导入。';
  }

  @override
  String get folderImportChoiceMerge => '合并为整本/整部';

  @override
  String get folderImportChoicePerFile => '逐文件分别导入';

  @override
  String get folderFileSelectTitle => '选择要导入的漫画文件';

  @override
  String folderFileSelectHint(Object count) {
    return '文件夹内共 $count 个文件（每个为一话），勾选需要导入的文件。';
  }

  @override
  String get folderFileSelectAll => '全选';

  @override
  String get folderFileSelectNone => '全不选';

  @override
  String get folderFileSelectMerge => '合并为一部';

  @override
  String get folderFileSelectSeparate => '逐个分开';

  @override
  String folderFileSelectConfirm(Object count) {
    return '导入所选（$count）';
  }

  @override
  String get setAsShelfCover => '设为书架封面';

  @override
  String get openDownloadManager => '打开下载管理';

  @override
  String get details => '详情';

  @override
  String get coverUpdated => '封面已更新';

  @override
  String get coverUpdateFailed => '封面更新失败：未找到收藏条目';

  @override
  String get authorLabel => '作者';

  @override
  String get statusLabel => '状态';

  @override
  String get setAsCover => '设为封面';

  @override
  String get mediaInfo => '媒体信息';

  @override
  String get playExternal => '外部播放';

  @override
  String get loadExternalSubtitle => '导入外部字幕';

  @override
  String get loadExternalSubtitleFailed => '外部字幕加载失败';

  @override
  String get danmakuCustomUrl => '自定义 URL';

  @override
  String get danmakuCustomUrlHint => '输入弹幕源 URL';

  @override
  String get danmakuCustomUrlDesc => '从自定义 URL 加载弹幕';

  @override
  String get onlineTabHome => '首页';

  @override
  String get onlineTabSchedule => '周期表';

  @override
  String get onlineTabRanking => '排行';

  @override
  String get filterYear => '年份';

  @override
  String get filterRegion => '地区';

  @override
  String get filterSort => '排序';

  @override
  String get filterCategory => '分类';

  @override
  String get filterTag => '标签';

  @override
  String get sortHottest => '最热';

  @override
  String get sortRating => '评分';

  @override
  String get viewAll => '查看全部';

  @override
  String get latestUpdates => '最新更新';

  @override
  String get hotRecommendations => '热门推荐';

  @override
  String get weekdayMon => '周一';

  @override
  String get weekdayTue => '周二';

  @override
  String get weekdayWed => '周三';

  @override
  String get weekdayThu => '周四';

  @override
  String get weekdayFri => '周五';

  @override
  String get weekdaySat => '周六';

  @override
  String get weekdaySun => '周日';

  @override
  String get regionChina => '中国大陆';

  @override
  String get regionHongKong => '中国香港';

  @override
  String get regionTaiwan => '中国台湾';

  @override
  String get regionJapan => '日本';

  @override
  String get regionKorea => '韩国';

  @override
  String get regionUSA => '美国';

  @override
  String get regionOther => '其他';

  @override
  String get unsupportedRarFormat => '暂不支持 RAR 格式漫画';

  @override
  String get unsupportedEpubFormat => '暂不支持 EPUB 格式，请使用专用阅读器';

  @override
  String get unsupportedFormat => '暂不支持该格式';

  @override
  String get localFileLabel => '本地文件';

  @override
  String get localFileLoadFailed => '本地文件读取失败';

  @override
  String get playerDefaultOrientation => '锁定方向';

  @override
  String get playerOrientationAuto => '自动跟随';

  @override
  String get playerOrientationPortrait => '竖屏';

  @override
  String get playerOrientationLandscape => '横屏';

  @override
  String get playerGestureSeekMultiplier => '拖动进度倍率';

  @override
  String get playerSeekHalf => '0.5x';

  @override
  String get playerSeekNormal => '1x';

  @override
  String get playerSeekDouble => '2x';

  @override
  String get playerLongPressSpeedUp => '长按加速';

  @override
  String get playerBottomProgress => '隐藏控制栏时显示底部进度条';

  @override
  String get playerAutoSelectLine => '自动选择可用线路';

  @override
  String get playerCurrentPlayingLine => '正在播放的线路';

  @override
  String playerLineSwitched(Object line) {
    return '已切换到线路 $line';
  }

  @override
  String playerLineFailover(Object from, Object to) {
    return '线路 $from 不可用，已切换到线路 $to';
  }

  @override
  String get playerDefaultVolume => '默认音量';

  @override
  String get playerResetEpisodeSettings => '重置该视频设置';

  @override
  String get playerResetEpisodeSettingsDone => '已恢复该视频的全局默认设置';

  @override
  String get playerCoreGroup => '播放核心';

  @override
  String get playerSubtitleGroup => '字幕';

  @override
  String get playerGestureGroup => '手势与控制';

  @override
  String get playerScreenshotGroup => '截图';

  @override
  String get novelDefaultGroupTitle => '小说默认';

  @override
  String get novelDefaultPageTurnAnimation => '翻页动画';

  @override
  String get novelDefaultFontSize => '默认字号';

  @override
  String get novelDefaultLineHeight => '默认行距';

  @override
  String get novelDefaultBackground => '背景色';

  @override
  String get novelDefaultTtsRate => '朗读语速';

  @override
  String get novelDefaultChineseConversion => '简繁转换';

  @override
  String get novelBgWhite => '白色';

  @override
  String get novelBgCream => '米黄';

  @override
  String get novelBgDarkGray => '深灰';

  @override
  String get novelBgBlack => '黑色';

  @override
  String get comicDefaultGroupTitle => '漫画默认';

  @override
  String get comicDefaultReadingDirection => '阅读方向';

  @override
  String get comicDefaultTapZoneLayout => '点击区域';

  @override
  String get comicDefaultInvertFilter => '反色滤镜';

  @override
  String get comicDefaultInitialZoom => '初始缩放';

  @override
  String get comicDefaultDoubleTapZoom => '双击缩放';

  @override
  String get comicDefaultScrollWheel => '滚轮方向';

  @override
  String get comicTapLayout1 => '布局 1';

  @override
  String get comicTapLayout2 => '布局 2';

  @override
  String get comicTapLayout3 => '布局 3';

  @override
  String get comicTapLayout4 => '布局 4';

  @override
  String get comicTapLayout5 => '布局 5';

  @override
  String get comicZoomFitWidth => '适应宽度';

  @override
  String get comicZoomFitHeight => '适应高度';

  @override
  String get comicZoomOriginal => '原始尺寸';

  @override
  String get comicZoom2x => '2x';

  @override
  String get comicZoom3x => '3x';

  @override
  String get comicWheelNatural => '自然';

  @override
  String get comicWheelInverted => '反向';

  @override
  String get comicDirLtr => '左→右';

  @override
  String get comicDirRtl => '右→左';

  @override
  String get comicDirVertical => '上下';

  @override
  String get comicDirWebtoon => '瀑布流';

  @override
  String get comicDirWebtoonGap => '瀑布流（带间距）';

  @override
  String get danmakuDisplayFontSize => '字体大小';

  @override
  String get danmakuDisplayOpacity => '透明度';

  @override
  String get danmakuDisplayScrollSpeed => '滚动速度';

  @override
  String get danmakuDisplayArea => '显示区域';

  @override
  String get danmakuDisplayMaxOnScreen => '同屏上限';

  @override
  String get danmakuSizeSmall => '小';

  @override
  String get danmakuSizeMedium => '中';

  @override
  String get danmakuSizeLarge => '大';

  @override
  String get danmakuSpeedSlow => '慢';

  @override
  String get danmakuSpeedMedium => '中';

  @override
  String get danmakuSpeedFast => '快';

  @override
  String get danmakuAreaQuarter => '1/4';

  @override
  String get danmakuAreaHalf => '半屏';

  @override
  String get danmakuAreaFull => '全屏';

  @override
  String get danmakuMaxTen => '10';

  @override
  String get danmakuMaxTwenty => '20';

  @override
  String get danmakuMaxFifty => '50';

  @override
  String get danmakuMaxHundred => '100';

  @override
  String get danmakuDisplayGroupFilter => '过滤与屏蔽';

  @override
  String get danmakuDisplayGroupAppearance => '外观';

  @override
  String get danmakuDisplayGroupDisplay => '显示';

  @override
  String get danmakuDisplayGroupDisplayRange => '显示范围';

  @override
  String get danmakuDisplayGroupSpeed => '速度';

  @override
  String get layoutTypeLabel => '布局类型';

  @override
  String get layoutGridLarge => '大网格';

  @override
  String get layoutGridMedium => '中网格';

  @override
  String get layoutGridSmall => '小网格';

  @override
  String get layoutListComfortable => '舒适列表';

  @override
  String get layoutListCompact => '紧凑列表';

  @override
  String get layoutGridColumns => '网格列数';

  @override
  String get layoutGridSpacing => '网格间距';

  @override
  String get layoutCoverRadius => '封面圆角';

  @override
  String get layoutTitleFontSize => '标题字号';

  @override
  String get layoutShowTitle => '显示标题';

  @override
  String get layoutTitleMaxLines => '标题行数';

  @override
  String get layoutShowAuthor => '显示作者';

  @override
  String get layoutShowProgress => '显示进度';

  @override
  String get layoutOpenSettings => '打开布局设置';

  @override
  String get bookshelfLayoutGroup => '书架布局';

  @override
  String get layoutTypeGroup => '全局布局类型';

  @override
  String get layoutGridCoverGroup => '网格与封面';

  @override
  String get layoutDisplayGroup => '显示选项';

  @override
  String get downloadStatusInProgress => '进行中';

  @override
  String get cloudSyncWebdavUrl => 'WebDAV 地址';

  @override
  String get cloudSyncWebdavUsername => '用户名';

  @override
  String get cloudSyncWebdavPassword => '密码';

  @override
  String get cloudSyncTestConnection => '测试连接';

  @override
  String cloudSyncConnectionSuccess(int ms) {
    return '连接成功（${ms}ms）';
  }

  @override
  String get cloudSyncConnectionFailed => '连接失败';

  @override
  String get cloudSyncAutoSync => '自动同步';

  @override
  String get cloudSyncSyncFrequencyManual => '手动';

  @override
  String get cloudSyncSyncFrequencyDaily => '每日';

  @override
  String get cloudSyncSyncFrequencyWeekly => '每周';

  @override
  String get cloudSyncSyncNow => '立即同步';

  @override
  String get novelProgressSyncNow => '同步阅读进度';

  @override
  String get novelProgressConflictTitle => '阅读进度冲突';

  @override
  String novelProgressConflictBody(int n) {
    return '云端有 $n 本书的阅读进度领先于本机，是否采用云端进度？';
  }

  @override
  String get novelProgressUseRemote => '采用云端';

  @override
  String novelProgressSyncedUploaded(int n) {
    return '已上传 $n 本';
  }

  @override
  String novelProgressSyncedRestored(int n) {
    return '恢复 $n 本';
  }

  @override
  String novelProgressSyncedConflicted(int n) {
    return '$n 本待确认';
  }

  @override
  String get novelProgressSyncedNone => '阅读进度无变化';

  @override
  String cloudSyncLastSyncTime(String time) {
    return '上次同步：$time';
  }

  @override
  String get cloudSyncNeverSynced => '尚未同步';

  @override
  String get cloudSyncSyncSuccess => '同步成功';

  @override
  String get cloudSyncSyncFailed => '同步失败';

  @override
  String get cloudSyncSaveConfig => '保存配置';

  @override
  String get readingProgress => '阅读进度';

  @override
  String get watchingProgress => '观看进度';

  @override
  String get totalChapters => '总章节';

  @override
  String get totalEpisodes => '总集数';

  @override
  String get chaptersRead => '已读';

  @override
  String get episodesWatched => '已看';

  @override
  String get progressLabel => '进度';

  @override
  String get layoutModeLabel => '布局模式';

  @override
  String get layoutListStyle => '列表风格';

  @override
  String get lastReadAt => '上次阅读';

  @override
  String get lastWatchedAt => '上次观看';

  @override
  String get anime => '番剧';

  @override
  String get episodeList => '选集';

  @override
  String chapterListWithCount(int count) {
    return '章节目录（$count）';
  }

  @override
  String episodeListWithCount(int count) {
    return '选集（$count）';
  }

  @override
  String lastReadInfo(String time, String chapter) {
    return '上次阅读：$time · $chapter';
  }

  @override
  String lastWatchedInfo(String time, String episode) {
    return '上次观看：$time · $episode';
  }

  @override
  String get notStartedYet => '尚未开始';

  @override
  String get timeJustNow => '刚刚';

  @override
  String timeMinutesAgo(int n) {
    return '$n 分钟前';
  }

  @override
  String timeHoursAgo(int n) {
    return '$n 小时前';
  }

  @override
  String timeDaysAgo(int n) {
    return '$n 天前';
  }

  @override
  String get expand => '展开';

  @override
  String get collapse => '收起';

  @override
  String expandCount(int count) {
    return '展开 $count 位';
  }

  @override
  String get sortSectionTitle => '排序';

  @override
  String get displayTitle => '显示选项';

  @override
  String sortByIndex(Object unitWord) {
    return '按$unitWord顺序';
  }

  @override
  String sortByName(Object unitWord) {
    return '按$unitWord名';
  }

  @override
  String get sortBySource => '按来源';

  @override
  String get sortByUploadDate => '按更新时间';

  @override
  String get sortAscendingLabel => '升序';

  @override
  String get sortDescendingLabel => '降序';

  @override
  String get filterUnread => '仅未读';

  @override
  String get filterDownloaded => '已下载';

  @override
  String get filterBookmarked => '已书签';

  @override
  String get displaySourceTitle => '来源标题';

  @override
  String displayNumber(Object unitWord) {
    return '$unitWord序号';
  }

  @override
  String get resetButton => '重置';

  @override
  String get doneButton => '完成';

  @override
  String get wordCount => '字数';

  @override
  String updatedTo(Object n) {
    return '更新至 $n';
  }

  @override
  String get unitWordChapter => '章';

  @override
  String get unitWordComicChapter => '话';

  @override
  String get unitWordEpisode => '集';

  @override
  String get prevPage => '上一页';

  @override
  String get nextPage => '下一页';

  @override
  String get nightMode => '夜间模式';

  @override
  String get toolToc => '目录';

  @override
  String get toolPrevChapter => '上一章';

  @override
  String get toolNextChapter => '下一章';

  @override
  String get toolNightMode => '夜间';

  @override
  String get toolAutoPage => '自动翻页';

  @override
  String get toolSettings => '设置';

  @override
  String get toolBookmark => '书签';

  @override
  String get toolBookmarkList => '书签列表';

  @override
  String get toolSearch => '书内搜索';

  @override
  String get toolTts => '朗读';

  @override
  String get configureBottomToolbar => '配置底部工具栏';

  @override
  String get bottomToolbarConfigTitle => '底部工具栏';

  @override
  String get slotsShown => '已显示';

  @override
  String get slotsHidden => '已隐藏（点 + 添加）';

  @override
  String get novelCacheBook => '缓存';

  @override
  String get novelResetBookPrefs => '恢复本书默认';

  @override
  String get novelResetBookDone => '已恢复本书默认设置';

  @override
  String get readerCropEdge => '裁边';

  @override
  String get readerRotatePage => '旋转页面';

  @override
  String get readerKeepScreenOn => '屏幕常亮';

  @override
  String get readerProgressBarOnRight => '进度条在右侧';

  @override
  String get readerShowChapterSlider => '章节导航滑块';

  @override
  String get readerShowPageNumber => '显示页码';

  @override
  String get readerSplitDoublePage => '双页拆分';

  @override
  String get readerSplitDoublePageHint => '已开启双页拆分，已切换到横排单页模式';

  @override
  String get readerInitialZoom => '初始缩放';

  @override
  String get readerZoomFitWidth => '适配宽度';

  @override
  String get readerZoomFitHeight => '适配高度';

  @override
  String get readerZoomOriginal => '原始大小';

  @override
  String get readerFullscreen => '全屏';

  @override
  String get readerLongPressMenu => '长按菜单';

  @override
  String get readerGrayscale => '灰度';

  @override
  String get readerPreventShrink => '防止缩小';

  @override
  String get readerChapterTransition => '章节过渡';

  @override
  String get readerPreloadCount => '预加载数量';

  @override
  String get readerPreloadCountDesc => '距章末 / 章首多少页时开始预载相邻章节（越大越流畅，占用更多流量）';

  @override
  String get readerSeamlessReading => '跨章无缝续读';

  @override
  String get readerSeamlessReadingDesc => '章末 / 章首直接续读相邻章（复用预载缓存），不重建章节、无白屏';

  @override
  String get readerChapterSeparator => '章分割过渡';

  @override
  String get readerChapterSeparatorDesc => '条漫连续模式下，章节之间插入章节标题卡';

  @override
  String get readerWebtoonDecodeLimit => '条漫解码限幅';

  @override
  String get readerScrollSpeed => '滚动速度';

  @override
  String get readerScrollSpeedDesc => '鼠标滚轮在条漫模式下的滚动增量倍率（0.5x–3x）';

  @override
  String get readerVolumeKeyPageTurn => '音量键翻页';

  @override
  String get readerVolumeKeyPageTurnDesc =>
      'Android / 鸿蒙拦截音量上/下翻页（翻页模式：翻页；条漫模式：按距离滚动）';

  @override
  String get readerVolumeKeyDistance => '音量键滚动距离';

  @override
  String get readerVolumeKeyDistanceDesc => '条漫模式下音量键每次滚动的距离（占视口高度百分比）';

  @override
  String get readerLongPressZoom => '长按缩放';

  @override
  String get readerLongPressZoomDesc => '长按进入 1.75x 缩放（再长按/松手退出）；关闭时保持长按弹菜单';

  @override
  String get readerLongPressAtPress => '按触点';

  @override
  String get readerLongPressAtCenter => '屏幕中心';

  @override
  String get readerLongPressZoomPosition => '长按缩放锚点';

  @override
  String get readerZoomStart => '缩放锚点';

  @override
  String get readerZoomStartLeft => '左侧';

  @override
  String get readerZoomStartCenter => '中心';

  @override
  String get readerZoomStartRight => '右侧';

  @override
  String get readerAutoPageTurning => '自动翻页';

  @override
  String get readerAutoPageTurningDesc => '翻页模式按固定间隔自动翻页（0=关闭）';

  @override
  String get readerAutoPageInterval => '自动翻页间隔（秒）';

  @override
  String get readerAutoScroll => '自动滚动';

  @override
  String get readerAutoScrollDesc => '条漫模式下按上方滚动速度平滑自动滚动';

  @override
  String get readerSleepTimer => '睡眠定时';

  @override
  String get readerSleepTimerDesc => '按分钟或按话数定时暂停阅读';

  @override
  String get readerSleepTimerOff => '关闭定时';

  @override
  String readerSleepTimerChapters(Object count) {
    return '再读 $count 话后暂停';
  }

  @override
  String get readerSleepTimerFired => '定时已触发，暂停阅读';

  @override
  String get readerPageAnimation => '翻页过渡动画';

  @override
  String get readerPageAnimNone => '无动画';

  @override
  String get readerPageAnimSlide => '滑入';

  @override
  String get readerPageAnimFade => '淡入淡出';

  @override
  String get motionEffectTitle => '动态效果';

  @override
  String get motionEffectDesc =>
      '把静态漫画页渲染成分层动效（视差 / 呼吸 / 粒子 / 光效 / 漫画动势），翻页与条漫滚动模式均生效';

  @override
  String get motionEffectEnabled => '开启动态效果';

  @override
  String get motionEffectEnabledDesc =>
      '翻页停留或条漫滚动停止约 1 秒后，当前页在后台自动渲染为动态页；下方可逐项开关与调参';

  @override
  String get motionInteractiveTitle => '互动阅读';

  @override
  String get motionInteractiveDesc =>
      '翻页单页模式下点按页面中心，聚焦当前页并撕开揭示动效，再点收回；放大、旋转、条漫与双页模式保持普通动态页';

  @override
  String get motionEffectStateOff => '已关闭';

  @override
  String get motionEffectStateOn => '已开启';

  @override
  String get motionPresets => '快速预设';

  @override
  String get motionPresetClassic => '经典氛围';

  @override
  String get motionPresetSakura => '樱花';

  @override
  String get motionPresetNightRain => '夜雨';

  @override
  String get motionPresetStarryNight => '星夜';

  @override
  String get motionPresetBattle => '热血战斗';

  @override
  String get motionQuality => '画质与流畅度';

  @override
  String get motionFps => '帧率';

  @override
  String get motionDuration => '循环时长';

  @override
  String get motionResolution => '渲染分辨率上限';

  @override
  String get motionQualityHint =>
      '数值越高越清晰，但渲染更慢、体积更大；动态页由后台生成，翻页停留片刻后自动呈现，放大查看时临时恢复静态';

  @override
  String get motionWebtoonModeTitle => '条漫渲染时机';

  @override
  String get motionWebtoonModeDwell => '停留渲染（省电）';

  @override
  String get motionWebtoonModeFollow => '实时跟随（更耗电）';

  @override
  String get motionWebtoonModeHint =>
      '停留渲染：滚动停止约 1 秒后才渲染可见页，省电；实时跟随：视野变化立即切换渲染目标，滚动中先出快速版（降帧/降分辨率），停止后自动升级为完整画质，CPU / 电量开销更高';

  @override
  String get motionEffectCountHint => '每种效果可独立开关，展开可调参数；全部关闭等于静态显示';

  @override
  String get motionGroupAmbient => '基础氛围';

  @override
  String get motionGroupParticles => '粒子天气';

  @override
  String get motionGroupLight => '光影明暗';

  @override
  String get motionGroupManga => '漫画动势';

  @override
  String get motionFxParallax => '视差';

  @override
  String get motionFxBreathing => '呼吸缩放';

  @override
  String get motionFxSlowPush => '缓慢推近';

  @override
  String get motionFxHeartbeat => '心跳';

  @override
  String get motionFxToneShift => '色温流转';

  @override
  String get motionFxVignette => '暗角呼吸';

  @override
  String get motionFxAmbient => '氛围微粒';

  @override
  String get motionFxDust => '尘埃';

  @override
  String get motionFxRain => '落雨';

  @override
  String get motionFxSnow => '落雪';

  @override
  String get motionFxSakura => '樱花飘落';

  @override
  String get motionFxLeaves => '落叶';

  @override
  String get motionFxBubbles => '气泡';

  @override
  String get motionFxFireflies => '流萤';

  @override
  String get motionFxEmbers => '飞烬';

  @override
  String get motionFxMeteors => '流星';

  @override
  String get motionFxFog => '雾气';

  @override
  String get motionFxSmoke => '烟雾';

  @override
  String get motionFxFlame => '火焰';

  @override
  String get motionFxGodRays => '云隙光';

  @override
  String get motionFxLightSweep => '光扫';

  @override
  String get motionFxShimmer => '波光';

  @override
  String get motionFxStarlight => '星光';

  @override
  String get motionFxLightning => '闪电';

  @override
  String get motionFxImpactFlash => '闪光冲击';

  @override
  String get motionFxSpeedLines => '速度线';

  @override
  String get motionFxFocusLines => '集中线';

  @override
  String get motionFxScreenTone => '网点纸';

  @override
  String get motionFxMangaShake => '震屏';

  @override
  String get motionFxImpactRings => '冲击波环';

  @override
  String get motionFxBrushStreak => '飞白笔触';

  @override
  String get motionFxMoodScript => '情绪调制';

  @override
  String get motionParamAmplitude => '幅度';

  @override
  String get motionParamPeriod => '周期（秒）';

  @override
  String get motionParamVerticalRatio => '纵向占比';

  @override
  String get motionParamPushFrac => '推近幅度';

  @override
  String get motionParamBeats => '拍数';

  @override
  String get motionParamIntensity => '强度';

  @override
  String get motionParamShift => '偏移量';

  @override
  String get motionParamStrength => '深度';

  @override
  String get motionParamCount => '数量';

  @override
  String get motionParamSpeed => '速度';

  @override
  String get motionParamOpacity => '不透明度';

  @override
  String get motionParamAngle => '角度';

  @override
  String get motionParamSize => '大小';

  @override
  String get motionParamSpin => '自转圈数';

  @override
  String get motionParamGlow => '光晕';

  @override
  String get motionParamLengthFrac => '长度占比';

  @override
  String get motionParamBlobs => '雾团数';

  @override
  String get motionParamPuffs => '烟团数';

  @override
  String get motionParamTongues => '火苗数';

  @override
  String get motionParamRows => '波带数';

  @override
  String get motionParamStrikes => '闪电次数';

  @override
  String get motionParamFlashes => '闪光次数';

  @override
  String get motionParamPulses => '脉冲次数';

  @override
  String get motionParamLines => '线条数';

  @override
  String get motionParamSpacing => '网格间距';

  @override
  String get motionParamDensity => '疏密';

  @override
  String get motionParamShakes => '震动次数';

  @override
  String get motionParamRings => '环数';

  @override
  String get motionParamStreaks => '笔触数';

  @override
  String get motionParamHeightFrac => '高度占比';

  @override
  String get readerDoubleTapAnimSpeed => '双击缩放动画';

  @override
  String get readerDoubleTapAnimSpeedDesc => '双击缩放动画时长（毫秒，随系统减弱动态效果按比例缩放）';

  @override
  String get readerPageSpacing => '页间距';

  @override
  String get readerPageSpacingDesc => '条漫相邻页间距（像素）';

  @override
  String get readerShowSingleImageOnFirstPage => '首屏单图';

  @override
  String get readerShowSingleImageOnFirstPageDesc => '双页模式第一章第一页单独显示，其后恢复双页';

  @override
  String get readerClockBattery => '时间 / 电量浮层';

  @override
  String get readerClockBatteryDesc => '在阅读器显示当前时间与电量，随控制栏显隐';

  @override
  String get readerClockPosition => '浮层位置';

  @override
  String get readerClockPosTop => '顶部';

  @override
  String get readerClockPosBottom => '底部';

  @override
  String get readerClockMargin => '边距';

  @override
  String get readerClockOpacity => '透明度';

  @override
  String get readerClockFontSize => '字号';

  @override
  String get readerBrightness => '阅读亮度';

  @override
  String get readerBrightnessDesc => '正值写入系统亮度；负值压暗系统亮度并叠加黑色遮罩';

  @override
  String get readerNightLight => '夜览';

  @override
  String get readerNightLightDesc => '叠加暖色盖层减少蓝光，独立于阅读亮度';

  @override
  String get readerNightLightOpacity => '夜览强度';

  @override
  String get readerAutoDownload => '自动下载后续章节';

  @override
  String get readerAutoDownloadDesc => '读到当前章 25% 后后台下载后续章节（失败静默）';

  @override
  String get readerSkipReadChapters => '跳过已读章节';

  @override
  String get readerSkipReadChaptersDesc => '下/上一章时跳过已读章节';

  @override
  String get readerSkipFilteredChapters => '跳过被筛选章节';

  @override
  String get readerSkipFilteredChaptersDesc => '下/上一章时跳过被筛选的章节';

  @override
  String get readerSkipDuplicateChapters => '跳过重复章节';

  @override
  String get readerSkipDuplicateChaptersDesc => '下/上一章时跳过标题重复的章节';

  @override
  String get readerColorProfile => '色彩配置';

  @override
  String get readerColorProfileNone => '无';

  @override
  String get readerColorProfileSrgb => 'sRGB';

  @override
  String get readerColorProfileWarm => '暖色';

  @override
  String get readerColorProfileCool => '冷色';

  @override
  String get readerColorProfileManga => '漫画';

  @override
  String get readerColorProfilePaper => '纸感';

  @override
  String get readerEInkRefresh => 'E-Ink 刷新';

  @override
  String get readerEInkRefreshDesc => '墨水屏防残影：按翻页间隔自动全屏闪烁清残影';

  @override
  String get readerEInkRefreshInterval => '刷新间隔（页）';

  @override
  String get readerEInkRefreshDuration => '刷新时长（毫秒）';

  @override
  String get readerEInkRefreshWhite => '白闪';

  @override
  String get readerEInkRefreshBlack => '黑闪';

  @override
  String get readerEInkRefreshStyle => '刷新样式';

  @override
  String get readerGroupEInk => 'E-Ink 刷新';

  @override
  String get readerGroupEInkDesc => '墨水屏设备专用：防残影全屏刷新';

  @override
  String get readerAutoFavorite => '自动收藏';

  @override
  String get readerAutoFavoriteDesc => '打开漫画即加入收藏（已收藏则不重复操作）';

  @override
  String get readerScreenPicNumberPortrait => '竖屏每屏图片数';

  @override
  String get readerScreenPicNumberLandscape => '横屏每屏图片数';

  @override
  String get readerScreenPicNumberDesc => '一屏纵向堆叠多张图片（1–5）';

  @override
  String get readerChapterBookmark => '收藏此章';

  @override
  String get readerChapterBookmarked => '已收藏该章';

  @override
  String get readerChapterBookmarkRemoved => '已取消收藏该章';

  @override
  String get readerImageFavorite => '图片收藏';

  @override
  String get readerFavoriteImage => '收藏此图';

  @override
  String get imageFavoriteAdded => '已收藏此图';

  @override
  String get imageFavoriteRemoved => '已取消收藏此图';

  @override
  String get imageFavoriteAdd => '收藏到图库';

  @override
  String get imageFavoriteSourceComic => '漫画';

  @override
  String get imageFavoriteSourcePlayer => '媒体';

  @override
  String get imageFavoriteSourceNovel => '小说';

  @override
  String get imageFavoriteAll => '全部';

  @override
  String get imageFavoriteSearchHint => '搜索标题 / 作品 / 链接';

  @override
  String get imageFavoriteSortNewest => '最新';

  @override
  String get imageFavoriteSortOldest => '最早';

  @override
  String get imageFavoriteSortTitle => '按标题';

  @override
  String imageFavoriteCount(Object count) {
    return '$count 张';
  }

  @override
  String get imageFavoriteNoMatch => '无匹配收藏';

  @override
  String get imageFavoriteFilter => '筛选分类';

  @override
  String get imageFavoriteTimeAll => '全部时间';

  @override
  String get imageFavoriteTimeToday => '今天';

  @override
  String get imageFavoriteTimeWeek => '本周';

  @override
  String get imageFavoriteTimeMonth => '本月';

  @override
  String get imageFavoriteTimeYear => '今年';

  @override
  String get imageFavoriteTimeOlder => '更早';

  @override
  String get imageFavoriteLayoutGrid => '网格';

  @override
  String get imageFavoriteLayoutMasonry => '瀑布流';

  @override
  String get imageFavoriteGroupByWork => '按作品';

  @override
  String get imageFavoriteDisplayOptions => '显示与排序';

  @override
  String get imageFavoriteShowTitle => '显示标题';

  @override
  String get imageFavoriteShowTime => '显示时间';

  @override
  String get imageFavoriteRename => '重命名标题';

  @override
  String get imageFavoriteRenamed => '已重命名';

  @override
  String get imageFavoriteTitleHint => '新标题';

  @override
  String get imageFavoriteAllFolders => '全部';

  @override
  String get backToFolders => '返回文件夹';

  @override
  String get imageFavoriteFiltersToggle => '收起 / 展开筛选';

  @override
  String get imageFavoriteUnfiled => '未分类';

  @override
  String get imageFavoriteNewFolder => '新建文件夹';

  @override
  String get imageFavoriteFolderHint => '文件夹名称';

  @override
  String get imageFavoriteDeleteFolder => '删除文件夹';

  @override
  String imageFavoriteDeleteFolderConfirm(Object folder) {
    return '删除文件夹 $folder？其中图片将回到未分类';
  }

  @override
  String imageFavoriteSelected(Object count) {
    return '已选 $count 张';
  }

  @override
  String get imageFavoriteSelectAll => '全选';

  @override
  String get imageFavoriteMoveTo => '移动到文件夹';

  @override
  String get imageFavoriteMoved => '已移动';

  @override
  String imageFavoriteDeleteMulti(Object count) {
    return '确定删除选中的 $count 张图片？';
  }

  @override
  String get imageFavoriteRenameSingle => '请仅选择一张进行重命名';

  @override
  String get imageFavoriteGalleryDesc => '漫画截图、播放器截图与小说插图的统一图库（文件夹/多选管理）';

  @override
  String get readingQueueTitle => '待读队列';

  @override
  String get readingQueueAdd => '加入待读队列';

  @override
  String get readingQueueAdded => '已加入待读队列';

  @override
  String get readingQueueOpen => '待读队列';

  @override
  String get readingQueueEmpty => '待读队列为空\n在作品菜单或书架长按中添加入队';

  @override
  String get readingQueueClear => '清空';

  @override
  String readingQueueLoading(Object title) {
    return '正在打开 $title…';
  }

  @override
  String get readingQueueLoadFailed => '打开待读作品失败';

  @override
  String get readingQueueTypeNovel => '小说';

  @override
  String get readingQueueTypeComic => '漫画';

  @override
  String readerClockBatteryPercent(int percent) {
    return '$percent%';
  }

  @override
  String get comicDefaultFullscreen => '全屏';

  @override
  String get comicDefaultLongPressMenu => '长按菜单';

  @override
  String get comicDefaultGrayscale => '灰度';

  @override
  String get comicDefaultPreventShrink => '防止缩小';

  @override
  String get comicDefaultChapterTransition => '章节过渡';

  @override
  String get copyImage => '复制图片';

  @override
  String get copyImageSuccess => '图片已复制到剪贴板';

  @override
  String get copyImageFailed => '图片复制失败';

  @override
  String chapterTransitionCard(Object title) {
    return '章节：$title';
  }

  @override
  String get readerProgress => '进度';

  @override
  String get regexSearch => '正则';

  @override
  String get locateCurrent => '定位当前';

  @override
  String get scrollToTop => '置顶';

  @override
  String get scrollToBottom => '置底';

  @override
  String get bookmarkedHint => '已加书签';

  @override
  String get playerFullscreen => '全屏';

  @override
  String get playerExitFullscreen => '退出全屏';

  @override
  String get playerScreenshot => '截图';

  @override
  String get playerBrightness => '亮度';

  @override
  String get playerVolume => '音量';

  @override
  String get playerSuperRes => '超分辨率';

  @override
  String get playerLine => '播放线路';

  @override
  String get playerSelectLine => '选择线路';

  @override
  String get playerLineEmpty => '暂无播放线路（解析失败或源未提供视频地址）';

  @override
  String get playerLineSingleHint =>
      '当前源只返回了 1 条线路，无法切换。\n如需多线路切换，请联系源作者在视频解析 API 中返回 urls 数组。';

  @override
  String playerLineEpisodesProgress(int current, int total) {
    return '第 $current / $total 集';
  }

  @override
  String get playerEpisodes => '选集';

  @override
  String get playerPip => '画中画';

  @override
  String get playerCast => '投屏';

  @override
  String get playerMore => '更多';

  @override
  String get seekForward10 => '快进 10 秒';

  @override
  String get seekBackward10 => '快退 10 秒';

  @override
  String get playerSeekCancel => '已取消快进';

  @override
  String get playerSkipOpEd => '跳过片头/片尾';

  @override
  String get playerSkipOp => '跳过片头';

  @override
  String get playerSkipEd => '跳过片尾';

  @override
  String get playerSkipOpEndLabel => '片头结束（分:秒）';

  @override
  String get playerSkipEdStartLabel => '片尾开始（分:秒）';

  @override
  String get playerSkipUseCurrent => '用当前时间';

  @override
  String get playerSkipAuto => '自动跳过';

  @override
  String get playerSkipHint => '留空表示不启用；设置对该作品的全部剧集生效。';

  @override
  String get novelReadingSummary => '阅读速览';

  @override
  String get novelParagraphTranslate => '段落翻译';

  @override
  String get novelTranslateAction => '翻译本章';

  @override
  String get novelTranslateRetranslate => '重新翻译';

  @override
  String get translationStaleNotice => '原文、术语表或翻译风格已更新，当前缓存译文可能过期。';

  @override
  String get translationRefinedMode => '精译模式（三稿合成，约 4× token）';

  @override
  String novelTranslateProgress(String done, String total) {
    return '已译 $done 段';
  }

  @override
  String get novelTranslateNoApi => '翻译失败——请先在「阅读速览」中配置云端 AI 接口';

  @override
  String get novelTranslating => '正在翻译…';

  @override
  String get novelTranslateHint => '点按「翻译本章」生成本章双语对照译文';

  @override
  String get novelContentEdit => '内容编辑';

  @override
  String get novelContentEditHint =>
      '每段一段；@@NEXHUB_IMG@@ 开头行为插图，@@NEXHUB_TITLE@@ 前缀标记章节标题';

  @override
  String get novelContentEditSaved => '本章内容已更新';

  @override
  String get novelContentEditEmpty => '内容为空，未保存';

  @override
  String get novelContentEditBadge => '已编辑';

  @override
  String get novelContentEditRestore => '恢复原文';

  @override
  String get novelContentEditRestoreConfirm => '放弃对本章的修改并恢复为源站原文？';

  @override
  String get novelContentEditRestored => '已恢复原文';

  @override
  String novelSummaryProgress(int read, int total) {
    return '进度：读到第 $read / $total 章';
  }

  @override
  String get novelSummaryTotalRead => '累计阅读';

  @override
  String get novelSummaryToday => '今日阅读';

  @override
  String novelSummarySessionsValue(int count) {
    return '$count 次';
  }

  @override
  String novelSummaryRemaining(String duration) {
    return '预计读完还需 $duration';
  }

  @override
  String novelSummaryCurrentChars(int count) {
    return '本章 $count 字';
  }

  @override
  String novelDurationHourMin(int h, int m) {
    return '$h 小时 $m 分';
  }

  @override
  String novelDurationHour(int h) {
    return '$h 小时';
  }

  @override
  String novelDurationMin(int m) {
    return '$m 分钟';
  }

  @override
  String get novelSummaryNoStats => '暂无阅读统计';

  @override
  String novelSummaryPosition(String chapter, int page, int pages) {
    return '当前：$chapter · 第 $page/$pages 页';
  }

  @override
  String get playerAutoPlayCountdown => '自动连播倒计时';

  @override
  String get playerCountdownImmediate => '立即';

  @override
  String playerAutoNextCountdown(int left) {
    return '$left 秒后播放下一集';
  }

  @override
  String get novelTitleAlignLeft => '左对齐';

  @override
  String get novelTitleAlignCenter => '居中';

  @override
  String get novelTitleAlignRight => '右对齐';

  @override
  String get novelTitleAlignHidden => '隐藏';

  @override
  String get novelSectionToolbar => '底部工具栏';

  @override
  String get novelSectionTts => '朗读设置';

  @override
  String get ttsRate => '朗读语速';

  @override
  String get ttsPlaybackFailed => '朗读失败，请检查系统语音引擎';

  @override
  String get ttsSleepTimer => '睡眠定时';

  @override
  String get ttsSleepOff => '关闭';

  @override
  String get ttsSleepCustom => '自定义';

  @override
  String get ttsSleepCustomMinutes => '自定义分钟数';

  @override
  String ttsSleepRemaining(int min, int sec) {
    return '剩余 $min 分 $sec 秒';
  }

  @override
  String get ttsPrevSentence => '上一句';

  @override
  String get ttsPauseOrResume => '暂停 / 继续';

  @override
  String get ttsExit => '退出朗读';

  @override
  String get ttsNextSentence => '下一句';

  @override
  String minuteUnit(int minutes) {
    return '$minutes 分钟';
  }

  @override
  String get novelFontFileGroup => '字体文件与强调色';

  @override
  String get novelChooseFontFile => '正文字体文件';

  @override
  String get novelTitleFontFile => '标题字体文件';

  @override
  String get novelResetConfirm => '确定要将所有小说阅读设置恢复为默认吗？此操作不可恢复。';

  @override
  String get novelSettingsSearch => '搜索设置';

  @override
  String get novelSettingsCommon => '常用';

  @override
  String get novelSettingsNoResult => '无匹配的设置项';

  @override
  String novelFontFileCurrent(String name) {
    return '已选：$name';
  }

  @override
  String get novelClearFontFile => '清除字体文件';

  @override
  String get novelEmphasisColor => '强调色';

  @override
  String get novelEmphasisColorAuto => '自动（标题色）';

  @override
  String get novelSectionShadowUnderline => '阴影与下划线';

  @override
  String get novelShadowBlur => '阴影模糊半径';

  @override
  String get novelShadowOffsetX => '阴影水平偏移';

  @override
  String get novelShadowOffsetY => '阴影垂直偏移';

  @override
  String get novelUnderlineColor => '下划线颜色';

  @override
  String get novelUnderlineColorAuto => '自动（正文色）';

  @override
  String get novelUnderlineDashed => '虚线下划线';

  @override
  String get novelUnderlineStyle => '下划线样式';

  @override
  String get novelUnderlineStyleSolid => '实线';

  @override
  String get novelUnderlineStyleDashed => '虚线';

  @override
  String get novelUnderlineStyleWavy => '波浪线';

  @override
  String get novelUnderlineStyleDotted => '点线';

  @override
  String get novelFontWeightFine => '加粗字重（100-900）';

  @override
  String get novelTextAlignMode => '对齐方式';

  @override
  String get novelTextAlignStart => '自然（左对齐）';

  @override
  String get novelTextAlignJustify => '两端对齐';

  @override
  String get novelLineBreakMode => '中文断行';

  @override
  String get novelLineBreakStandard => '原生折行';

  @override
  String get novelLineBreakCjkStrict => '逐字断行+禁则';

  @override
  String get novelScrollImageMode => '滚动插图样式';

  @override
  String get novelScrollImageModeBanner => '通栏';

  @override
  String get novelScrollImageModeCard => '卡片式';

  @override
  String get novelScrollImageAlign => '插图对齐';

  @override
  String get novelScrollImageAlignLeft => '靠左';

  @override
  String get novelScrollImageAlignCenter => '居中';

  @override
  String get novelScrollImageAlignRight => '靠右';

  @override
  String get novelUnderlineThickness => '下划线线宽';

  @override
  String get novelUnderlineDashLength => '实线段长';

  @override
  String get novelUnderlineDashGap => '间隙比例';

  @override
  String get novelTitlePosition => '标题显示位置';

  @override
  String get novelTitleSegmentMode => '标题分段模式';

  @override
  String get novelTitleSubScale => '次行字号倍率';

  @override
  String get novelTitleSegmentSpacing => '主次行间距';

  @override
  String get novelTitleSubLineSpacing => '次行行距';

  @override
  String get novelTitleTopMargin => '标题上边距';

  @override
  String get novelTitleBottomMargin => '标题下边距';

  @override
  String get novelSectionHeaderFooter => '页眉页脚';

  @override
  String get novelHeaderLeft => '页眉左侧';

  @override
  String get novelHeaderCenter => '页眉中间';

  @override
  String get novelHeaderRight => '页眉右侧';

  @override
  String get novelFooterLeft => '页脚左侧';

  @override
  String get novelFooterCenter => '页脚中间';

  @override
  String get novelFooterRight => '页脚右侧';

  @override
  String get novelHeaderFooterColor => '页眉页脚颜色';

  @override
  String get novelHeaderFooterMargin => '页眉页脚边距';

  @override
  String get novelHfPageAndProgress => '页码及进度';

  @override
  String get novelHfBookPageNumber => '整本页码';

  @override
  String get novelTwoPageMode => '双页模式';

  @override
  String get novelAiIllustrate => 'AI 配图';

  @override
  String get novelAiIllustrateConfirm => '使用已配置的云端 AI 为本章生成一张插图，并追加到本章内容？';

  @override
  String get novelAiIllustrating => '正在生成插图…';

  @override
  String get novelAiIllustrateDone => '插图已追加到本章';

  @override
  String get novelAiIllustrateFailed => '配图失败';

  @override
  String get novelTwoPageModeDesc => '翻页模式下宽屏左右并排显示两页，如摊开的实体书';

  @override
  String get novelHfTimeAndBattery => '时间及电量';

  @override
  String get layoutDetailGroup => '布局细节';

  @override
  String get layoutProgressDisplay => '进度显示方式';

  @override
  String get progressBar => '进度条';

  @override
  String get progressText => '百分比';

  @override
  String get editRoute => '修改路由';

  @override
  String get routeTitle => '标题';

  @override
  String get routeUrl => '地址';

  @override
  String get routeSaved => '路由已保存';

  @override
  String get requiredHint => '此项为必填';

  @override
  String get localImportPickFile => '选择本地文件';

  @override
  String get sourceName => '名称';

  @override
  String get sourceBaseUrl => '基础地址';

  @override
  String get sourceCannotEdit => '内置源不可编辑';

  @override
  String get sourceCannotDelete => '内置源不可删除';

  @override
  String get comicVisualZoomGroup => '画面与缩放';

  @override
  String get comicPageProgressGroup => '页面与进度';

  @override
  String get generalSettingsGroup => '通用';

  @override
  String get playbackProgressGroup => '播放进度';

  @override
  String get playbackModulesSection => '各模块设置';

  @override
  String get settingsCatAppearance => '外观与语言';

  @override
  String get settingsCatAppearanceDesc => '主题、配色、深浅模式与语言';

  @override
  String get settingsCatPlayback => '播放与阅读';

  @override
  String get settingsCatPlaybackDesc => '播放器、漫画、小说与弹幕显示';

  @override
  String get settingsCatContent => '配置与网络';

  @override
  String get settingsCatContentDesc => '源管理、RSS 订阅、网页爬取、AI 与网络设置';

  @override
  String get settingsCatDetailAppearance => '详情页外观';

  @override
  String get settingsCatDetailAppearanceDesc => '封面取色与模糊背景';

  @override
  String get detailAppearanceDynamicAccent => '封面动态强调色';

  @override
  String get detailAppearanceDynamicAccentDesc => '根据封面或获取的图片自动提取详情页强调色';

  @override
  String get detailAppearanceBlurredBg => '封面模糊背景';

  @override
  String get detailAppearanceBlurredBgDesc =>
      '页面白色背景替换为封面或获取的图片并高斯模糊，关闭时保持白色背景';

  @override
  String get detailAppearanceBlurStrength => '模糊强度';

  @override
  String get detailAppearanceLeftSwipe => '左滑动作';

  @override
  String get detailAppearanceLeftSwipeDesc => '详情页章节列表中向左滑动章节条目时执行';

  @override
  String get detailAppearanceRightSwipe => '右滑动作';

  @override
  String get detailAppearanceRightSwipeDesc => '详情页章节列表中向右滑动章节条目时执行';

  @override
  String get swipeActionDownload => '下载';

  @override
  String get swipeActionBookmark => '书签';

  @override
  String get swipeActionRead => '已读';

  @override
  String get aiSettingsTitle => 'AI 配置';

  @override
  String get aiSettingsDesc => '统一管理 AI 接口与智能功能（速览 / 配图 / 翻译）';

  @override
  String get aiCommonApiSection => '通用 API 配置';

  @override
  String get aiCommonApiDesc => '所有 AI 功能的兜底接口；某功能单独配置后会优先使用其专用接口';

  @override
  String get aiBaseUrl => '接口地址';

  @override
  String get aiBaseUrlHint => '如 https://api.openai.com/v1';

  @override
  String get aiApiKey => 'API 密钥';

  @override
  String get aiModel => '模型';

  @override
  String get aiModelHint => '如 gpt-3.5-turbo';

  @override
  String get aiOverrideHint => '留空则使用通用配置';

  @override
  String get aiSummarySection => '章节速览';

  @override
  String get aiSummaryDesc => '速览方式与独立接口（留空则用通用配置）';

  @override
  String get aiSummaryMode => '速览方式';

  @override
  String get aiIllustrationSection => 'AI 配图';

  @override
  String get aiIllustrationDesc => '章节配图独立接口与生图选项（留空则用通用配置）';

  @override
  String get aiIllustrationModel => '生图模型';

  @override
  String get aiIllustrationModelHint => '留空则由服务端决定';

  @override
  String get aiIllustrationSize => '图片尺寸';

  @override
  String get aiSaved => 'AI 配置已保存';

  @override
  String get aiSettingsEntry => 'AI 配置';

  @override
  String get aiSettingsEntryDesc => '统一管理 AI 接口、章节速览、AI 配图与双语翻译';

  @override
  String get translationSettingsTitle => '双语/段落翻译';

  @override
  String get translationSettingsDesc => '翻译目标语言、接口与选项';

  @override
  String get translationApiSection => '翻译接口';

  @override
  String get translationApiDesc => '翻译专用接口；留空则用通用配置';

  @override
  String get translationTargetLang => '目标语言';

  @override
  String get translationTargetLangHint => '如 中文 / 英文 / 日文';

  @override
  String get translationBatchSize => '分块大小（段/块）';

  @override
  String get translationBatchHint => '整章请求失败后按此分块重试';

  @override
  String get translationSaved => '翻译配置已保存';

  @override
  String get translationSettingsEntry => '双语/段落翻译';

  @override
  String get translationSettingsEntryDesc => '翻译目标语言与接口配置';

  @override
  String get novelSectionAi => 'AI 功能';

  @override
  String get novelAiOpenSummary => '打开章节速览';

  @override
  String get novelAiOpenTranslation => '打开段落翻译';

  @override
  String get settingsCatData => '数据与账户';

  @override
  String get settingsCatDataDesc => '统计、备份、云同步与 Bangumi';

  @override
  String get settingsCatPrivacy => '隐私与安全';

  @override
  String get settingsCatPrivacyDesc => '隐私、高级设置与缓存清理';

  @override
  String get settingsCatAbout => '关于';

  @override
  String get settingsCatAboutDesc => '版本、许可与致谢';

  @override
  String get launchScreenTitle => '启动界面';

  @override
  String get dateFormatTitle => '日期格式';

  @override
  String get dateFormatDefault => '默认（yyyy/mm/dd）';

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
  String get comicSettingsOverview => '当前设置概览';

  @override
  String get comicResetConfirm => '确定要将所有漫画阅读设置恢复为默认吗？此操作不可恢复。';

  @override
  String get on => '开';

  @override
  String get off => '关';

  @override
  String get readerGroupPageTap => '翻页与点击';

  @override
  String get readerGroupViewFilter => '画面与滤镜';

  @override
  String get readerGroupProgress => '进度与显示';

  @override
  String get readerGroupFlash => '闪屏效果';

  @override
  String get readerGroupAuto => '自动（下载/跳章过滤）';

  @override
  String get readerGroupAutoDesc => '阅读中自动下载后续章节，以及下/上一章时跳过已读、被筛选或重复章节。';

  @override
  String get readerGroupOverlay => '浮层（时间/电量）';

  @override
  String get readerGroupOverlayDesc => '在阅读器显示当前时间与电量，并调节其位置、边距、透明度与字号。';

  @override
  String get readerGroupMulti => '多图与间距';

  @override
  String get readerGroupMultiDesc => '每屏多图、首屏单图与条漫页间距设置。';

  @override
  String get readerCommonSettings => '常用设置';

  @override
  String get readerGroupPageTapDesc => '调整翻页方式、屏幕方向、点击区域与缩放等基础阅读操作。';

  @override
  String get readerGroupViewFilterDesc => '调节亮度、对比度、色温与灰度等画面效果。';

  @override
  String get readerGroupProgressDesc => '控制页码、进度条、全屏、常亮与页面旋转等显示选项。';

  @override
  String get readerGroupFlashDesc => '设置翻页时的闪光提示效果（模拟翻页灯）。';

  @override
  String get readerSearchSettings => '搜索设置…';

  @override
  String get readerGroupMouseWheel => '鼠标滚轮';

  @override
  String get readerGroupMouseWheelDesc => '设置滚轮的作用（缩放页面或翻页）以及滚动方向。';

  @override
  String get readerWheelZoom => '缩放';

  @override
  String get readerWheelPage => '翻页';

  @override
  String get readerWheelAction => '作用';

  @override
  String get favoriteGroups => '收藏分组';

  @override
  String get noGroups => '暂无分组，点击下方按钮新建';

  @override
  String get groupAll => '全部';

  @override
  String get groupUngrouped => '未分组';

  @override
  String get manageGroups => '管理分组';

  @override
  String get newGroup => '新建分组';

  @override
  String get renameGroup => '重命名';

  @override
  String get renameHint => '请输入新名称';

  @override
  String get groupName => '分组名称';

  @override
  String get groupNameEmpty => '名称不能为空';

  @override
  String get groupNameDuplicate => '已存在同名分组';

  @override
  String get deleteGroup => '删除分组';

  @override
  String deleteGroupConfirm(Object name) {
    return '删除分组「$name」？仅解除条目与该分组的关联，收藏不受影响。';
  }

  @override
  String get setGroups => '设分组';

  @override
  String get filterByGroup => '分组';

  @override
  String groupItemCount(Object n) {
    return '$n 项';
  }

  @override
  String get hideCategory => '隐藏';

  @override
  String get showCategory => '显示';

  @override
  String get categoryHidden => '已隐藏';

  @override
  String get noGroupsHint => '还没有分类，点「新建分组」创建一个';

  @override
  String get comments => '评论';

  @override
  String commentsCount(Object n) {
    return '评论 ($n)';
  }

  @override
  String get writeComment => '写评论';

  @override
  String get replyComment => '回复';

  @override
  String get viewAllComments => '查看全部评论';

  @override
  String get allCommentsTitle => '全部评论';

  @override
  String get emptyComments => '暂无评论';

  @override
  String get beFirstToComment => '发表第一条评论';

  @override
  String get commentPublish => '发布';

  @override
  String get commentHint => '说点什么…';

  @override
  String get commentPublishSuccess => '评论已发布';

  @override
  String get commentPublishFailed => '发布失败';

  @override
  String get likeAction => '点赞';

  @override
  String get likeFailed => '点赞失败';

  @override
  String get reportAction => '举报';

  @override
  String get reportSuccess => '已举报';

  @override
  String get reportFailed => '举报失败';

  @override
  String get viewMoreReplies => '查看更多回复';

  @override
  String get commentsLoadFailed => '评论加载失败';

  @override
  String get loginToComment => '登录后评论';

  @override
  String get loginRequired => '该操作需要登录';

  @override
  String get sourceLogin => '源登录';

  @override
  String get getCookie => '获取 Cookie';

  @override
  String get cookieNotFoundHint => '未检测到登录 Cookie，请确认已登录后重试';

  @override
  String get webLogin => '网页登录';

  @override
  String get webLoginDesc => '在站点页面完成登录，自动捕获会话';

  @override
  String get pasteCookie => '粘贴 Cookie';

  @override
  String get pasteCookieDesc => '手动粘贴浏览器中的 Cookie 头';

  @override
  String get cookieHint => '如 token=abc; session=xyz';

  @override
  String get loginSuccess => '登录成功';

  @override
  String get loginExpired => '登录已失效，请重新登录';

  @override
  String get logoutAction => '退出登录';

  @override
  String get loggedInState => '已登录';

  @override
  String get loginDone => '完成';

  @override
  String get webviewLoginUnsupported => '当前平台不支持内置网页登录，请使用「粘贴 Cookie」方式。';

  @override
  String get apiKeyTitle => 'API Key';

  @override
  String get apiKeyHint => '在源站账户设置页复制 API Key（收藏等受保护请求需要）。';

  @override
  String get apiKeyPlaceholder => '粘贴 API Key';

  @override
  String get apiKeySave => '保存并校验';

  @override
  String get apiKeyValid => 'API Key 有效';

  @override
  String get apiKeyInvalid => 'API Key 无效，请检查后重试';

  @override
  String get bangumiSettings => 'Bangumi 同步';

  @override
  String get bangumiSettingsSubtitle => '推送收藏与进度到 bgm.tv';

  @override
  String get bangumiRatingSync => 'Bangumi 评分与同步';

  @override
  String get bangumiAccount => '账号';

  @override
  String get bangumiTokenHint => '粘贴个人 Access Token';

  @override
  String get bangumiTokenVerify => '验证并保存';

  @override
  String get bangumiGetToken => '获取 Token';

  @override
  String bangumiLoggedInAs(String name) {
    return '已登录：$name';
  }

  @override
  String get bangumiTokenSaved => 'Token 验证成功';

  @override
  String get bangumiTokenInvalid => 'Token 无效，请检查后重试';

  @override
  String get bangumiNotLoggedIn => '未登录';

  @override
  String get bangumiSyncNow => '立即同步';

  @override
  String get bangumiSyncDone => '同步完成';

  @override
  String get bangumiSyncFailed => '同步失败';

  @override
  String bangumiLastSync(String time) {
    return '上次同步：$time';
  }

  @override
  String get bangumiNeverSynced => '尚未同步';

  @override
  String get bangumiSyncTypes => '同步类型';

  @override
  String get bangumiSyncTypeAnime => '动漫与影视';

  @override
  String get bangumiSyncTypeManga => '漫画';

  @override
  String get bangumiSyncTypeNovel => '小说';

  @override
  String get bangumiSyncLog => '同步日志';

  @override
  String get bangumiLogSuccess => '已同步';

  @override
  String get bangumiLogSkipped => '跳过（无变化）';

  @override
  String get bangumiLogFailed => '失败';

  @override
  String get bangumiPendingBind => '待手动绑定';

  @override
  String get bangumiBindAndRate => 'Bangumi 绑定与评分';

  @override
  String get bangumiBindSubject => '绑定 Bangumi 条目';

  @override
  String get bangumiSearchHint => '搜索 Bangumi 条目';

  @override
  String get bangumiNoResults => '无匹配条目';

  @override
  String bangumiBoundTo(int id) {
    return '已绑定条目 #$id';
  }

  @override
  String get bangumiUnbind => '解除绑定';

  @override
  String get bangumiMarkCollected => '标记为看过';

  @override
  String get bangumiMyRating => '我的评分';

  @override
  String get bangumiRatingNone => '未评分';

  @override
  String get bangumiMyComment => '我的短评';

  @override
  String get bangumiCommentHint => '写点短评（将同步到 Bangumi）';

  @override
  String get bangumiSaved => '已保存';

  @override
  String get bangumiSyncOptions => '同步选项';

  @override
  String get bangumiPrivateCollection => '新收藏设为私有';

  @override
  String get bangumiPrivateCollectionHint => '仅影响新创建的收藏，不改动远端已有收藏';

  @override
  String get bangumiTagsSync => '收藏分组推送为标签';

  @override
  String get bangumiTagsSyncHint => '与远端标签合并，不丢失在 Bangumi 手动添加的标签';

  @override
  String get bangumiImport => '从 Bangumi 导入';

  @override
  String bangumiImportDone(int count) {
    return '导入完成：已绑定 $count 项';
  }

  @override
  String get bangumiForcedState => '同步状态覆盖';

  @override
  String get bangumiStateAuto => '自动判定';

  @override
  String get bangumiStateWish => '想看';

  @override
  String get bangumiStateDoing => '在看';

  @override
  String get bangumiStateCollect => '看过';

  @override
  String get bangumiStateOnHold => '搁置';

  @override
  String get bangumiStateDropped => '抛弃';

  @override
  String get bangumiPullFromRemote => '从 Bangumi 拉取';

  @override
  String get bangumiPullDone => '已拉取远端评分与短评';

  @override
  String get bangumiPullEmpty => '远端暂无该条目收藏';

  @override
  String get backupCategorySource => '源与订阅';

  @override
  String get backupCategoryBookmark => '收藏与书签';

  @override
  String get backupCategoryProgress => '进度与历史';

  @override
  String get backupCategorySettings => '设置与偏好';

  @override
  String get backupCategoryDownload => '下载任务';

  @override
  String get backupCategoryDanmaku => '弹幕缓存';

  @override
  String get backupCategoryOther => '其它';

  @override
  String get backupSelectScope => '选择备份内容';

  @override
  String get backupSelectAll => '全选';

  @override
  String get backupMerge => '合并（保留本地）';

  @override
  String get backupReplace => '覆盖（以备份为准）';

  @override
  String get backupMergeDesc => '把备份内容并入本地，本地已有的数据保留，同名项以备份覆盖';

  @override
  String get backupReplaceDesc => '用备份完全替换本地对应数据，此操作不可恢复';

  @override
  String get backupImportMode => '恢复方式';

  @override
  String get backupScopeNone => '请至少选择一类要备份的数据';

  @override
  String backupPreviewTitle(Object count) {
    return '即将恢复 $count 项数据';
  }

  @override
  String backupExported(Object count) {
    return '已导出备份（$count 项）';
  }

  @override
  String get pullNow => '从云端恢复';

  @override
  String get cloudSyncPullMode => '恢复方式';

  @override
  String get cloudSyncErrorNoConfig => '未配置 WebDAV，请先填写地址、账号与密码';

  @override
  String get cloudSyncErrorNoRemote => '云端没有可用的备份文件';

  @override
  String get cloudSyncErrorEncode => '打包备份失败，请重试';

  @override
  String get cloudSyncErrorNetwork => '网络错误，请检查 WebDAV 地址与网络连接';

  @override
  String cloudSyncErrorUnknown(Object detail) {
    return '同步出错：$detail';
  }

  @override
  String get cloudSyncStatusSection => '同步状态';

  @override
  String get cloudSyncStatusUpload => '上传备份';

  @override
  String get cloudSyncStatusRestore => '恢复数据';

  @override
  String get cloudSyncStatusSuccess => '成功';

  @override
  String get cloudSyncStatusFailed => '失败';

  @override
  String get cloudSyncStatusNoChanges => '无变化';

  @override
  String get cloudSyncStatusNotRun => '尚未执行';

  @override
  String cloudSyncStatusItems(Object count) {
    return '共 $count 项';
  }

  @override
  String cloudSyncNextSync(Object time) {
    return '下次自动同步：$time';
  }

  @override
  String get cloudSyncResolveConflicts => '解决冲突';

  @override
  String get cloudSyncConflictTitle => '同步冲突';

  @override
  String get cloudSyncConflictNone => '本地与云端没有冲突';

  @override
  String get cloudSyncConflictIntro => '下列分类在本地与云端版本不同，请为每个分类选择保留哪一侧：';

  @override
  String get cloudSyncConflictUseRemote => '使用云端';

  @override
  String get cloudSyncConflictKeepLocal => '保留本地';

  @override
  String get cloudSyncConflictMerge => '合并';

  @override
  String cloudSyncConflictCount(Object count) {
    return '$count 处冲突';
  }

  @override
  String get cloudSyncConflictLocal => '本地';

  @override
  String get cloudSyncConflictRemote => '云端';

  @override
  String get cloudSyncConflictApply => '应用并恢复';

  @override
  String get cloudSyncConflictLoading => '正在分析冲突…';

  @override
  String get bangumiSyncThis => '同步到 Bangumi';

  @override
  String get syncWorking => '正在同步到 Bangumi…';

  @override
  String get syncBusy => '正在同步中，请稍候';

  @override
  String get bangumiFavoriteFirst => '收藏后即可评分与短评';

  @override
  String get bangumiCollectionStatus => 'Bangumi 收藏状态';

  @override
  String get bangumiBindFirst => '请先绑定 Bangumi 条目';

  @override
  String get bangumiSiteRating => 'Bangumi 评分';

  @override
  String get bangumiSyncSettings => '同步设置';

  @override
  String get bangumiBindToViewRating => '绑定条目后查看 Bangumi 评分与评价';

  @override
  String bangumiRatingUsers(int count) {
    return '$count 人评分';
  }

  @override
  String bangumiRank(int rank) {
    return '排名 #$rank';
  }

  @override
  String get bangumiSummary => '简介';

  @override
  String get bangumiTags => '标签';

  @override
  String get bangumiNoRating => '暂无评分';

  @override
  String get bangumiLoadFailed => '加载失败';

  @override
  String get bangumiViewOnWeb => '在 Bangumi 打开';

  @override
  String get bangumiBrowseCollection => '浏览 Bangumi 收藏';

  @override
  String get bangumiCollectionEmpty => '该状态下暂无条目';

  @override
  String get bangumiSubjectTypeAnime => '动画';

  @override
  String get bangumiSubjectTypeBook => '书籍';

  @override
  String get bangumiSubjectTypeReal => '三次元';

  @override
  String get bangumiLoginWithOAuth => '使用 Bangumi 登录';

  @override
  String get bangumiOauthHint => '更安全的授权方式：在浏览器中完成 Bangumi 授权后自动返回应用。';

  @override
  String get bangumiOauthNotConfigured =>
      '尚未配置 OAuth：请在 Bangumi 开放平台创建应用并填入 Client ID / Secret。';

  @override
  String get bangumiOauthFailed => 'Bangumi 授权失败，请重试。';

  @override
  String get networkSettingsTitle => '网络设置';

  @override
  String get networkSettingsDesc => '代理、DNS、DoH/DoT、SNI、ECH 与 Hosts';

  @override
  String get networkInfoTitle => '关于网络设置';

  @override
  String get networkInfoBody =>
      '全局设置对应用内所有 HTTP 流量生效（封面、下载、同步、抓取）。原生组件（网页视图、播放器、投屏）走原生栈，不受影响。源级覆盖仅作用于该源的抓取。';

  @override
  String get networkHelpDoc => '帮助与文档';

  @override
  String get networkExperimentalNote => '实验性：受 Dart TLS 栈限制，可能无法在所有路径生效。';

  @override
  String get networkProxyTitle => '代理';

  @override
  String get networkProxyModeDirect => '直连';

  @override
  String get networkProxyModeSystem => '系统';

  @override
  String get networkProxyModeManual => '手动';

  @override
  String get networkProxyProtocolHttp => 'HTTP';

  @override
  String get networkProxyProtocolSocks5 => 'SOCKS5';

  @override
  String get networkProxyHost => '主机';

  @override
  String get networkProxyPort => '端口';

  @override
  String get networkProxyUsername => '用户名';

  @override
  String get networkProxyPassword => '密码';

  @override
  String get networkTestProxy => '测试代理';

  @override
  String networkTestSuccess(int ms) {
    return '成功（$ms 毫秒）';
  }

  @override
  String get networkTestFailed => '测试失败';

  @override
  String get networkDnsTitle => 'DNS';

  @override
  String get networkDnsModeSystem => '系统';

  @override
  String get networkDnsModeCustom => '自定义';

  @override
  String get networkDnsModeDoh => 'DoH';

  @override
  String get networkDnsModeDot => 'DoT';

  @override
  String get networkDnsServers => 'DNS 服务器';

  @override
  String get networkDnsServersEmpty => '未配置服务器';

  @override
  String get networkAddServer => '添加服务器';

  @override
  String get networkDnsCacheEnabled => '启用 DNS 缓存';

  @override
  String networkDnsCacheStatus(int count) {
    return '缓存条目：$count';
  }

  @override
  String get networkClearCache => '清理缓存';

  @override
  String get networkTestDns => '测试 DNS 解析';

  @override
  String get networkDnsTestHost => '待解析主机';

  @override
  String networkDnsTestResult(Object ips, int ms) {
    return '$ips（$ms 毫秒）';
  }

  @override
  String get networkDohTitle => 'DNS over HTTPS (DoH)';

  @override
  String get networkDohPreset => '预设';

  @override
  String get networkDohUrl => 'DoH 地址';

  @override
  String get networkTestDoh => '测试 DoH';

  @override
  String get networkDotTitle => 'DNS over TLS (DoT)';

  @override
  String get networkDotHost => 'DoT 主机';

  @override
  String get networkDotPort => 'DoT 端口';

  @override
  String get networkHostsTitle => '自定义 Hosts';

  @override
  String get networkHostsEmpty => '无 Hosts 条目';

  @override
  String get networkAddHost => '添加 Hosts 条目';

  @override
  String get networkHostsIp => 'IP 地址';

  @override
  String get networkHostsHost => '主机名';

  @override
  String get networkSniTitle => 'SNI';

  @override
  String get networkSniEnabled => '启用自定义 SNI';

  @override
  String get networkSniDefault => '默认 SNI 值';

  @override
  String get networkSniRuntimeNote =>
      '对 https 直连生效：默认 SNI 值作用于全部域名，填 - 表示免 SNI（握手不携带 server_name，可绕过按 SNI 的阻断，建议配合自定义 Hosts 钉定可达 IP）；下方域名映射可按站点覆盖默认值。经代理连接时不生效。';

  @override
  String get networkSniDomainTitle => '域名 → SNI 映射';

  @override
  String get networkSniDomainEmpty => '无映射条目';

  @override
  String get networkSniAddDomain => '添加 SNI 映射';

  @override
  String get networkSniDomainHost => '匹配域名（.example.com 为后缀通配）';

  @override
  String get networkSniDomainValue => 'SNI 值（- 为免 SNI）';

  @override
  String get networkSniTestHost => '待测试主机';

  @override
  String get networkTestSni => '测试 SNI 握手';

  @override
  String networkSniTestResult(String name, int ms) {
    return '$name（$ms 毫秒）';
  }

  @override
  String get networkEchTitle => 'ECH（加密客户端问候）';

  @override
  String get networkEchEnabled => '启用 ECH';

  @override
  String get networkEchConfigList => 'ECH 配置列表（base64）';

  @override
  String get networkEchRuntimeNote =>
      '应用内直连默认走 Dart TLS 栈，无法启用 ECH。开启后，请求改经应用内置的 ECH 本地代理转发，由原生 TLS 栈完成 ECH 握手；不支持 ECH 的站点会自动回落为直连，不影响正常访问。填写「ECH 配置列表」则直接使用你提供的配置；留空时由代理自动获取。';

  @override
  String get networkReset => '恢复默认网络设置';

  @override
  String get networkResetTitle => '恢复默认网络设置';

  @override
  String get networkResetConfirm => '将所有网络设置恢复为默认值？';

  @override
  String get networkResetDone => '已恢复默认网络设置';

  @override
  String get networkSaved => '网络设置已保存';

  @override
  String get networkCacheCleared => '已清理 DNS 缓存';

  @override
  String get networkErrorInvalidHost => '主机无效';

  @override
  String get networkErrorInvalidPort => '端口无效（1-65535）';

  @override
  String get networkErrorInvalidIp => 'IP 地址无效';

  @override
  String get networkErrorInvalidDomain => '域名无效';

  @override
  String get networkErrorInvalidDohUrl => 'DoH 地址无效（必须为 https）';

  @override
  String get sourceNetworkOverride => '网络覆盖';

  @override
  String get sourceNetworkScopeNote =>
      '这些设置仅作用于该源的抓取，逐方面覆盖全局网络设置；未开启的方面继承全局配置。';

  @override
  String get sourceNetworkFromSourceNote =>
      '该源自带了网络配置，已自动沿用，无需重新配置；如需调整可直接修改并保存为自定义覆盖。';

  @override
  String get networkOverrideEnable => '覆盖全局';

  @override
  String get networkInheritGlobal => '继承全局';

  @override
  String get sourceNetworkSaved => '源级网络覆盖已保存';

  @override
  String get sourceNetworkClear => '清除覆盖';

  @override
  String get sourceNetworkClearConfirm => '移除该源的网络覆盖并继承全局设置？';

  @override
  String get sourceNetworkClearConfirmFromSource =>
      '该源自带了网络配置，清除自定义覆盖后将恢复为源自带配置（而非全局设置）。确定继续？';

  @override
  String get sourceNetworkCleared => '源级网络覆盖已清除';

  @override
  String get sourceNetworkClearedToSource => '已清除自定义覆盖，该源恢复为源自带网络配置';

  @override
  String get bangumiNoMatch => '未在 Bangumi 找到匹配条目';

  @override
  String get bangumiManualBind => '手动搜索绑定';

  @override
  String get bangumiConfirmBind => '确认绑定以下条目';

  @override
  String get bangumiFromBangumi => '数据来自 Bangumi';

  @override
  String get bangumiHideCollection => '隐藏收藏';

  @override
  String get bangumiProgress => '进度（已看集/章）';

  @override
  String get bangumiSaveSync => '保存并同步';

  @override
  String get bangumiSavedLocal => '未登录：已保存到本地';

  @override
  String get websiteComments => '网站评论';

  @override
  String get bangumiComments => 'Bangumi 吐槽';

  @override
  String get bangumiCommentsEmpty => '暂无吐槽';

  @override
  String get bangumiCommentsLoadFailed => '吐槽加载失败';

  @override
  String bangumiGuessMatch(Object name) {
    return '疑似匹配：$name';
  }

  @override
  String bangumiEps(int count) {
    return '$count 话';
  }

  @override
  String bangumiAirDate(String date) {
    return '放送：$date';
  }

  @override
  String bangumiCollectionWish(int count) {
    return '$count 想看';
  }

  @override
  String bangumiCollectionDoing(int count) {
    return '$count 在看';
  }

  @override
  String bangumiCollectionCollect(int count) {
    return '$count 看过';
  }

  @override
  String get bangumiCharacters => '角色';

  @override
  String get bangumiRelated => '关联作品';

  @override
  String get bangumiCollectionStat => '收藏统计';

  @override
  String get bangumiProxyTitle => '连接模式';

  @override
  String get bangumiProxyDirect => '直连';

  @override
  String get bangumiProxyMirror => '镜像';

  @override
  String get bangumiProxyEch => 'ECH';

  @override
  String get bangumiProxyMainSite => '主站域名';

  @override
  String get bangumiProxyApi => 'API 域名';

  @override
  String get bangumiProxyImage => '图片域名';

  @override
  String get bangumiProxyHint => '镜像 / 反代模式下填写你的自建域名（不含路径）。留空则该类别仍走官方默认域名。';

  @override
  String get bangumiProxySaved => '代理设置已保存';

  @override
  String get bangumiEchProxyHint =>
      '仍连接官方域名，但 Bangumi 相关域名的请求由本地 ECH（加密客户端问候）代理透明接管并隐藏 SNI，无需任何配置。此模式若可用就没必要再考虑「镜像 / 反代」。需打包了原生 ECH 引擎的版本；没有引擎时无法开启此模式。';

  @override
  String get bangumiEchStatus => 'ECH 代理状态';

  @override
  String get bangumiEchUnavailable => 'ECH 本地代理启动失败，当前平台可能未打包原生引擎。';

  @override
  String bangumiEchProxyRunning(int port) {
    return '运行中（端口 $port）';
  }

  @override
  String get bangumiEchProxyIdle => '未运行';

  @override
  String get bangumiDetail => '详情';

  @override
  String get bangumiStaff => '制作人员';

  @override
  String get bangumiTapToExpand => '点击展开';

  @override
  String get bangumiSyncRating => '评分';

  @override
  String get bangumiSyncComment => '吐槽';

  @override
  String get bangumiSync => '同步';

  @override
  String get bangumiPublic => '公开';

  @override
  String get bangumiPrivate => '私密';

  @override
  String get bangumiSyncLoginHint => '请先在设置中登录 Bangumi';

  @override
  String get bangumiSyncSaved => '已保存';

  @override
  String get bangumiSyncWatchedEpisodes => '已看集数';

  @override
  String get bangumiSyncWatchedChapters => '已读章节';

  @override
  String get bangumiSyncProgressHint => '留空则自动同步本地进度';

  @override
  String get bangumiSyncExpandList => '选择具体集 / 章节';

  @override
  String get bangumiSyncCollapseList => '收起';

  @override
  String bangumiSyncChaptersTotal(Object count, Object unit) {
    return '共 $count $unit';
  }

  @override
  String bangumiSyncChaptersLoadedHint(Object count, Object unit) {
    return '已加载 $count $unit，可单独勾选';
  }

  @override
  String bangumiSyncNoEpisodeList(Object eps) {
    return 'Bangumi 未返回该条目的剧集列表（$eps），无法逐集勾选';
  }

  @override
  String bangumiSyncLoadEpisodesFailed(Object error) {
    return '加载剧集列表失败：$error';
  }

  @override
  String get bangumiSyncUnitEp => '集';

  @override
  String get bangumiSyncUnitVolume => '话';

  @override
  String get bangumiSyncUnitChapter => '章';

  @override
  String get bangumiSyncMyCompletion => '我的完成度';

  @override
  String get bangumiSyncUpdate => '更新';

  @override
  String get bangumiSyncAdvancedOptions => '高级选项';

  @override
  String get bangumiSyncAdvancedHint => '评分 / 吐槽 / 状态 / 公开私密';

  @override
  String get bangumiSyncChapLabel => 'Chap.';

  @override
  String get bangumiSyncVolLabel => 'Vol.';

  @override
  String get bangumiSyncIncrement => '+';

  @override
  String get bangumiSyncAnimeGridTitle => '章节';

  @override
  String get bangumiSyncAnimeGridHint => '点击格子标记已看 / 取消';

  @override
  String get bangumiSyncScheduleWeek => '周';

  @override
  String get bangumiSyncScheduleHour => '时';

  @override
  String get bangumiSyncScheduleMinute => '分';

  @override
  String get bangumiSyncScheduleTitle => '放送时间';

  @override
  String bangumiSyncPageOf(int current, int total) {
    return '$current / $total 页';
  }

  @override
  String get bangumiSyncUnknown => '??';

  @override
  String bangumiRatingValue(int count) {
    return '$count 分';
  }

  @override
  String get clear => '清除';

  @override
  String get mirrorAddCustom => '添加自定义镜像';

  @override
  String get mirrorName => '镜像名称';

  @override
  String get mirrorDomain => '域名';

  @override
  String get mirrorBaseUrl => '基址';

  @override
  String get mirrorCustom => '自定义';

  @override
  String get mirrorDelete => '删除';

  @override
  String get mirrorExtractFromPublish => '从发布页提取镜像';

  @override
  String get mirrorExtracting => '正在提取…';

  @override
  String get mirrorNoMirrorsExtracted => '未提取到可用镜像';

  @override
  String get mirrorImportSelected => '导入选中镜像';

  @override
  String get mirrorExtractFailed => '提取失败';

  @override
  String get mirrorAddInvalid => '基址必须以 http:// 或 https:// 开头';

  @override
  String get importLibraryTab => '库导入';

  @override
  String get libraryUrlHint => '输入源库订阅地址';

  @override
  String get fetchLibrary => '拉取';

  @override
  String get saveLibrary => '保存常用';

  @override
  String get libraryBookmarks => '源库';

  @override
  String get sourceNotLoggedIn => '未登录';

  @override
  String get novelThemeFollowApp => '跟随应用';

  @override
  String get novelThemeFollowDark => '始终夜间';

  @override
  String get novelThemeFollowLight => '始终日间';

  @override
  String get libraryEmpty => '暂无常用库地址';

  @override
  String get addLibraryTitle => '添加源库';

  @override
  String get libraryNameHint => '名称（可选）';

  @override
  String get subscribeLibrary => '订阅';

  @override
  String get fetchLibraryAndImport => '更新并导入';

  @override
  String get openHomepage => '打开主页';

  @override
  String get unsubscribeLibrary => '取消订阅';

  @override
  String unsubscribeLibraryConfirm(String name) {
    return '确定要取消订阅「$name」吗？';
  }

  @override
  String get viewLibrarySources => '查看源';

  @override
  String get librarySubscribeFailed => '订阅失败，请检查 URL';

  @override
  String libraryImportResult(int success, int total, int failed) {
    return '已导入 $success/$total 个源（$failed 失败）';
  }

  @override
  String libraryVersion(int lib, int installed) {
    return '库 v$lib · 已装 v$installed';
  }

  @override
  String get libraryNotInstalled => '未安装';

  @override
  String get libraryUpdate => '更新';

  @override
  String get libraryUpdateAll => '一键更新';

  @override
  String get libraryUpdateAvailable => '可更新';

  @override
  String get libraryUpdating => '更新中…';

  @override
  String get libraryUpdated => '已更新';

  @override
  String get libraryUpdateFailed => '更新失败';

  @override
  String get libraryAllUpToDate => '全部已是最新';

  @override
  String libraryAlreadyLatestCount(int count) {
    return '$count 个已是最新';
  }

  @override
  String get sourcePin => '置顶';

  @override
  String get sourceUnpin => '取消置顶';

  @override
  String get mirrorTestAll => '测速全部';

  @override
  String get sourceTypeOther => '其他';

  @override
  String get official => '官方';

  @override
  String get loginStatusLoggedIn => '已登录';

  @override
  String get loginStatusLoggedOut => '未登录';

  @override
  String get cookieInputHint => '粘贴该源的 Cookie 字符串';

  @override
  String get incognitoMode => '无痕模式';

  @override
  String get incognitoModeHint => '开启后不记录该源的浏览历史与搜索记录';

  @override
  String get incognitoModeOn => '已无痕';

  @override
  String get incognitoOnToast => '已开启无痕：该源不再记录浏览与搜索历史';

  @override
  String get incognitoOffToast => '已关闭无痕：该源恢复记录浏览历史';

  @override
  String get globalIncognito => '全局无痕浏览';

  @override
  String get globalIncognitoHint => '开启后所有源都不记录浏览历史与搜索记录（各源仍可单独在源管理中覆盖）';

  @override
  String get rememberPosition => '记住播放/阅读位置';

  @override
  String get rememberPositionHint => '开启后，重新打开动漫/漫画/小说会自动跳到上次观看的进度；关闭则每次从开头开始';

  @override
  String mirrorAutoAdded(Object count) {
    return '已从发布页自动添加 $count 个镜像';
  }

  @override
  String get sourceAnnouncementView => '查看详情';

  @override
  String get announcementDontShowAgain => '以后再不显示';

  @override
  String get announcementSettingsDesc => '查看历史公告与版本更新说明';

  @override
  String get announcementsEmpty => '暂无公告';

  @override
  String get appAnnouncement => '软件公告';

  @override
  String get appAnnouncementGotIt => '知道了';

  @override
  String get watchedThreshold => '已看阈值';

  @override
  String get watchedThresholdHint => '播放/阅读进度达到该百分比视为已看';

  @override
  String get watchedThresholdUnit => '%';

  @override
  String get onlineTabWebFavorite => '网络收藏';

  @override
  String get favoriteLocal => '本地收藏';

  @override
  String get favoriteLocalHint => '保存到本机';

  @override
  String get favoriteWeb => '加入网络收藏';

  @override
  String get favoriteWebHint => '收藏到源站账号（需联网）';

  @override
  String get favoriteWebRequiresLogin => '需先登录源站';

  @override
  String get webFavoriteDefaultFolder => '默认收藏夹';

  @override
  String get webFavoriteAdded => '已加入网络收藏';

  @override
  String get webFavoriteAddFailed => '加入网络收藏失败';

  @override
  String get ageRatingGeneral => '全年龄';

  @override
  String get ageRatingTeen => '青少年 (16+)';

  @override
  String get ageRatingMature => '成人 (18+)';

  @override
  String get ageRatingLabel => '年龄分级';

  @override
  String get ageRestrictionImportMatureBlocked =>
      '年龄限制已开启，无法导入成人（18+）源（请在设置中关闭年龄限制）';

  @override
  String ageBlockedManageHint(int count) {
    return '已隐藏 $count 个成人（18+）源（关闭年龄限制后可见）';
  }

  @override
  String ageBlockedImportHint(int count) {
    return '因年龄限制，$count 个成人（18+）源未导入';
  }

  @override
  String get ageRestriction => '年龄限制';

  @override
  String get ageRestrictionHint => '开启后隐藏成人（18+）分级的源';

  @override
  String get ageRestrictionDisclaimerTitle => '免责声明';

  @override
  String get ageRestrictionDisclaimerBody =>
      '关闭年龄限制即表示你已知晓：本应用可能会展示成人（18+）分级内容，包含明确的成人素材。你确认你已达到所在司法辖区法律规定的可观看此类内容的法定年龄，并自愿承担由此产生的全部后果。开发者不对第三方源提供的任何内容负责。请务必遵守当地法律法规。';

  @override
  String get ageRestrictionDisclaimerConfirm => '我已知晓并继续';

  @override
  String get ageRestrictionDisclaimerScrollHint => '请滚动阅读完全部免责内容后再确认';

  @override
  String ageRestrictionDisclaimerCounting(Object seconds) {
    return '还需等待 $seconds 秒';
  }

  @override
  String ageRestrictionDisclaimerWait(Object seconds) {
    return '确认（还需 $seconds 秒）';
  }

  @override
  String get comicSectionTapPage => '翻页与点击';

  @override
  String get comicSectionVisualFilter => '画面与滤镜';

  @override
  String get comicSectionProgress => '进度与显示';

  @override
  String get comicSectionFlash => '闪屏效果';

  @override
  String get comicSectionMouseWheel => '鼠标滚轮';

  @override
  String get comicReaderAutoSection => '自动（下载 / 跳章过滤）';

  @override
  String get comicReaderOverlaySection => '浮层（时间 / 电量）';

  @override
  String get comicReaderMultiImageSection => '多图 / 间距';

  @override
  String get statsOverviewTitle => '统计';

  @override
  String get statsSearchHint => '搜索记录';

  @override
  String get statsHeatmap => '热力图';

  @override
  String get statsSectionTrend => '趋势';

  @override
  String get statsTrend7d => '近 7 天';

  @override
  String get statsTrend30d => '近 30 天';

  @override
  String get statsTotalDuration => '总时长';

  @override
  String get statsWorkCount => '作品数';

  @override
  String get statsSessionCount => '会话次数';

  @override
  String get statsLastRead => '最后阅读';

  @override
  String get statsNoRecords => '暂无记录，去读点什么吧';

  @override
  String statsDurSec(int s) {
    return '$s 秒';
  }

  @override
  String statsDurHours(int h) {
    return '$h 小时';
  }

  @override
  String statsDurHm(int h, int m) {
    return '$h 时 $m 分';
  }

  @override
  String statsDurMs(int m, int s) {
    return '$m 分 $s 秒';
  }

  @override
  String get statsClearTitle => '清除统计';

  @override
  String statsClearBody(String name) {
    return '确定清除「$name」的全部统计记录？';
  }

  @override
  String get statsClearConfirm => '清除';

  @override
  String get statsPrevMonth => '上一月';

  @override
  String get statsNextMonth => '下一月';

  @override
  String statsHeatmapMonthYear(String y, String m) {
    return '$y 年 $m 月';
  }

  @override
  String get statsAll => '全部';

  @override
  String get statsHeatmapLess => '少';

  @override
  String get statsHeatmapMore => '多';

  @override
  String get statsHeatmapTotal => '本月合计';

  @override
  String get stats7dActive => '近 7 天活跃';

  @override
  String get stats30dActive => '近 30 天活跃';

  @override
  String get statsActiveDays => '活跃天数';

  @override
  String get statsAvgSession => '平均会话时长';

  @override
  String get statsMaxDaily => '最长单日';

  @override
  String get statsStreak => '当前连续';

  @override
  String get statsSectionOverview => '总览';

  @override
  String get statsSectionActivity => '活跃';

  @override
  String get statsSectionPace => '节奏';

  @override
  String get heatmapActiveDays => '活跃天数';

  @override
  String get heatmapMaxDaily => '最长单日';

  @override
  String get heatmapStreak => '当前连续';

  @override
  String get downloadAutoDelete => '读后自动删除';

  @override
  String get downloadAutoDeleteHint => '看完/读完该内容后自动删除已下载的文件';

  @override
  String get downloadAutoDeleteExclude => '排除分类';

  @override
  String get downloadAutoDeleteExcludeNone => '全部执行自动删除';

  @override
  String get downloadPreDownload => '预下载后续内容';

  @override
  String get downloadPreDownloadOff => '关闭';

  @override
  String downloadEpisodesCount(int count) {
    return '$count 个';
  }

  @override
  String get categoriesManageTitle => '分类管理';

  @override
  String get categoriesManageDesc => '管理动漫、漫画、小说的收藏分类';

  @override
  String get settingsGroupPrivacy => '隐私';

  @override
  String get onboardingWelcomeTitle => '欢迎使用 NexHub';

  @override
  String get onboardingWelcomeBody =>
      '四合一媒体聚合客户端：动漫、漫画、小说、影视。应用不内置任何站点，内容来自你导入的源。';

  @override
  String get onboardingSourcesTitle => '添加你的源';

  @override
  String get onboardingSourcesBody => '前往「源管理」导入社区维护的源，即可开始浏览与搜索。';

  @override
  String get onboardingBangumiTitle => '关联 Bangumi';

  @override
  String get onboardingBangumiBody => '登录后可同步「在看 / 想看」到 Bangumi，并在详情页查看评分与吐槽。';

  @override
  String get onboardingBangumiLogin => '立即登录';

  @override
  String get onboardingDandanplayTitle => '关联 弹弹play';

  @override
  String get onboardingDandanplayBody => '登录后可发送并同步弹幕到弹弹play，跨设备共享弹幕库。';

  @override
  String get onboardingDandanplayLogin => '去登录';

  @override
  String get onboardingPrivacyTitle => '隐私与合规';

  @override
  String get onboardingPrivacyBody => '你的源、凭据与浏览记录只保存在本机，不上传任何服务器。应用不写死任何密钥。';

  @override
  String get onboardingSkip => '跳过';

  @override
  String get onboardingNext => '下一步';

  @override
  String get onboardingGetStarted => '开始使用';

  @override
  String get onboardingSettingsTitle => '基础设置';

  @override
  String get onboardingSettingsBody => '选择外观主题与界面语言，之后也能在「设置」中随时更改。';

  @override
  String get onboardingThemeLabel => '外观主题';

  @override
  String get onboardingLanguageLabel => '界面语言';

  @override
  String get onboardingPermissionTitle => '授予权限';

  @override
  String get onboardingPermissionBody =>
      '为了正常导入本地文件、保存下载与截图，建议授予以下权限；稍后也能在「设置」中处理。';

  @override
  String get onboardingGrantPermission => '授予权限';

  @override
  String get onboardingPermissionGranted => '已授予必要权限';

  @override
  String get onboardingPermissionNotNeeded => '当前平台无需运行时权限';

  @override
  String get onboardingPermissionStorage => '存储';

  @override
  String get onboardingPermissionStorageDesc => '访问本地文件（旧系统版本使用）';

  @override
  String get onboardingPermissionPhotos => '照片';

  @override
  String get onboardingPermissionPhotosDesc => '读取图库中的图片';

  @override
  String get onboardingPermissionVideos => '视频';

  @override
  String get onboardingPermissionVideosDesc => '读取图库中的视频';

  @override
  String get onboardingPermissionAudio => '音频';

  @override
  String get onboardingPermissionAudioDesc => '读取本地音频文件';

  @override
  String get onboardingPermissionItemGranted => '已授权';

  @override
  String get onboardingPermissionItemDenied => '未授权';

  @override
  String get onboardingDownloadTitle => '下载位置';

  @override
  String get onboardingDownloadBody =>
      '设置动漫 / 漫画 / 小说 / 影视等内容下载后的保存目录，之后也可在「设置 → 下载」中修改。';

  @override
  String get onboardingChooseDownloadPath => '选择下载目录';

  @override
  String get onboardingThemeColorLabel => '主题色';

  @override
  String get onboardingThemePreviewLabel => '样式预览';

  @override
  String get privacySettingsTitle => '隐私设置';

  @override
  String get privacySettingsDesc => '通知打码与隐身选项';

  @override
  String get privacyNotificationsGroup => '通知';

  @override
  String get hideNotificationContent => '隐藏通知内容';

  @override
  String get hideNotificationContentHint => '开启后通知只显示「新内容」，不显示具体条数，防旁人窥屏';

  @override
  String get privacyNetworkGroup => '网络';

  @override
  String get privacyPageHint => '全局隐身会随机延迟请求并轮换浏览器指纹，降低被站点识别为脚本的风险';

  @override
  String get settingsGroupAdvanced => '高级与缓存';

  @override
  String get advancedSettingsTitle => '高级设置';

  @override
  String get advancedSettingsDesc => '崩溃日志、详细日志、数据清理与请求指纹';

  @override
  String get advancedLogGroup => '日志';

  @override
  String get detailedLogging => '详细日志';

  @override
  String get detailedLoggingHint => '记录每个网络请求与响应，便于排查抓取问题';

  @override
  String get crashLog => '崩溃日志';

  @override
  String get crashLogDesc => '查看应用运行期错误与未捕获异常';

  @override
  String get crashLogTitle => '崩溃日志';

  @override
  String get crashLogEmpty => '暂无崩溃记录。若遇到问题，复现一次后再回来查看';

  @override
  String get crashLogCopied => '已复制到剪贴板';

  @override
  String get crashLogClear => '清空崩溃日志';

  @override
  String get crashLogCleared => '已清空';

  @override
  String get crashLogCopyAll => '复制全部';

  @override
  String get runtimeLog => '运行日志';

  @override
  String get runtimeLogDesc => '本次运行期的网络请求、响应与错误记录（详细日志开关控制记录程度）';

  @override
  String get logEmpty => '暂无日志。开启「详细日志」后复现问题，再回来查看';

  @override
  String get logCopied => '日志已复制到剪贴板';

  @override
  String get advancedCleanGroup => '数据清理';

  @override
  String get clearCookies => '清除 Cookie';

  @override
  String get clearCookiesDesc => '清除爬取与 WebView 的会话 Cookie';

  @override
  String get cookiesCleared => 'Cookie 已清除';

  @override
  String get cloudSyncAutoUploadNovelExports => '小说导出自动上传';

  @override
  String get cloudSyncAutoUploadNovelExportsDesc =>
      '下载完成后自动把导出的 EPUB 上传到 WebDAV nexhub/exports 目录';

  @override
  String get uploadToWebdav => '上传导出到 WebDAV';

  @override
  String get uploadToWebdavDone => '个导出文件已上传到 WebDAV';

  @override
  String get uploadToWebdavNoFiles => '本书还没有已下载的 EPUB 导出产物';

  @override
  String get uploadToWebdavFailed => '导出上传失败，请检查 WebDAV 配置';

  @override
  String get novelExportTemplate => '导出模板（EPUB）';

  @override
  String get novelExportTemplateDesc => '自定义样式表、封面页与简介页随导出的 EPUB 一并生成';

  @override
  String get novelExportCss => '自定义 CSS（style.css）';

  @override
  String get novelExportCssHint => '直接写普通 CSS 规则，应用于全部章节（可自定义字体族、行距等）';

  @override
  String get novelExportIntro => '书籍简介页';

  @override
  String get novelExportIntroHint => '空行分段；书名与作者占位符会自动替换';

  @override
  String get novelExportIncludeCover => '嵌入网络封面为书首封面页';

  @override
  String get novelExportIncludeIntro => '封面后追加简介页';

  @override
  String get novelExportSaved => '导出模板已保存';

  @override
  String get advancedImageCache => '图片缓存';

  @override
  String get advancedImageCacheDesc => '已下载图片的磁盘占用，点按清理';

  @override
  String get imageCacheCleared => '图片缓存已清理';

  @override
  String get imageCacheClearConfirm => '清理图片缓存？';

  @override
  String get imageCacheCalculating => '计算中…';

  @override
  String get cacheManagerTitle => '缓存管理';

  @override
  String get cacheManagerTotal => '缓存总占用';

  @override
  String cacheManagerTotalDesc(String size) {
    return '当前共 $size，按类别可单独清理';
  }

  @override
  String get cacheManagerHint => '清理缓存不会删除收藏、下载与书源；图片收藏图库中的图片保存在收藏目录，不受影响。';

  @override
  String get cacheCategoryGroup => '缓存分类';

  @override
  String get cacheCatImages => '图片缓存';

  @override
  String get cacheCatImagesDesc => '封面、漫画页与 RSS 内嵌图';

  @override
  String get cacheCatDanmaku => '弹幕缓存';

  @override
  String get cacheCatDanmakuDesc => '已缓存的视频弹幕（按过期时间自动淘汰）';

  @override
  String get cacheCatTranslations => '翻译缓存';

  @override
  String get cacheCatTranslationsDesc => '小说 / 漫画 / 字幕的 AI 翻译结果';

  @override
  String get cacheCatWebview => 'WebView 数据';

  @override
  String get cacheCatWebviewDesc => '内嵌浏览器缓存与本地存储';

  @override
  String get cacheCatTemp => '临时文件';

  @override
  String get cacheCatTempDesc => 'PDF 渲染、归档解压等派生文件';

  @override
  String get cacheCatUpdates => '更新包残留';

  @override
  String get cacheCatUpdatesDesc => '已下载的安装包与旧版本目录';

  @override
  String get cacheSizeUnknown => '无法统计';

  @override
  String get cacheClearCategory => '清理此类';

  @override
  String cacheClearCategoryConfirm(String name) {
    return '清理「$name」？';
  }

  @override
  String get cacheClearAll => '全部清理';

  @override
  String get cacheClearAllConfirm => '清理全部缓存类别？';

  @override
  String get cacheCategoryCleared => '已清理';

  @override
  String get cacheClearFailed => '清理失败，请稍后重试';

  @override
  String get cacheAutoCleanGroup => '缓存自动清理';

  @override
  String get cacheAutoCleanGroupDesc => '启动时后台按「年龄 + 容量」自动清理派生缓存';

  @override
  String get cacheAutoClean => '自动清理缓存';

  @override
  String get cacheAutoCleanDesc => '关闭后仅在「缓存管理」页手动清理';

  @override
  String get cacheMaxAge => '缓存保留时长';

  @override
  String cacheMaxAgeValue(int days) {
    return '$days 天';
  }

  @override
  String get cacheMaxTotal => '缓存总容量上限';

  @override
  String get cacheAutoCleanNow => '按策略清理';

  @override
  String cacheAutoCleanDone(String size) {
    return '已释放 $size';
  }

  @override
  String get cacheAutoCleanNothing => '没有需要清理的缓存';

  @override
  String get readerUpscale => '图片超分';

  @override
  String get readerUpscaleMode => '超分档位';

  @override
  String get readerUpscaleOff => '关闭';

  @override
  String get readerUpscaleResample => '高清重采样';

  @override
  String get readerUpscaleSharpen => '超分（锐化）';

  @override
  String get readerUpscaleDesc =>
      '仅单页翻页模式生效：图片被放大显示时用 GPU 实时重采样并锐化线条（条漫与超长单图保持原始渲染）；低端机卡顿时可关闭';

  @override
  String get confirmActionHint => '该操作不可撤销，确定继续？';

  @override
  String get advancedRequestGroup => '请求指纹';

  @override
  String get defaultUserAgent => '默认 UA';

  @override
  String get userAgentAuto => '自动（内置指纹轮换）';

  @override
  String get userAgentAutoHint => '不同站点自动使用不同浏览器指纹';

  @override
  String get userAgentCustom => '自定义 UA';

  @override
  String get advancedPageHint => '修改默认 UA 后立即生效；部分站点对固定指纹可能更敏感';

  @override
  String get refresh => '刷新';

  @override
  String get rssNewContentGeneric => '有新内容';

  @override
  String get readerClockPosTopLeft => '左上';

  @override
  String get readerClockPosTopRight => '右上';

  @override
  String get readerClockPosBottomLeft => '左下';

  @override
  String get readerClockPosBottomRight => '右下';

  @override
  String get cacheBook => '缓存';

  @override
  String get cacheChaptersTitle => '选择要缓存的章节';

  @override
  String get cacheSelected => '缓存选中';

  @override
  String cacheSelectedCount(int count) {
    return '已选 $count 章';
  }

  @override
  String get searchPause => '暂停';

  @override
  String get searchResume => '继续';

  @override
  String get searchScope => '范围';

  @override
  String get searchScopeAll => '全书';

  @override
  String get searchScopeFromHere => '当前章之后';

  @override
  String get searchScopeRange => '起止章';

  @override
  String get searchUseRegex => '正则';

  @override
  String get searchRegexInvalid => '正则表达式无效';

  @override
  String get searchRangeStart => '起始章';

  @override
  String get searchRangeEnd => '结束章';

  @override
  String get overviewChapterSummary => '本章速览';

  @override
  String get overviewMode => '总结方式';

  @override
  String get overviewModeLocal => '离线摘要';

  @override
  String get overviewModeApi => '云端总结';

  @override
  String get overviewGenerate => '生成速览';

  @override
  String get overviewGenerating => '生成中…';

  @override
  String get overviewEmpty => '本章暂无内容可总结';

  @override
  String get overviewApiSettings => '速览 API 设置';

  @override
  String get overviewApiBaseUrl => 'API 地址';

  @override
  String get overviewApiKey => 'API 密钥';

  @override
  String get overviewApiModel => '模型名称';

  @override
  String get overviewApiError => '调用失败';

  @override
  String get overviewApiMissing => '未配置 API，请在设置中填写';

  @override
  String get overviewRetry => '重试';

  @override
  String get overviewCopy => '复制';

  @override
  String get importLegadoSource => '导入 legado 书源';

  @override
  String get legadoImportTitle => 'legado 书源导入';

  @override
  String get legadoImportHint => '选择 legado 书源 JSON 文件（可多选）';

  @override
  String get legadoImportedCount => '已导入 \$count 个书源';

  @override
  String get legadoParseError => '书源解析失败';

  @override
  String get legadoGroupDefault => 'legado';

  @override
  String get searchPaused => '已暂停';

  @override
  String get selectionCopy => '复制';

  @override
  String get selectionCopied => '已复制';

  @override
  String get selectionHighlight => '高亮';

  @override
  String get selectionUnderline => '划线';

  @override
  String get underlineStyle => '划线样式';

  @override
  String get underlineColor => '划线颜色';

  @override
  String get underlineStyleSolid => '实线';

  @override
  String get underlineStyleWavy => '波浪线';

  @override
  String get underlineStyleDotted => '虚线';

  @override
  String get customColorApply => '应用自定义颜色';

  @override
  String get selectionNote => '摘录';

  @override
  String get selectionShare => '分享';

  @override
  String get selectionTranslate => '翻译';

  @override
  String get selectionAskAi => '问AI';

  @override
  String get selTranslateTitle => '划词翻译';

  @override
  String get selTranslateSource => '原文';

  @override
  String get selTranslateResult => '译文';

  @override
  String get selTranslateRetry => '重试';

  @override
  String get selTranslateFailed => '翻译失败';

  @override
  String get askAiTitle => '问 AI';

  @override
  String get askAiHint => '就选中内容或本章提问…';

  @override
  String get askAiSend => '发送';

  @override
  String get askAiThinking => '思考中…';

  @override
  String get askAiFailed => '请求失败，请重试';

  @override
  String get askAiNoEndpoints => '未配置 AI 接口，请先在「设置 → AI」中配置';

  @override
  String askAiContextTag(String book, String chapter) {
    return '上下文：《$book》· $chapter';
  }

  @override
  String get notesSheetTitle => '笔记';

  @override
  String get notesExport => '导出 Markdown';

  @override
  String notesExported(int count) {
    return '已生成 $count 条划线笔记';
  }

  @override
  String get shareChangeCover => '更换封面';

  @override
  String get selectionCancel => '取消';

  @override
  String get selectionParagraph => '整段';

  @override
  String get highlightList => '标记列表';

  @override
  String get highlightEmpty => '暂无标记';

  @override
  String get highlightDelete => '删除标记';

  @override
  String get highlightEditNote => '编辑摘录';

  @override
  String get highlightNoteHint => '写下你的想法…';

  @override
  String get highlightSave => '保存';

  @override
  String get highlightJump => '跳转';

  @override
  String get highlightColor => '颜色';

  @override
  String get comicTranslateSettingLabel => '漫画翻译';

  @override
  String get comicTranslateTurnOn => '翻译本页';

  @override
  String get comicTranslateTurnOff => '关闭翻译';

  @override
  String get comicTranslateLoading => '翻译中…';

  @override
  String get comicTranslateFailed => '翻译失败';

  @override
  String get comicTranslatePartial => '部分翻译';

  @override
  String get subTransSectionTitle => '实时翻译';

  @override
  String get subTransToggle => '实时翻译字幕';

  @override
  String get subTransToggleDesc => '识别当前字幕并实时显示译文';

  @override
  String get subTransShowOriginal => '显示原文';

  @override
  String get subTransOcrFallback => '无字幕时识别画面';

  @override
  String get subTransOcrFallbackDesc => '无字幕轨时按间隔截取画面识别台词（消耗更多流量）';

  @override
  String get aiComicTranslationSection => '漫画翻译';

  @override
  String get aiComicTranslationDesc => '漫画页 OCR+翻译使用的视觉模型接口，留空回落通用配置';

  @override
  String get aiComicModelHint => '需支持视觉的模型，如 gpt-4o-mini';

  @override
  String get aiMediaTranslationSection => '视频字幕翻译';

  @override
  String get aiMediaTranslationDesc => '播放器实时字幕翻译接口，留空回落通用配置';

  @override
  String get translationCacheTitle => '翻译缓存';

  @override
  String get translationCacheDesc => '本地缓存的逐条 AI 译文；清除后相同内容会重新翻译（重新计费）';

  @override
  String get translationCacheNovel => '小说段落翻译';

  @override
  String get translationCacheComic => '漫画页翻译';

  @override
  String get translationCacheSubtitle => '视频字幕翻译';

  @override
  String translationCacheEntries(Object count) {
    return '$count 条';
  }

  @override
  String get translationCacheClear => '清除全部翻译缓存';

  @override
  String get translationCacheClearConfirm => '确定清除全部翻译缓存？已译内容将重新翻译并产生接口费用。';

  @override
  String get translationCacheCleared => '翻译缓存已清除';

  @override
  String get glossaryTitle => '翻译术语表';

  @override
  String glossaryTargetLang(String lang) {
    return '目标语言：$lang';
  }

  @override
  String get glossaryEmpty => '暂无术语。添加人名与专名后，翻译将全书保持同一译名。';

  @override
  String get glossaryAdd => '添加术语';

  @override
  String get glossaryEdit => '编辑术语';

  @override
  String get glossaryTerm => '术语（原文）';

  @override
  String get glossaryPreferred => '统一译名';

  @override
  String get glossaryAliases => '可接受别名（顿号或逗号分隔，可选）';

  @override
  String get glossaryNote => '备注（可选）';

  @override
  String get glossaryImport => '从 JSON 导入';

  @override
  String get glossaryExport => '导出 JSON';

  @override
  String glossaryImportOk(int count) {
    return '已导入 $count 条术语';
  }

  @override
  String get glossaryImportFail => '导入失败：术语表文件格式非法';

  @override
  String glossaryDeleteConfirm(String term) {
    return '删除术语「$term」？';
  }

  @override
  String glossaryAliasesPreview(String aliases) {
    return '别名：$aliases';
  }

  @override
  String get glossaryOpen => '术语表编辑器';

  @override
  String get glossaryWorkTitle => '作品术语表';

  @override
  String get glossaryScopeGlobal => '全局术语表 · 所有作品生效';

  @override
  String get glossaryScopeWork => '当前作品 + 全局术语';

  @override
  String glossaryConflictsTitle(int count) {
    return '待裁决术语冲突（$count）';
  }

  @override
  String get glossaryConflictExisting => '既有译名';

  @override
  String get glossaryConflictProposed => '本次译法';

  @override
  String glossaryConflictChapter(String chapter) {
    return '出自：$chapter';
  }

  @override
  String get glossaryConflictAdopt => '采用新译法';

  @override
  String get glossaryConflictKeep => '保留原译名';

  @override
  String get glossaryConflictResolved => '冲突已裁决';

  @override
  String get glossaryConflictBadge => '待裁决';

  @override
  String get glossaryGlobalEntryHint => '全局条目，请到全局术语表修改或删除';

  @override
  String get glossaryTypeTerm => '术语';

  @override
  String get glossaryTypePerson => '人名';

  @override
  String get glossaryTypePlace => '地名';

  @override
  String get glossaryTypeOrg => '组织';

  @override
  String get glossaryTypeAppellation => '称谓';

  @override
  String get glossaryTypeHonorific => '敬称';

  @override
  String get glossaryTypeSpeech => '口癖';

  @override
  String get glossaryTypeFixed => '固定表达';

  @override
  String glossaryExtractedNotice(int terms, int conflicts) {
    return '已收录 $terms 个术语，$conflicts 个待裁决';
  }

  @override
  String get glossaryExtractedOpen => '查看';

  @override
  String get translationStyle => '翻译风格';

  @override
  String get translationStyleStandard => '标准';

  @override
  String get translationStyleColloquial => '口语化';

  @override
  String get translationStyleElegant => '文雅';

  @override
  String get translationStyleInternet => '网络用语';

  @override
  String get translationCot => '审慎翻译（思维链）';

  @override
  String get translationCotHint => '翻译前先让模型理解语境与术语，质量更高但更慢、更贵；适合短篇/低批量场景。';

  @override
  String get translationSubtitleLightweight => '字幕轻量输出';

  @override
  String get translationSubtitleLightweightHint =>
      '字幕译文按行输出、不带编号以省 token；对位失败自动回退编号协议。';

  @override
  String get translationAutoExtract => '自动提取术语';

  @override
  String get translationAutoExtractHint =>
      '每批翻译后自动收录人名、地名与固定译名；发现异译时进入待裁决冲突。关闭可减少请求。';

  @override
  String get translationExportLayout => '小说译文附录排版';

  @override
  String get translationLayoutTranslationFirst => '译文优先';

  @override
  String get translationLayoutSourceFirst => '原文优先';

  @override
  String get translationLayoutBilingual => '双语对照';

  @override
  String get novelTranslateResume => '继续翻译';

  @override
  String novelTranslateResumable(Object done, Object total) {
    return '已译 $done/$total 段，可从断点继续';
  }

  @override
  String get prescanStart => '全书预扫描';

  @override
  String prescanProgress(Object done, Object total) {
    return '预扫描中：已完成 $done/$total 章';
  }

  @override
  String get prescanReady => '已注入全书概述';

  @override
  String get translationPolish => '译文润色（二阶段）';

  @override
  String get translationPolishHint =>
      '章节翻译完成后可再润色一遍，使行文自然、术语统一。默认关闭；每章润色会产生一次额外请求。';

  @override
  String get polishAction => '润色本章';

  @override
  String get translationVariantOriginal => '初译';

  @override
  String get translationVariantPolished => '润色';

  @override
  String get reviewOpen => '翻译审查报告';

  @override
  String get reviewTitle => '翻译审查';

  @override
  String get reviewBooksEmpty => '暂无已翻译章节。先翻译若干章节，再回来运行审查。';

  @override
  String reviewBookChapters(Object count) {
    return '已译 $count 章';
  }

  @override
  String reviewBookFindings(Object count) {
    return '最近报告 $count 条发现';
  }

  @override
  String get reviewRunFailed => '审查失败';

  @override
  String reviewFindingCount(Object count) {
    return '$count 条发现';
  }

  @override
  String get reviewNoFindings => '未发现问题，全部检查通过。';

  @override
  String get reviewTruncated => '摘要版：仅显示前 100 条发现，完整报告已保存为 JSON 文件。';

  @override
  String get reviewTypeGlossary => '术语';

  @override
  String get reviewTypeMissing => '漏译';

  @override
  String get reviewTypeLiteral => '直译腔';

  @override
  String get reviewTypeAdded => '过度翻译';

  @override
  String get reviewTypeMistranslation => '误译';

  @override
  String get reviewTypeTerminology => '术语不一致';

  @override
  String get reviewTypePronoun => '指代';

  @override
  String get reviewAiAction => 'AI 审校';

  @override
  String reviewAiProgress(Object done, Object total) {
    return 'AI 审校中 $done/$total';
  }

  @override
  String get reviewAiPartial => '部分段落块被跳过，报告可能不完整。';

  @override
  String get reviewRevision => '修订';

  @override
  String get reviewAccept => '采纳';

  @override
  String get reviewIgnore => '忽略';

  @override
  String get reviewApplyAll => '全部应用';

  @override
  String reviewAppliedCount(Object count) {
    return '已应用 $count 条修订';
  }

  @override
  String get offlineTranslateTitle => '整片翻译（离线）';

  @override
  String get offlineHint => '选择外挂字幕文件（SRT / VTT / ASS），整片批量翻译后可导出双语字幕；中断后自动续跑。';

  @override
  String get offlinePickSubtitle => '选择字幕文件开始翻译';

  @override
  String offlineJobProgress(Object done, Object total) {
    return '已译 $done/$total 句';
  }

  @override
  String get offlineJobDone => '翻译完成，可导出双语字幕';

  @override
  String get offlineJobFailed => '翻译失败';

  @override
  String get offlineResume => '继续任务';

  @override
  String get offlineCancel => '取消任务';

  @override
  String get offlineRetranslate => '重新翻译 / 补齐缺句';

  @override
  String get offlineExportSrt => '导出双语 SRT';

  @override
  String get offlineExportAss => '导出双语 ASS';

  @override
  String get offlineUpload => '上传到 WebDAV';

  @override
  String offlineUploaded(Object url) {
    return '已上传：$url';
  }

  @override
  String get comicTranslateBackfillLabel => '气泡内回填排版';

  @override
  String get comicTranslateBackfillDesc =>
      '译文以描边文字回填到气泡内（按气泡宽度换行、字号自适应）。竖排页降级为横排居中。';

  @override
  String get aiBackupSection => '备用接口（主接口故障时自动切换）';

  @override
  String get comicTranslationExport => '导出翻译数据';

  @override
  String get comicTranslationImport => '导入翻译数据';

  @override
  String comicTranslationImportOk(Object imported, Object skipped) {
    return '已导入 $imported 页，跳过已有 $skipped 页';
  }

  @override
  String get comicTranslationImportFail => '导入失败：翻译数据文件格式非法';

  @override
  String get offlineExportAll => '导出全部已完成（双语 SRT）';

  @override
  String get networkRssAppliesNote =>
      'RSS 订阅同样应用本页的代理、DNS、SNI 与 Hosts 配置：已在此页配置的全局网络，对 RSS 抓取与 RSSHub 测速一并生效。';

  @override
  String get rssGlobalSubscriptionDesc => '与浏览页同源的全局 RSS 订阅源';

  @override
  String get rssBindModuleTitle => '绑定到模块';

  @override
  String get rssBindToNovel => '绑定到小说';

  @override
  String get rssBindToAnime => '绑定到视频';

  @override
  String get rssBindToManga => '绑定到漫画';

  @override
  String get rssUnbindGlobal => '移回全局订阅';

  @override
  String get rssArticleFavorited => '已收藏';

  @override
  String get rssArticleUnfavorited => '已取消收藏';

  @override
  String get rssFavorites => 'RSS 收藏';

  @override
  String get rssFavoritesDesc => '已收藏的 RSS 文章';

  @override
  String get rssFavoritesEmpty => '暂无收藏';

  @override
  String get rssMarkAllRead => '全部标为已读';

  @override
  String get rssMarkedAllRead => '已全部标为已读';

  @override
  String get rssOfflineCached => '正在显示离线缓存（上次抓取）';

  @override
  String get rssShowAll => '全部';

  @override
  String get rssShowUnread => '未读';

  @override
  String get rssStarAdd => '收藏';

  @override
  String get rssStarRemove => '取消收藏';

  @override
  String rssDiscoverAddSelected(Object count) {
    return '添加所选（$count）';
  }

  @override
  String rssDiscoverAdded(Object count) {
    return '已添加 $count 个订阅';
  }

  @override
  String get rssDiscoverButton => '查找订阅源';

  @override
  String get rssDiscoverDesc => '输入站点地址，自动查找 RSS / Atom 源';

  @override
  String rssDiscoverFailed(Object error) {
    return '查找失败：$error';
  }

  @override
  String rssDiscoverFound(Object count) {
    return '找到 $count 个订阅源';
  }

  @override
  String get rssDiscoverFromLink => '页面声明';

  @override
  String get rssDiscoverFromProbe => '常见路径';

  @override
  String get rssDiscoverInputHint => 'https://example.com';

  @override
  String get rssDiscoverInvalidUrl => '请输入有效的网址';

  @override
  String get rssDiscoverNone => '没有找到订阅源';

  @override
  String get rssDiscoverProbing => '正在探测常见路径…';

  @override
  String get rssDiscoverTitle => '从网站发现订阅';

  @override
  String get rssExportOpml => '导出 OPML';

  @override
  String get rssGroupAdd => '新建分组';

  @override
  String rssGroupAddExists(Object name) {
    return '分组「$name」已存在';
  }

  @override
  String get rssAudioFailed => '音频加载失败';

  @override
  String get rssOpenExternally => '用外部应用打开';

  @override
  String get rssVideoFailed => '视频加载失败';

  @override
  String get rssVideoPlay => '播放视频';

  @override
  String get rssFetchWebsite => '拉取网站解析';

  @override
  String get rssFetchSucceeded => '已更新为网站正文';

  @override
  String get rssListLayout => '列表样式';

  @override
  String get rssLayoutList => '列表';

  @override
  String get rssLayoutCard => '卡片';

  @override
  String get rssLayoutCompact => '紧凑';

  @override
  String get rssLayoutMagazine => '大图';

  @override
  String get rssSort => '排序';

  @override
  String get rssSortNewest => '最新在前';

  @override
  String get rssSortOldest => '最旧在前';

  @override
  String get rssSortUnreadFirst => '未读优先';

  @override
  String get rssPrevArticle => '上一篇';

  @override
  String get rssNextArticle => '下一篇';

  @override
  String get rssAutoReadTitle => '关键词自动已读';

  @override
  String get rssAutoReadDesc => '刷新时标题命中关键词的新文章自动标记为已读，不计入未读数';

  @override
  String get rssAutoReadAdd => '添加关键词';

  @override
  String get rssAutoReadEmpty => '暂无关键词';

  @override
  String get rssAutoReadHint => '输入标题包含的关键词';

  @override
  String get rssOpenInBrowser => '在浏览器打开';

  @override
  String get rssAutoFetchFullText => '自动抓取全文';

  @override
  String get rssIframeOpen => '在内置浏览器打开';

  @override
  String get rssFetchFullText => '抓取整页';

  @override
  String get rssFetching => '正在抓取…';

  @override
  String get rssFetchFullTextFailed => '抓取失败';

  @override
  String get rssFetchFullTextEmpty => '未能提取到正文';

  @override
  String get rssImageSaved => '图片已保存';

  @override
  String get rssImageSaveFailed => '保存失败';

  @override
  String get rssLinkUnsupported => '该链接不受支持';

  @override
  String get rssGroupAll => '全部';

  @override
  String get rssGroupDelete => '删除分组';

  @override
  String rssGroupDeleteConfirm(Object name) {
    return '删除分组「$name」？订阅不会被删除，仅移除该分组标记。';
  }

  @override
  String get rssGroupEmpty => '还没有分组';

  @override
  String rssGroupFeedCount(Object count) {
    return '$count 个订阅';
  }

  @override
  String get rssGroupManage => '管理分组';

  @override
  String get rssGroupRename => '重命名分组';

  @override
  String get rssGroupSetDone => '分组已更新';

  @override
  String get rssGroupUngrouped => '未分组';

  @override
  String get rssImportOpml => '导入 OPML';

  @override
  String rssOpmlCategory(Object name) {
    return '分组：$name';
  }

  @override
  String get rssOpmlConfirmImport => '导入所选';

  @override
  String get rssOpmlEmpty => '没有可导入的订阅';

  @override
  String get rssOpmlExportDesc => '将全部订阅导出为标准 OPML';

  @override
  String get rssOpmlExportDesc2 => '生成 OPML 备份并分享';

  @override
  String get rssOpmlExportTitle => '导出';

  @override
  String get rssOpmlImportDesc => '从文件或文本批量导入订阅';

  @override
  String get rssOpmlImportFile => '从文件导入';

  @override
  String get rssOpmlImportFileDesc => '选择本机的 .opml / .xml 文件';

  @override
  String get rssOpmlImportPreviewTitle => '导入预览';

  @override
  String get rssOpmlImportText => '粘贴文本导入';

  @override
  String get rssOpmlImportTextDesc => '直接粘贴 OPML 内容';

  @override
  String get rssOpmlImportTitle => '导入';

  @override
  String rssOpmlParseFailed(Object error) {
    return 'OPML 解析失败：$error';
  }

  @override
  String rssOpmlPreviewSummary(Object selected, Object total) {
    return '已选 $selected / 共 $total 条';
  }

  @override
  String rssOpmlPreviewSummarySkipped(
      Object selected, Object skipped, Object total) {
    return '已选 $selected / 共 $total 条（跳过 $skipped 个无效节点）';
  }

  @override
  String get rssSetGroups => '设置分组';

  @override
  String get rssOpmlTitle => 'OPML 导入导出';

  @override
  String get rssOpmlExport => '导出为 OPML';

  @override
  String get rssOpmlPasteHint => '在此粘贴 OPML 内容';

  @override
  String rssOpmlImported(Object count) {
    return '已导入 $count 条订阅';
  }

  @override
  String get rssGroupName => '分组名称';

  @override
  String get rssSearchTitle => 'RSS 搜索';

  @override
  String get rssSearchHint => '搜索已订阅源的文章';

  @override
  String get rssSearchNoResult => '没有匹配的文章';

  @override
  String get rssSearchBuilding => '正在建立索引…';

  @override
  String get rssSearchEmpty => '还没有可搜索的缓存（先打开订阅源）';

  @override
  String rssSearchCount(Object shown, Object total) {
    return '命中 $shown / 共 $total 条';
  }

  @override
  String get rssAttachments => '附件';

  @override
  String get rssSystemNotification => '系统通知';

  @override
  String get rssSystemNotificationSubtitle =>
      '有新文章时发送系统通知（Android/iOS/Linux/macOS；Windows 不支持，仅应用内提醒）';

  @override
  String get articleMargin => '左右边距';

  @override
  String get articleFontUnderline => '下划线';

  @override
  String get articleUnderlineDashed => '下划线虚线';

  @override
  String get articleUnderlineThickness => '下划线宽度';

  @override
  String get articleUnderlineColor => '下划线颜色';

  @override
  String get articleBackground => '背景';

  @override
  String get articleTextColor => '文字颜色';

  @override
  String get articleEmphasisColor => '强调色';

  @override
  String get articleShadow => '文字阴影';

  @override
  String get articleShadowBlur => '阴影模糊';

  @override
  String get articleShadowOffsetX => '阴影 X 偏移';

  @override
  String get articleShadowOffsetY => '阴影 Y 偏移';

  @override
  String get articleChooseFont => '选择自定义字体';

  @override
  String get articleClearFont => '清除字体';

  @override
  String articleFontCurrent(Object file) {
    return '当前：$file';
  }

  @override
  String get articleTitleScale => '标题字号';

  @override
  String get articleTitleBold => '标题加粗';

  @override
  String get articleTitleColor => '标题颜色';

  @override
  String get articleTitleAlign => '标题对齐';

  @override
  String get alignLeft => '左对齐';

  @override
  String get alignCenter => '居中';

  @override
  String get alignRight => '右对齐';

  @override
  String get colorFollowDefault => '跟随默认';

  @override
  String get rssChargeCheck => '充电时自动检测';

  @override
  String get rssChargeCheckSubtitle => '接入充电器后自动检测一次新内容（触发条件：充电）';

  @override
  String get articleSecTypography => '排版';

  @override
  String get articleSecTextStyle => '文字样式';

  @override
  String get articleSecColor => '颜色与背景';

  @override
  String get articleSecShadow => '阴影';

  @override
  String get articleSecFont => '字体';

  @override
  String get articleSecTitle => '标题';

  @override
  String get mediaServerSettings => '媒体服务器';

  @override
  String get mediaServerSettingsDesc => '管理 Emby / Jellyfin 服务器连接与登录';

  @override
  String get mediaServerSettingsSubtitle => '连接 Emby / Jellyfin 观看进度双向同步';

  @override
  String mediaServerTileConnected(Object n) {
    return '已连接 $n 台';
  }

  @override
  String get mediaServerAddServer => '添加服务器';

  @override
  String get mediaServerAddressLabel => '服务器地址';

  @override
  String get mediaServerAddressHint => '例如 http://192.168.1.10:8096';

  @override
  String get mediaServerDetect => '探测';

  @override
  String get mediaServerDetecting => '探测中…';

  @override
  String get mediaServerTypeLabel => '类型';

  @override
  String mediaServerDetectedAs(Object name) {
    return '已识别：$name';
  }

  @override
  String get mediaServerManualTypeHint => '识别失败？可手动选择类型后直接登录';

  @override
  String get mediaServerUsernameLabel => '用户名';

  @override
  String get mediaServerPasswordLabel => '密码';

  @override
  String get mediaServerLogin => '登录';

  @override
  String get mediaServerLoggingIn => '登录中…';

  @override
  String get mediaServerNotLoggedIn => '未登录';

  @override
  String mediaServerLoggedInAs(Object user) {
    return '账号：$user';
  }

  @override
  String get mediaServerStatusOnline => '在线';

  @override
  String get mediaServerStatusOffline => '离线';

  @override
  String get mediaServerStatusNeedRelogin => '需重新登录';

  @override
  String get mediaServerStatusChecking => '检测中…';

  @override
  String get mediaServerRename => '重命名';

  @override
  String get mediaServerRenameTitle => '重命名服务器';

  @override
  String get mediaServerRelogin => '重新登录';

  @override
  String mediaServerReloginTitle(Object name) {
    return '重新登录「$name」';
  }

  @override
  String get mediaServerDelete => '删除';

  @override
  String get mediaServerDeleteTitle => '删除服务器';

  @override
  String mediaServerDeleteBody(Object name) {
    return '将移除「$name」的本机配置与登录凭证；服务器上的媒体库与观看进度不受影响。';
  }

  @override
  String get mediaServerEmptyTitle => '尚未添加服务器';

  @override
  String get mediaServerEmptyHint => '支持 Emby 与 Jellyfin。输入内网或反代地址，登录后即可浏览与播放。';

  @override
  String mediaServerOperationFailed(Object error) {
    return '操作失败：$error';
  }

  @override
  String get mediaServerAddressRequired => '请先填写服务器地址';

  @override
  String get mediaServerCredentialsRequired => '请填写用户名和密码';

  @override
  String get mediaServerHomeResume => '继续观看';

  @override
  String get mediaServerHomeLatest => '最新添加';

  @override
  String get mediaServerHomeLibraries => '媒体库';

  @override
  String get mediaServerUnsupportedLibraries => '音乐 / 图片等其他类型的库暂不支持，已隐藏';

  @override
  String get mediaServerRetry => '重试';

  @override
  String mediaServerLoadFailed(Object error) {
    return '加载失败：$error';
  }

  @override
  String get mediaServerSearchHint => '在服务器内搜索';

  @override
  String get mediaServerNoResults => '没有匹配的结果';

  @override
  String get mediaServerPlay => '播放';

  @override
  String get mediaServerResumePlay => '继续播放';

  @override
  String get mediaServerPlayFromStart => '从头播放';

  @override
  String get mediaServerTypeSeries => '剧集';

  @override
  String get mediaServerPgsSubtitleWarn => '该集内封图形字幕需转码，暂不支持';

  @override
  String get mediaServerTranscodeRequired => '该格式需转码，暂不支持';

  @override
  String mediaServerRuntimeMinutes(Object m) {
    return '$m 分钟';
  }

  @override
  String mediaServerRuntimeHoursMinutes(Object h, Object m) {
    return '$h 小时 $m 分';
  }

  @override
  String get mediaServerGoAdd => '去添加服务器';

  @override
  String get mediaServerCredentialsWrong => '用户名或密码错误，请检查后重试';

  @override
  String get mediaServerManageAction => '添加 / 管理媒体服务器';

  @override
  String get mediaServerConnecting => '正在连接服务器…';

  @override
  String get mediaServerBlockedByChallenge =>
      '服务器防护（Cloudflare 人机验证）拦截了播放请求：请在浏览器打开服务器地址完成一次验证，或联系管理员放行 API 路径';

  @override
  String get mediaServerUnreachable => '无法连接媒体服务器（网络错误或被临时限流），请稍后重试';

  @override
  String get mediaServerBitrateTier => '码率档位';

  @override
  String get mediaServerBitrateAuto => '自动（服务器决策）';

  @override
  String get mediaServerBitrateOriginal => '原画（强制直连）';

  @override
  String get mediaServerBitrate720p => '720p 限档';

  @override
  String get mediaServerTranscodingNotice => '原格式直连不支持，正在转码播放';

  @override
  String get mediaServerOriginalNeedsDirect => '原画档位需要直连，该格式不支持直连；请选择其他码率档位';

  @override
  String get mediaServerAudioTrack => '音轨';

  @override
  String get mediaServerFavorites => '我的收藏';

  @override
  String get mediaServerNextUp => '接下来观看';

  @override
  String get mediaServerFavorite => '收藏';

  @override
  String get mediaServerFavoriteAdded => '已加入收藏';

  @override
  String get mediaServerFavoriteRemoved => '已取消收藏';

  @override
  String get mediaServerMarkWatched => '标记已看';

  @override
  String get mediaServerMarkUnwatched => '取消已看';

  @override
  String get mediaServerMarkAllWatched => '全部标已看';

  @override
  String mediaServerRemaining(Object m) {
    return '剩 $m 分钟';
  }

  @override
  String get mediaServerFilterAll => '全部';

  @override
  String get mediaServerFilterUnwatched => '未看';

  @override
  String get mediaServerFilterWatched => '已看';

  @override
  String get mediaServerFilterGenre => '流派';

  @override
  String get mediaServerFilterYear => '年份';

  @override
  String get mediaServerSort => '排序';

  @override
  String get mediaServerSortByName => '名称';

  @override
  String get mediaServerSortByYear => '年份';

  @override
  String get mediaServerSortByAdded => '入库时间';

  @override
  String get mediaServerAddresses => '服务器地址';

  @override
  String get mediaServerAddressesHint => '每行一个地址；首个可达地址将作为活动地址（内外网可并存）';

  @override
  String get mediaServerAddressSaved => '地址已更新';

  @override
  String get mediaServerTypeBoxSet => '合集';

  @override
  String get mediaServerStatsPlayMethod => '播放方式';

  @override
  String get mediaServerPlayMethodDirect => '直连';

  @override
  String get mediaServerPlayMethodDirectStream => '直接流';

  @override
  String get mediaServerPlayMethodTranscode => '转码';

  @override
  String get mediaServerSearchHistory => '搜索历史';

  @override
  String get mediaServerSearchHistoryClear => '清空搜索历史';

  @override
  String get bingTranslationTitle => 'Bing 免费翻译';

  @override
  String get bingTranslationDesc => '无需 API Key，同时用于标题、标签、简介与评论';

  @override
  String get bingTranslationEnable => '启用 Bing 免费翻译';

  @override
  String get bingTranslationEnableHint => '关闭后小说/字幕仅走 AI，详情页自动翻译同时停用';

  @override
  String get bingTranslationPriority => '引擎优先级';

  @override
  String get bingTranslationBingFirst => 'Bing 优先';

  @override
  String get bingTranslationAiFirst => 'AI 优先';

  @override
  String get bingTranslationAutoTitle => '自动翻译标题';

  @override
  String get bingTranslationAutoTags => '自动翻译标签';

  @override
  String get bingTranslationAutoSummary => '自动翻译简介';

  @override
  String get bingTranslationAutoComments => '自动翻译评论';

  @override
  String get bingTranslationTest => '测试 Bing 连通性';

  @override
  String get bingTranslationTesting => '测试中...';

  @override
  String get bingTranslationTestOk => 'Bing 翻译可用';

  @override
  String get bingTranslationTestFail => 'Bing 当前不可用，将使用 AI 兜底';

  @override
  String get translationNotNeeded => '该内容已是目标语言，无需翻译';

  @override
  String get bingTranslationPrivacy =>
      '文本会发送到 Microsoft 翻译服务；该接口非官方公开接口，可能随时调整或失效。';

  @override
  String get translationCacheUiText => '详情页与评论翻译';

  @override
  String get storageLocationAppPrivate => '应用私有目录';

  @override
  String get storageLocationAppPrivateHint => '保存在应用内，卸载应用时一并删除';

  @override
  String get storageLocationSystemDownloads => '系统「下载」目录';

  @override
  String get storageLocationSystemDownloadsHint => '「文件」应用中可见，卸载应用后仍保留';

  @override
  String get storageLocationSystemScreenshots => '系统「下载」/ Screenshots';

  @override
  String get storageLocationSystemScreenshotsHint => '「文件」应用中可见，卸载应用后仍保留';

  @override
  String get ttsAutoNext => '跨章连播';

  @override
  String get ttsAutoNextDesc => '一章读完自动加载下一章继续朗读';

  @override
  String get ttsCastTitle => '角色与声音';

  @override
  String get ttsCastSubtitle => '为本书角色分配不同朗读音色，未配置角色走旁白/性别兜底';

  @override
  String get ttsCastHttpSlots => '在线音色兜底（HTTP TTS）';

  @override
  String get ttsCastSystemSlots => '系统声音（本机引擎）';

  @override
  String get ttsCastNarratorVoice => '旁白音色';

  @override
  String get ttsCastMaleVoice => '男性兜底音色';

  @override
  String get ttsCastFemaleVoice => '女性兜底音色';

  @override
  String get ttsCastHttpVoice => '在线音色 ID（HTTP TTS）';

  @override
  String get ttsCastSystemVoice => '系统声音';

  @override
  String get ttsCastEngineDefault => '引擎默认';

  @override
  String get ttsCastCharacters => '本书角色';

  @override
  String get ttsCastEmpty => '暂无角色卡。朗读时 AI 会自动识别说话人建卡，也可手动添加。';

  @override
  String get ttsCastAddRole => '添加角色';

  @override
  String get ttsCastEditRole => '编辑角色';

  @override
  String get ttsCastRoleName => '角色名';

  @override
  String get ttsCastAliases => '别名（选填）';

  @override
  String get ttsCastAliasesHint => '多个别名用逗号分隔';

  @override
  String get ttsCastMale => '男';

  @override
  String get ttsCastFemale => '女';

  @override
  String get ttsCastGenderUnknown => '未知';

  @override
  String get ttsCastEnable => '启用';

  @override
  String get ttsCastDisable => '停用';

  @override
  String get ttsCastDelete => '删除';

  @override
  String get ttsCastAiRelabel => 'AI 归因本章';

  @override
  String get ttsCastAiRunning => 'AI 归因中…';

  @override
  String ttsCastAiDone(int count) {
    return 'AI 归因完成：$count 句已标注';
  }

  @override
  String get ttsCastAiNoConfig => '未配置 AI 接口，请先在设置 → AI 中配置小说总览或通用接口';

  @override
  String get ttsCastAiFailed => 'AI 归因失败，已保留本地判定';

  @override
  String get ttsCastVoiceMapHint => '全局兜底映射（角色名=音色 ID，每行一条）；按书配置请在阅读器「角色与声音」面板';

  @override
  String get ttsCacheClear => '清空朗读音频缓存';

  @override
  String get ttsCacheEmpty => '暂无缓存';

  @override
  String ttsCacheCount(int count) {
    return '已缓存 $count 条音频';
  }

  @override
  String ttsCacheCleared(int count) {
    return '已清理 $count 条朗读音频';
  }

  @override
  String homeWidgetUpdates(int count) {
    return '追更 · 收藏 $count 部';
  }

  @override
  String get homeWidgetUpdatesIdle => '追更 · 暂无收藏';

  @override
  String homeWidgetDownloads(int count, int percent) {
    return '下载 · $count 个任务 $percent%';
  }

  @override
  String get homeWidgetDownloadsIdle => '下载 · 暂无任务';

  @override
  String homeWidgetWeek(int minutes) {
    return '本周 · $minutes 分钟';
  }

  @override
  String get homeWidgetWeekIdle => '本周 · 还没开始';

  @override
  String get homeWidgetEmptyTitle => '还没有观看记录';

  @override
  String get homeWidgetEmptyHint => '打开 NexHub 挑一部开始';

  @override
  String get homeWidgetContinueLabel => '继续观看';

  @override
  String get homeWidgetUpdatesLabel => '追更';

  @override
  String get homeWidgetDownloadsLabel => '下载';

  @override
  String get homeWidgetStatsLabel => '统计';

  @override
  String homeWidgetChapterProgress(int index, int total) {
    return '第 $index 话 · 共 $total 话';
  }

  @override
  String homeWidgetChapterProgressOpen(int index) {
    return '第 $index 话';
  }

  @override
  String homeWidgetEpisodeProgress(int index, int minutes) {
    return '第 $index 集 · 已看 $minutes 分钟';
  }

  @override
  String homeWidgetEpisodeWatched(int index) {
    return '第 $index 集';
  }

  @override
  String homeWidgetToday(int minutes) {
    return '今日 · $minutes 分钟';
  }

  @override
  String get homeWidgetTodayIdle => '今日 · 还没开始';

  @override
  String homeWidgetStreak(int active, int streak) {
    return '活跃 $active 天 · 连续 $streak 天';
  }

  @override
  String get settingsCatWidget => '桌面卡片';

  @override
  String get settingsCatWidgetDesc => '背景、模糊与记录条数';

  @override
  String get widgetBackgroundSection => '背景';

  @override
  String get widgetBgCover => '作品封面';

  @override
  String get widgetBgCoverDesc => '用最近在看的封面，模糊后铺满卡片';

  @override
  String get widgetBgTheme => '主题色';

  @override
  String get widgetBgThemeDesc => '跟随当前主题色的渐变';

  @override
  String get widgetBgNone => '无背景';

  @override
  String get widgetBgNoneDesc => '只保留卡片底色';

  @override
  String get widgetTuningSection => '外观';

  @override
  String get widgetBlurStrength => '模糊强度';

  @override
  String get widgetOpacity => '不透明度';

  @override
  String get widgetRecordsSection => '记录';

  @override
  String get widgetContinueLimit => '继续观看条数';

  @override
  String widgetContinueLimitDesc(int count) {
    return '显示 $count 条';
  }

  @override
  String get widgetLimitNote => '系统限制';

  @override
  String get widgetLimitNoteDesc => '系统卡片最多显示 4~5 条（视平台）';

  @override
  String get widgetHeatmapCaption => '本月打卡';

  @override
  String get widgetMinuteUnit => '分钟';

  @override
  String get widgetStreakCaption => '连续打卡';

  @override
  String widgetLifetimeHours(int hours) {
    return '累计 $hours 小时';
  }

  @override
  String widgetWeekSessions(int count) {
    return '本周 $count 次';
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
  String get widgetTrendFlat => '持平';

  @override
  String get widgetTrendNew => '本周新增';
}
