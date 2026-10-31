package com.nexhub.app

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.util.Log
import android.widget.RemoteViews

/**
 * 另外三种「单一主题」卡片：追更 / 下载 / 统计。
 *
 * 与继续观看卡分开成独立 provider 的原因：用户添加卡片时要能在系统面板里直接
 * 挑到「追更」「下载」「统计」，而不是加一张再切换。三者都是固定尺寸（不可拉伸），
 * 各自只读快照里的一小部分键，实现极薄——公共逻辑都收敛在 [WidgetRender]。
 */

/** 追更卡（2x4）：收藏总数 + 最近 3 部收藏。 */
class NexHubUpdatesWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        appWidgetIds.forEach { render(context, appWidgetManager, it) }
    }

    companion object {
        private const val TAG = "NexHubWidget"

        fun refresh(context: Context) {
            try {
                val manager = AppWidgetManager.getInstance(context)
                WidgetRender.ids(context, NexHubUpdatesWidgetProvider::class.java)
                    .forEach { render(context, manager, it) }
            } catch (e: Exception) {
                Log.w(TAG, "刷新追更卡失败", e)
            }
        }

        private fun render(context: Context, manager: AppWidgetManager, widgetId: Int) {
            try {
                val views = RemoteViews(context.packageName, R.layout.widget_updates)
                views.setTextViewText(
                    R.id.widget_title,
                    WidgetRender.str(context, "label_updates"),
                )
                views.setTextViewText(
                    R.id.widget_line_main,
                    WidgetRender.str(context, "update_text"),
                )
                val slots = intArrayOf(
                    R.id.widget_line_a, R.id.widget_line_b, R.id.widget_line_c,
                )
                for (i in slots.indices) {
                    val name = WidgetRender.str(context, "favorite_$i")
                    views.setViewVisibility(
                        slots[i],
                        if (name.isEmpty()) android.view.View.GONE else android.view.View.VISIBLE,
                    )
                    if (name.isNotEmpty()) views.setTextViewText(slots[i], "· $name")
                }
                // 收藏名是本卡主内容：统一主题化后覆盖为主文字色。
                WidgetRender.applyTheme(context, views)
                val onSurface =
                    WidgetRender.themedColor(context, "text_primary", R.color.widget_text_primary)
                for (id in intArrayOf(R.id.widget_line_a, R.id.widget_line_b, R.id.widget_line_c)) {
                    views.setTextColor(id, onSurface)
                }
                WidgetRender.bindBackground(views, WidgetRender.str(context, "bg_path"))
                WidgetRender.bindClick(context, views, "updates", WidgetRender.RC_UPDATES)
                manager.updateAppWidget(widgetId, views)
            } catch (e: Exception) {
                Log.w(TAG, "渲染追更卡 $widgetId 失败", e)
            }
        }
    }
}

/** 下载卡（2x4）：任务数与整体进度 + 首个任务标题。 */
class NexHubDownloadWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        appWidgetIds.forEach { render(context, appWidgetManager, it) }
    }

    companion object {
        private const val TAG = "NexHubWidget"

        fun refresh(context: Context) {
            try {
                val manager = AppWidgetManager.getInstance(context)
                WidgetRender.ids(context, NexHubDownloadWidgetProvider::class.java)
                    .forEach { render(context, manager, it) }
            } catch (e: Exception) {
                Log.w(TAG, "刷新下载卡失败", e)
            }
        }

        private fun render(context: Context, manager: AppWidgetManager, widgetId: Int) {
            try {
                val views = RemoteViews(context.packageName, R.layout.widget_downloads)
                views.setTextViewText(
                    R.id.widget_title,
                    WidgetRender.str(context, "label_downloads"),
                )
                views.setTextViewText(
                    R.id.widget_line_main,
                    WidgetRender.str(context, "download_text"),
                )
                views.setTextViewText(
                    R.id.widget_line_sub,
                    WidgetRender.str(context, "download_title"),
                )
                WidgetRender.applyTheme(context, views)
                WidgetRender.bindBackground(views, WidgetRender.str(context, "bg_path"))
                WidgetRender.bindClick(context, views, "downloads", WidgetRender.RC_DOWNLOADS)
                manager.updateAppWidget(widgetId, views)
            } catch (e: Exception) {
                Log.w(TAG, "渲染下载卡 $widgetId 失败", e)
            }
        }
    }
}

/** 统计卡（2x2）：本周 / 今日 / 活跃连续。 */
class NexHubStatsWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        appWidgetIds.forEach { render(context, appWidgetManager, it) }
    }

    companion object {
        private const val TAG = "NexHubWidget"

        fun refresh(context: Context) {
            try {
                val manager = AppWidgetManager.getInstance(context)
                WidgetRender.ids(context, NexHubStatsWidgetProvider::class.java)
                    .forEach { render(context, manager, it) }
            } catch (e: Exception) {
                Log.w(TAG, "刷新统计卡失败", e)
            }
        }

        private fun render(context: Context, manager: AppWidgetManager, widgetId: Int) {
            try {
                val views = RemoteViews(context.packageName, R.layout.widget_stats)
                views.setTextViewText(
                    R.id.widget_title,
                    WidgetRender.str(context, "label_stats"),
                )
                // 三列指标：总时长 / 作品数 / 会话 —— 与统计页「总览」卡、
                // 鸿蒙统计卡同一组数据与配色（primary / tertiary / secondary）。
                val metrics = arrayOf(
                    Triple("⏱", WidgetRender.str(context, "stats_total_hours") + " h", "color_primary"),
                    Triple("📖", WidgetRender.str(context, "stats_work_count"), "color_tertiary"),
                    Triple("🔁", WidgetRender.str(context, "stats_sessions"), "color_secondary"),
                )
                val labels = arrayOf(
                    WidgetRender.str(context, "label_total"),
                    WidgetRender.str(context, "label_works"),
                    WidgetRender.str(context, "label_sessions"),
                )
                val valueIds = intArrayOf(
                    R.id.widget_metric0_value, R.id.widget_metric1_value, R.id.widget_metric2_value,
                )
                val labelIds = intArrayOf(
                    R.id.widget_metric0_label, R.id.widget_metric1_label, R.id.widget_metric2_label,
                )
                val iconIds = intArrayOf(
                    R.id.widget_metric0_icon, R.id.widget_metric1_icon, R.id.widget_metric2_icon,
                )
                val fallbacks = intArrayOf(
                    R.color.widget_accent, R.color.widget_accent, R.color.widget_accent,
                )
                for (i in metrics.indices) {
                    views.setTextViewText(iconIds[i], metrics[i].first)
                    views.setTextViewText(valueIds[i], metrics[i].second)
                    views.setTextColor(valueIds[i], WidgetRender.themedColor(context, metrics[i].third, fallbacks[i]))
                    views.setTextViewText(labelIds[i], labels[i])
                }
                views.setTextViewText(
                    R.id.widget_line_a,
                    WidgetRender.str(context, "today_text"),
                )
                views.setTextViewText(
                    R.id.widget_line_b,
                    WidgetRender.str(context, "streak_text"),
                )
                // 当月打卡月历（与统计页热力图同源），无数据时整块隐藏。
                WidgetRender.bindOptionalImage(
                    views,
                    R.id.widget_stats_heatmap,
                    WidgetRender.str(context, "heatmap_path"),
                    700,
                )
                // 主数字用主题强调色（= 统计页大数字的 primary 观感）。
                WidgetRender.applyTheme(context, views)
                WidgetRender.bindBackground(views, WidgetRender.str(context, "bg_path"))
                WidgetRender.bindClick(context, views, "stats", WidgetRender.RC_STATS)
                manager.updateAppWidget(widgetId, views)
            } catch (e: Exception) {
                Log.w(TAG, "渲染统计卡 $widgetId 失败", e)
            }
        }
    }
}

/** 热力图卡（2*4）：近 30 天打卡格子图。 */
class NexHubHeatmapWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        appWidgetIds.forEach { render(context, appWidgetManager, it) }
    }

    companion object {
        private const val TAG = "NexHubWidget"

        fun refresh(context: Context) {
            try {
                val manager = AppWidgetManager.getInstance(context)
                WidgetRender.ids(context, NexHubHeatmapWidgetProvider::class.java)
                    .forEach { render(context, manager, it) }
            } catch (e: Exception) {
                Log.w(TAG, "刷新Heatmap失败", e)
            }
        }

        private fun render(context: Context, manager: AppWidgetManager, widgetId: Int) {
            try {
                val views = RemoteViews(context.packageName, R.layout.widget_heatmap)
                views.setTextViewText(
                    R.id.widget_title,
                    WidgetRender.str(context, "label_stats"),
                )
                // 热力图同样由 Flutter 预渲染成 PNG，这里只显示图片。
                WidgetRender.bindCover(
                    views,
                    R.id.widget_heatmap_image,
                    WidgetRender.str(context, "heatmap_path"),
                    700,
                )
                views.setTextViewText(
                    R.id.widget_line_a,
                    WidgetRender.str(context, "heatmap_caption"),
                )
                views.setTextViewText(
                    R.id.widget_line_b,
                    WidgetRender.str(context, "today_text"),
                )
                WidgetRender.applyTheme(context, views)
                WidgetRender.bindBackground(views, WidgetRender.str(context, "bg_path"))
                WidgetRender.bindClick(context, views, "stats", WidgetRender.RC_HEATMAP)
                manager.updateAppWidget(widgetId, views)
            } catch (e: Exception) {
                Log.w(TAG, "渲染Heatmap $widgetId 失败", e)
            }
        }
    }
}

/** 大数字卡（2*2）：本周阅读时长超大字号。 */
class NexHubBigNumberWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        appWidgetIds.forEach { render(context, appWidgetManager, it) }
    }

    companion object {
        private const val TAG = "NexHubWidget"

        fun refresh(context: Context) {
            try {
                val manager = AppWidgetManager.getInstance(context)
                WidgetRender.ids(context, NexHubBigNumberWidgetProvider::class.java)
                    .forEach { render(context, manager, it) }
            } catch (e: Exception) {
                Log.w(TAG, "刷新BigNumber失败", e)
            }
        }

        private fun render(context: Context, manager: AppWidgetManager, widgetId: Int) {
            try {
                val views = RemoteViews(context.packageName, R.layout.widget_bignumber)
                views.setTextViewText(
                    R.id.widget_title,
                    WidgetRender.str(context, "label_stats"),
                )
                views.setTextViewText(
                    R.id.widget_number,
                    WidgetRender.str(context, "stats_week_minutes"),
                )
                views.setTextViewText(
                    R.id.widget_unit,
                    WidgetRender.str(context, "minute_unit"),
                )
                views.setTextViewText(
                    R.id.widget_line_a,
                    WidgetRender.str(context, "today_text"),
                )
                // 超大数字用主题强调色（= 统计页大数字的 primary 观感）。
                WidgetRender.applyTheme(context, views, intArrayOf(R.id.widget_number))
                WidgetRender.bindBackground(views, WidgetRender.str(context, "bg_path"))
                WidgetRender.bindClick(context, views, "stats", WidgetRender.RC_BIG)
                manager.updateAppWidget(widgetId, views)
            } catch (e: Exception) {
                Log.w(TAG, "渲染BigNumber $widgetId 失败", e)
            }
        }
    }
}

/** 分模块统计卡（2*4）：小说 / 漫画 / 媒体 本周时长。 */
class NexHubModulesWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        appWidgetIds.forEach { render(context, appWidgetManager, it) }
    }

    companion object {
        private const val TAG = "NexHubWidget"

        fun refresh(context: Context) {
            try {
                val manager = AppWidgetManager.getInstance(context)
                WidgetRender.ids(context, NexHubModulesWidgetProvider::class.java)
                    .forEach { render(context, manager, it) }
            } catch (e: Exception) {
                Log.w(TAG, "刷新Modules失败", e)
            }
        }

        private fun render(context: Context, manager: AppWidgetManager, widgetId: Int) {
            try {
                val views = RemoteViews(context.packageName, R.layout.widget_modules)
                views.setTextViewText(
                    R.id.widget_title,
                    WidgetRender.str(context, "label_stats"),
                )
                val unit = WidgetRender.str(context, "minute_unit")
                val line = arrayOf(
                    WidgetRender.str(context, "label_novel") + " · " +
                        WidgetRender.str(context, "novel_week_minutes") + " " + unit,
                    WidgetRender.str(context, "label_comic") + " · " +
                        WidgetRender.str(context, "comic_week_minutes") + " " + unit,
                    WidgetRender.str(context, "label_media") + " · " +
                        WidgetRender.str(context, "media_week_minutes") + " " + unit,
                )
                views.setTextViewText(R.id.widget_line_a, line[0])
                views.setTextViewText(R.id.widget_line_b, line[1])
                views.setTextViewText(R.id.widget_line_c, line[2])
                WidgetRender.applyTheme(context, views)
                WidgetRender.bindBackground(views, WidgetRender.str(context, "bg_path"))
                WidgetRender.bindClick(context, views, "stats", WidgetRender.RC_MODULES)
                manager.updateAppWidget(widgetId, views)
            } catch (e: Exception) {
                Log.w(TAG, "渲染Modules $widgetId 失败", e)
            }
        }
    }
}

/** 连续打卡卡（2*2）：连续天数放大 + 今日时长。 */
class NexHubStreakWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        appWidgetIds.forEach { render(context, appWidgetManager, it) }
    }

    companion object {
        private const val TAG = "NexHubWidget"

        fun refresh(context: Context) {
            try {
                val manager = AppWidgetManager.getInstance(context)
                WidgetRender.ids(context, NexHubStreakWidgetProvider::class.java)
                    .forEach { render(context, manager, it) }
            } catch (e: Exception) {
                Log.w(TAG, "刷新Streak失败", e)
            }
        }

        private fun render(context: Context, manager: AppWidgetManager, widgetId: Int) {
            try {
                val views = RemoteViews(context.packageName, R.layout.widget_streak)
                views.setTextViewText(
                    R.id.widget_title,
                    WidgetRender.str(context, "streak_caption"),
                )
                views.setTextViewText(
                    R.id.widget_number,
                    WidgetRender.str(context, "stats_streak_days"),
                )
                views.setTextViewText(
                    R.id.widget_line_a,
                    WidgetRender.str(context, "today_text"),
                )
                views.setTextViewText(
                    R.id.widget_line_b,
                    WidgetRender.str(context, "streak_text"),
                )
                // 连续天数大数字用主题强调色（= 统计页大数字的 primary 观感）。
                WidgetRender.applyTheme(context, views, intArrayOf(R.id.widget_number))
                WidgetRender.bindBackground(views, WidgetRender.str(context, "bg_path"))
                WidgetRender.bindClick(context, views, "stats", WidgetRender.RC_STREAK)
                manager.updateAppWidget(widgetId, views)
            } catch (e: Exception) {
                Log.w(TAG, "渲染Streak $widgetId 失败", e)
            }
        }
    }
}
