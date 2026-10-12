package cn.edu.nwafu.nwafu_bksxk

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONArray

/**
 * Home-screen widget: the class on now or next today. The app writes today's
 * and tomorrow's classes (start/end epoch millis) as JSON under "classes",
 * so the widget picks the right one at each update without the app running.
 */
class NextClassWidget : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val now = System.currentTimeMillis()
        var title = "今天没有课了"
        var detail = widgetData.getString("empty", "") ?: ""
        var badge = ""
        try {
            val list = JSONArray(widgetData.getString("classes", "[]"))
            for (i in 0 until list.length()) {
                val c = list.getJSONObject(i)
                if (c.getLong("end") <= now) continue
                title = c.getString("name")
                detail = listOf(c.optString("time"), c.optString("room"))
                    .filter { it.isNotEmpty() }.joinToString(" · ")
                badge = when {
                    c.getLong("start") <= now -> "上课中"
                    c.optBoolean("tomorrow") -> "明天"
                    else -> "下一节"
                }
                break
            }
        } catch (_: Exception) {
        }
        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.next_class_widget).apply {
                setTextViewText(R.id.widget_badge, badge)
                setTextViewText(R.id.widget_title, title)
                setTextViewText(R.id.widget_detail, detail)
                setOnClickPendingIntent(
                    R.id.widget_root,
                    HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java),
                )
            }
            appWidgetManager.updateAppWidget(id, views)
        }
    }
}
