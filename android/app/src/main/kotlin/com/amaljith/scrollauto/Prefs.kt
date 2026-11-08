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
        return m
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
