package cn.edu.nwafu.nwafu_bksxk

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.view.View
import android.widget.RemoteViews

/**
 * 2×2: today's classes (up to 4 rows; finished ones scroll off first), the
 * one on now highlighted, the next one marked. After the last class it
 * shows tomorrow's list instead.
 */
class ClassWidgetToday : ClassWidgetProvider() {
    private val rows = intArrayOf(R.id.row0, R.id.row1, R.id.row2, R.id.row3)
    private val times = intArrayOf(R.id.row0_time, R.id.row1_time, R.id.row2_time, R.id.row3_time)
    private val names = intArrayOf(R.id.row0_name, R.id.row1_name, R.id.row2_name, R.id.row3_name)
    private val rooms = intArrayOf(R.id.row0_room, R.id.row1_room, R.id.row2_room, R.id.row3_room)

    override fun render(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val now = System.currentTimeMillis()
        val data = ClassWidgets.read(widgetData)
        val today = ClassWidgets.today(data, now)
        val todayClasses = today?.classes.orEmpty()
        val todayDone = todayClasses.isNotEmpty() && todayClasses.all { it.end <= now }
        // After today's last class, look ahead to tomorrow.
        val tomorrowKey = ClassWidgets.todayKey(now + 24 * 3600 * 1000L)
        val tomorrow = data.days.firstOrNull { it.date == tomorrowKey }
        val showTomorrow = (todayClasses.isEmpty() || todayDone) &&
            tomorrow != null && tomorrow.classes.isNotEmpty()
        val list = if (showTomorrow) tomorrow!!.classes else todayClasses
        // Drop finished classes first when more than four.
        var from = 0
        while (list.size - from > rows.size && list[from].end <= now) from++
        val shown = list.drop(from).take(rows.size)
        val nextIndex = shown.indexOfFirst { it.start > now }

        for (id in appWidgetIds) {
            val v = RemoteViews(context.packageName, R.layout.class_widget_today)
            v.setOnClickPendingIntent(R.id.widget_root, ClassWidgets.launch(context))
            v.setTextViewText(
                R.id.widget_header,
                if (showTomorrow) "明天" else ClassWidgets.dateLabel(now),
            )
            v.setTextViewText(R.id.widget_week, ClassWidgets.weekLabel(data, now))
            val more = list.size - from - shown.size
            v.setTextViewText(R.id.widget_more, if (more > 0) "还有 $more 节" else "")
            v.setViewVisibility(R.id.widget_more, if (more > 0) View.VISIBLE else View.GONE)
            if (shown.isEmpty()) {
                v.setViewVisibility(R.id.widget_empty, View.VISIBLE)
                v.setTextViewText(R.id.widget_empty, ClassWidgets.emptyText(data, now))
            } else {
                v.setViewVisibility(R.id.widget_empty, View.GONE)
            }
            for (i in rows.indices) {
                val c = shown.getOrNull(i)
                if (c == null) {
                    v.setViewVisibility(rows[i], View.GONE)
                    continue
                }
                v.setViewVisibility(rows[i], View.VISIBLE)
                val live = c.start <= now && c.end > now
                val past = c.end <= now
                v.setInt(
                    rows[i],
                    "setBackgroundResource",
                    when {
                        live -> R.drawable.widget_row_live
                        i == nextIndex -> R.drawable.widget_row_next
                        else -> R.drawable.widget_row
                    },
                )
                v.setTextViewText(times[i], c.time.replace("-", "\n"))
                v.setTextViewText(names[i], if (live) "● ${c.name}" else c.name)
                v.setTextViewText(rooms[i], listOf(c.room, c.sec).filter { it.isNotEmpty() }.joinToString(" · "))
                val primary = context.getColor(
                    if (past) R.color.widget_text_faint else R.color.widget_text,
                )
                val secondary = context.getColor(
                    if (past) R.color.widget_text_faint else R.color.widget_text_secondary,
                )
                v.setTextColor(times[i], secondary)
                v.setTextColor(names[i], if (live) context.getColor(R.color.widget_accent) else primary)
                v.setTextColor(rooms[i], secondary)
            }
            appWidgetManager.updateAppWidget(id, v)
        }
    }
}
