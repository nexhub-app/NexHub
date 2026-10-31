/// 设置主页 —— 分类入口（动态取色 / 编辑式版面）。
///
/// 设计取向：色彩随用户选择的种子色（Monet / 预设 / 自定义）实时变化，
/// 不使用任何固定色值。顶部品牌头（monogram + 色板圆点）打破纯列表的单调感，
/// 下方 6 张分类卡用 primaryContainer 图标瓦 + outlineVariant 发丝边，
/// 克制而统一。整体风格取自 Linear / Vercel 的编辑式留白美学。
library;

import 'package:material_ui/material_ui.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/utils/app_haptics.dart';
import '../../../core/widgets/app_animations.dart';
import '../../../core/widgets/app_glass_bar.dart';
import 'package:nexhub/generated/app_localizations.dart';
import 'package:nexhub/core/navigation/app_page_route.dart';
import '../../../core/settings/general_settings.dart';
import '../../../core/platform/platform_service.dart';
import './widgets/hero_carousel.dart';
import './widgets/settings_widgets.dart';
import './settings_hero_screen.dart';
import './settings_appearance_screen.dart';
import './settings_playback_screen.dart';
import './settings_content_screen.dart';
import './settings_data_screen.dart';
import './settings_privacy_security_screen.dart';
import './about_screen.dart';
import './settings_announcements_screen.dart';
// 设置搜索注册表所引用的子页 / 汇总页（按用途分组）：
import './settings_player_screen.dart';
import './settings_novel_reader_screen.dart';
import './settings_comic_reader_screen.dart';
import './settings_motion_effects_screen.dart';
import './settings_danmaku_display_screen.dart';
import './settings_watched_threshold_screen.dart';
import './settings_remember_position_screen.dart';
import './settings_network_screen.dart';
import './settings_privacy_screen.dart';
import './settings_advanced_screen.dart';
import './settings_cache_manager_screen.dart';
import './settings_categories_screen.dart';
import './settings_download_screen.dart';
import './settings_import_export_screen.dart';
import './settings_ai_screen.dart';
import './crash_log_screen.dart';
import './log_viewer_screen.dart';
import './settings_dandanplay_account_screen.dart';
import './settings_update_screen.dart';
import './settings_cloud_sync_screen.dart';
import './settings_bangumi_screen.dart';
import './media_server_manage_screen.dart';
import './settings_rss_notifications_screen.dart';
import './settings_rsshub_screen.dart';
import '../../rss/presentation/rss_feed_list_screen.dart';
import '../../rss/presentation/rss_favorites_screen.dart';
import '../../sources/presentation/source_manager_screen.dart';
import '../../home/presentation/browse_web_scrape_screen.dart';
import '../../stats/presentation/stats_overview_screen.dart';
import './widgets/settings_search_target.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);

    final List<_Category> categories = _buildCategories(context, l10n);

    return AppShrinkTitleScaffold(
      title: Text(l10n.settingsTitle),
      actions: <Widget>[
        IconButton(
          icon: const Icon(Icons.search_rounded),
          tooltip: l10n.search,
          onPressed: () => _showSettingsSearch(context),
        ),
      ],
      // Legado MD3 观感：分类入口合并进一张连体卡（组内发丝分隔线）。
      body: ListView(
        // 文字列表：移动端避让玻璃底栏。
        padding:
            const EdgeInsets.all(AppTokens.spaceLg) + context.glassBarInset,
        children: <Widget>[
          const _HeroSection(),
          const SizedBox(height: AppTokens.spaceLg),
          Entrance(
            onceKey: 'settings_categories',
            offset: 16,
            fromScale: 0.96,
            duration: AppTokens.durSpring,
            child: SettingsGroup(
              children: <Widget>[
                for (final c in categories)
                  SettingsTile(
                    icon: c.icon,
                    title: c.title,
                    subtitle: c.desc,
                    onTap: () {
                      AppHaptics.selectionClick();
                      Navigator.of(context).push(
                        AppPageRoute<void>(builder: (_) => c.builder()),
                      );
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<_Category> _buildCategories(
      BuildContext context, AppLocalizations l10n) {
    return <_Category>[
      _Category(
        icon: Icons.palette_rounded,
        title: l10n.settingsCatAppearance,
        desc: l10n.settingsCatAppearanceDesc,
        builder: () => const SettingsAppearanceScreen(),
      ),
      _Category(
        icon: Icons.play_circle_rounded,
        title: l10n.settingsCatPlayback,
        desc: l10n.settingsCatPlaybackDesc,
        builder: () => const SettingsPlaybackScreen(),
      ),
      _Category(
        icon: Icons.rss_feed_rounded,
        title: l10n.settingsCatContent,
        desc: l10n.settingsCatContentDesc,
        builder: () => const SettingsContentScreen(),
      ),
      _Category(
        icon: Icons.storage_rounded,
        title: l10n.settingsCatData,
        desc: l10n.settingsCatDataDesc,
        builder: () => const SettingsDataScreen(),
      ),
      _Category(
        icon: Icons.shield_rounded,
        title: l10n.settingsCatPrivacy,
        desc: l10n.settingsCatPrivacyDesc,
        builder: () => const SettingsPrivacySecurityScreen(),
      ),
      _Category(
        icon: Icons.info_rounded,
        title: l10n.settingsCatAbout,
        desc: l10n.settingsCatAboutDesc,
        builder: () => const AboutScreen(),
      ),
    ];
  }

  void _showSettingsSearch(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final List<_SettingEntry> entries = _buildSettingsRegistry(l10n);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppTokens.radiusLg),
        ),
      ),
      builder: (BuildContext ctx) => _SettingsSearchSheet(entries: entries),
    );
  }

  /// 具体设置项搜索注册表：每条直接跳转到对应设置页（含各分类的子页）。
  ///
  /// 「搜索能精确到具体设置」的关键：把每个子页面 + 常用子项都注册进来，
  /// 配合 [keywords] 让用户模糊输入（如「弹幕」「备份」「字号」）即可直达。
  /// `builder` 是 `WidgetBuilder`，构造时给定 `BuildContext` 以便后续
  /// `Navigator.of(context).push(...)` 时保持原页面的 Provider 作用域。
  List<_SettingEntry> _buildSettingsRegistry(AppLocalizations l10n) {
    return <_SettingEntry>[
      // ───────────────── 外观与语言 ─────────────────
      _SettingEntry(
        icon: Icons.palette_rounded,
        title: l10n.settingsCatAppearance,
        desc: l10n.settingsCatAppearanceDesc,
        keywords: const <String>[
          '外观',
          '主题',
          '颜色',
          '字体',
          '语言',
          '深色',
          '浅色',
          '配色',
          '启动',
          '日期',
          'monet',
          '主题色',
          '动态',
          '取色'
        ],
        builder: (_) => const SettingsAppearanceScreen(),
      ),
      _SettingEntry(
        icon: Icons.dark_mode_rounded,
        title: l10n.appearanceThemeSection,
        keywords: const <String>['主题', '深色', '浅色', '暗黑', '跟随系统', '主题模式'],
        builder: (_) => const SettingsAppearanceScreen(),
        scrollKeyId: 'appearance.theme',
      ),
      // 鸿蒙：莫奈取色恒回退默认主题（见外观页注释），搜索入口同步隐藏。
      if (!PlatformService.instance.isOHOS)
        _SettingEntry(
          icon: Icons.auto_awesome_rounded,
          title: l10n.useMonet,
          keywords: const <String>['动态色彩', 'monet', '动态取色'],
          builder: (_) => const SettingsAppearanceScreen(),
          scrollKeyId: 'appearance.theme',
        ),
      _SettingEntry(
        icon: Icons.color_lens_rounded,
        title: l10n.appearanceColorsSection,
        keywords: const <String>[
          '颜色',
          '配色',
          'monet',
          '动态色彩',
          '预设',
          '主题色',
          '取色',
          '自定义颜色',
          '调色'
        ],
        builder: (_) => const SettingsAppearanceScreen(),
        scrollKeyId: 'appearance.colors',
      ),
      _SettingEntry(
        icon: Icons.brush_rounded,
        title: l10n.customColor,
        keywords: const <String>['自定义颜色', '取色', '调色器', '选颜色', 'picker'],
        builder: (_) => const SettingsAppearanceScreen(),
        scrollKeyId: 'appearance.customColor',
      ),
      _SettingEntry(
        icon: Icons.font_download_rounded,
        title: l10n.appearanceFont,
        keywords: const <String>['字体', '界面字体', 'font', '得意黑', '霞鹜文楷', '思源黑体', '自定义字体'],
        builder: (_) => const SettingsAppearanceScreen(),
        scrollKeyId: 'appearance.font',
      ),
      _SettingEntry(
        icon: Icons.image_rounded,
        title: l10n.heroSettingsTitle,
        desc: l10n.heroEmptyHint,
        keywords: const <String>['背景', '壁纸', '头图', '启动图', 'hero', '图片', '轮播'],
        builder: (_) => const SettingsHeroScreen(),
      ),
      // Hero 子页内更细的设置项：
      _SettingEntry(
        icon: Icons.link_rounded,
        title: l10n.heroAddFromUrl,
        keywords: const <String>['url', '链接', '网络图片', '添加图片'],
        builder: (_) => const SettingsHeroScreen(),
      ),
      _SettingEntry(
        icon: Icons.photo_library_rounded,
        title: l10n.heroAddFromDevice,
        keywords: const <String>['设备', '本地图片', '相册', '选择图片'],
        builder: (_) => const SettingsHeroScreen(),
      ),
      _SettingEntry(
        icon: Icons.rocket_launch_rounded,
        title: l10n.appearanceStartupSection,
        keywords: const <String>['启动', '启动页', '日期', '日期格式'],
        builder: (_) => const SettingsAppearanceScreen(),
        scrollKeyId: 'appearance.startup',
      ),
      _SettingEntry(
        icon: Icons.translate_rounded,
        title: l10n.settingsGroupLanguage,
        keywords: const <String>['语言', '中文', '英文', '国际化', '切换语言'],
        builder: (_) => const SettingsAppearanceScreen(),
        scrollKeyId: 'appearance.language',
      ),
      _SettingEntry(
        icon: Icons.image_rounded,
        title: l10n.appearanceHeroSection,
        keywords: const <String>['背景图', 'hero', '头图'],
        builder: (_) => const SettingsAppearanceScreen(),
        scrollKeyId: 'appearance.hero',
      ),

      // ───────────────── 详情页外观（外观与语言内分组） ─────────────────
      _SettingEntry(
        icon: Icons.wallpaper_rounded,
        title: l10n.settingsCatDetailAppearance,
        desc: l10n.settingsCatDetailAppearanceDesc,
        keywords: const <String>[
          '详情页',
          '外观',
          '封面',
          '取色',
          '强调色',
          '模糊',
          '背景',
          '高斯模糊',
          '动态颜色'
        ],
        builder: (_) => const SettingsAppearanceScreen(),
        scrollKeyId: 'appearance.detailAppearance',
      ),
      _SettingEntry(
        icon: Icons.colorize_rounded,
        title: l10n.detailAppearanceDynamicAccent,
        desc: l10n.detailAppearanceDynamicAccentDesc,
        keywords: const <String>['取色', '强调色', '封面颜色', '动态颜色', 'accent'],
        builder: (_) => const SettingsAppearanceScreen(),
        scrollKeyId: 'appearance.detailAppearance',
      ),
      _SettingEntry(
        icon: Icons.blur_on_rounded,
        title: l10n.detailAppearanceBlurredBg,
        desc: l10n.detailAppearanceBlurredBgDesc,
        keywords: const <String>['模糊', '背景', '封面背景', '高斯模糊', 'blur'],
        builder: (_) => const SettingsAppearanceScreen(),
        scrollKeyId: 'appearance.detailAppearance',
      ),

      // ───────────────── 播放与阅读 ─────────────────
      _SettingEntry(
        icon: Icons.play_circle_rounded,
        title: l10n.settingsCatPlayback,
        desc: l10n.settingsCatPlaybackDesc,
        keywords: const <String>['播放', '阅读'],
        builder: (_) => const SettingsPlaybackScreen(),
      ),
      _SettingEntry(
        icon: Icons.category_rounded,
        title: l10n.playbackModulesSection,
        keywords: const <String>['播放模块', '阅读模块', '入口'],
        builder: (_) => const SettingsPlaybackScreen(),
        scrollKeyId: 'playback_modules',
      ),
      _SettingEntry(
        icon: Icons.play_circle_rounded,
        title: l10n.playerSettingsTitle,
        desc: l10n.playerSettingsDesc,
        keywords: const <String>[
          '播放器',
          '解码',
          '音频',
          '倍速',
          '画面比例',
          '进度',
          '长按',
          '默认',
          '硬解',
          '软解',
          '音轨'
        ],
        builder: (_) => const SettingsPlayerScreen(),
      ),
      _SettingEntry(
        icon: Icons.play_circle_rounded,
        title: l10n.playerCoreGroup,
        keywords: const <String>['播放核心', '解码', '音量', '倍速'],
        builder: (_) => const SettingsPlayerScreen(),
        scrollKeyId: 'player.core',
      ),
      _SettingEntry(
        icon: Icons.touch_app_rounded,
        title: l10n.playerGestureGroup,
        keywords: const <String>['手势', '控制', '长按', '拖动'],
        builder: (_) => const SettingsPlayerScreen(),
        scrollKeyId: 'player.gesture',
      ),
      // 播放器子页内具体项（滚动定位）：
      _SettingEntry(
        icon: Icons.videocam_rounded,
        title: l10n.playerDefaultDecodeMode,
        keywords: const <String>['解码', '硬解', '软解', '解码模式', 'hw', 'sw'],
        builder: (_) => const SettingsPlayerScreen(),
        scrollKeyId: 'player.decodeMode',
      ),
      _SettingEntry(
        icon: Icons.surround_sound_rounded,
        title: l10n.playerDefaultAudioChannel,
        keywords: const <String>['音频', '声道', '音轨', '声音', 'audio'],
        builder: (_) => const SettingsPlayerScreen(),
        scrollKeyId: 'player.audioChannel',
      ),
      _SettingEntry(
        icon: Icons.aspect_ratio_rounded,
        title: l10n.playerDefaultAspectRatio,
        keywords: const <String>['画面比例', '宽高比', '拉伸', '比例', 'aspect'],
        builder: (_) => const SettingsPlayerScreen(),
        scrollKeyId: 'player.aspectRatio',
      ),
      _SettingEntry(
        icon: Icons.screen_rotation_rounded,
        title: l10n.playerDefaultOrientation,
        keywords: const <String>['方向', '横屏', '竖屏', '旋转', '锁定方向'],
        builder: (_) => const SettingsPlayerScreen(),
        scrollKeyId: 'player.orientation',
      ),
      _SettingEntry(
        icon: Icons.playlist_play_rounded,
        title: l10n.playerDefaultAutoPlay,
        keywords: const <String>['连播', '自动连播', '自动播放', '下一集', 'autoplay'],
        builder: (_) => const SettingsPlayerScreen(),
        scrollKeyId: 'player.autoplay',
      ),
      _SettingEntry(
        icon: Icons.fast_forward_rounded,
        title: l10n.playerGestureSeekMultiplier,
        keywords: const <String>['拖动', '快进', '倍率', '手势', 'seek'],
        builder: (_) => const SettingsPlayerScreen(),
        scrollKeyId: 'player.gestureSeek',
      ),
      _SettingEntry(
        icon: Icons.speed_rounded,
        title: l10n.playerLongPressSpeedUp,
        keywords: const <String>['长按', '加速', '长按加速', '倍速'],
        builder: (_) => const SettingsPlayerScreen(),
        scrollKeyId: 'player.longPressSpeed',
      ),
      _SettingEntry(
        icon: Icons.subtitles_rounded,
        title: l10n.playerSubtitleGroup,
        keywords: const <String>['字幕', '显示字幕', 'subtitle'],
        builder: (_) => const SettingsPlayerScreen(),
        scrollKeyId: 'player.subtitle',
      ),
      _SettingEntry(
        icon: Icons.visibility_rounded,
        title: l10n.subtitleShow,
        keywords: const <String>['显示字幕', '字幕开关'],
        builder: (_) => const SettingsPlayerScreen(),
        scrollKeyId: 'player.subtitle',
      ),
      _SettingEntry(
        icon: Icons.photo_camera_rounded,
        title: l10n.playerScreenshotGroup,
        keywords: const <String>['截图', '保存图片', '截屏'],
        builder: (_) => const SettingsPlayerScreen(),
        scrollKeyId: 'player.screenshot',
      ),
      // 播放器子页内更细的设置项：
      _SettingEntry(
        icon: Icons.speed_rounded,
        title: l10n.playerDefaultSpeed,
        keywords: const <String>['默认倍速', '倍速', '播放速度'],
        builder: (_) => const SettingsPlayerScreen(),
        scrollKeyId: 'player.core',
      ),
      _SettingEntry(
        icon: Icons.volume_up_rounded,
        title: l10n.playerDefaultVolume,
        keywords: const <String>['默认音量', '音量', '声音'],
        builder: (_) => const SettingsPlayerScreen(),
        scrollKeyId: 'player.core',
      ),
      _SettingEntry(
        icon: Icons.text_fields_rounded,
        title: l10n.subtitleFontSize,
        keywords: const <String>['字幕字号', '字幕大小', '字体'],
        builder: (_) => const SettingsPlayerScreen(),
        scrollKeyId: 'player.subtitle',
      ),
      _SettingEntry(
        icon: Icons.zoom_out_map_rounded,
        title: l10n.subtitleScale,
        keywords: const <String>['字幕缩放', '缩放', '大小'],
        builder: (_) => const SettingsPlayerScreen(),
        scrollKeyId: 'player.subtitle',
      ),
      _SettingEntry(
        icon: Icons.border_outer_rounded,
        title: l10n.subtitleBorderSize,
        keywords: const <String>['字幕边框', '边框粗细'],
        builder: (_) => const SettingsPlayerScreen(),
        scrollKeyId: 'player.subtitle',
      ),
      _SettingEntry(
        icon: Icons.blur_on_rounded,
        title: l10n.subtitleShadowOffset,
        keywords: const <String>['字幕阴影', '阴影偏移'],
        builder: (_) => const SettingsPlayerScreen(),
        scrollKeyId: 'player.subtitle',
      ),
      _SettingEntry(
        icon: Icons.schedule_rounded,
        title: l10n.subtitleOffset,
        keywords: const <String>['字幕偏移', '时间偏移', '延迟'],
        builder: (_) => const SettingsPlayerScreen(),
        scrollKeyId: 'player.subtitle',
      ),
      _SettingEntry(
        icon: Icons.colorize_rounded,
        title: l10n.subtitleTextColor,
        keywords: const <String>['字幕颜色', '文字颜色'],
        builder: (_) => const SettingsPlayerScreen(),
        scrollKeyId: 'player.subtitle',
      ),
      _SettingEntry(
        icon: Icons.bolt_rounded,
        title: l10n.playerLongPressSpeed,
        keywords: const <String>['长按倍速', '加速速度'],
        builder: (_) => const SettingsPlayerScreen(),
        scrollKeyId: 'player.gesture',
      ),
      _SettingEntry(
        icon: Icons.menu_book_rounded,
        title: l10n.novelReaderSettingsTitle,
        desc: l10n.novelReaderSettingsDesc,
        keywords: const <String>[
          '小说',
          '阅读',
          '翻页',
          '卷轴',
          '字号',
          '行距',
          '段距',
          '目录',
          '章节'
        ],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      // 小说阅读器子页内具体项（滚动定位）：
      _SettingEntry(
        icon: Icons.text_fields_rounded,
        title: l10n.novelSectionFont,
        keywords: const <String>['字号', '字体', '行距', '段距', '字距', 'font'],
        builder: (_) => const SettingsNovelReaderScreen(),
        scrollKeyId: 'novel.font',
      ),
      _SettingEntry(
        icon: Icons.palette_rounded,
        title: l10n.novelSectionColor,
        keywords: const <String>['颜色', '背景', '文字颜色', '强调色', '深色'],
        builder: (_) => const SettingsNovelReaderScreen(),
        scrollKeyId: 'novel.color',
      ),
      _SettingEntry(
        icon: Icons.auto_stories_rounded,
        title: l10n.comicReaderSettingsTitle,
        desc: l10n.comicReaderSettingsDesc,
        keywords: const <String>[
          '漫画',
          '阅读',
          '方向',
          '点击区',
          '滤镜',
          '缩放',
          '手势',
          '翻页'
        ],
        builder: (_) => const SettingsComicReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.animation_rounded,
        title: l10n.motionEffectTitle,
        desc: l10n.motionEffectDesc,
        keywords: const <String>[
          '动态效果',
          '动效',
          '漫画',
          '视差',
          '呼吸',
          '粒子',
          '樱花',
          '预设',
          '互动',
          'motion',
          'interactive'
        ],
        builder: (_) => const SettingsMotionEffectsScreen(),
      ),
      // 漫画阅读器子页内具体项（滚动定位）：
      _SettingEntry(
        icon: Icons.touch_app_rounded,
        title: l10n.comicSectionTapPage,
        keywords: const <String>['点击', '翻页', '点击区', '手势', '点击翻转'],
        builder: (_) => const SettingsComicReaderScreen(),
        scrollKeyId: 'comic.tapPage',
      ),
      _SettingEntry(
        icon: Icons.filter_vintage_rounded,
        title: l10n.comicSectionVisualFilter,
        keywords: const <String>['滤镜', '画面', '裁边', '缩放', '双页', '灰度'],
        builder: (_) => const SettingsComicReaderScreen(),
        scrollKeyId: 'comic.visualFilter',
      ),
      _SettingEntry(
        icon: Icons.flash_on_rounded,
        title: l10n.comicSectionFlash,
        keywords: const <String>['闪屏', '闪光', '翻页闪光', '闪白', '闪烁'],
        builder: (_) => const SettingsComicReaderScreen(),
        scrollKeyId: 'comic.flash',
      ),
      _SettingEntry(
        icon: Icons.mouse_rounded,
        title: l10n.comicSectionMouseWheel,
        keywords: const <String>['滚轮', '鼠标', '滚轮翻页'],
        builder: (_) => const SettingsComicReaderScreen(),
        scrollKeyId: 'comic.mouseWheel',
      ),
      _SettingEntry(
        icon: Icons.subtitles_rounded,
        title: l10n.danmakuDisplaySettingsTitle,
        desc: l10n.danmakuDisplaySettingsDesc,
        keywords: const <String>[
          '弹幕',
          '屏蔽',
          '过滤',
          '不透明度',
          '行高',
          '字号',
          '区域',
          '时长',
          'danmaku',
          '显示',
          '关键词',
          '关键字'
        ],
        builder: (_) => const SettingsDanmakuDisplayScreen(),
      ),
      // 弹幕显示子页内具体项（滚动定位）：
      _SettingEntry(
        icon: Icons.font_download_rounded,
        title: l10n.danmakuDisplayGroupAppearance,
        keywords: const <String>['弹幕外观', '字号', '不透明度', '行高', '字体'],
        builder: (_) => const SettingsDanmakuDisplayScreen(),
        scrollKeyId: 'danmaku.appearance',
      ),
      _SettingEntry(
        icon: Icons.visibility_rounded,
        title: l10n.danmakuDisplayGroupDisplay,
        keywords: const <String>[
          '弹幕显示',
          '区域',
          '顶部',
          '底部',
          '滚动',
          '时长',
          '跟随倍速',
          '隐藏'
        ],
        builder: (_) => const SettingsDanmakuDisplayScreen(),
        scrollKeyId: 'danmaku.display',
      ),
      _SettingEntry(
        icon: Icons.block_rounded,
        title: l10n.danmakuDisplayGroupFilter,
        keywords: const <String>['屏蔽', '过滤', '关键词', '关键字', '弹幕屏蔽'],
        builder: (_) => const SettingsDanmakuDisplayScreen(),
        scrollKeyId: 'danmaku.filter',
      ),
      // 弹幕显示子页内更细的设置项：
      _SettingEntry(
        icon: Icons.opacity_rounded,
        title: l10n.danmakuOpacity,
        keywords: const <String>['不透明度', '透明度', 'opacity'],
        builder: (_) => const SettingsDanmakuDisplayScreen(),
        scrollKeyId: 'danmaku.appearance',
      ),
      _SettingEntry(
        icon: Icons.font_download_rounded,
        title: l10n.danmakuFontSize,
        keywords: const <String>['弹幕字号', '弹幕字体', '字体大小'],
        builder: (_) => const SettingsDanmakuDisplayScreen(),
        scrollKeyId: 'danmaku.appearance',
      ),
      _SettingEntry(
        icon: Icons.area_chart_rounded,
        title: l10n.danmakuArea,
        keywords: const <String>['显示区域', '区域', '弹幕区域'],
        builder: (_) => const SettingsDanmakuDisplayScreen(),
        scrollKeyId: 'danmaku.display',
      ),
      _SettingEntry(
        icon: Icons.timer_rounded,
        title: l10n.danmakuDuration,
        keywords: const <String>['弹幕时长', '时长', '存活时间'],
        builder: (_) => const SettingsDanmakuDisplayScreen(),
        scrollKeyId: 'danmaku.display',
      ),
      _SettingEntry(
        icon: Icons.height_rounded,
        title: l10n.danmakuLineHeight,
        keywords: const <String>['行高', '间距', 'lineHeight'],
        builder: (_) => const SettingsDanmakuDisplayScreen(),
        scrollKeyId: 'danmaku.display',
      ),
      _SettingEntry(
        icon: Icons.schedule_rounded,
        title: l10n.danmakuTimeOffset,
        keywords: const <String>['时间偏移', '偏移', '同步', 'timeoffset'],
        builder: (_) => const SettingsDanmakuDisplayScreen(),
        scrollKeyId: 'danmaku.display',
      ),
      _SettingEntry(
        icon: Icons.fast_forward_rounded,
        title: l10n.danmakuFollowSpeed,
        keywords: const <String>['跟随倍速', '倍速', '播放速度'],
        builder: (_) => const SettingsDanmakuDisplayScreen(),
        scrollKeyId: 'danmaku.display',
      ),
      _SettingEntry(
        icon: Icons.vertical_align_top_rounded,
        title: l10n.danmakuHideTop,
        keywords: const <String>['隐藏顶部', '顶部弹幕'],
        builder: (_) => const SettingsDanmakuDisplayScreen(),
        scrollKeyId: 'danmaku.display',
      ),
      _SettingEntry(
        icon: Icons.vertical_align_bottom_rounded,
        title: l10n.danmakuHideBottom,
        keywords: const <String>['隐藏底部', '底部弹幕'],
        builder: (_) => const SettingsDanmakuDisplayScreen(),
        scrollKeyId: 'danmaku.display',
      ),
      _SettingEntry(
        icon: Icons.swap_vert_rounded,
        title: l10n.danmakuHideScroll,
        keywords: const <String>['隐藏滚动', '滚动弹幕'],
        builder: (_) => const SettingsDanmakuDisplayScreen(),
        scrollKeyId: 'danmaku.display',
      ),
      _SettingEntry(
        icon: Icons.filter_alt_rounded,
        title: l10n.danmakuFilterKeywords,
        keywords: const <String>['屏蔽词', '过滤词', '弹幕关键词'],
        builder: (_) => const SettingsDanmakuDisplayScreen(),
        scrollKeyId: 'danmaku.filter',
      ),

      // 漫画阅读器子页内更细的设置项：
      _SettingEntry(
        icon: Icons.import_contacts_rounded,
        title: l10n.readerMode,
        keywords: const <String>['阅读模式', '单页', '双页', 'webtoon', '条漫', '竖排'],
        builder: (_) => const SettingsComicReaderScreen(),
        scrollKeyId: 'comic.common',
      ),
      _SettingEntry(
        icon: Icons.category_rounded,
        title: l10n.readerCommonSettings,
        keywords: const <String>['常用设置', '快捷'],
        builder: (_) => const SettingsComicReaderScreen(),
        scrollKeyId: 'comic.common',
      ),
      _SettingEntry(
        icon: Icons.horizontal_rule_rounded,
        title: l10n.readerProgressBarOnRight,
        keywords: const <String>['进度条', '进度条右侧', '右侧'],
        builder: (_) => const SettingsComicReaderScreen(),
        scrollKeyId: 'comic.progress',
      ),
      _SettingEntry(
        icon: Icons.more_horiz_rounded,
        title: l10n.readerLongPressMenu,
        keywords: const <String>['长按菜单', '长按'],
        builder: (_) => const SettingsComicReaderScreen(),
        scrollKeyId: 'comic.progress',
      ),
      _SettingEntry(
        icon: Icons.zoom_out_map_rounded,
        title: l10n.readerPreventShrink,
        keywords: const <String>['防止缩小', '防缩', '放大'],
        builder: (_) => const SettingsComicReaderScreen(),
        scrollKeyId: 'comic.progress',
      ),
      _SettingEntry(
        icon: Icons.swap_horiz_rounded,
        title: l10n.readerChapterTransition,
        keywords: const <String>['章节过渡', '过渡', '章节切换'],
        builder: (_) => const SettingsComicReaderScreen(),
        scrollKeyId: 'comic.progress',
      ),
      _SettingEntry(
        icon: Icons.color_lens_rounded,
        title: l10n.readerFlashColor,
        keywords: const <String>['闪光颜色', '闪白颜色'],
        builder: (_) => const SettingsComicReaderScreen(),
        scrollKeyId: 'comic.flash',
      ),
      _SettingEntry(
        icon: Icons.touch_app_rounded,
        title: l10n.tapZonePreview,
        keywords: const <String>['点击区预览', '预览', '点击区域'],
        builder: (_) => const SettingsComicReaderScreen(),
        scrollKeyId: 'comic.tapPage',
      ),
      _SettingEntry(
        icon: Icons.palette_rounded,
        title: l10n.readerBackground,
        keywords: const <String>['背景', '背景颜色', '底色', '黑底', '白底'],
        builder: (_) => const SettingsComicReaderScreen(),
        scrollKeyId: 'comic.common',
      ),
      _SettingEntry(
        icon: Icons.screen_rotation_rounded,
        title: l10n.readerOrientation,
        keywords: const <String>['方向', '屏幕方向', '横屏', '竖屏', '旋转'],
        builder: (_) => const SettingsComicReaderScreen(),
        scrollKeyId: 'comic.common',
      ),
      _SettingEntry(
        icon: Icons.zoom_in_rounded,
        title: l10n.readerZoom,
        keywords: const <String>['缩放', '双击', '放大'],
        builder: (_) => const SettingsComicReaderScreen(),
        scrollKeyId: 'comic.common',
      ),
      _SettingEntry(
        icon: Icons.fullscreen_rounded,
        title: l10n.readerFullscreen,
        keywords: const <String>['全屏', '沉浸'],
        builder: (_) => const SettingsComicReaderScreen(),
        scrollKeyId: 'comic.common',
      ),
      _SettingEntry(
        icon: Icons.brightness_high_rounded,
        title: l10n.readerKeepScreenOn,
        keywords: const <String>['常亮', '屏幕常亮'],
        builder: (_) => const SettingsComicReaderScreen(),
        scrollKeyId: 'comic.common',
      ),
      _SettingEntry(
        icon: Icons.horizontal_rule_rounded,
        title: l10n.readerSideMargin,
        keywords: const <String>['边距', '侧边距', '留白'],
        builder: (_) => const SettingsComicReaderScreen(),
        scrollKeyId: 'comic.tapPage',
      ),
      _SettingEntry(
        icon: Icons.touch_app_rounded,
        title: l10n.readerTapZone,
        keywords: const <String>['点击区域', '点击区', '点按', 'tapzone'],
        builder: (_) => const SettingsComicReaderScreen(),
        scrollKeyId: 'comic.tapPage',
      ),
      _SettingEntry(
        icon: Icons.flip_rounded,
        title: l10n.readerTapInvert,
        keywords: const <String>['点击翻转', '翻转', '反向点击'],
        builder: (_) => const SettingsComicReaderScreen(),
        scrollKeyId: 'comic.tapPage',
      ),
      _SettingEntry(
        icon: Icons.crop_rounded,
        title: l10n.readerCropEdge,
        keywords: const <String>['裁边', '裁剪', '白边'],
        builder: (_) => const SettingsComicReaderScreen(),
        scrollKeyId: 'comic.visualFilter',
      ),
      _SettingEntry(
        icon: Icons.filter_rounded,
        title: l10n.comicSectionVisualFilter,
        keywords: const <String>['滤镜', '亮度', '对比度', '饱和度', '灰度'],
        builder: (_) => const SettingsComicReaderScreen(),
        scrollKeyId: 'comic.visualFilter',
      ),
      // 图片超分（GPU 实时 shader）：关键词覆盖「超分 / 画质 / 锐化 / 重采样」等说法。
      _SettingEntry(
        icon: Icons.auto_awesome_rounded,
        title: l10n.readerUpscale,
        desc: l10n.readerUpscaleDesc,
        keywords: const <String>[
          '超分',
          '图片超分',
          '分辨率',
          '画质',
          '增强',
          '锐化',
          '重采样',
          '放大',
          '清晰',
          'upscale',
          'super resolution',
        ],
        builder: (_) => const SettingsComicReaderScreen(),
        scrollKeyId: 'comic.visualFilter',
      ),
      _SettingEntry(
        icon: Icons.pin_rounded,
        title: l10n.readerShowPageNumber,
        keywords: const <String>['页码', '显示页码'],
        builder: (_) => const SettingsComicReaderScreen(),
        scrollKeyId: 'comic.progress',
      ),
      _SettingEntry(
        icon: Icons.rotate_right_rounded,
        title: l10n.readerRotatePage,
        keywords: const <String>['旋转', '横屏', '转页'],
        builder: (_) => const SettingsComicReaderScreen(),
        scrollKeyId: 'comic.progress',
      ),
      _SettingEntry(
        icon: Icons.auto_stories_rounded,
        title: l10n.readerSplitDoublePage,
        keywords: const <String>['双页', '拆分', '跨页'],
        builder: (_) => const SettingsComicReaderScreen(),
        scrollKeyId: 'comic.progress',
      ),
      _SettingEntry(
        icon: Icons.flash_on_rounded,
        title: l10n.readerFlashEnabled,
        keywords: const <String>['翻页闪光', '闪屏', '闪光'],
        builder: (_) => const SettingsComicReaderScreen(),
        scrollKeyId: 'comic.flash',
      ),
      _SettingEntry(
        icon: Icons.timer_rounded,
        title: l10n.readerFlashTime,
        keywords: const <String>['闪光时长', '闪白时长'],
        builder: (_) => const SettingsComicReaderScreen(),
        scrollKeyId: 'comic.flash',
      ),
      _SettingEntry(
        icon: Icons.hourglass_empty_rounded,
        title: l10n.readerFlashInterval,
        keywords: const <String>['闪光间隔', '间隔'],
        builder: (_) => const SettingsComicReaderScreen(),
        scrollKeyId: 'comic.flash',
      ),
      _SettingEntry(
        icon: Icons.mouse_rounded,
        title: l10n.comicDefaultScrollWheel,
        keywords: const <String>['滚轮方向', '自然', '反向', '滚轮'],
        builder: (_) => const SettingsComicReaderScreen(),
        scrollKeyId: 'comic.mouseWheel',
      ),
      _SettingEntry(
        icon: Icons.insights_rounded,
        title: l10n.comicSectionProgress,
        keywords: const <String>['进度', '显示', '页码'],
        builder: (_) => const SettingsComicReaderScreen(),
        scrollKeyId: 'comic.progress',
      ),

      // 小说阅读器子页内更细的设置项：
      _SettingEntry(
        icon: Icons.text_fields_rounded,
        title: l10n.novelFontSize,
        keywords: const <String>['字号', '字体大小'],
        builder: (_) => const SettingsNovelReaderScreen(),
        scrollKeyId: 'novel.font',
      ),
      _SettingEntry(
        icon: Icons.format_line_spacing_rounded,
        title: l10n.novelLineHeight,
        keywords: const <String>['行距', '行高', '行间距'],
        builder: (_) => const SettingsNovelReaderScreen(),
        scrollKeyId: 'novel.font',
      ),
      _SettingEntry(
        icon: Icons.space_bar_rounded,
        title: l10n.novelParagraphSpacing,
        keywords: const <String>['段距', '段间距'],
        builder: (_) => const SettingsNovelReaderScreen(),
        scrollKeyId: 'novel.font',
      ),
      _SettingEntry(
        icon: Icons.format_color_text_rounded,
        title: l10n.novelTextColor,
        keywords: const <String>['正文颜色', '文字颜色'],
        builder: (_) => const SettingsNovelReaderScreen(),
        scrollKeyId: 'novel.color',
      ),
      _SettingEntry(
        icon: Icons.format_color_fill_rounded,
        title: l10n.novelEmphasisColor,
        keywords: const <String>['强调色', '高亮色'],
        builder: (_) => const SettingsNovelReaderScreen(),
        scrollKeyId: 'novel.color',
      ),
      _SettingEntry(
        icon: Icons.brightness_medium_rounded,
        title: l10n.novelBrightness,
        keywords: const <String>['亮度', '背景亮度'],
        builder: (_) => const SettingsNovelReaderScreen(),
        scrollKeyId: 'novel.color',
      ),
      _SettingEntry(
        icon: Icons.blur_on_rounded,
        title: l10n.novelTextShadow,
        keywords: const <String>['文字阴影', '阴影', '描边'],
        builder: (_) => const SettingsNovelReaderScreen(),
        scrollKeyId: 'novel.shadowUnderline',
      ),
      _SettingEntry(
        icon: Icons.format_underlined_rounded,
        title: l10n.novelUnderlineDashed,
        keywords: const <String>['下划线', '虚线', '着重号'],
        builder: (_) => const SettingsNovelReaderScreen(),
        scrollKeyId: 'novel.shadowUnderline',
      ),
      _SettingEntry(
        icon: Icons.title_rounded,
        title: l10n.novelShowChapterTitle,
        keywords: const <String>['章节标题', '显示标题'],
        builder: (_) => const SettingsNovelReaderScreen(),
        scrollKeyId: 'novel.title',
      ),
      _SettingEntry(
        icon: Icons.format_bold_rounded,
        title: l10n.novelTitleBold,
        keywords: const <String>['标题加粗', '加粗'],
        builder: (_) => const SettingsNovelReaderScreen(),
        scrollKeyId: 'novel.title',
      ),
      _SettingEntry(
        icon: Icons.format_color_text_rounded,
        title: l10n.novelTitleColor,
        keywords: const <String>['标题颜色'],
        builder: (_) => const SettingsNovelReaderScreen(),
        scrollKeyId: 'novel.title',
      ),
      _SettingEntry(
        icon: Icons.record_voice_over_rounded,
        title: l10n.ttsRate,
        keywords: const <String>['朗读速度', '语速', 'tts'],
        builder: (_) => const SettingsNovelReaderScreen(),
        scrollKeyId: 'novel.tts',
      ),
      _SettingEntry(
        icon: Icons.record_voice_over_rounded,
        title: l10n.novelTtsBackground,
        keywords: const <String>['后台朗读', '后台播放', '朗读'],
        builder: (_) => const SettingsNovelReaderScreen(),
        scrollKeyId: 'novel.tts',
      ),
      // 小说阅读器分组标题（可定位到对应卡片）：
      _SettingEntry(
        icon: Icons.menu_book_rounded,
        title: l10n.novelSettingsCommon,
        keywords: const <String>['常用设置'],
        builder: (_) => const SettingsNovelReaderScreen(),
        scrollKeyId: 'novel.common',
      ),
      _SettingEntry(
        icon: Icons.text_fields_rounded,
        title: l10n.novelSectionText,
        keywords: const <String>['阅读基础', '翻页'],
        builder: (_) => const SettingsNovelReaderScreen(),
        scrollKeyId: 'novel.text',
      ),
      _SettingEntry(
        icon: Icons.blur_on_rounded,
        title: l10n.novelSectionShadowUnderline,
        keywords: const <String>['阴影', '下划线'],
        builder: (_) => const SettingsNovelReaderScreen(),
        scrollKeyId: 'novel.shadowUnderline',
      ),
      _SettingEntry(
        icon: Icons.title_rounded,
        title: l10n.novelSectionTitle,
        keywords: const <String>['章节标题'],
        builder: (_) => const SettingsNovelReaderScreen(),
        scrollKeyId: 'novel.title',
      ),
      _SettingEntry(
        icon: Icons.apps_rounded,
        title: l10n.novelSectionHeaderFooter,
        keywords: const <String>['页眉', '页脚'],
        builder: (_) => const SettingsNovelReaderScreen(),
        scrollKeyId: 'novel.headerFooter',
      ),
      _SettingEntry(
        icon: Icons.swipe_rounded,
        title: l10n.novelSectionPage,
        keywords: const <String>['翻页', '手势'],
        builder: (_) => const SettingsNovelReaderScreen(),
        scrollKeyId: 'novel.page',
      ),
      _SettingEntry(
        icon: Icons.construction_rounded,
        title: l10n.novelSectionToolbar,
        keywords: const <String>['工具栏', '底部'],
        builder: (_) => const SettingsNovelReaderScreen(),
        scrollKeyId: 'novel.toolbar',
      ),
      _SettingEntry(
        icon: Icons.record_voice_over_rounded,
        title: l10n.novelSectionTts,
        keywords: const <String>['朗读', 'tts', '语音'],
        builder: (_) => const SettingsNovelReaderScreen(),
        scrollKeyId: 'novel.tts',
      ),
      _SettingEntry(
        icon: Icons.more_horiz_rounded,
        title: l10n.novelSectionMisc,
        keywords: const <String>['其他', '更多'],
        builder: (_) => const SettingsNovelReaderScreen(),
        scrollKeyId: 'novel.misc',
      ),
      _SettingEntry(
        icon: Icons.format_color_fill_rounded,
        title: l10n.novelShadowColor,
        keywords: const <String>['阴影颜色', '描边颜色'],
        builder: (_) => const SettingsNovelReaderScreen(),
        scrollKeyId: 'novel.shadowUnderline',
      ),
      _SettingEntry(
        icon: Icons.format_color_fill_rounded,
        title: l10n.novelUnderlineColor,
        keywords: const <String>['下划线颜色', '着重色'],
        builder: (_) => const SettingsNovelReaderScreen(),
        scrollKeyId: 'novel.shadowUnderline',
      ),
      _SettingEntry(
        icon: Icons.format_color_fill_rounded,
        title: l10n.novelHeaderFooterColor,
        keywords: const <String>['页眉页脚颜色', '页眉颜色'],
        builder: (_) => const SettingsNovelReaderScreen(),
        scrollKeyId: 'novel.headerFooter',
      ),
      // 小说滑块类设置项：
      _SettingEntry(
        icon: Icons.space_bar_rounded,
        title: l10n.novelMargin,
        keywords: const <String>['页边距', '边距'],
        builder: (_) => const SettingsNovelReaderScreen(),
        scrollKeyId: 'novel.font',
      ),
      _SettingEntry(
        icon: Icons.text_fields_rounded,
        title: l10n.novelLetterSpacing,
        keywords: const <String>['字距', '字间距'],
        builder: (_) => const SettingsNovelReaderScreen(),
        scrollKeyId: 'novel.font',
      ),
      _SettingEntry(
        icon: Icons.blur_on_rounded,
        title: l10n.novelShadowBlur,
        keywords: const <String>['阴影模糊', '模糊', '阴影大小'],
        builder: (_) => const SettingsNovelReaderScreen(),
        scrollKeyId: 'novel.shadowUnderline',
      ),
      _SettingEntry(
        icon: Icons.open_with_rounded,
        title: l10n.novelShadowOffsetX,
        keywords: const <String>['阴影偏移', '横向偏移'],
        builder: (_) => const SettingsNovelReaderScreen(),
        scrollKeyId: 'novel.shadowUnderline',
      ),
      _SettingEntry(
        icon: Icons.swap_vert_rounded,
        title: l10n.novelShadowOffsetY,
        keywords: const <String>['阴影偏移', '纵向偏移'],
        builder: (_) => const SettingsNovelReaderScreen(),
        scrollKeyId: 'novel.shadowUnderline',
      ),
      _SettingEntry(
        icon: Icons.text_fields_rounded,
        title: l10n.novelTitleFontScale,
        keywords: const <String>['标题字号', '标题大小'],
        builder: (_) => const SettingsNovelReaderScreen(),
        scrollKeyId: 'novel.title',
      ),
      _SettingEntry(
        icon: Icons.vertical_align_top_rounded,
        title: l10n.novelTitleTopMargin,
        keywords: const <String>['标题上边距'],
        builder: (_) => const SettingsNovelReaderScreen(),
        scrollKeyId: 'novel.title',
      ),
      _SettingEntry(
        icon: Icons.vertical_align_bottom_rounded,
        title: l10n.novelTitleBottomMargin,
        keywords: const <String>['标题下边距'],
        builder: (_) => const SettingsNovelReaderScreen(),
        scrollKeyId: 'novel.title',
      ),
      _SettingEntry(
        icon: Icons.notes_rounded,
        title: l10n.novelTitleSubScale,
        keywords: const <String>['副标题大小'],
        builder: (_) => const SettingsNovelReaderScreen(),
        scrollKeyId: 'novel.title',
      ),
      _SettingEntry(
        icon: Icons.notes_rounded,
        title: l10n.novelTitleSubLineSpacing,
        keywords: const <String>['副标题行距'],
        builder: (_) => const SettingsNovelReaderScreen(),
        scrollKeyId: 'novel.title',
      ),
      _SettingEntry(
        icon: Icons.space_bar_rounded,
        title: l10n.novelTitleSegmentSpacing,
        keywords: const <String>['标题段间距'],
        builder: (_) => const SettingsNovelReaderScreen(),
        scrollKeyId: 'novel.title',
      ),
      _SettingEntry(
        icon: Icons.horizontal_rule_rounded,
        title: l10n.novelUnderlineThickness,
        keywords: const <String>['下划线粗细'],
        builder: (_) => const SettingsNovelReaderScreen(),
        scrollKeyId: 'novel.shadowUnderline',
      ),
      _SettingEntry(
        icon: Icons.horizontal_rule_rounded,
        title: l10n.novelUnderlineDashLength,
        keywords: const <String>['下划线长度', '虚线长'],
        builder: (_) => const SettingsNovelReaderScreen(),
        scrollKeyId: 'novel.shadowUnderline',
      ),
      _SettingEntry(
        icon: Icons.horizontal_rule_rounded,
        title: l10n.novelUnderlineDashGap,
        keywords: const <String>['下划线间隔', '虚线间隔'],
        builder: (_) => const SettingsNovelReaderScreen(),
        scrollKeyId: 'novel.shadowUnderline',
      ),
      _SettingEntry(
        icon: Icons.horizontal_rule_rounded,
        title: l10n.novelHeaderFooterMargin,
        keywords: const <String>['页眉边距', '页脚边距'],
        builder: (_) => const SettingsNovelReaderScreen(),
        scrollKeyId: 'novel.headerFooter',
      ),

      _SettingEntry(
        icon: Icons.view_quilt_rounded,
        title: l10n.layoutSettings,
        desc: l10n.layoutSettingsDesc,
        keywords: const <String>['布局', '网格', '列数', '封面', '卡片', '排版'],
        builder: (_) => const SettingsPlaybackScreen(),
        scrollKeyId: 'playback.layout',
      ),
      _SettingEntry(
        icon: Icons.percent_rounded,
        title: l10n.watchedThreshold,
        desc: l10n.watchedThresholdHint,
        keywords: const <String>['已看', '阈值', '看完', '进度'],
        builder: (_) => const SettingsWatchedThresholdScreen(),
      ),
      _SettingEntry(
        icon: Icons.playlist_play_rounded,
        title: l10n.playbackProgressGroup,
        keywords: const <String>['播放进度', '已看', '记住位置'],
        builder: (_) => const SettingsPlaybackScreen(),
        scrollKeyId: 'playback_progress',
      ),
      _SettingEntry(
        icon: Icons.history_rounded,
        title: l10n.rememberPosition,
        desc: l10n.rememberPositionHint,
        keywords: const <String>['记住', '位置', '进度', '自动', '断点', '继续'],
        builder: (_) => const SettingsRememberPositionScreen(),
      ),

      // ───────────────── 配置与网络 ─────────────────
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.settingsCatContent,
        desc: l10n.settingsCatContentDesc,
        keywords: const <String>['配置', '网络', '内容', '源', 'ai', 'AI', '爬取', '翻译'],
        builder: (_) => const SettingsContentScreen(),
      ),
      _SettingEntry(
        icon: Icons.auto_awesome_rounded,
        title: l10n.aiSettingsEntry,
        desc: l10n.aiSettingsEntryDesc,
        keywords: const <String>[
          'ai',
          'AI',
          '接口',
          '密钥',
          '模型',
          'api',
          'openai',
          '速览',
          '总结',
          '摘要',
          '配图',
          '生图',
          '云端',
          'gpt'
        ],
        builder: (_) => const SettingsAiScreen(),
        scrollKeyId: 'ai.common',
      ),
      _SettingEntry(
        icon: Icons.insights_rounded,
        title: l10n.aiSummarySection,
        desc: l10n.aiSummaryDesc,
        keywords: const <String>['速览', '总结', '摘要', '章节速览', '离线', '云端'],
        builder: (_) => const SettingsAiScreen(),
        scrollKeyId: 'ai.summary',
      ),
      _SettingEntry(
        icon: Icons.auto_awesome_rounded,
        title: l10n.aiIllustrationSection,
        desc: l10n.aiIllustrationDesc,
        keywords: const <String>[
          '配图',
          '生图',
          '插图',
          '图片',
          '章节配图',
          'illustration',
          'ai配图'
        ],
        builder: (_) => const SettingsAiScreen(),
        scrollKeyId: 'ai.illustration',
      ),
      _SettingEntry(
        icon: Icons.translate_rounded,
        title: l10n.translationSettingsEntry,
        desc: l10n.translationSettingsEntryDesc,
        keywords: const <String>[
          '翻译',
          '双语',
          '译文',
          '目标语言',
          '段落翻译',
          'translate',
          '翻译接口'
        ],
        builder: (_) => const SettingsAiScreen(),
        scrollKeyId: 'translation.api',
      ),
      _SettingEntry(
        icon: Icons.image_search_rounded,
        title: l10n.aiComicTranslationSection,
        desc: l10n.aiComicTranslationDesc,
        keywords: const <String>[
          '漫画翻译',
          '漫画',
          '气泡',
          'OCR',
          'ocr',
          '识别',
          '视觉模型',
          'manga',
        ],
        builder: (_) => const SettingsAiScreen(),
        scrollKeyId: 'ai.comicTranslation',
      ),
      _SettingEntry(
        icon: Icons.closed_caption_rounded,
        title: l10n.aiMediaTranslationSection,
        desc: l10n.aiMediaTranslationDesc,
        keywords: const <String>[
          '视频翻译',
          '字幕翻译',
          '实时翻译',
          '视频',
          '字幕',
          'subtitle',
        ],
        builder: (_) => const SettingsAiScreen(),
        scrollKeyId: 'ai.mediaTranslation',
      ),
      _SettingEntry(
        icon: Icons.delete_sweep_rounded,
        title: l10n.translationCacheTitle,
        desc: l10n.translationCacheDesc,
        keywords: const <String>[
          '翻译缓存',
          '缓存',
          '清除',
          '清理',
          'cache',
        ],
        builder: (_) => const SettingsAiScreen(),
        scrollKeyId: 'translation.cache',
      ),
      _SettingEntry(
        icon: Icons.extension_rounded,
        title: l10n.sourceManagementTitle,
        desc: l10n.sourceManagementDesc,
        keywords: const <String>[
          '源',
          '源管理',
          '插件',
          '导入',
          '仓库',
          '源导入',
          '推荐',
          '订阅'
        ],
        builder: (_) => const SourceManagerScreen(),
      ),
      _SettingEntry(
        icon: Icons.add_circle_rounded,
        title: l10n.addSource,
        keywords: const <String>['添加源', '新增源', '导入源'],
        builder: (_) => const SourceManagerScreen(),
      ),
      _SettingEntry(
        icon: Icons.vertical_align_bottom_rounded,
        title: l10n.pullNow,
        keywords: const <String>['拉取', '立即拉取', '更新源'],
        builder: (_) => const SourceManagerScreen(),
      ),
      _SettingEntry(
        icon: Icons.travel_explore_rounded,
        title: l10n.webScrapeSetting,
        desc: l10n.webScrapeSettingSameAsBrowse,
        keywords: const <String>['网页', '爬取', '嗅探', 'scrape', '抓取'],
        builder: (_) => const BrowseWebScrapeScreen(),
      ),
      _SettingEntry(
        icon: Icons.lan_rounded,
        title: l10n.networkSettingsTitle,
        desc: l10n.networkSettingsDesc,
        keywords: const <String>[
          '网络',
          '代理',
          'dns',
          'doh',
          'dot',
          'sni',
          'hosts',
          '翻墙',
          'vpn'
        ],
        builder: (_) => const SettingsNetworkScreen(),
      ),
      // 网络子页内具体项（滚动定位）：
      _SettingEntry(
        icon: Icons.vpn_key_rounded,
        title: l10n.networkProxyTitle,
        keywords: const <String>['代理', 'proxy', 'http代理', 'socks'],
        builder: (_) => const SettingsNetworkScreen(),
        scrollKeyId: 'network.proxy',
      ),
      _SettingEntry(
        icon: Icons.dns_rounded,
        title: l10n.networkDnsTitle,
        keywords: const <String>['dns', '域名解析', 'dns服务器'],
        builder: (_) => const SettingsNetworkScreen(),
        scrollKeyId: 'network.dns',
      ),
      _SettingEntry(
        icon: Icons.lock_rounded,
        title: l10n.networkDohTitle,
        keywords: const <String>['doh', 'https', '加密dns'],
        builder: (_) => const SettingsNetworkScreen(),
        scrollKeyId: 'network.doh',
      ),
      _SettingEntry(
        icon: Icons.lock_clock_rounded,
        title: l10n.networkDotTitle,
        keywords: const <String>['dot', 'tls', '加密dns'],
        builder: (_) => const SettingsNetworkScreen(),
        scrollKeyId: 'network.dot',
      ),
      _SettingEntry(
        icon: Icons.badge_rounded,
        title: l10n.networkSniTitle,
        keywords: const <String>['sni', '域名', '指纹'],
        builder: (_) => const SettingsNetworkScreen(),
        scrollKeyId: 'network.sni',
      ),
      _SettingEntry(
        icon: Icons.enhanced_encryption_rounded,
        title: l10n.networkEchTitle,
        keywords: const <String>['ech', '加密', '问候'],
        builder: (_) => const SettingsNetworkScreen(),
        scrollKeyId: 'network.ech',
      ),
      _SettingEntry(
        icon: Icons.edit_document,
        title: l10n.networkHostsTitle,
        keywords: const <String>['hosts', 'host', '自定义', '域名映射'],
        builder: (_) => const SettingsNetworkScreen(),
        scrollKeyId: 'network.hosts',
      ),
      // 网络子页内更细的设置项：
      _SettingEntry(
        icon: Icons.add_box_rounded,
        title: l10n.networkAddHost,
        keywords: const <String>['添加host', '新增域名', 'hosts添加'],
        builder: (_) => const SettingsNetworkScreen(),
        scrollKeyId: 'network.hosts',
      ),
      _SettingEntry(
        icon: Icons.cleaning_services_rounded,
        title: l10n.networkClearCache,
        keywords: const <String>['dns缓存', '清除缓存', 'dns'],
        builder: (_) => const SettingsNetworkScreen(),
        scrollKeyId: 'network.dns',
      ),
      _SettingEntry(
        icon: Icons.restore_rounded,
        title: l10n.networkReset,
        keywords: const <String>['重置', '恢复默认', '还原网络'],
        builder: (_) => const SettingsNetworkScreen(),
      ),
      _SettingEntry(
        icon: Icons.help_rounded,
        title: l10n.networkHelpDoc,
        keywords: const <String>['帮助', '文档', '说明', '教程'],
        builder: (_) => const SettingsNetworkScreen(),
        scrollKeyId: 'network.info',
      ),
      _SettingEntry(
        icon: Icons.badge_rounded,
        title: l10n.networkSniEnabled,
        keywords: const <String>['sni开关', '加密sni', 'tls指纹'],
        builder: (_) => const SettingsNetworkScreen(),
        scrollKeyId: 'network.sni',
      ),
      _SettingEntry(
        icon: Icons.enhanced_encryption_rounded,
        title: l10n.networkEchEnabled,
        keywords: const <String>['ech开关', '加密问候'],
        builder: (_) => const SettingsNetworkScreen(),
        scrollKeyId: 'network.ech',
      ),
      _SettingEntry(
        icon: Icons.dns_rounded,
        title: l10n.networkDnsServers,
        keywords: const <String>['dns服务器', 'dns地址', '域名服务器'],
        builder: (_) => const SettingsNetworkScreen(),
        scrollKeyId: 'network.dns',
      ),
      _SettingEntry(
        icon: Icons.storage_rounded,
        title: l10n.networkDnsCacheEnabled,
        keywords: const <String>['dns缓存', '缓存开关'],
        builder: (_) => const SettingsNetworkScreen(),
        scrollKeyId: 'network.dns',
      ),
      _SettingEntry(
        icon: Icons.info_rounded,
        title: l10n.networkInfoTitle,
        keywords: const <String>['网络说明', '网络信息'],
        builder: (_) => const SettingsNetworkScreen(),
        scrollKeyId: 'network.info',
      ),

      // ───────────────── 数据与账户 ─────────────────
      _SettingEntry(
        icon: Icons.storage_rounded,
        title: l10n.settingsCatData,
        desc: l10n.settingsCatDataDesc,
        keywords: const <String>['数据', '账户'],
        builder: (_) => const SettingsDataScreen(),
      ),
      _SettingEntry(
        icon: Icons.bar_chart_rounded,
        title: l10n.statsOverviewTitle,
        keywords: const <String>['统计', '阅读', '观看', '时长', '阅读时长', '观看时长', '热力图'],
        builder: (_) => const StatsOverviewScreen(),
      ),
      _SettingEntry(
        icon: Icons.folder_rounded,
        title: l10n.categoriesManageTitle,
        desc: l10n.categoriesManageDesc,
        keywords: const <String>['分类', '收藏分类', '分组', '文件夹'],
        builder: (_) => const SettingsCategoriesScreen(),
      ),
      _SettingEntry(
        icon: Icons.create_new_folder_rounded,
        title: l10n.newGroup,
        keywords: const <String>['新建分组', '新增分组', '创建分类'],
        builder: (_) => const SettingsCategoriesScreen(),
      ),
      _SettingEntry(
        icon: Icons.drive_file_rename_outline_rounded,
        title: l10n.renameGroup,
        keywords: const <String>['重命名', '改名', '分组改名'],
        builder: (_) => const SettingsCategoriesScreen(),
      ),
      _SettingEntry(
        icon: Icons.delete_rounded,
        title: l10n.deleteGroup,
        keywords: const <String>['删除分组', '删除分类'],
        builder: (_) => const SettingsCategoriesScreen(),
      ),
      _SettingEntry(
        icon: Icons.download_rounded,
        title: l10n.downloadManagementTitle,
        keywords: const <String>['下载', '下载管理', '任务', '队列', '速度'],
        builder: (_) => const SettingsDownloadScreen(),
      ),
      // 下载子页内具体项（滚动定位）：
      _SettingEntry(
        icon: Icons.folder_open_rounded,
        title: l10n.downloadPath,
        keywords: const <String>['下载路径', '目录', '保存位置', '存储路径'],
        builder: (_) => const SettingsDownloadScreen(),
        scrollKeyId: 'download.path',
      ),
      _SettingEntry(
        icon: Icons.wifi_rounded,
        title: l10n.downloadWifiOnly,
        keywords: const <String>['wifi', '无线', '流量', '移动网络'],
        builder: (_) => const SettingsDownloadScreen(),
        scrollKeyId: 'download.wifiOnly',
      ),
      _SettingEntry(
        icon: Icons.download_for_offline_rounded,
        title: l10n.downloadPreDownload,
        keywords: const <String>['预下载', '后续', '缓存下一集'],
        builder: (_) => const SettingsDownloadScreen(),
        scrollKeyId: 'download.preDownload',
      ),
      _SettingEntry(
        icon: Icons.auto_delete_rounded,
        title: l10n.downloadAutoDelete,
        keywords: const <String>['自动删除', '读完删除', '清理'],
        builder: (_) => const SettingsDownloadScreen(),
        scrollKeyId: 'download.autoDelete',
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.maxConcurrentDownloads,
        keywords: const <String>['同时下载', '并发', '最大下载数'],
        builder: (_) => const SettingsDownloadScreen(),
        scrollKeyId: 'download.concurrent',
      ),
      _SettingEntry(
        icon: Icons.bolt_rounded,
        title: l10n.threadCount,
        keywords: const <String>['线程', '线程数', '分片'],
        builder: (_) => const SettingsDownloadScreen(),
        scrollKeyId: 'download.thread',
      ),
      // 下载子页内更细的设置项：
      _SettingEntry(
        icon: Icons.list_alt_rounded,
        title: l10n.downloadListTitle,
        keywords: const <String>['下载列表', '任务列表', '正在下载'],
        builder: (_) => const SettingsDownloadScreen(),
        scrollKeyId: 'download.list',
      ),
      _SettingEntry(
        icon: Icons.download_done_rounded,
        title: l10n.downloadedContent,
        keywords: const <String>['已下载', '下载完成', '已下载内容'],
        builder: (_) => const SettingsDownloadScreen(),
        scrollKeyId: 'download.downloaded',
      ),
      _SettingEntry(
        icon: Icons.cloud_download_rounded,
        title: l10n.downloaderType,
        keywords: const <String>['下载器', '下载器类型', '引擎'],
        builder: (_) => const SettingsDownloadScreen(),
        scrollKeyId: 'download.downloaderType',
      ),
      _SettingEntry(
        icon: Icons.picture_as_pdf_rounded,
        title: l10n.comicFormatSelectTitle,
        keywords: const <String>['漫画格式', 'cbz', 'epub', '下载格式'],
        builder: (_) => const SettingsDownloadScreen(),
        scrollKeyId: 'download.comicFormat',
      ),
      _SettingEntry(
        icon: Icons.menu_book_rounded,
        title: l10n.novelFormatSelectTitle,
        keywords: const <String>['小说格式', 'txt', 'epub', '下载格式'],
        builder: (_) => const SettingsDownloadScreen(),
        scrollKeyId: 'download.novelFormat',
      ),
      _SettingEntry(
        icon: Icons.remove_circle_rounded,
        title: l10n.downloadAutoDeleteExclude,
        keywords: const <String>['自动删除排除', '排除分类', '保留'],
        builder: (_) => const SettingsDownloadScreen(),
        scrollKeyId: 'download.autoDeleteExclude',
      ),
      _SettingEntry(
        icon: Icons.swap_vert_rounded,
        title: l10n.dataImportExport,
        keywords: const <String>['导入', '导出', '备份', '还原', '迁移', '导出数据'],
        builder: (_) => const SettingsImportExportScreen(),
      ),
      _SettingEntry(
        icon: Icons.extension_rounded,
        title: l10n.exportPlugins,
        keywords: const <String>['导出插件', '插件', '备份源', '源备份'],
        builder: (_) => const SettingsImportExportScreen(),
      ),
      _SettingEntry(
        icon: Icons.cloud_sync_rounded,
        title: l10n.cloudSync,
        keywords: const <String>['云', '同步', 'cloud', 'webdav', '云端'],
        builder: (_) => const SettingsCloudSyncScreen(),
      ),
      _SettingEntry(
        icon: Icons.autorenew_rounded,
        title: l10n.cloudSyncAutoSync,
        keywords: const <String>['自动同步', '定时同步'],
        builder: (_) => const SettingsCloudSyncScreen(),
      ),
      // 云同步子页内更细的设置项：
      _SettingEntry(
        icon: Icons.sync_rounded,
        title: l10n.cloudSyncSyncNow,
        keywords: const <String>['立即同步', '同步', '现在同步'],
        builder: (_) => const SettingsCloudSyncScreen(),
      ),
      _SettingEntry(
        icon: Icons.wifi_tethering_rounded,
        title: l10n.cloudSyncTestConnection,
        keywords: const <String>['测试连接', '连接测试', '测试'],
        builder: (_) => const SettingsCloudSyncScreen(),
      ),
      _SettingEntry(
        icon: Icons.save_rounded,
        title: l10n.cloudSyncSaveConfig,
        keywords: const <String>['保存配置', '保存', '保存设置'],
        builder: (_) => const SettingsCloudSyncScreen(),
      ),
      _SettingEntry(
        icon: Icons.call_split_rounded,
        title: l10n.cloudSyncResolveConflicts,
        keywords: const <String>['冲突', '冲突处理', '解决冲突'],
        builder: (_) => const SettingsCloudSyncScreen(),
      ),
      _SettingEntry(
        icon: Icons.schedule_rounded,
        title: l10n.cloudSyncSyncFrequencyManual,
        keywords: const <String>['同步频率', '手动', '每天', '每周'],
        builder: (_) => const SettingsCloudSyncScreen(),
      ),
      _SettingEntry(
        icon: Icons.merge_rounded,
        title: l10n.backupMerge,
        keywords: const <String>['备份合并', '合并', 'merge'],
        builder: (_) => const SettingsCloudSyncScreen(),
      ),
      _SettingEntry(
        icon: Icons.swap_horiz_rounded,
        title: l10n.backupReplace,
        keywords: const <String>['备份替换', '替换', 'replace'],
        builder: (_) => const SettingsCloudSyncScreen(),
      ),
      _SettingEntry(
        icon: Icons.live_tv_rounded,
        title: l10n.bangumiSettings,
        keywords: const <String>['bangumi', '番组', '评分', '同步', '账户', 'bgm'],
        builder: (_) => const SettingsBangumiScreen(),
      ),
      _SettingEntry(
        icon: Icons.video_library_rounded,
        title: l10n.mediaServerSettings,
        desc: l10n.mediaServerSettingsDesc,
        keywords: const <String>[
          '媒体服务器',
          'emby',
          'jellyfin',
          '服务器',
          'nas',
          '影音',
          '家庭影院',
          'media server'
        ],
        builder: (_) => const MediaServerManageScreen(),
      ),
      // 订阅 / RSS 相关：
      _SettingEntry(
        icon: Icons.rss_feed_rounded,
        title: l10n.rssFeedListTitle,
        desc: l10n.rssGlobalSubscriptionDesc,
        keywords: const <String>['rss', '订阅', '订阅源', '订阅列表', 'feed', '信息源'],
        builder: (_) => const RssFeedListScreen(moduleType: null),
      ),
      _SettingEntry(
        icon: Icons.bookmark_rounded,
        title: l10n.rssFavorites,
        desc: l10n.rssFavoritesDesc,
        keywords: const <String>[
          'rss',
          '收藏',
          'rss收藏',
          '星标',
          'favorites',
          '已收藏文章'
        ],
        builder: (_) => const RssFavoritesScreen(),
      ),
      _SettingEntry(
        icon: Icons.notifications_rounded,
        title: l10n.rssNotificationsTitle,
        keywords: const <String>['rss', '订阅通知', '更新通知'],
        builder: (_) => const SettingsRssNotificationsScreen(),
      ),
      _SettingEntry(
        icon: Icons.notifications_active_rounded,
        title: l10n.rssNotificationEnabled,
        keywords: const <String>['通知开关', '更新提醒'],
        builder: (_) => const SettingsRssNotificationsScreen(),
      ),
      _SettingEntry(
        icon: Icons.update_rounded,
        title: l10n.rssUpdateInterval,
        keywords: const <String>['更新间隔', '刷新频率'],
        builder: (_) => const SettingsRssNotificationsScreen(),
      ),
      _SettingEntry(
        icon: Icons.refresh_rounded,
        title: l10n.rssCheckNow,
        keywords: const <String>['立即检查', '检查更新', '刷新订阅'],
        builder: (_) => const SettingsRssNotificationsScreen(),
      ),
      _SettingEntry(
        icon: Icons.dns_rounded,
        title: l10n.rsshubSettingsTitle,
        keywords: const <String>['rsshub', '订阅源', '自建实例'],
        builder: (_) => const SettingsRssHubScreen(),
      ),
      // RSSHub 子页内更细的设置项：
      _SettingEntry(
        icon: Icons.public_rounded,
        title: l10n.currentInstance,
        keywords: const <String>['当前实例', 'rsshub地址', '实例地址'],
        builder: (_) => const SettingsRssHubScreen(),
        scrollKeyId: 'rsshub.current',
      ),
      _SettingEntry(
        icon: Icons.view_list_rounded,
        title: l10n.presetInstances,
        keywords: const <String>['预设实例', '官方实例', '公共实例'],
        builder: (_) => const SettingsRssHubScreen(),
        scrollKeyId: 'rsshub.preset',
      ),
      _SettingEntry(
        icon: Icons.add_link_rounded,
        title: l10n.customInstance,
        keywords: const <String>['自定义实例', '自建', '私有实例'],
        builder: (_) => const SettingsRssHubScreen(),
        scrollKeyId: 'rsshub.custom',
      ),
      _SettingEntry(
        icon: Icons.speed_rounded,
        title: l10n.rsshubTestAll,
        keywords: const <String>['测试', '测速', '全部实例', '延迟'],
        builder: (_) => const SettingsRssHubScreen(),
        scrollKeyId: 'rsshub.preset',
      ),
      _SettingEntry(
        icon: Icons.settings_backup_restore_rounded,
        title: l10n.restoreDefault,
        keywords: const <String>['恢复默认', '重置', '默认实例'],
        builder: (_) => const SettingsRssHubScreen(),
        scrollKeyId: 'rsshub.restore',
      ),
      _SettingEntry(
        icon: Icons.help_rounded,
        title: l10n.rsshubTroubleshoot,
        desc: l10n.rsshubTroubleshootHint,
        keywords: const <String>['故障', '排查', '帮助', '无法连接'],
        builder: (_) => const SettingsRssHubScreen(),
        scrollKeyId: 'rsshub.troubleshoot',
      ),
      // Bangumi 子页内更细的设置项：
      _SettingEntry(
        icon: Icons.login_rounded,
        title: l10n.bangumiLoginWithOAuth,
        keywords: const <String>['登录', 'oauth', '授权登录', 'bgm登录'],
        builder: (_) => const SettingsBangumiScreen(),
      ),
      _SettingEntry(
        icon: Icons.key_rounded,
        title: l10n.bangumiGetToken,
        keywords: const <String>['token', '令牌', '手动输入'],
        builder: (_) => const SettingsBangumiScreen(),
      ),
      _SettingEntry(
        icon: Icons.verified_rounded,
        title: l10n.bangumiTokenVerify,
        keywords: const <String>['验证', '校验token', '连接'],
        builder: (_) => const SettingsBangumiScreen(),
      ),
      // 云同步 / Bangumi 选项标签：
      _SettingEntry(
        icon: Icons.swap_horiz_rounded,
        title: l10n.cloudSyncConflictKeepLocal,
        keywords: const <String>['冲突', '保留本地'],
        builder: (_) => const SettingsCloudSyncScreen(),
      ),
      _SettingEntry(
        icon: Icons.merge_rounded,
        title: l10n.cloudSyncConflictMerge,
        keywords: const <String>['冲突', '合并'],
        builder: (_) => const SettingsCloudSyncScreen(),
      ),
      _SettingEntry(
        icon: Icons.cloud_done_rounded,
        title: l10n.cloudSyncConflictUseRemote,
        keywords: const <String>['冲突', '使用远端'],
        builder: (_) => const SettingsCloudSyncScreen(),
      ),
      _SettingEntry(
        icon: Icons.schedule_rounded,
        title: l10n.cloudSyncSyncFrequencyDaily,
        keywords: const <String>['同步频率', '每天同步'],
        builder: (_) => const SettingsCloudSyncScreen(),
      ),
      _SettingEntry(
        icon: Icons.schedule_rounded,
        title: l10n.cloudSyncSyncFrequencyWeekly,
        keywords: const <String>['同步频率', '每周同步'],
        builder: (_) => const SettingsCloudSyncScreen(),
      ),
      _SettingEntry(
        icon: Icons.bolt_rounded,
        title: l10n.bangumiProxyDirect,
        keywords: const <String>['bgm代理', '直连'],
        builder: (_) => const SettingsBangumiScreen(),
      ),
      _SettingEntry(
        icon: Icons.gpp_maybe_rounded,
        title: l10n.bangumiProxyMirror,
        keywords: const <String>['bgm代理', '镜像'],
        builder: (_) => const SettingsBangumiScreen(),
      ),
      _SettingEntry(
        icon: Icons.file_upload_rounded,
        title: l10n.exportData,
        desc: l10n.exportDataDesc,
        keywords: const <String>['导出数据', '数据备份'],
        builder: (_) => const SettingsImportExportScreen(),
      ),
      _SettingEntry(
        icon: Icons.file_download_rounded,
        title: l10n.importData,
        desc: l10n.importDataDesc,
        keywords: const <String>['导入数据', '数据恢复'],
        builder: (_) => const SettingsImportExportScreen(),
      ),
      _SettingEntry(
        icon: Icons.chat_bubble_rounded,
        title: l10n.danmakuAccountSection,
        keywords: const <String>[
          '弹弹',
          '弹弹play',
          '账号',
          '弹幕账号',
          'dandanplay',
          '登录'
        ],
        builder: (_) => const SettingsDandanplayAccountScreen(),
      ),
      _SettingEntry(
        icon: Icons.login_rounded,
        title: l10n.danmakuLoginAction,
        keywords: const <String>['登录', '弹弹登录', '账号登录'],
        builder: (_) => const SettingsDandanplayAccountScreen(),
      ),
      _SettingEntry(
        icon: Icons.person_add_alt_rounded,
        title: l10n.dandanplayRegisterAction,
        keywords: const <String>['注册', '新用户', '创建账号'],
        builder: (_) => const SettingsDandanplayAccountScreen(),
      ),

      // ───────────────── 隐私与安全 ─────────────────
      _SettingEntry(
        icon: Icons.shield_rounded,
        title: l10n.settingsCatPrivacy,
        desc: l10n.settingsCatPrivacyDesc,
        keywords: const <String>['隐私', '安全'],
        builder: (_) => const SettingsPrivacySecurityScreen(),
      ),
      _SettingEntry(
        icon: Icons.privacy_tip_rounded,
        title: l10n.privacySettingsTitle,
        desc: l10n.privacySettingsDesc,
        keywords: const <String>['通知', '打码', '隐身', '敏感', '无痕', '隐私'],
        builder: (_) => const SettingsPrivacyScreen(),
      ),
      // 隐私子页内具体项（滚动定位）：
      _SettingEntry(
        icon: Icons.visibility_off_rounded,
        title: l10n.globalIncognito,
        desc: l10n.globalIncognitoHint,
        keywords: const <String>['无痕', '隐身', '浏览', '隐私'],
        builder: (_) => const SettingsPrivacyScreen(),
        scrollKeyId: 'privacy.incognito',
      ),
      _SettingEntry(
        icon: Icons.notifications_off_rounded,
        title: l10n.hideNotificationContent,
        desc: l10n.hideNotificationContentHint,
        keywords: const <String>['通知', '打码', '通知内容', '消息'],
        builder: (_) => const SettingsPrivacyScreen(),
        scrollKeyId: 'privacy.hideNotification',
      ),
      _SettingEntry(
        icon: Icons.notifications_rounded,
        title: l10n.privacyNotificationsGroup,
        keywords: const <String>['通知', '打码'],
        builder: (_) => const SettingsPrivacyScreen(),
        scrollKeyId: 'privacy.notifications',
      ),
      _SettingEntry(
        icon: Icons.network_check_rounded,
        title: l10n.privacyNetworkGroup,
        keywords: const <String>['无痕', '隐身'],
        builder: (_) => const SettingsPrivacyScreen(),
        scrollKeyId: 'privacy.network',
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.advancedSettingsTitle,
        desc: l10n.advancedSettingsDesc,
        keywords: const <String>[
          '高级',
          '崩溃',
          '日志',
          '数据清理',
          '指纹',
          '调试',
          '开发者',
          '详细'
        ],
        builder: (_) => const SettingsAdvancedScreen(),
      ),
      // 高级子页内具体项（滚动定位）：
      _SettingEntry(
        icon: Icons.article_rounded,
        title: l10n.detailedLogging,
        desc: l10n.detailedLoggingHint,
        keywords: const <String>['日志', '详细', 'debug', '调试'],
        builder: (_) => const SettingsAdvancedScreen(),
        scrollKeyId: 'advanced.detailedLogging',
      ),
      _SettingEntry(
        icon: Icons.bug_report_rounded,
        title: l10n.crashLog,
        desc: l10n.crashLogDesc,
        keywords: const <String>['崩溃', 'crash', '崩溃日志'],
        builder: (_) => const SettingsAdvancedScreen(),
        scrollKeyId: 'advanced.crashLog',
      ),
      _SettingEntry(
        icon: Icons.cookie_rounded,
        title: l10n.clearCookies,
        desc: l10n.clearCookiesDesc,
        keywords: const <String>['cookie', '清除cookie', '删除cookie'],
        builder: (_) => const SettingsAdvancedScreen(),
        scrollKeyId: 'advanced.clearCookies',
      ),
      // 高级设置分组标题：
      _SettingEntry(
        icon: Icons.article_rounded,
        title: l10n.advancedLogGroup,
        keywords: const <String>['日志', 'debug'],
        builder: (_) => const SettingsAdvancedScreen(),
        scrollKeyId: 'advanced.log',
      ),
      _SettingEntry(
        icon: Icons.cleaning_services_rounded,
        title: l10n.advancedCleanGroup,
        keywords: const <String>['数据清理', '清除'],
        builder: (_) => const SettingsAdvancedScreen(),
        scrollKeyId: 'advanced.clean',
      ),
      _SettingEntry(
        icon: Icons.fingerprint_rounded,
        title: l10n.advancedRequestGroup,
        keywords: const <String>['请求指纹', '指纹', 'ua'],
        builder: (_) => const SettingsAdvancedScreen(),
        scrollKeyId: 'advanced.request',
      ),
      _SettingEntry(
        icon: Icons.badge_rounded,
        title: l10n.defaultUserAgent,
        keywords: const <String>['ua', 'useragent', '指纹', '请求头'],
        builder: (_) => const SettingsAdvancedScreen(),
        scrollKeyId: 'advanced.request',
      ),
      _SettingEntry(
        icon: Icons.cached_rounded,
        title: l10n.userAgentAuto,
        keywords: const <String>['自动ua', '指纹轮换'],
        builder: (_) => const SettingsAdvancedScreen(),
        scrollKeyId: 'advanced.request',
      ),
      // 缓存管理（分类占用 + 单独清理 + 自动清理）：替代原先只指向
      // 「清除 WebView 数据」的条目，关键词同时覆盖 webview / 清理 / 分类 / 自动。
      _SettingEntry(
        icon: Icons.sd_storage_rounded,
        title: l10n.cacheManagerTitle,
        desc: l10n.cacheManagerTotalDesc(l10n.cacheSizeUnknown),
        keywords: const <String>[
          '缓存',
          '缓存管理',
          '缓存分类',
          '清理缓存',
          '清除缓存',
          '清缓存',
          '自动清理',
          'webview数据',
          '清除webview',
          '网页数据',
          '图片缓存',
          '弹幕缓存',
          '翻译缓存',
          '临时文件',
          '更新包',
          'cache',
          'cleanup',
        ],
        builder: (_) => const SettingsCacheManagerScreen(),
      ),
      _SettingEntry(
        icon: Icons.bug_report_rounded,
        title: l10n.crashLogTitle,
        desc: l10n.crashLogDesc,
        keywords: const <String>['崩溃', '日志', '异常', '错误', '闪退', 'crash'],
        builder: (_) => const CrashLogScreen(),
      ),
      _SettingEntry(
        icon: Icons.article_rounded,
        title: l10n.runtimeLog,
        desc: l10n.runtimeLogDesc,
        keywords: const <String>['日志', '运行日志', '网络请求', '响应', 'log', '详细日志'],
        builder: (_) => const LogViewerScreen(),
      ),
      _SettingEntry(
        icon: Icons.colorize_rounded,
        title: l10n.customBgColor,
        keywords: const <String>['自定义背景色', '背景色', '底色'],
        builder: (_) => const SettingsNovelReaderScreen(),
        scrollKeyId: 'novel.color',
      ),
      _SettingEntry(
        icon: Icons.title_rounded,
        title: l10n.novelTitleSegmentMode,
        keywords: const <String>['标题分段', '分段模式'],
        builder: (_) => const SettingsNovelReaderScreen(),
        scrollKeyId: 'novel.title',
      ),
      _SettingEntry(
        icon: Icons.no_adult_content_rounded,
        title: l10n.ageRestriction,
        desc: l10n.ageRestrictionHint,
        keywords: const <String>['年龄', '限制', '成人', 'age', '未成年', '分级'],
        builder: (_) => const SettingsPrivacySecurityScreen(),
        scrollKeyId: 'privacy.ageRestriction',
      ),
      // 注：原「清除缓存」快捷项（指向隐私与安全页的内联清理）已随该入口一并
      // 移除，缓存清理统一由上面的「缓存管理」条目承担（分类 + 自动清理）。

      // ───────────────── 关于 ─────────────────
      _SettingEntry(
        icon: Icons.info_rounded,
        title: l10n.settingsCatAbout,
        desc: l10n.settingsCatAboutDesc,
        keywords: const <String>[
          '关于',
          '版本',
          '许可',
          '致谢',
          '开源',
          '仓库',
          '更新',
          '版权',
          '鸣谢'
        ],
        builder: (_) => const AboutScreen(),
      ),
      _SettingEntry(
        icon: Icons.update_rounded,
        title: l10n.checkUpdate,
        keywords: const <String>['更新', '检查更新', '版本'],
        builder: (_) => const AboutScreen(),
      ),
      _SettingEntry(
        icon: Icons.system_update_alt_rounded,
        title: l10n.updateSettings,
        desc: l10n.updateSettingsDesc,
        keywords: PlatformService.instance.isOHOS
            ? const <String>[
                '更新设置',
                '检查更新',
                '升级通道',
                '稳定版',
                '测试版',
              ]
            : const <String>[
                '镜像',
                '更新源',
                '下载源',
                'mirror',
                '更新镜像',
                '更新设置',
                '检查更新',
                '升级通道',
                '稳定版',
                '测试版',
                '自动下载',
                '应用内下载',
                'WiFi',
                '无线'
              ],
        builder: (_) => const SettingsUpdateScreen(),
      ),
      // 更新设置页内更细的设置项：
      _SettingEntry(
        icon: Icons.shield_rounded,
        title: l10n.updateChannelSection,
        desc: l10n.updateChannelStableDesc,
        keywords: const <String>[
          '升级通道',
          '稳定版',
          '测试版',
          'beta',
          '正式版',
          '预发布',
          '通道',
          '尝鲜'
        ],
        builder: (_) => const SettingsUpdateScreen(),
        scrollKeyId: 'update.channel',
      ),
      _SettingEntry(
        icon: Icons.notifications_active_rounded,
        title: l10n.updateAutoCheck,
        desc: l10n.updateAutoCheckDesc,
        keywords: const <String>['自动检查', '检查更新', '版本检测'],
        builder: (_) => const SettingsUpdateScreen(),
        scrollKeyId: 'update.autoCheck',
      ),
      // 鸿蒙已移除内置更新：下载 / 镜像相关搜索入口同步隐藏。
      if (!PlatformService.instance.isOHOS) ...<_SettingEntry>[
        _SettingEntry(
          icon: Icons.download_for_offline_rounded,
          title: l10n.updateAutoDownload,
          desc: l10n.updateAutoDownloadDesc,
          keywords: const <String>['自动下载', '静默下载', '后台下载', '安装包'],
          builder: (_) => const SettingsUpdateScreen(),
          scrollKeyId: 'update.autoDownload',
        ),
        _SettingEntry(
          icon: Icons.wifi_rounded,
          title: l10n.updateWifiOnlyAutoDownload,
          desc: l10n.updateWifiOnlyAutoDownloadDesc,
          keywords: const <String>['WiFi', '无线', '流量', '移动网络', '省流量'],
          builder: (_) => const SettingsUpdateScreen(),
          scrollKeyId: 'update.wifiOnly',
        ),
        _SettingEntry(
          icon: Icons.storage_rounded,
          title: l10n.updateInAppDownload,
          desc: l10n.updateInAppDownloadDesc,
          keywords: const <String>['应用内下载', '浏览器下载', '下载方式'],
          builder: (_) => const SettingsUpdateScreen(),
          scrollKeyId: 'update.inAppDownload',
        ),
        _SettingEntry(
          icon: Icons.cloud_rounded,
          title: l10n.updateMirrorSelection,
          desc: l10n.updateMirrorSection,
          keywords: const <String>[
            '镜像',
            '加速',
            '下载源',
            '测速',
            'ghproxy',
            'mirror',
            '选择镜像'
          ],
          builder: (_) => const SettingsUpdateScreen(),
          scrollKeyId: 'update.mirror',
        ),
        _SettingEntry(
          icon: Icons.speed_rounded,
          title: l10n.updateTestMirrors,
          keywords: const <String>['测速', '测试镜像', '延迟', '速度'],
          builder: (_) => const SettingsUpdateScreen(),
          scrollKeyId: 'update.mirror',
        ),
      ],
      _SettingEntry(
        icon: Icons.code_rounded,
        title: l10n.projectRepository,
        desc: l10n.aboutGithubDesc,
        keywords: const <String>[
          '仓库',
          '源码',
          'github',
          '项目',
          '联系',
          '反馈',
          'issue',
        ],
        builder: (_) => const AboutScreen(),
      ),
      _SettingEntry(
        icon: Icons.forum_rounded,
        title: l10n.aboutQqGroup,
        desc: l10n.aboutQqGroupDesc(kQqGroupNumber),
        keywords: const <String>[
          'qq',
          'qq群',
          '群',
          '群号',
          '交流',
          '联系',
          '反馈',
        ],
        builder: (_) => const AboutScreen(),
      ),
      _SettingEntry(
        icon: Icons.favorite_rounded,
        title: l10n.acknowledgements,
        keywords: const <String>['致谢', '鸣谢', '感谢', '开源'],
        builder: (_) => const AboutScreen(),
      ),
      // 关于页内更细的设置项：
      _SettingEntry(
        icon: Icons.campaign_rounded,
        title: l10n.appAnnouncement,
        desc: l10n.announcementSettingsDesc,
        keywords: const <String>[
          '公告',
          '更新公告',
          '通知',
          'announcement',
          'release notes',
          '版本说明',
        ],
        builder: (_) => const SettingsAnnouncementsScreen(),
      ),
      _SettingEntry(
        icon: Icons.info_rounded,
        title: l10n.aboutAppTitle,
        keywords: const <String>['关于应用', '应用介绍', '简介'],
        builder: (_) => const AboutScreen(),
      ),
      _SettingEntry(
        icon: Icons.description_rounded,
        title: l10n.openSourceLicenses,
        keywords: const <String>['开源许可', 'licenses', '许可', '协议'],
        builder: (_) => const AboutScreen(),
      ),
      _SettingEntry(
        icon: Icons.library_books_rounded,
        title: l10n.thirdPartyLibraries,
        keywords: const <String>['第三方', '库', '依赖', '三方库'],
        builder: (_) => const AboutScreen(),
      ),
      // 精细化搜索补全：comic.webtoonLimit
      _SettingEntry(
        icon: Icons.image_rounded,
        title: l10n.readerWebtoonDecodeLimit,
        keywords: const <String>['漫画', '阅读'],
        builder: (_) => const SettingsComicReaderScreen(),
        scrollKeyId: 'comic.webtoonLimit',
      ),
      // 精细化搜索补全：comic.skipRead
      _SettingEntry(
        icon: Icons.image_rounded,
        title: l10n.readerSkipReadChapters,
        keywords: const <String>['漫画', '阅读'],
        builder: (_) => const SettingsComicReaderScreen(),
        scrollKeyId: 'comic.skipRead',
      ),
      // 精细化搜索补全：comic.einkToggle
      _SettingEntry(
        icon: Icons.image_rounded,
        title: l10n.readerEInkRefresh,
        keywords: const <String>['漫画', '阅读'],
        builder: (_) => const SettingsComicReaderScreen(),
        scrollKeyId: 'comic.einkToggle',
      ),
      // 精细化搜索补全：comic.preload
      _SettingEntry(
        icon: Icons.image_rounded,
        title: l10n.readerPreloadCount,
        keywords: const <String>['漫画', '阅读'],
        builder: (_) => const SettingsComicReaderScreen(),
        scrollKeyId: 'comic.preload',
      ),
      // 精细化搜索补全：comic.volumeDistance
      _SettingEntry(
        icon: Icons.image_rounded,
        title: l10n.readerVolumeKeyDistance,
        keywords: const <String>['漫画', '阅读'],
        builder: (_) => const SettingsComicReaderScreen(),
        scrollKeyId: 'comic.volumeDistance',
      ),
      // 精细化搜索补全：comic.autoDownload
      _SettingEntry(
        icon: Icons.image_rounded,
        title: l10n.readerAutoDownload,
        keywords: const <String>['漫画', '阅读'],
        builder: (_) => const SettingsComicReaderScreen(),
        scrollKeyId: 'comic.autoDownload',
      ),
      // 精细化搜索补全：comic.clockOpacity
      _SettingEntry(
        icon: Icons.image_rounded,
        title: l10n.readerClockOpacity,
        keywords: const <String>['漫画', '阅读'],
        builder: (_) => const SettingsComicReaderScreen(),
        scrollKeyId: 'comic.clockOpacity',
      ),
      // 精细化搜索补全：comic.chapterSlider
      _SettingEntry(
        icon: Icons.image_rounded,
        title: l10n.readerShowChapterSlider,
        keywords: const <String>['漫画', '阅读'],
        builder: (_) => const SettingsComicReaderScreen(),
        scrollKeyId: 'comic.chapterSlider',
      ),
      // 精细化搜索补全：comic.clockMargin
      _SettingEntry(
        icon: Icons.image_rounded,
        title: l10n.readerClockMargin,
        keywords: const <String>['漫画', '阅读'],
        builder: (_) => const SettingsComicReaderScreen(),
        scrollKeyId: 'comic.clockMargin',
      ),
      // 精细化搜索补全：comic.doubleTapSpeed
      _SettingEntry(
        icon: Icons.image_rounded,
        title: l10n.readerDoubleTapAnimSpeed,
        keywords: const <String>['漫画', '阅读'],
        builder: (_) => const SettingsComicReaderScreen(),
        scrollKeyId: 'comic.doubleTapSpeed',
      ),
      // 精细化搜索补全：comic.clockBattery
      _SettingEntry(
        icon: Icons.image_rounded,
        title: l10n.readerClockBattery,
        keywords: const <String>['漫画', '阅读'],
        builder: (_) => const SettingsComicReaderScreen(),
        scrollKeyId: 'comic.clockBattery',
      ),
      // 精细化搜索补全：comic.singleFirst
      _SettingEntry(
        icon: Icons.image_rounded,
        title: l10n.readerShowSingleImageOnFirstPage,
        keywords: const <String>['漫画', '阅读'],
        builder: (_) => const SettingsComicReaderScreen(),
        scrollKeyId: 'comic.singleFirst',
      ),
      // 精细化搜索补全：comic.nightLight
      _SettingEntry(
        icon: Icons.image_rounded,
        title: l10n.readerNightLight,
        keywords: const <String>['漫画', '阅读'],
        builder: (_) => const SettingsComicReaderScreen(),
        scrollKeyId: 'comic.nightLight',
      ),
      // 精细化搜索补全：comic.autoScroll
      _SettingEntry(
        icon: Icons.image_rounded,
        title: l10n.readerAutoScroll,
        keywords: const <String>['漫画', '阅读'],
        builder: (_) => const SettingsComicReaderScreen(),
        scrollKeyId: 'comic.autoScroll',
      ),
      // 精细化搜索补全：comic.brightness
      _SettingEntry(
        icon: Icons.image_rounded,
        title: l10n.readerBrightness,
        keywords: const <String>['漫画', '阅读'],
        builder: (_) => const SettingsComicReaderScreen(),
        scrollKeyId: 'comic.brightness',
      ),
      // 精细化搜索补全：comic.einkDuration
      _SettingEntry(
        icon: Icons.image_rounded,
        title: l10n.readerEInkRefreshDuration,
        keywords: const <String>['漫画', '阅读'],
        builder: (_) => const SettingsComicReaderScreen(),
        scrollKeyId: 'comic.einkDuration',
      ),
      // 精细化搜索补全：comic.scrollSpeed
      _SettingEntry(
        icon: Icons.image_rounded,
        title: l10n.readerScrollSpeed,
        keywords: const <String>['漫画', '阅读'],
        builder: (_) => const SettingsComicReaderScreen(),
        scrollKeyId: 'comic.scrollSpeed',
      ),
      // 精细化搜索补全：comic.einkInterval
      _SettingEntry(
        icon: Icons.image_rounded,
        title: l10n.readerEInkRefreshInterval,
        keywords: const <String>['漫画', '阅读'],
        builder: (_) => const SettingsComicReaderScreen(),
        scrollKeyId: 'comic.einkInterval',
      ),
      // 精细化搜索补全：comic.chapterSeparator
      _SettingEntry(
        icon: Icons.image_rounded,
        title: l10n.readerChapterSeparator,
        keywords: const <String>['漫画', '阅读'],
        builder: (_) => const SettingsComicReaderScreen(),
        scrollKeyId: 'comic.chapterSeparator',
      ),
      // 精细化搜索补全：comic.pageSpacing
      _SettingEntry(
        icon: Icons.image_rounded,
        title: l10n.readerPageSpacing,
        keywords: const <String>['漫画', '阅读'],
        builder: (_) => const SettingsComicReaderScreen(),
        scrollKeyId: 'comic.pageSpacing',
      ),
      // 精细化搜索补全：comic.seamless
      _SettingEntry(
        icon: Icons.image_rounded,
        title: l10n.readerSeamlessReading,
        keywords: const <String>['漫画', '阅读'],
        builder: (_) => const SettingsComicReaderScreen(),
        scrollKeyId: 'comic.seamless',
      ),
      // 精细化搜索补全：comic.screenCountLandscape
      _SettingEntry(
        icon: Icons.image_rounded,
        title: l10n.readerScreenPicNumberLandscape,
        keywords: const <String>['漫画', '阅读'],
        builder: (_) => const SettingsComicReaderScreen(),
        scrollKeyId: 'comic.screenCountLandscape',
      ),
      // 精细化搜索补全：comic.autoPageTurning
      _SettingEntry(
        icon: Icons.image_rounded,
        title: l10n.readerAutoPageTurning,
        keywords: const <String>['漫画', '阅读'],
        builder: (_) => const SettingsComicReaderScreen(),
        scrollKeyId: 'comic.autoPageTurning',
      ),
      // 精细化搜索补全：comic.screenCountPortrait
      _SettingEntry(
        icon: Icons.image_rounded,
        title: l10n.readerScreenPicNumberPortrait,
        keywords: const <String>['漫画', '阅读'],
        builder: (_) => const SettingsComicReaderScreen(),
        scrollKeyId: 'comic.screenCountPortrait',
      ),
      // 精细化搜索补全：comic.skipDuplicate
      _SettingEntry(
        icon: Icons.image_rounded,
        title: l10n.readerSkipDuplicateChapters,
        keywords: const <String>['漫画', '阅读'],
        builder: (_) => const SettingsComicReaderScreen(),
        scrollKeyId: 'comic.skipDuplicate',
      ),
      // 精细化搜索补全：comic.clockFontSize
      _SettingEntry(
        icon: Icons.image_rounded,
        title: l10n.readerClockFontSize,
        keywords: const <String>['漫画', '阅读'],
        builder: (_) => const SettingsComicReaderScreen(),
        scrollKeyId: 'comic.clockFontSize',
      ),
      // 精细化搜索补全：comic.volumePageTurn
      _SettingEntry(
        icon: Icons.image_rounded,
        title: l10n.readerVolumeKeyPageTurn,
        keywords: const <String>['漫画', '阅读'],
        builder: (_) => const SettingsComicReaderScreen(),
        scrollKeyId: 'comic.volumePageTurn',
      ),
      // 精细化搜索补全：comic.autoFavorite
      _SettingEntry(
        icon: Icons.image_rounded,
        title: l10n.readerAutoFavorite,
        keywords: const <String>['漫画', '阅读'],
        builder: (_) => const SettingsComicReaderScreen(),
        scrollKeyId: 'comic.autoFavorite',
      ),
      // 精细化搜索补全：comic.nightLightOpacity
      _SettingEntry(
        icon: Icons.image_rounded,
        title: l10n.readerNightLightOpacity,
        keywords: const <String>['漫画', '阅读'],
        builder: (_) => const SettingsComicReaderScreen(),
        scrollKeyId: 'comic.nightLightOpacity',
      ),
      // 精细化搜索补全：comic.autoPageInterval
      _SettingEntry(
        icon: Icons.image_rounded,
        title: l10n.readerAutoPageInterval,
        keywords: const <String>['漫画', '阅读'],
        builder: (_) => const SettingsComicReaderScreen(),
        scrollKeyId: 'comic.autoPageInterval',
      ),
      // 精细化搜索补全：comic.skipFiltered
      _SettingEntry(
        icon: Icons.image_rounded,
        title: l10n.readerSkipFilteredChapters,
        keywords: const <String>['漫画', '阅读'],
        builder: (_) => const SettingsComicReaderScreen(),
        scrollKeyId: 'comic.skipFiltered',
      ),
      // 精细化搜索补全：comic.longPressZoom
      _SettingEntry(
        icon: Icons.image_rounded,
        title: l10n.readerLongPressZoom,
        keywords: const <String>['漫画', '阅读'],
        builder: (_) => const SettingsComicReaderScreen(),
        scrollKeyId: 'comic.longPressZoom',
      ),
      // 精细化搜索补全：novel.preDownloadCount
      _SettingEntry(
        icon: Icons.menu_book_rounded,
        title: l10n.preDownloadCount,
        keywords: const <String>['小说', '阅读'],
        builder: (_) => const SettingsNovelReaderScreen(),
        scrollKeyId: 'novel.preDownloadCount',
      ),
      // 精细化搜索补全：novel.wheelInverted
      _SettingEntry(
        icon: Icons.menu_book_rounded,
        title: l10n.novelWheelInverted,
        keywords: const <String>['小说', '阅读'],
        builder: (_) => const SettingsNovelReaderScreen(),
        scrollKeyId: 'novel.wheelInverted',
      ),
      // 精细化搜索补全：novel.preDownloadThreshold
      _SettingEntry(
        icon: Icons.menu_book_rounded,
        title: l10n.preDownloadThreshold,
        keywords: const <String>['小说', '阅读'],
        builder: (_) => const SettingsNovelReaderScreen(),
        scrollKeyId: 'novel.preDownloadThreshold',
      ),
      // 精细化搜索补全：novel.ttsSilent
      _SettingEntry(
        icon: Icons.menu_book_rounded,
        title: l10n.httpTtsSilentPlaceholder,
        keywords: const <String>['小说', '阅读'],
        builder: (_) => const SettingsNovelReaderScreen(),
        scrollKeyId: 'novel.ttsSilent',
      ),
      // 精细化搜索补全：novel.ttsMaxFailures
      _SettingEntry(
        icon: Icons.menu_book_rounded,
        title: l10n.httpTtsMaxFailures,
        keywords: const <String>['小说', '阅读'],
        builder: (_) => const SettingsNovelReaderScreen(),
        scrollKeyId: 'novel.ttsMaxFailures',
      ),
      // 精细化搜索补全：novel.autoPageSmooth
      _SettingEntry(
        icon: Icons.menu_book_rounded,
        title: l10n.autoPageSmooth,
        keywords: const <String>['小说', '阅读'],
        builder: (_) => const SettingsNovelReaderScreen(),
        scrollKeyId: 'novel.autoPageSmooth',
      ),
      // 精细化搜索补全：novel.preDownload
      _SettingEntry(
        icon: Icons.menu_book_rounded,
        title: l10n.preDownloadEnabled,
        keywords: const <String>['小说', '阅读'],
        builder: (_) => const SettingsNovelReaderScreen(),
        scrollKeyId: 'novel.preDownload',
      ),
      // 精细化搜索补全：novel.ttsEnable
      _SettingEntry(
        icon: Icons.menu_book_rounded,
        title: l10n.httpTtsEnable,
        keywords: const <String>['小说', '阅读'],
        builder: (_) => const SettingsNovelReaderScreen(),
        scrollKeyId: 'novel.ttsEnable',
      ),
      // 精细化搜索补全：novel.fontWeightFine
      _SettingEntry(
        icon: Icons.menu_book_rounded,
        title: l10n.novelFontWeightFine,
        keywords: const <String>['小说', '阅读'],
        builder: (_) => const SettingsNovelReaderScreen(),
        scrollKeyId: 'novel.fontWeightFine',
      ),
      // 精细化搜索补全：novel.exportCover
      _SettingEntry(
        icon: Icons.menu_book_rounded,
        title: l10n.novelExportIncludeCover,
        keywords: const <String>['小说', '阅读'],
        builder: (_) => const SettingsNovelReaderScreen(),
        scrollKeyId: 'novel.exportCover',
      ),
      // 精细化搜索补全：novel.exportIntro
      _SettingEntry(
        icon: Icons.menu_book_rounded,
        title: l10n.novelExportIncludeIntro,
        keywords: const <String>['小说', '阅读'],
        builder: (_) => const SettingsNovelReaderScreen(),
        scrollKeyId: 'novel.exportIntro',
      ),
      // 精细化搜索补全：novel.twoPage
      _SettingEntry(
        icon: Icons.menu_book_rounded,
        title: l10n.novelTwoPageMode,
        keywords: const <String>['小说', '阅读'],
        builder: (_) => const SettingsNovelReaderScreen(),
        scrollKeyId: 'novel.twoPage',
      ),
      // 精细化搜索补全：novel.ttsConcurrency
      _SettingEntry(
        icon: Icons.menu_book_rounded,
        title: l10n.httpTtsConcurrency,
        keywords: const <String>['小说', '阅读'],
        builder: (_) => const SettingsNovelReaderScreen(),
        scrollKeyId: 'novel.ttsConcurrency',
      ),
      // 精细化搜索补全：ai.translationBatchSize
      _SettingEntry(
        icon: Icons.translate_rounded,
        title: l10n.translationBatchSize,
        keywords: const <String>['翻译', '批大小'],
        builder: (_) => const SettingsAiScreen(),
        scrollKeyId: 'ai.translationBatchSize',
      ),
      // 精细化搜索补全：cloud.novelAutoUpload
      _SettingEntry(
        icon: Icons.cloud_upload_rounded,
        title: l10n.cloudSyncAutoUploadNovelExports,
        keywords: const <String>['云同步', '上传', '导出'],
        builder: (_) => const SettingsCloudSyncScreen(),
        scrollKeyId: 'cloud.novelAutoUpload',
      ),
      _SettingEntry(
        icon: Icons.sd_storage_rounded,
        title: l10n.cacheManagerTitle,
        keywords: const <String>['图片缓存', '磁盘占用', 'image cache'],
        builder: (_) => const SettingsCacheManagerScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.ageRestrictionDisclaimerTitle,
        keywords: const <String>[],
        builder: (_) => const SettingsPrivacySecurityScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.aiCommonApiSection,
        keywords: const <String>[],
        builder: (_) => const SettingsAiScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.aiIllustrationSize,
        keywords: const <String>[],
        builder: (_) => const SettingsAiScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.aiSettingsTitle,
        keywords: const <String>[],
        builder: (_) => const SettingsAiScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.aiSummaryMode,
        keywords: const <String>[],
        builder: (_) => const SettingsAiScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.cloudSyncConflictApply,
        keywords: const <String>[],
        builder: (_) => const SettingsCloudSyncScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.comicReaderAutoSection,
        keywords: const <String>[],
        builder: (_) => const SettingsComicReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.comicReaderMultiImageSection,
        keywords: const <String>[],
        builder: (_) => const SettingsComicReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.comicReaderOverlaySection,
        keywords: const <String>[],
        builder: (_) => const SettingsComicReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.comicWheelInverted,
        keywords: const <String>[],
        builder: (_) => const SettingsComicReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.comicWheelNatural,
        keywords: const <String>[],
        builder: (_) => const SettingsComicReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.dandanplayLoginTab,
        keywords: const <String>[],
        builder: (_) => const SettingsDandanplayAccountScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.dandanplayRegisterTab,
        keywords: const <String>[],
        builder: (_) => const SettingsDandanplayAccountScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.dataImportExportTitle,
        keywords: const <String>[],
        builder: (_) => const SettingsImportExportScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.downloadListTab,
        keywords: const <String>[],
        builder: (_) => const SettingsDownloadScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.downloadSettingsTitle,
        keywords: const <String>[],
        builder: (_) => const SettingsDownloadScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.downloaderSelectTitle,
        keywords: const <String>[],
        builder: (_) => const SettingsDownloadScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.downloads,
        keywords: const <String>[],
        builder: (_) => const SettingsDownloadScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.exportFolderCustom,
        keywords: const <String>[],
        builder: (_) => const SettingsImportExportScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.exportFolderDefault,
        keywords: const <String>[],
        builder: (_) => const SettingsImportExportScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.fontBold,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.fontItalic,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.fontMonospace,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.fontSerif,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.fontSystem,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.fontUnderline,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.heroUrlDialogTitle,
        keywords: const <String>[],
        builder: (_) => const SettingsHeroScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.imageFavoriteGalleryTitle,
        keywords: const <String>[],
        builder: (_) => const SettingsDataScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.networkDnsModeCustom,
        keywords: const <String>[],
        builder: (_) => const SettingsNetworkScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.networkDnsModeDoh,
        keywords: const <String>[],
        builder: (_) => const SettingsNetworkScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.networkDnsModeDot,
        keywords: const <String>[],
        builder: (_) => const SettingsNetworkScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.networkDnsModeSystem,
        keywords: const <String>[],
        builder: (_) => const SettingsNetworkScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.networkProxyModeDirect,
        keywords: const <String>[],
        builder: (_) => const SettingsNetworkScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.networkProxyModeManual,
        keywords: const <String>[],
        builder: (_) => const SettingsNetworkScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.networkProxyModeSystem,
        keywords: const <String>[],
        builder: (_) => const SettingsNetworkScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.networkProxyProtocolHttp,
        keywords: const <String>[],
        builder: (_) => const SettingsNetworkScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.networkProxyProtocolSocks5,
        keywords: const <String>[],
        builder: (_) => const SettingsNetworkScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.networkResetTitle,
        keywords: const <String>[],
        builder: (_) => const SettingsNetworkScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.noConvert,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.novelExportTemplate,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.novelProgressConflictTitle,
        keywords: const <String>[],
        builder: (_) => const SettingsCloudSyncScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.novelProgressSyncNow,
        keywords: const <String>[],
        builder: (_) => const SettingsCloudSyncScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.novelProgressUseRemote,
        keywords: const <String>[],
        builder: (_) => const SettingsCloudSyncScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.novelSectionPreDownload,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.novelTypographyGroup,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.overviewModeApi,
        keywords: const <String>[],
        builder: (_) => const SettingsAiScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.overviewModeLocal,
        keywords: const <String>[],
        builder: (_) => const SettingsAiScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.playerAspect169,
        keywords: const <String>[],
        builder: (_) => const SettingsPlayerScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.playerAspect43,
        keywords: const <String>[],
        builder: (_) => const SettingsPlayerScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.playerAspectDefault,
        keywords: const <String>[],
        builder: (_) => const SettingsPlayerScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.playerAspectFill,
        keywords: const <String>[],
        builder: (_) => const SettingsPlayerScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.playerAudioMono,
        keywords: const <String>[],
        builder: (_) => const SettingsPlayerScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.playerAudioStereo,
        keywords: const <String>[],
        builder: (_) => const SettingsPlayerScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.playerAutoPlayCountdown,
        keywords: const <String>[],
        builder: (_) => const SettingsPlayerScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.playerAutoSelectLine,
        keywords: const <String>[],
        builder: (_) => const SettingsPlayerScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.playerBottomProgress,
        keywords: const <String>[],
        builder: (_) => const SettingsPlayerScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.playerCountdownImmediate,
        keywords: const <String>[],
        builder: (_) => const SettingsPlayerScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.playerDecodeAuto,
        keywords: const <String>[],
        builder: (_) => const SettingsPlayerScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.playerDecodeHw,
        keywords: const <String>[],
        builder: (_) => const SettingsPlayerScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.playerDecodeHwPlus,
        keywords: const <String>[],
        builder: (_) => const SettingsPlayerScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.playerDecodeSw,
        keywords: const <String>[],
        builder: (_) => const SettingsPlayerScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.playerOrientationAuto,
        keywords: const <String>[],
        builder: (_) => const SettingsPlayerScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.playerOrientationLandscape,
        keywords: const <String>[],
        builder: (_) => const SettingsPlayerScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.playerOrientationPortrait,
        keywords: const <String>[],
        builder: (_) => const SettingsPlayerScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.playerSeekDouble,
        keywords: const <String>[],
        builder: (_) => const SettingsPlayerScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.playerSeekHalf,
        keywords: const <String>[],
        builder: (_) => const SettingsPlayerScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.playerSeekNormal,
        keywords: const <String>[],
        builder: (_) => const SettingsPlayerScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.playerUpscaleShader,
        keywords: const <String>[],
        builder: (_) => const SettingsPlayerScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.playerUpscaleShaderOff,
        keywords: const <String>[],
        builder: (_) => const SettingsPlayerScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.playerUpscaleShaderPerformance,
        keywords: const <String>[],
        builder: (_) => const SettingsPlayerScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.playerUpscaleShaderQuality,
        keywords: const <String>[],
        builder: (_) => const SettingsPlayerScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.readerClockPosBottomLeft,
        keywords: const <String>[],
        builder: (_) => const SettingsComicReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.readerClockPosBottomRight,
        keywords: const <String>[],
        builder: (_) => const SettingsComicReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.readerClockPosTopLeft,
        keywords: const <String>[],
        builder: (_) => const SettingsComicReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.readerClockPosTopRight,
        keywords: const <String>[],
        builder: (_) => const SettingsComicReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.readerGroupEInk,
        keywords: const <String>[],
        builder: (_) => const SettingsComicReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.simplifiedToTraditional,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.subtitleBorderColorLabel,
        keywords: const <String>[],
        builder: (_) => const SettingsPlayerScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.subtitleShadowColorLabel,
        keywords: const <String>[],
        builder: (_) => const SettingsPlayerScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.traditionalToSimplified,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.translationSettingsTitle,
        keywords: const <String>[],
        builder: (_) => const SettingsAiScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.aiApiKey,
        keywords: const <String>[],
        builder: (_) => const SettingsAiScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.aiBaseUrl,
        keywords: const <String>[],
        builder: (_) => const SettingsAiScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.aiIllustrationModel,
        keywords: const <String>[],
        builder: (_) => const SettingsAiScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.aiModel,
        keywords: const <String>[],
        builder: (_) => const SettingsAiScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.autoPageInterval,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.autoPageOff,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.backupImportMode,
        keywords: const <String>[],
        builder: (_) => const SettingsImportExportScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.backupScopeNone,
        keywords: const <String>[],
        builder: (_) => const SettingsImportExportScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.backupSelectScope,
        keywords: const <String>[],
        builder: (_) => const SettingsCloudSyncScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.bangumiAccount,
        keywords: const <String>[],
        builder: (_) => const SettingsBangumiScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.bangumiBrowseCollection,
        keywords: const <String>[],
        builder: (_) => const SettingsBangumiScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.bangumiProxyApi,
        keywords: const <String>[],
        builder: (_) => const SettingsBangumiScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.bangumiProxyImage,
        keywords: const <String>[],
        builder: (_) => const SettingsBangumiScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.bangumiProxyMainSite,
        keywords: const <String>[],
        builder: (_) => const SettingsBangumiScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.bangumiProxyTitle,
        keywords: const <String>[],
        builder: (_) => const SettingsBangumiScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.bangumiSettingsSubtitle,
        keywords: const <String>[],
        builder: (_) => const SettingsDataScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.chineseConverter,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.cloudSyncConflictLocal,
        keywords: const <String>[],
        builder: (_) => const SettingsCloudSyncScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.cloudSyncConflictNone,
        keywords: const <String>[],
        builder: (_) => const SettingsCloudSyncScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.cloudSyncConflictRemote,
        keywords: const <String>[],
        builder: (_) => const SettingsCloudSyncScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.cloudSyncConflictTitle,
        keywords: const <String>[],
        builder: (_) => const SettingsCloudSyncScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.cloudSyncPullMode,
        keywords: const <String>[],
        builder: (_) => const SettingsCloudSyncScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.cloudSyncWebdavPassword,
        keywords: const <String>[],
        builder: (_) => const SettingsCloudSyncScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.cloudSyncWebdavUrl,
        keywords: const <String>[],
        builder: (_) => const SettingsCloudSyncScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.cloudSyncWebdavUsername,
        keywords: const <String>[],
        builder: (_) => const SettingsCloudSyncScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.comicFormatCbz,
        keywords: const <String>[],
        builder: (_) => const SettingsDownloadScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.comicFormatJpg,
        keywords: const <String>[],
        builder: (_) => const SettingsDownloadScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.comicFormatPng,
        keywords: const <String>[],
        builder: (_) => const SettingsDownloadScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.crashLogClear,
        keywords: const <String>[],
        builder: (_) => const LogViewerScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.customFont,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.danmakuAddKeyword,
        keywords: const <String>[],
        builder: (_) => const SettingsDanmakuDisplayScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.dateFormatDdMmYy,
        keywords: const <String>[],
        builder: (_) => const SettingsAppearanceScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.dateFormatDdMmmYyyy,
        keywords: const <String>[],
        builder: (_) => const SettingsAppearanceScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.dateFormatDefault,
        keywords: const <String>[],
        builder: (_) => const SettingsAppearanceScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.dateFormatMmDdYy,
        keywords: const <String>[],
        builder: (_) => const SettingsAppearanceScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.dateFormatMmmDd,
        keywords: const <String>[],
        builder: (_) => const SettingsAppearanceScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.dateFormatYyyy,
        keywords: const <String>[],
        builder: (_) => const SettingsAppearanceScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.dateFormatYyyyMmDd,
        keywords: const <String>[],
        builder: (_) => const SettingsAppearanceScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.downloadAutoDeleteExcludeNone,
        keywords: const <String>[],
        builder: (_) => const SettingsDownloadScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.downloadPreDownloadOff,
        keywords: const <String>[],
        builder: (_) => const SettingsDownloadScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.downloaderExternal,
        keywords: const <String>[],
        builder: (_) => const SettingsDownloadScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.downloaderInternal,
        keywords: const <String>[],
        builder: (_) => const SettingsDownloadScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.formatFolder,
        keywords: const <String>[],
        builder: (_) => const SettingsDownloadScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.heroRemoveTooltip,
        keywords: const <String>[],
        builder: (_) => const SettingsHeroScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.httpTtsDefaultVoice,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.httpTtsUrlTemplate,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.httpTtsVoiceMap,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.interval15m,
        keywords: const <String>[],
        builder: (_) => const SettingsRssNotificationsScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.interval1h,
        keywords: const <String>[],
        builder: (_) => const SettingsRssNotificationsScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.interval2h,
        keywords: const <String>[],
        builder: (_) => const SettingsRssNotificationsScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.interval30m,
        keywords: const <String>[],
        builder: (_) => const SettingsRssNotificationsScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.interval4h,
        keywords: const <String>[],
        builder: (_) => const SettingsRssNotificationsScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.launchScreenTitle,
        keywords: const <String>[],
        builder: (_) => const SettingsAppearanceScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.networkAddServer,
        keywords: const <String>[],
        builder: (_) => const SettingsNetworkScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.networkDnsTestHost,
        keywords: const <String>[],
        builder: (_) => const SettingsNetworkScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.networkDohUrl,
        keywords: const <String>[],
        builder: (_) => const SettingsNetworkScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.networkDotHost,
        keywords: const <String>[],
        builder: (_) => const SettingsNetworkScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.networkDotPort,
        keywords: const <String>[],
        builder: (_) => const SettingsNetworkScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.networkEchConfigList,
        keywords: const <String>[],
        builder: (_) => const SettingsNetworkScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.networkHostsHost,
        keywords: const <String>[],
        builder: (_) => const SettingsNetworkScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.networkHostsIp,
        keywords: const <String>[],
        builder: (_) => const SettingsNetworkScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.networkProxyHost,
        keywords: const <String>[],
        builder: (_) => const SettingsNetworkScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.networkProxyPassword,
        keywords: const <String>[],
        builder: (_) => const SettingsNetworkScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.networkProxyPort,
        keywords: const <String>[],
        builder: (_) => const SettingsNetworkScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.networkProxyUsername,
        keywords: const <String>[],
        builder: (_) => const SettingsNetworkScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.networkSniDefault,
        keywords: const <String>[],
        builder: (_) => const SettingsNetworkScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.networkTestDns,
        keywords: const <String>[],
        builder: (_) => const SettingsNetworkScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.networkTestDoh,
        keywords: const <String>[],
        builder: (_) => const SettingsNetworkScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.networkTestProxy,
        keywords: const <String>[],
        builder: (_) => const SettingsNetworkScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.nightMode,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.noGroups,
        keywords: const <String>[],
        builder: (_) => const SettingsCategoriesScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.novelAnimCover,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.novelAnimFade,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.novelAnimNone,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.novelAnimScroll,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.novelAnimSimulation,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.novelAnimSlide,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.novelBgWhite,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.novelChooseFontFile,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.novelClearFontFile,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.novelEmphasisColorAuto,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.novelExportCss,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.novelFontStyle,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.novelFooterCenter,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.novelFooterLeft,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.novelFooterRight,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.novelFormatEpub,
        keywords: const <String>[],
        builder: (_) => const SettingsDownloadScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.novelFormatTxt,
        keywords: const <String>[],
        builder: (_) => const SettingsDownloadScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.novelHeaderCenter,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.novelHeaderLeft,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.novelHeaderRight,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.novelHfBattery,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.novelHfBookName,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.novelHfBookPageNumber,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.novelHfChapterTitle,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.novelHfNone,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.novelHfPageAndProgress,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.novelHfPageNumber,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.novelHfProgressPercent,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.novelHfTime,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.novelHfTimeAndBattery,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.novelLineBreakCjkStrict,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.novelLineBreakMode,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.novelLineBreakStandard,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.novelPageAnimation,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.novelScrollImageAlign,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.novelScrollImageAlignCenter,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.novelScrollImageAlignLeft,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.novelScrollImageAlignRight,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.novelScrollImageMode,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.novelScrollImageModeBanner,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.novelScrollImageModeCard,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.novelShadowColorAuto,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.novelTextAlignJustify,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.novelTextAlignMode,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.novelTextAlignStart,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.novelTextColorFollowBg,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.novelThemeFollowApp,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.novelThemeFollowDark,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.novelThemeFollowLight,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.novelTitleAlignCenter,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.novelTitleAlignHidden,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.novelTitleAlignLeft,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.novelTitleAlignRight,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.novelTitleColorAuto,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.novelTitleFontFile,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.novelTitlePosition,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.novelUnderlineColorAuto,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.novelUnderlineStyle,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.novelUnderlineStyleDashed,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.novelUnderlineStyleDotted,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.novelUnderlineStyleSolid,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.novelUnderlineStyleWavy,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.readerBgApricot,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.readerBgAuto,
        keywords: const <String>[],
        builder: (_) => const SettingsComicReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.readerBgBeanGreen,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.readerBgBlack,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.readerBgDarkGray,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.readerBgEInk,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.readerBgEyeCare,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.readerBgGray,
        keywords: const <String>[],
        builder: (_) => const SettingsComicReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.readerBgGrayBlue,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.readerBgLightBrown,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.readerBgMint,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.readerBgParchment,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.readerBgWarmLinen,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.readerBgWhite,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.readerClockPosition,
        keywords: const <String>[],
        builder: (_) => const SettingsComicReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.readerColorProfile,
        keywords: const <String>[],
        builder: (_) => const SettingsComicReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.readerColorProfileCool,
        keywords: const <String>[],
        builder: (_) => const SettingsComicReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.readerColorProfileManga,
        keywords: const <String>[],
        builder: (_) => const SettingsComicReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.readerColorProfileNone,
        keywords: const <String>[],
        builder: (_) => const SettingsComicReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.readerColorProfilePaper,
        keywords: const <String>[],
        builder: (_) => const SettingsComicReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.readerColorProfileSrgb,
        keywords: const <String>[],
        builder: (_) => const SettingsComicReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.readerColorProfileWarm,
        keywords: const <String>[],
        builder: (_) => const SettingsComicReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.readerEInkRefreshBlack,
        keywords: const <String>[],
        builder: (_) => const SettingsComicReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.readerEInkRefreshStyle,
        keywords: const <String>[],
        builder: (_) => const SettingsComicReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.readerEInkRefreshWhite,
        keywords: const <String>[],
        builder: (_) => const SettingsComicReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.readerFlashBlack,
        keywords: const <String>[],
        builder: (_) => const SettingsComicReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.readerFlashBlackWhite,
        keywords: const <String>[],
        builder: (_) => const SettingsComicReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.readerFlashWhite,
        keywords: const <String>[],
        builder: (_) => const SettingsComicReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.readerInitialZoom,
        keywords: const <String>[],
        builder: (_) => const SettingsComicReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.readerLongPressAtCenter,
        keywords: const <String>[],
        builder: (_) => const SettingsComicReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.readerLongPressAtPress,
        keywords: const <String>[],
        builder: (_) => const SettingsComicReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.readerLongPressZoomPosition,
        keywords: const <String>[],
        builder: (_) => const SettingsComicReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.readerModeSingleLTR,
        keywords: const <String>[],
        builder: (_) => const SettingsComicReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.readerModeSingleRTL,
        keywords: const <String>[],
        builder: (_) => const SettingsComicReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.readerModeSingleVertical,
        keywords: const <String>[],
        builder: (_) => const SettingsComicReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.readerModeWebtoon,
        keywords: const <String>[],
        builder: (_) => const SettingsComicReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.readerModeWebtoonWithGap,
        keywords: const <String>[],
        builder: (_) => const SettingsComicReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.readerOrientationDefault,
        keywords: const <String>[],
        builder: (_) => const SettingsComicReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.readerOrientationLandscape,
        keywords: const <String>[],
        builder: (_) => const SettingsComicReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.readerOrientationLockLandscape,
        keywords: const <String>[],
        builder: (_) => const SettingsComicReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.readerOrientationLockPortrait,
        keywords: const <String>[],
        builder: (_) => const SettingsComicReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.readerOrientationPortrait,
        keywords: const <String>[],
        builder: (_) => const SettingsComicReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.readerOrientationReversePortrait,
        keywords: const <String>[],
        builder: (_) => const SettingsComicReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.readerOrientationSystem,
        keywords: const <String>[],
        builder: (_) => const SettingsComicReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.readerPageAnimFade,
        keywords: const <String>[],
        builder: (_) => const SettingsComicReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.readerPageAnimNone,
        keywords: const <String>[],
        builder: (_) => const SettingsComicReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.readerPageAnimSlide,
        keywords: const <String>[],
        builder: (_) => const SettingsComicReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.readerPageAnimation,
        keywords: const <String>[],
        builder: (_) => const SettingsComicReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.readerTapBothSides,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.readerTapInvertAll,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.readerTapInvertLeftRight,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.readerTapInvertNone,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.readerTapInvertUpDown,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.readerTapKindle,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.readerTapLShape,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.readerTapLeftRight,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.readerTapOff,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.readerWheelAction,
        keywords: const <String>[],
        builder: (_) => const SettingsComicReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.readerWheelPage,
        keywords: const <String>[],
        builder: (_) => const SettingsComicReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.readerWheelZoom,
        keywords: const <String>[],
        builder: (_) => const SettingsComicReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.readerZoomFitHeight,
        keywords: const <String>[],
        builder: (_) => const SettingsComicReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.readerZoomFitWidth,
        keywords: const <String>[],
        builder: (_) => const SettingsComicReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.readerZoomOriginal,
        keywords: const <String>[],
        builder: (_) => const SettingsComicReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.readerZoomStart,
        keywords: const <String>[],
        builder: (_) => const SettingsComicReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.readerZoomStartCenter,
        keywords: const <String>[],
        builder: (_) => const SettingsComicReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.readerZoomStartLeft,
        keywords: const <String>[],
        builder: (_) => const SettingsComicReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.readerZoomStartRight,
        keywords: const <String>[],
        builder: (_) => const SettingsComicReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.rssNotificationEnabledSubtitle,
        keywords: const <String>[],
        builder: (_) => const SettingsRssNotificationsScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.selectExportFolder,
        keywords: const <String>[],
        builder: (_) => const SettingsImportExportScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.subtitleAssOverride,
        keywords: const <String>[],
        builder: (_) => const SettingsPlayerScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.subtitlePosition,
        keywords: const <String>[],
        builder: (_) => const SettingsPlayerScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.toolAutoPage,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.toolBookmark,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.toolBookmarkList,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.toolNextChapter,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.toolNightMode,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.toolPrevChapter,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.toolSearch,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.toolSettings,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.toolToc,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.toolTts,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.translationTargetLang,
        keywords: const <String>[],
        builder: (_) => const SettingsAiScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.ttsSleepTimer,
        keywords: const <String>[],
        builder: (_) => const SettingsNovelReaderScreen(),
      ),
      _SettingEntry(
        icon: Icons.tune_rounded,
        title: l10n.userAgentCustom,
        keywords: const <String>[],
        builder: (_) => const SettingsAdvancedScreen(),
      ),
    ];
  }
}

/// 单条具体设置项：搜索结果中的最小单位。
class _SettingEntry {
  final IconData icon;
  final String title;
  final String? desc;
  final List<String> keywords;
  final WidgetBuilder builder;

  /// 可选：跳转到 [builder] 返回的页后，滚动到该 id 对应的 [ValueKey] 位置。
  /// 对应页面 body 必须用 [SettingsAutoScroll] 包裹，且该 id 的 widget
  /// 在首帧时已在树中（建议 Column + SingleChildScrollView，避免懒构建）。
  final String? scrollKeyId;

  const _SettingEntry({
    required this.icon,
    required this.title,
    this.desc,
    required this.keywords,
    required this.builder,
    this.scrollKeyId,
  });
}

/// 设置项搜索：按具体设置项的标题 / 描述 / 关键词实时过滤，
/// 点击直接跳转到对应设置页（漫画阅读器、弹幕显示、云同步等子页也能搜到）。
class _SettingsSearchSheet extends StatefulWidget {
  final List<_SettingEntry> entries;

  const _SettingsSearchSheet({required this.entries});

  @override
  State<_SettingsSearchSheet> createState() => _SettingsSearchSheetState();
}

class _SettingsSearchSheetState extends State<_SettingsSearchSheet> {
  final TextEditingController _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final String queryLower = _query.toLowerCase();
    final List<_SettingEntry> filtered = widget.entries.where((e) {
      if (queryLower.isEmpty) return true;
      if (e.title.toLowerCase().contains(queryLower)) return true;
      if (e.desc != null && e.desc!.toLowerCase().contains(queryLower))
        return true;
      return e.keywords.any((k) => k.toLowerCase().contains(queryLower));
    }).toList();

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85),
        child: Padding(
          padding: const EdgeInsets.all(AppTokens.spaceMd),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextField(
                controller: _controller,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: l10n.search,
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear_rounded),
                          onPressed: () {
                            _controller.clear();
                            setState(() => _query = '');
                          },
                        ),
                ),
                onChanged: (String v) => setState(() => _query = v),
              ),
              const SizedBox(height: AppTokens.spaceMd),
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Text(
                          l10n.emptySearch,
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                      )
                    : ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (BuildContext ctx, int i) {
                          final e = filtered[i];
                          return ListTile(
                            leading: Icon(e.icon, color: scheme.primary),
                            title: Text(e.title),
                            subtitle: e.desc == null || e.desc!.isEmpty
                                ? null
                                : Text(
                                    e.desc!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: scheme.onSurfaceVariant),
                                  ),
                            trailing: Icon(
                              Icons.chevron_right_rounded,
                              color: scheme.onSurfaceVariant,
                            ),
                            onTap: () {
                              AppHaptics.selectionClick();
                              final scrollKeyId = e.scrollKeyId;
                              if (scrollKeyId != null) {
                                requestSettingsScroll(scrollKeyId);
                              }
                              Navigator.of(ctx).pop();
                              Navigator.of(context).push(
                                AppPageRoute<void>(
                                  builder: e.builder,
                                ),
                              );
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Category {
  final IconData icon;
  final String title;
  final String desc;
  final Widget Function() builder;

  const _Category({
    required this.icon,
    required this.title,
    required this.desc,
    required this.builder,
  });
}

/// 顶部 Hero 区：可左右滑动的自定义背景图轮播 + 品牌字 + 编辑入口。
///
/// 背景图来自 [GeneralSettingsStore] 的 `heroImageUrls`（默认二次元图，
/// 可在 Hero 设置页替换为任意网络/本地图）。右上角按钮跳转配置页；
/// 左上品牌字叠加暗化底纹保证在任意图片上可读。
class _HeroSection extends StatelessWidget {
  const _HeroSection();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final store = GeneralSettingsStore.instance;

    return AnimatedBuilder(
      animation: store,
      builder: (BuildContext context, _) {
        final ColorScheme scheme = Theme.of(context).colorScheme;
        return Stack(
          children: <Widget>[
            HeroCarousel(imageUrls: store.settings.heroImageUrls),
            Positioned(
              top: AppTokens.spaceSm,
              right: AppTokens.spaceSm,
              child: _HeroEditButton(
                tooltip: l10n.heroSettingsTitle,
                onTap: () {
                  Navigator.of(context).push(
                    AppPageRoute<void>(
                      builder: (_) => const SettingsHeroScreen(),
                    ),
                  );
                },
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.all(AppTokens.spaceLg),
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(AppTokens.radiusLg),
                    bottomRight: Radius.circular(AppTokens.radiusLg),
                  ),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[
                      // 图片叠加层遮罩：走 scheme.shadow（深浅色均黑系），
                      // 保证在任意 Hero 图上文字可读；白字为图片叠加必要对比。
                      scheme.shadow.withValues(alpha: 0.0),
                      scheme.shadow.withValues(alpha: 0.55),
                    ],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'NexHub',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      l10n.settingsTagline,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.white.withValues(alpha: 0.85),
                          ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Hero 区右上角的「自定义」按钮（半透明圆形）。
class _HeroEditButton extends StatelessWidget {
  final String tooltip;
  final VoidCallback onTap;

  const _HeroEditButton({
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: scheme.shadow.withValues(alpha: 0.4),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: const Padding(
            padding: EdgeInsets.all(AppTokens.spaceSm),
            child: Icon(Icons.tune_rounded, color: Colors.white, size: 20),
          ),
        ),
      ),
    );
  }
}
