import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG: string = 'NexHubWidget';

/// 快照存储文件名：必须与 Android 侧无关、与本应用 Dart 侧约定一致。
/// FormExtensionAbility 与 EntryAbility 是**两个进程**，靠同应用沙箱下的同名
/// preferences 共享数据（官方支持跨进程读取），因此不要改成 per-form 名字。
const PREFS_NAME: string = 'nexhub_home_widget';

/// 已添加卡片的 formId 列表（JSON 数组字符串）。应用侧主动 push 时需要它。
const FORM_IDS_KEY: string = 'form_ids';

/// 与 Dart 侧 `HomeWidgetSnapshot.toMap()` 的键一一对应。
///
/// **Dart 新增任何快照键都必须同步加到这里**：读写两侧都按本表过滤，
/// 漏加的表现是「数据已写入、updateForm 也成功，但卡片字段仍是默认值」。
export const SNAPSHOT_KEYS: string[] = [
  'updated_at',
  'has_continue',
  'continue_count',
  'continue_title',
  'continue_subtitle',
  'continue_cover_path',
  'continue_0_title',
  'continue_0_subtitle',
  'continue_0_cover',
  'continue_1_title',
  'continue_1_subtitle',
  'continue_1_cover',
  'continue_2_title',
  'continue_2_subtitle',
  'continue_2_cover',
  'continue_0_cover_b64',
  'continue_1_cover_b64',
  'continue_2_cover_b64',
  'continue_3_cover_b64',
  'continue_4_cover_b64',
  'continue_3_title',
  'continue_3_subtitle',
  'continue_3_cover',
  'continue_4_title',
  'continue_4_subtitle',
  'continue_4_cover',
  'continue_5_title',
  'continue_5_subtitle',
  'continue_5_cover',
  'continue_6_title',
  'continue_6_subtitle',
  'continue_6_cover',
  'continue_7_title',
  'continue_7_subtitle',
  'continue_7_cover',
  'favorite_0',
  'favorite_1',
  'favorite_2',
  'update_text',
  'download_text',
  'download_title',
  'stats_text',
  'today_text',
  'streak_text',
  'label_continue',
  'label_updates',
  'label_downloads',
  'label_stats',
  'bg_path',
  'heatmap_path',
  'heatmap_b64',
  'color_primary',
  'color_tertiary',
  'color_secondary',
  'bg_color',
  'bg_color_light',
  'bg_color_dark',
  'card_bg',
  'text_primary',
  'text_secondary',
  'card_bg_light',
  'card_bg_dark',
  'text_primary_light',
  'text_primary_dark',
  'text_secondary_light',
  'text_secondary_dark',
  'color_primary_light',
  'color_primary_dark',
  'stats_week_minutes',
  'stats_today_minutes',
  'stats_streak_days',
  'stats_active_days',
  'stats_total_hours',
  'stats_sessions',
  'stats_daily_avg',
  'stats_work_count',
  'label_total',
  'label_works',
  'label_sessions',
  'label_active',
  'lifetime_text',
  'sessions_text',
  'trend_text',
  'trend_up',
  'day_0_color',
  'day_1_color',
  'day_2_color',
  'day_3_color',
  'day_4_color',
  'day_5_color',
  'day_6_color',
  'novel_week_minutes',
  'comic_week_minutes',
  'media_week_minutes',
  'label_novel',
  'label_comic',
  'label_media',
  'heatmap_caption',
  'minute_unit',
  'streak_caption',
  'empty_title',
  'empty_hint',
];


/**
 * 卡片快照与 formId 的持久化。
 *
 * 为什么不直接把数据塞进卡片：卡片渲染在 FormExtensionAbility 进程，Flutter
 * 在 EntryAbility 进程，两者只能通过持久化或 formProvider 推送交互。这里统一
 * 「写 preferences + 读 preferences 组装 formBindingData」的读法，保证卡片重建
 * （设备重启、卡片被系统回收后恢复）时仍能拿到最新一份数据。
 */
export class HomeWidgetStore {
  private static open(context: common.Context): preferences.Preferences | null {
    try {
      return preferences.getPreferencesSync(context, { name: PREFS_NAME });
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(0x0000, TAG, 'open preferences failed: %{public}s', err.message);
      return null;
    }
  }

  /** 读整份快照；缺失键补空串，卡片侧无需再判空。 */
  static readSnapshot(context: common.Context): Record<string, string> {
    const out: Record<string, string> = {};
    const prefs = HomeWidgetStore.open(context);
    if (prefs == null) {
      return out;
    }
    for (const key of SNAPSHOT_KEYS) {
      try {
        const value = prefs.getSync(key, '');
        out[key] = typeof value === 'string' ? value as string : '';
      } catch (e) {
        out[key] = '';
      }
    }
    return out;
  }

  /** 整份覆盖写入（键集合固定，逐个覆盖即可；不依赖 clearSync 的版本差异）。 */
  static writeSnapshot(context: common.Context, data: Map<string, string>): boolean {
    const prefs = HomeWidgetStore.open(context);
    if (prefs == null) {
      return false;
    }
    try {
      data.forEach((value: string, key: string) => {
        if (SNAPSHOT_KEYS.indexOf(key) >= 0) {
          prefs.putSync(key, value);
        }
      });
      // 同步落盘：另一个进程（卡片 FormAbility）可能立刻就要读。
      prefs.flushSync();
      return true;
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(0x0000, TAG, 'write snapshot failed: %{public}s', err.message);
      return false;
    }
  }

  /** 记录一张新添加的卡片（onAddForm 时调用）。 */
  static addFormId(context: common.Context, formId: string): void {
    if (formId.length === 0) {
      return;
    }
    const ids = HomeWidgetStore.listFormIds(context);
    if (ids.indexOf(formId) >= 0) {
      return;
    }
    ids.push(formId);
    // 只保留最近 32 个：反复重装会留下大量失效 id，全量推送既慢又刷日志。
    while (ids.length > 32) {
      ids.shift();
    }
    HomeWidgetStore.saveFormIds(context, ids);
  }

  /** 卡片被移除时清理，避免应用侧向已删除的卡片推送。 */
  static removeFormId(context: common.Context, formId: string): void {
    const ids = HomeWidgetStore.listFormIds(context);
    const remain = ids.filter((id: string) => id !== formId);
    HomeWidgetStore.saveFormIds(context, remain);
  }

  static listFormIds(context: common.Context): string[] {
    const prefs = HomeWidgetStore.open(context);
    if (prefs == null) {
      return [];
    }
    try {
      const raw = prefs.getSync(FORM_IDS_KEY, '[]') as string;
      const parsed = JSON.parse(raw) as string[];
      return Array.isArray(parsed) ? parsed : [];
    } catch (e) {
      return [];
    }
  }

  private static saveFormIds(context: common.Context, ids: string[]): void {
    const prefs = HomeWidgetStore.open(context);
    if (prefs == null) {
      return;
    }
    try {
      prefs.putSync(FORM_IDS_KEY, JSON.stringify(ids));
      // 同步落盘：应用侧 updateForm 前必须能读到刚注册的 formId，
      // 异步 flush 会输掉与 Dart 首帧的竞速（实测卡片收不到刷新）。
      prefs.flushSync();
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(0x0000, TAG, 'save form ids failed: %{public}s', err.message);
    }
  }
}
