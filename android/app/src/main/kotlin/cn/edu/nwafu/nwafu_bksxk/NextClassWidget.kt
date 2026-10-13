package cn.edu.nwafu.nwafu_bksxk

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.view.View
import android.widget.RemoteViews

/**
 * 2×1: the class on now or next with time, room and periods, plus a live
 * countdown to its start (within 3 h) or, during class, to its end. Keeps
 * the original class name so widgets placed by earlier versions survive.
 */
class NextClassWidget : ClassWidgetProvider() {
    override fun render(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val now = System.currentTimeMillis()
        val data = ClassWidgets.read(widgetData)
        val cur = ClassWidgets.current(data, now)
        for (id in appWidgetIds) {
            val v = RemoteViews(context.packageName, R.layout.next_class_widget)
            v.setOnClickPendingIntent(R.id.widget_root, ClassWidgets.launch(context))
            v.setTextViewText(R.id.widget_week, ClassWidgets.weekLabel(data, now))
            if (cur == null) {
                v.setTextViewText(R.id.widget_badge, ClassWidgets.dateLabel(now))
                v.setTextViewText(R.id.widget_title, ClassWidgets.emptyText(data, now))
                v.setTextViewText(R.id.widget_detail, "")
                v.setViewVisibility(R.id.widget_countdown, View.GONE)
            } else {
                val (day, c) = cur
                v.setTextViewText(R.id.widget_badge, ClassWidgets.badge(day, c, now))
                v.setTextViewText(R.id.widget_title, c.name)
                v.setTextViewText(
                    R.id.widget_detail,
                    listOf(c.time, c.room, c.sec).filter { it.isNotEmpty() }.joinToString(" · "),
                )
                when {
                    c.start <= now ->
                        ClassWidgets.setCountdown(v, R.id.widget_countdown, c.end, "%s 后下课", now)
                    c.start - now < 3 * 3600 * 1000L ->
                        ClassWidgets.setCountdown(v, R.id.widget_countdown, c.start, "%s 后上课", now)
                    else -> v.setViewVisibility(R.id.widget_countdown, View.GONE)
                }
            }
            appWidgetManager.updateAppWidget(id, v)
        }
    }
}
