package com.amaljith.scrollauto

import android.content.Context
import android.content.SharedPreferences

/** Settings shared between the Flutter UI and the native services. */
object Prefs {
    private const val NAME = "scrollauto"

    const val AUTO = "autoEnabled"
    const val FALLBACK_SECONDS = "fallbackSeconds"
    const val STRICT = "strictScreen"
    const val YT = "ytEnabled"
    const val IG = "igEnabled"
    const val GESTURE_MODE = "gestureMode" // off | proximity | camera
    const val INVERT_CAMERA = "invertCamera"

    private val booleans = mapOf(
        AUTO to true, STRICT to true, YT to true, IG to true, INVERT_CAMERA to false
    )

    fun get(ctx: Context): SharedPreferences =
        ctx.applicationContext.getSharedPreferences(NAME, Context.MODE_PRIVATE)

    fun gestureMode(ctx: Context): String = get(ctx).getString(GESTURE_MODE, "off") ?: "off"

    fun toMap(ctx: Context): Map<String, Any> {
        val p = get(ctx)
        val m = HashMap<String, Any>()
        for ((k, d) in booleans) m[k] = p.getBoolean(k, d)
        m[FALLBACK_SECONDS] = p.getInt(FALLBACK_SECONDS, 0)
        m[GESTURE_MODE] = gestureMode(ctx)
        val today = p.getString(COUNT_DATE, "") == todayKey()
        m["countToday"] = if (today) p.getInt(COUNT_TODAY, 0) else 0
        m["countAutoToday"] = if (today) p.getInt(COUNT_AUTO, 0) else 0
        m["countGestureToday"] = if (today) p.getInt(COUNT_GESTURE, 0) else 0
        m["countTotal"] = p.getInt(COUNT_TOTAL, 0)
        return m
    }

    private const val COUNT_DATE = "countDate"
    private const val COUNT_TODAY = "countToday"
    private const val COUNT_AUTO = "countAuto"
    private const val COUNT_GESTURE = "countGesture"
    private const val COUNT_TOTAL = "countTotal"

    private fun todayKey(): String {
        val c = java.util.Calendar.getInstance()
        return "${c.get(java.util.Calendar.YEAR)}-${c.get(java.util.Calendar.DAY_OF_YEAR)}"
    }

    /** Count a swipe for the stats on the home screen. */
    fun recordSwipe(ctx: Context, gesture: Boolean) {
        val p = get(ctx)
        val day = todayKey()
        val sameDay = p.getString(COUNT_DATE, "") == day
        val today = if (sameDay) p.getInt(COUNT_TODAY, 0) else 0
        val auto = if (sameDay) p.getInt(COUNT_AUTO, 0) else 0
        val gest = if (sameDay) p.getInt(COUNT_GESTURE, 0) else 0
        p.edit()
            .putString(COUNT_DATE, day)
            .putInt(COUNT_TODAY, today + 1)
            .putInt(COUNT_AUTO, if (gesture) auto else auto + 1)
            .putInt(COUNT_GESTURE, if (gesture) gest + 1 else gest)
            .putInt(COUNT_TOTAL, p.getInt(COUNT_TOTAL, 0) + 1)
            .apply()
    }

    fun update(ctx: Context, values: Map<*, *>) {
        val e = get(ctx).edit()
        for ((k, v) in values) {
            val key = k as? String ?: continue
            when {
                booleans.containsKey(key) && v is Boolean -> e.putBoolean(key, v)
                key == FALLBACK_SECONDS && v is Number -> e.putInt(key, v.toInt().coerceIn(0, 600))
                key == GESTURE_MODE && v is String -> e.putString(key, v)
            }
        }
        e.apply()
    }
}
