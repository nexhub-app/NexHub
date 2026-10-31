package com.nexhub.app

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * 桌面卡片（系统小组件）与 Flutter 之间的桥。
 *
 * 职责只有三件：
 * 1. `update`：把 Flutter 算好的快照写进 SharedPreferences，再通知所有卡片重绘；
 * 2. `takeLaunchRoute`：取走「用户点了卡片」时带过来的跳转目标（一次性）；
 * 3. 记录 Intent 里的跳转目标（冷启动走 onCreate，热启动走 onNewIntent）。
 *
 * 快照按扁平字符串存储，键名与 Dart 侧 `HomeWidgetSnapshot.toMap()` 一一对应。
 * 原生不做任何业务计算——所有文案（含标签与单位）都由 Dart 按当前语言生成，
 * 卡片只负责摆布局，避免原生再维护一套多语言资源。
 */
object HomeWidgetBridge {
    private const val TAG = "NexHubWidget"
    private const val CHANNEL = "nexhub/home_widget"

    /** 快照存储文件名（仅本应用可读）。 */
    const val PREFS = "nexhub_home_widget"

    /** 点击卡片时塞进 Intent 的跳转目标 key。 */
    const val EXTRA_ROUTE = "nexhub_card_route"

    /** 待消费的跳转目标；Dart 取走即清空，避免重复跳转。 */
    @Volatile
    private var pendingRoute: String? = null

    fun register(messenger: BinaryMessenger, context: Context) {
        val appContext = context.applicationContext
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "update" -> {
                    val args = call.argument<Map<*, *>>("data")
                    if (args == null) {
                        result.error("bad_args", "data is null", null)
                    } else {
                        writeSnapshot(appContext, args)
                        // 四类卡片共用一份快照：整份写完再逐个刷新，避免出现
                        // 「继续观看已更新、统计还是旧值」的中间态。
                        NexHubWidgetProvider.refreshAll(appContext)
                        NexHubUpdatesWidgetProvider.refresh(appContext)
                        NexHubDownloadWidgetProvider.refresh(appContext)
                        NexHubStatsWidgetProvider.refresh(appContext)
                        NexHubHeatmapWidgetProvider.refresh(appContext)
                        NexHubBigNumberWidgetProvider.refresh(appContext)
                        NexHubModulesWidgetProvider.refresh(appContext)
                        NexHubStreakWidgetProvider.refresh(appContext)
                        result.success(true)
                    }
                }

                "takeLaunchRoute" -> {
                    val route = pendingRoute
                    pendingRoute = null
                    result.success(route)
                }

                else -> result.notImplemented()
            }
        }
    }

    /** 记录 Intent 携带的跳转目标（冷/热启动都要调用）。 */
    fun captureIntent(intent: Intent?) {
        val route = intent?.getStringExtra(EXTRA_ROUTE)
        if (!route.isNullOrEmpty()) {
            pendingRoute = route
            // 消费掉，防止 Activity 重建时同一目标被再次触发。
            intent.removeExtra(EXTRA_ROUTE)
        }
    }

    /** 把 Dart 传下的扁平字符串快照整份覆盖写入。 */
    private fun writeSnapshot(context: Context, args: Map<*, *>) {
        try {
            val editor = context
                .getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit()
            editor.clear()
            for ((key, value) in args) {
                val k = key as? String ?: continue
                editor.putString(k, value?.toString() ?: "")
            }
            editor.apply()
        } catch (e: Exception) {
            // 卡片是附属信息：写失败只记录，不向 Flutter 抛错打断主流程。
            Log.w(TAG, "写入卡片快照失败", e)
        }
    }

    /** 当前已添加的卡片 id（无卡片时返回空数组）。 */
    fun widgetIds(context: Context): IntArray {
        val manager = AppWidgetManager.getInstance(context)
        val component = ComponentName(context, NexHubWidgetProvider::class.java)
        return manager.getAppWidgetIds(component)
    }
}
