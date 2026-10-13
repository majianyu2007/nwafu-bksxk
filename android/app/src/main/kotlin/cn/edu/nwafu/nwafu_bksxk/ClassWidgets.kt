package cn.edu.nwafu.nwafu_bksxk

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.SystemClock
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale
import java.util.TimeZone

/**
 * Shared model + rendering helpers for the three timetable widgets
 * (ClassWidgetSmall 1×1, NextClassWidget 2×1, ClassWidgetToday 2×2).
 *
 * The app and the background refresh write one JSON document under "widget"
 * (see lib/data/home_widget_sync.dart): a week of dated classes with absolute
 * start/end epoch millis. Every redraw re-derives "now / next" from it, and a
 * single inexact, non-waking alarm redraws all widgets at the next class
 * start, class end or China-Standard-Time midnight, so nothing polls.
 */
object ClassWidgets {
    private val CST: TimeZone = TimeZone.getTimeZone("Asia/Shanghai")
    private val WEEKDAYS = arrayOf("", "周一", "周二", "周三", "周四", "周五", "周六", "周日")
    private const val ACTION_TICK = "cn.edu.nwafu.nwafu_bksxk.WIDGET_TICK"
    const val SYNC_HINT = "打开 App 同步课表"

    val providers: List<Class<out ClassWidgetProvider>> = listOf(
        ClassWidgetSmall::class.java,
        NextClassWidget::class.java,
        ClassWidgetToday::class.java,
    )

    class Item(
        val name: String,
        val room: String,
        val time: String,
        val sec: String,
        val start: Long,
        val end: Long,
    )

    class Day(val date: String, val week: Int?, val weekday: Int, val classes: List<Item>)

    class Data(val message: String, val days: List<Day>)

    fun read(prefs: SharedPreferences): Data {
        val raw = prefs.getString("widget", null) ?: return Data(SYNC_HINT, emptyList())
        return try {
            val j = JSONObject(raw)
            val days = mutableListOf<Day>()
            val arr = j.optJSONArray("days")
            if (arr != null) {
                for (i in 0 until arr.length()) {
                    val d = arr.getJSONObject(i)
                    val cs = d.optJSONArray("classes")
                    val items = mutableListOf<Item>()
                    if (cs != null) {
                        for (k in 0 until cs.length()) {
                            val c = cs.getJSONObject(k)
                            items.add(
                                Item(
                                    c.optString("name"),
                                    c.optString("room"),
                                    c.optString("time"),
                                    c.optString("sec"),
                                    c.getLong("start"),
                                    c.getLong("end"),
                                ),
                            )
                        }
                    }
                    days.add(
                        Day(
                            d.optString("date"),
                            if (d.isNull("week")) null else d.optInt("week"),
                            d.optInt("weekday"),
                            items,
                        ),
                    )
                }
            }
            Data(j.optString("message"), days)
        } catch (_: Exception) {
            Data(SYNC_HINT, emptyList())
        }
    }

    fun todayKey(now: Long): String =
        SimpleDateFormat("yyyy-MM-dd", Locale.US).apply { timeZone = CST }.format(now)

    private fun cstCalendar(now: Long): Calendar =
        Calendar.getInstance(CST, Locale.CHINA).apply { timeInMillis = now }

    /** "10月14日 周三" for the CST day of [now]. */
    fun dateLabel(now: Long): String {
        val c = cstCalendar(now)
        val wd = (c.get(Calendar.DAY_OF_WEEK) + 5) % 7 + 1
        return "${c.get(Calendar.MONTH) + 1}月${c.get(Calendar.DAY_OF_MONTH)}日 ${WEEKDAYS[wd]}"
    }

    private fun nextMidnight(now: Long): Long = cstCalendar(now).apply {
        add(Calendar.DAY_OF_MONTH, 1)
        set(Calendar.HOUR_OF_DAY, 0)
        set(Calendar.MINUTE, 0)
        set(Calendar.SECOND, 0)
        set(Calendar.MILLISECOND, 0)
    }.timeInMillis

    /** Today's entry, if the document still covers today. */
    fun today(data: Data, now: Long): Day? = data.days.firstOrNull { it.date == todayKey(now) }

    /** The class on now, else the next one (today or later), with its day. */
    fun current(data: Data, now: Long): Pair<Day, Item>? {
        val key = todayKey(now)
        for (d in data.days) {
            if (d.date < key) continue
            for (c in d.classes) if (c.end > now) return d to c
        }
        return null
    }

    /** "上课中" / "下一节" / "明天" / "周一". */
    fun badge(day: Day, item: Item, now: Long): String {
        if (item.start <= now) return "上课中"
        if (day.date == todayKey(now)) return "下一节"
        if (day.date == todayKey(now + 24 * 3600 * 1000L)) return "明天"
        return WEEKDAYS.getOrElse(day.weekday) { "之后" }
    }

    fun weekLabel(data: Data, now: Long): String {
        val w = today(data, now)?.week ?: return ""
        return "第${w}周"
    }

    /** What to say when there is no class to show. */
    fun emptyText(data: Data, now: Long): String {
        if (data.message.isNotEmpty()) return data.message
        if (data.days.none { it.date >= todayKey(now) }) return SYNC_HINT
        val t = today(data, now)
        return if (t != null && t.classes.isNotEmpty()) "今天的课已上完" else "今天没有课"
    }

    fun launch(context: Context): PendingIntent =
        HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java)

    /** A launcher-side Chronometer countdown: ticks without waking the app. */
    fun setCountdown(views: RemoteViews, id: Int, target: Long, format: String, now: Long) {
        views.setChronometer(id, SystemClock.elapsedRealtime() + (target - now), format, true)
        views.setChronometerCountDown(id, true)
        views.setViewVisibility(id, View.VISIBLE)
    }

    /** Redraws every placed widget of every size. */
    fun updateAll(context: Context) {
        val mgr = AppWidgetManager.getInstance(context)
        val prefs = HomeWidgetPlugin.getData(context)
        for (cls in providers) {
            val ids = mgr.getAppWidgetIds(ComponentName(context, cls))
            if (ids.isEmpty()) continue
            try {
                cls.getDeclaredConstructor().newInstance().render(context, mgr, ids, prefs)
            } catch (_: Exception) {
            }
        }
    }

    private fun anyPlaced(context: Context): Boolean {
        val mgr = AppWidgetManager.getInstance(context)
        return providers.any { mgr.getAppWidgetIds(ComponentName(context, it)).isNotEmpty() }
    }

    private fun tickIntent(context: Context): PendingIntent = PendingIntent.getBroadcast(
        context,
        0,
        Intent(context, ClassWidgetTick::class.java).setAction(ACTION_TICK),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    /**
     * Arms one inexact RTC (non-waking) alarm at the next class boundary or
     * CST midnight, whichever comes first. A sleeping device gets it when it
     * next wakes, which is when the widget can be seen anyway. Re-arming
     * replaces the previous alarm (same PendingIntent).
     */
    fun scheduleNext(context: Context, prefs: SharedPreferences) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
        if (!anyPlaced(context)) {
            am.cancel(tickIntent(context))
            return
        }
        val now = System.currentTimeMillis()
        var next = nextMidnight(now)
        for (d in read(prefs).days) {
            for (c in d.classes) {
                if (c.start in (now + 1) until next) next = c.start
                if (c.end in (now + 1) until next) next = c.end
            }
        }
        try {
            am.set(AlarmManager.RTC, next + 1000L, tickIntent(context))
        } catch (_: Exception) {
        }
    }

    fun cancelIfUnused(context: Context) {
        if (anyPlaced(context)) return
        val am = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
        am.cancel(tickIntent(context))
    }
}

/** Base of the three sizes: render, then arm the shared boundary alarm. */
abstract class ClassWidgetProvider : HomeWidgetProvider() {
    abstract fun render(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    )

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        render(context, appWidgetManager, appWidgetIds, widgetData)
        ClassWidgets.scheduleNext(context, widgetData)
    }

    override fun onDisabled(context: Context) {
        super.onDisabled(context)
        ClassWidgets.cancelIfUnused(context)
    }
}

/** The boundary alarm (and boot/time changes): redraw all, re-arm. */
class ClassWidgetTick : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        ClassWidgets.updateAll(context)
        ClassWidgets.scheduleNext(context, HomeWidgetPlugin.getData(context))
    }
}
