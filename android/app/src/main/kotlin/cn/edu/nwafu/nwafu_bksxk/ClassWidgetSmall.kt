package cn.edu.nwafu.nwafu_bksxk

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews

/** 1×1: start time, course name and room of the class on now or next. */
class ClassWidgetSmall : ClassWidgetProvider() {
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
            val v = RemoteViews(context.packageName, R.layout.class_widget_small)
            v.setOnClickPendingIntent(R.id.widget_root, ClassWidgets.launch(context))
            if (cur == null) {
                v.setTextViewText(R.id.widget_badge, ClassWidgets.weekLabel(data, now))
                v.setTextViewText(R.id.widget_time, "—")
                v.setTextViewText(R.id.widget_title, ClassWidgets.emptyText(data, now))
                v.setTextViewText(R.id.widget_room, "")
            } else {
                val (day, c) = cur
                v.setTextViewText(R.id.widget_badge, ClassWidgets.badge(day, c, now))
                v.setTextViewText(R.id.widget_time, c.time.substringBefore('-'))
                v.setTextViewText(R.id.widget_title, c.name)
                v.setTextViewText(R.id.widget_room, c.room)
            }
            appWidgetManager.updateAppWidget(id, v)
        }
    }
}
