package com.nexhub.app

import android.content.Context
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.os.Bundle
import android.util.Log
import android.view.View
import android.widget.RemoteViews

/**
 * 「继续观看」卡：一张卡片按尺寸在 小(2x2) / 中(2x4) / 大(4x4) 三套布局间切换。
 *
 * 只有一个 provider：用户添加后自由拉伸，[pickLayout] 按系统给出的最小宽高选布局
 * —— 比注册三个独立 provider 更好用，用户不必在添加面板里挑尺寸。
 */
class NexHubWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        appWidgetIds.forEach { render(context, appWidgetManager, it) }
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        // 用户拉伸卡片后系统只回调这里：按新尺寸重新选布局。
        render(context, appWidgetManager, appWidgetId)
    }

    companion object {
        private const val TAG = "NexHubWidget"

        fun refreshAll(context: Context) {
            try {
                val manager = AppWidgetManager.getInstance(context)
                WidgetRender.ids(context, NexHubWidgetProvider::class.java)
                    .forEach { render(context, manager, it) }
            } catch (e: Exception) {
                Log.w(TAG, "刷新继续观看卡失败", e)
            }
        }

        private fun render(context: Context, manager: AppWidgetManager, widgetId: Int) {
            try {
                val hasContinue = WidgetRender.str(context, "has_continue") == "1"
                val options = manager.getAppWidgetOptions(widgetId)
                val layoutId = pickLayout(
                    options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH),
                    options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT),
                )
                val views = RemoteViews(context.packageName, layoutId)
                views.setViewVisibility(
                    R.id.widget_content,
                    if (hasContinue) View.VISIBLE else View.GONE,
                )
                views.setViewVisibility(
                    R.id.widget_empty,
                    if (hasContinue) View.GONE else View.VISIBLE,
                )

                if (hasContinue) {
                    if (layoutId == R.layout.widget_large) {
                        bindList(context, views)
                    } else {
                        bindSingle(context, views, layoutId)
                    }
                } else {
                    // 快照为空（安装后从未启动过 App）时用资源兜底，避免白卡。
                    views.setTextViewText(
                        R.id.widget_empty_title,
                        WidgetRender.str(context, "empty_title").ifEmpty {
                            context.getString(R.string.widget_empty_title_default)
                        },
                    )
                    views.setTextViewText(
                        R.id.widget_empty_hint,
                        WidgetRender.str(context, "empty_hint").ifEmpty {
                            context.getString(R.string.widget_empty_hint_default)
                        },
                    )
                }

                WidgetRender.applyTheme(context, views)
                WidgetRender.bindBackground(views, WidgetRender.str(context, "bg_path"))
                WidgetRender.bindClick(context, views, "continue", WidgetRender.RC_CONTINUE)
                manager.updateAppWidget(widgetId, views)
            } catch (e: Exception) {
                Log.w(TAG, "渲染继续观看卡 $widgetId 失败", e)
            }
        }

        /** 小卡 / 中卡：单条作品 + 摘要行。 */
        private fun bindSingle(context: Context, views: RemoteViews, layoutId: Int) {
            views.setTextViewText(
                R.id.widget_title,
                WidgetRender.str(context, "continue_title"),
            )
            views.setTextViewText(
                R.id.widget_subtitle,
                WidgetRender.str(context, "continue_subtitle"),
            )
            WidgetRender.bindCover(
                views,
                R.id.widget_cover,
                WidgetRender.str(context, "continue_cover_path"),
                if (layoutId == R.layout.widget_small) 200 else 260,
            )
            if (layoutId != R.layout.widget_small) {
                views.setTextViewText(
                    R.id.widget_line_update,
                    WidgetRender.str(context, "update_text"),
                )
                views.setTextViewText(
                    R.id.widget_line_download,
                    WidgetRender.str(context, "download_text"),
                )
                views.setTextViewText(
                    R.id.widget_line_stats,
                    WidgetRender.str(context, "stats_text"),
                )
                views.setTextViewText(
                    R.id.widget_line_today,
                    WidgetRender.str(context, "today_text"),
                )
            }
        }

        /** 大卡：最近 3 条继续观看 + 一行统计脚注。 */
        private fun bindList(context: Context, views: RemoteViews) {
            views.setTextViewText(
                R.id.widget_title,
                WidgetRender.str(context, "label_continue"),
            )
            // Android 大卡固定 4 条：RemoteViews 不能动态增删行，设置里选 5~8
            // 条时这里按布局上限截断（鸿蒙侧可以全部显示）。
            val rows = intArrayOf(
                R.id.widget_item0_row, R.id.widget_item1_row,
                R.id.widget_item2_row, R.id.widget_item3_row,
            )
            val titleIds = intArrayOf(
                R.id.widget_item0_title, R.id.widget_item1_title,
                R.id.widget_item2_title, R.id.widget_item3_title,
            )
            val subIds = intArrayOf(
                R.id.widget_item0_sub, R.id.widget_item1_sub,
                R.id.widget_item2_sub, R.id.widget_item3_sub,
            )
            val count = WidgetRender.str(context, "continue_count").toIntOrNull() ?: 0
            for (i in rows.indices) {
                val title = WidgetRender.str(context, "continue_${i}_title")
                val hasItem = i < count && title.isNotEmpty()
                views.setViewVisibility(
                    rows[i],
                    if (hasItem) View.VISIBLE else View.GONE,
                )
                if (hasItem) {
                    views.setTextViewText(titleIds[i], title)
                    views.setTextViewText(
                        subIds[i],
                        WidgetRender.str(context, "continue_${i}_subtitle"),
                    )
                }
            }
            views.setTextViewText(
                R.id.widget_footer,
                WidgetRender.str(context, "stats_text"),
            )
        }

        /**
         * 按最小宽高选布局。
         *
         * 系统给的是 dp 且随 launcher 网格变化。首次添加时 options 可能为空
         * （minWidth/minHeight 为 0），按 2x2 兜底，否则会误判成大卡。
         */
        private fun pickLayout(minWidth: Int, minHeight: Int): Int {
            val w = if (minWidth > 0) minWidth else 110
            val h = if (minHeight > 0) minHeight else 110
            return when {
                w < 180 -> R.layout.widget_small
                h < 200 -> R.layout.widget_medium
                else -> R.layout.widget_large
            }
        }
    }
}
