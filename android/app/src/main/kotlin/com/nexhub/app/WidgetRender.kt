package com.nexhub.app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.util.Log
import android.view.View
import android.widget.RemoteViews
import java.io.File

/**
 * 卡片渲染公共工具。
 *
 * 四种卡片（继续观看 / 追更 / 下载 / 统计）共用同一份快照，各自只读关心的键。
 * 这里收敛三件重复活：读偏好、封面解码、点击意图，避免每个 provider 抄一遍。
 */
object WidgetRender {
    private const val TAG = "NexHubWidget"

    /** 每类卡片一个稳定的 requestCode（同类多个实例共用即可）。 */
    const val RC_CONTINUE = 1001
    const val RC_UPDATES = 1002
    const val RC_DOWNLOADS = 1003
    const val RC_STATS = 1004
    const val RC_HEATMAP = 1005
    const val RC_BIG = 1006
    const val RC_MODULES = 1007
    const val RC_STREAK = 1008

    private fun prefs(context: Context) = context
        .getSharedPreferences(HomeWidgetBridge.PREFS, Context.MODE_PRIVATE)

    /** 读快照字段（缺失返回空串，卡片侧无需判空）。 */
    fun str(context: Context, key: String): String =
        prefs(context).getString(key, "") ?: ""

    // ─────── 主题化：文字色与圆角跟随 App 当前主题 ───────

    /** 次要文字（标签 / 脚注 / 副标题）：对应 App 的 onSurfaceVariant。 */
    private val TEXT_SECONDARY_IDS = intArrayOf(
        R.id.widget_title, R.id.widget_unit, R.id.widget_subtitle,
        R.id.widget_line_a, R.id.widget_line_b, R.id.widget_line_c,
        R.id.widget_line_sub, R.id.widget_footer,
        R.id.widget_line_update, R.id.widget_line_download,
        R.id.widget_line_stats, R.id.widget_line_today,
        R.id.widget_item0_sub, R.id.widget_item1_sub,
        R.id.widget_item2_sub, R.id.widget_item3_sub,
        R.id.widget_empty_hint,
    )

    /** 主文字（正文 / 列表标题 / 空态标题）：对应 App 的 onSurface。 */
    private val TEXT_PRIMARY_IDS = intArrayOf(
        R.id.widget_line_main,
        R.id.widget_item0_title, R.id.widget_item1_title,
        R.id.widget_item2_title, R.id.widget_item3_title,
        R.id.widget_empty_title,
    )

    /**
     * 读快照下发的主题色（`#RRGGBB` / `#AARRGGBB`），缺失或非法时用资源兜底。
     *
     * 快照色来自 App 当前 ColorScheme（统计页卡片同源），因此换主题 /
     * 动态取色后卡片会跟着变；App 长期未运行期间保持上次快照 —— 底图与
     * 文字色出自同一份快照，对比度始终成立。
     */
    fun themedColor(context: Context, key: String, fallbackRes: Int): Int {
        val raw = str(context, key)
        if (raw.isNotEmpty()) {
            try {
                return Color.parseColor(raw)
            } catch (e: IllegalArgumentException) {
                Log.w(TAG, "快照色值非法，用资源兜底: $key=$raw")
            }
        }
        return context.getColor(fallbackRes)
    }

    /**
     * 给卡片统一上主题色 + 裁圆角。
     *
     * - [accentIds]：本卡中「强调数字」的 id（统计页大数字用 primary 色的习惯）；
     *   RemoteViews 对布局里不存在的 id 会静默跳过，所以各卡共用整组列表。
     * - `setClipToOutline`：让预渲染背景图（直角 PNG）按根布局 drawable 的
     *   16dp 圆角裁剪，封面背景不再是方角。
     */
    fun applyTheme(context: Context, views: RemoteViews, accentIds: IntArray = intArrayOf()) {
        val onSurface = themedColor(context, "text_primary", R.color.widget_text_primary)
        val onSurfaceVariant = themedColor(context, "text_secondary", R.color.widget_text_secondary)
        val accent = themedColor(context, "color_primary", R.color.widget_accent)
        for (id in TEXT_SECONDARY_IDS) views.setTextColor(id, onSurfaceVariant)
        for (id in TEXT_PRIMARY_IDS) views.setTextColor(id, onSurface)
        for (id in accentIds) views.setTextColor(id, accent)
        views.setBoolean(R.id.widget_root, "setClipToOutline", true)
    }

    /** 已添加的卡片 id。 */
    fun ids(context: Context, provider: Class<out AppWidgetProvider>): IntArray =
        AppWidgetManager.getInstance(context)
            .getAppWidgetIds(ComponentName(context, provider))

    /**
     * 绑定整卡点击：带 route 拉起应用，Dart 侧据此跳转。
     *
     * 两个细节缺一不可：
     * 1. action 必须带 route —— PendingIntent 的 filterEquals **忽略 extras**，
     *    action/组件相同就会被当成同一个 PendingIntent，后建的会覆盖先建的
     *    extras（实测：点统计卡跳到了继续观看详情页）。
     * 2. requestCode 各卡不同 —— 同理，避免跨卡复用。
     */
    fun bindClick(
        context: Context,
        views: RemoteViews,
        route: String,
        requestCode: Int,
    ) {
        val intent = Intent(context, MainActivity::class.java).apply {
            action = "com.nexhub.app.OPEN_FROM_WIDGET.$route"
            putExtra(HomeWidgetBridge.EXTRA_ROUTE, route)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }
        val pending = PendingIntent.getActivity(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        views.setOnClickPendingIntent(R.id.widget_root, pending)
    }

    /**
     * 读封面并降采样。
     *
     * 封面由历史管理器落盘（JPEG），这里必须限尺寸：RemoteViews 走 Binder，
     * 单次传输超过 1MB 会抛 TransactionTooLargeException；同时用 RGB_565
     * 把内存占用再减一半——卡片尺寸下肉眼无差。
     */
    /**
     * 绑定卡片背景图。
     *
     * 背景由 Flutter 预渲染成不透明 PNG（底色 + 封面模糊 + 不透明度都已合成），
     * 这里只负责显示：文件缺失或解码失败就隐藏，露出根布局的圆角底色。
     */
    fun bindBackground(views: RemoteViews, path: String) {
        val bitmap = if (path.isEmpty()) null else decodeCover(path, 900)
        if (bitmap == null) {
            views.setViewVisibility(R.id.widget_bg_image, View.GONE)
            return
        }
        views.setImageViewBitmap(R.id.widget_bg_image, bitmap)
        views.setViewVisibility(R.id.widget_bg_image, View.VISIBLE)
    }

    fun bindCover(views: RemoteViews, coverViewId: Int, path: String, targetPx: Int) {
        val bitmap = decodeCover(path, targetPx)
        if (bitmap != null) {
            views.setImageViewBitmap(coverViewId, bitmap)
        } else {
            views.setImageViewResource(coverViewId, R.drawable.widget_cover_placeholder)
        }
    }

    /**
     * 可选图片：有就显示，没有就隐藏视图。
     *
     * 与 [bindCover] 的差别：bindCover 缺图时显示占位色块（封面占位有意义），
     * 而统计卡的月历缺图时应该整块隐藏，不能露出一个蓝方块。
     */
    fun bindOptionalImage(views: RemoteViews, viewId: Int, path: String, targetPx: Int) {
        val bitmap = decodeCover(path, targetPx)
        if (bitmap != null) {
            views.setImageViewBitmap(viewId, bitmap)
            views.setViewVisibility(viewId, View.VISIBLE)
        } else {
            views.setViewVisibility(viewId, View.GONE)
        }
    }

    private fun decodeCover(path: String, targetPx: Int): Bitmap? {
        if (path.isEmpty()) return null
        if (!File(path).exists()) return null
        return try {
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFile(path, bounds)
            if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
            var sample = 1
            while (bounds.outWidth / (sample * 2) >= targetPx) {
                sample *= 2
            }
            val opts = BitmapFactory.Options().apply {
                inSampleSize = sample
                inPreferredConfig = Bitmap.Config.RGB_565
            }
            BitmapFactory.decodeFile(path, opts)
        } catch (e: Exception) {
            Log.w(TAG, "解码封面失败: $path", e)
            null
        }
    }
}
