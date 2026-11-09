package com.amaljith.scrollauto

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.Path
import android.graphics.Rect
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.widget.Toast

/**
 * Core of Doom.
 *
 * Every [TICK_MS] it inspects the foreground window. When Instagram Reels or
 * YouTube Shorts is showing it looks for the player's progress bar
 * (a node with RangeInfo). When the progress reaches the end, or wraps back
 * to the start because the video looped, it swipes up to the next reel.
 * If no progress bar is exposed, an optional fallback timer is used.
 *
 * Gesture sources ([GestureService]) call [requestSwipe] / [togglePause].
 */
class ScrollAccessibilityService : AccessibilityService() {

    companion object {
        @Volatile
        var instance: ScrollAccessibilityService? = null
            private set

        @Volatile
        var lastEvent: String = "Waiting for service"

        const val YT_PKG = "com.google.android.youtube"
        const val IG_PKG = "com.instagram.android"

        private const val TICK_MS = 400L
        private const val SWIPE_COOLDOWN_MS = 1500L
        private const val MAX_NODES = 1500
        private const val END_FRACTION = 0.98f
    }

    private val handler = Handler(Looper.getMainLooper())
    private var activePkg: String? = null
    private var reelStartedAt = 0L
    private var lastProgress = -1f
    private var lastSwipeAt = 0L
    private var lastScrollEventAt = 0L

    @Volatile
    var paused = false
        private set

    private val ticker = object : Runnable {
        override fun run() {
            try {
                tick()
            } catch (t: Throwable) {
                lastEvent = "Error: ${t.javaClass.simpleName}"
            }
            handler.postDelayed(this, TICK_MS)
        }
    }

    // ---------------------------------------------------------------- lifecycle

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        reelStartedAt = now()
        lastEvent = "Service connected"
        handler.removeCallbacks(ticker)
        handler.post(ticker)
    }

    override fun onUnbind(intent: Intent?): Boolean {
        shutdown()
        return super.onUnbind(intent)
    }

    override fun onDestroy() {
        shutdown()
        super.onDestroy()
    }

    private fun shutdown() {
        handler.removeCallbacksAndMessages(null)
        if (instance === this) instance = null
        lastEvent = "Service stopped"
    }

    override fun onInterrupt() {}

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        val e = event ?: return
        val pkg = e.packageName?.toString() ?: return
        if (pkg != YT_PKG && pkg != IG_PKG) return
        if (e.eventType == AccessibilityEvent.TYPE_VIEW_SCROLLED) {
            // The reel pager moved (user swipe or ours) -> a new reel started.
            val cls = e.className?.toString() ?: ""
            if (cls.contains("RecyclerView") || cls.contains("ViewPager")) {
                val t = now()
                if (t - lastScrollEventAt > 600) onNewReel()
                lastScrollEventAt = t
            }
        }
    }

    // ---------------------------------------------------------------- public API

    /** Thread-safe: may be called from sensor/camera threads. */
    fun requestSwipe(next: Boolean, reason: String) {
        handler.post {
            if (!isTargetEnabled(activePkg, Prefs.get(this))) {
                lastEvent = "Gesture ignored – open Reels or Shorts"
                return@post
            }
            if (swipe(next, reason)) Prefs.recordSwipe(this, gesture = true)
        }
    }

    private fun autoSwipe(reason: String) {
        if (swipe(true, reason)) Prefs.recordSwipe(this, gesture = false)
    }

    /** Swipe regardless of which app is open (used by the in-app test). */
    fun requestTestSwipe() {
        handler.post { swipe(true, "Test swipe") }
    }

    fun togglePause() {
        handler.post {
            paused = !paused
            onNewReel()
            lastEvent = if (paused) "Paused" else "Resumed"
            Toast.makeText(
                this,
                if (paused) "Doom paused" else "Doom resumed",
                Toast.LENGTH_SHORT
            ).show()
        }
    }

    // ---------------------------------------------------------------- logic

    private fun now() = SystemClock.elapsedRealtime()

    private fun onNewReel() {
        reelStartedAt = now()
        lastProgress = -1f
    }

    private fun isTargetEnabled(pkg: String?, prefs: SharedPreferences): Boolean = when (pkg) {
        YT_PKG -> prefs.getBoolean(Prefs.YT, true)
        IG_PKG -> prefs.getBoolean(Prefs.IG, true)
        else -> false
    }

    private fun tick() {
        val prefs = Prefs.get(this)
        val root = rootInActiveWindow
        val pkg = root?.packageName?.toString()

        if (pkg != activePkg) {
            activePkg = pkg
            onNewReel()
        }
        if (root == null || pkg == null || !isTargetEnabled(pkg, prefs)) {
            if (!paused) lastEvent = "Waiting for Reels / Shorts"
            return
        }
        if (paused) return
        if (!prefs.getBoolean(Prefs.AUTO, true)) {
            lastEvent = "Auto-scroll off (gestures still work)"
            return
        }

        val t = now()
        if (t - lastSwipeAt < SWIPE_COOLDOWN_MS) return

        val scan = scan(root, pkg)
        if (prefs.getBoolean(Prefs.STRICT, true) && !scan.onShortVideoScreen) {
            lastEvent = "Open a reel / short to start"
            onNewReel()
            return
        }

        val p = scan.progress
        if (p != null) {
            val prev = lastProgress
            lastProgress = p
            when {
                // Video looped back to the start -> it ended.
                prev >= 0.75f && p < prev - 0.5f -> autoSwipe("Reel ended (looped)")
                // Video is at the very end.
                p >= END_FRACTION && prev >= 0f -> autoSwipe("Reel ended")
                else -> lastEvent = "Watching – ${(p * 100).toInt()}%"
            }
            return
        }

        val fallback = prefs.getInt(Prefs.FALLBACK_SECONDS, 0)
        if (fallback > 0) {
            val elapsed = (t - reelStartedAt) / 1000
            if (elapsed >= fallback) {
                autoSwipe("Timer ($fallback s)")
            } else {
                lastEvent = "No progress bar – timer ${elapsed}/${fallback}s"
            }
        } else {
            lastEvent = "No progress bar found – set a fallback timer"
        }
    }

    private class Scan {
        var onShortVideoScreen = false
        var progress: Float? = null
        var progressWidth = 0
    }

    /** Breadth-first walk of the window looking for screen markers and the progress bar. */
    private fun scan(root: AccessibilityNodeInfo, pkg: String): Scan {
        val res = Scan()
        val markers = if (pkg == YT_PKG) {
            listOf("reel_", "shorts")
        } else {
            listOf("clips_", "reel")
        }
        val queue = ArrayDeque<AccessibilityNodeInfo>()
        queue.add(root)
        var visited = 0
        val rect = Rect()

        while (queue.isNotEmpty() && visited < MAX_NODES) {
            val node = queue.removeFirst()
            visited++

            if (!res.onShortVideoScreen) {
                val id = node.viewIdResourceName?.lowercase()
                if (id != null && markers.any { id.contains(it) }) res.onShortVideoScreen = true
            }

            val ri = node.rangeInfo
            if (ri != null && ri.max > ri.min && node.isVisibleToUser) {
                node.getBoundsInScreen(rect)
                if (rect.width() > res.progressWidth) {
                    // Progress bars rarely fire events, so force a fresh value.
                    node.refresh()
                    val r = node.rangeInfo ?: ri
                    if (r.max > r.min) {
                        res.progress = ((r.current - r.min) / (r.max - r.min)).coerceIn(0f, 1f)
                        res.progressWidth = rect.width()
                    }
                }
            }

            for (i in 0 until node.childCount) {
                node.getChild(i)?.let { queue.add(it) }
            }
        }
        return res
    }

    private fun swipe(next: Boolean, reason: String): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) {
            lastEvent = "Gestures need Android 7.0+"
            return false
        }
        val dm = resources.displayMetrics
        val x = dm.widthPixels * 0.42f
        val low = dm.heightPixels * 0.75f
        val high = dm.heightPixels * 0.28f
        val path = Path().apply {
            if (next) {
                moveTo(x, low); lineTo(x, high)
            } else {
                moveTo(x, high); lineTo(x, low)
            }
        }
        val gesture = GestureDescription.Builder()
            .addStroke(GestureDescription.StrokeDescription(path, 0, 220))
            .build()
        lastSwipeAt = now()
        onNewReel()
        lastEvent = if (next) "$reason → next" else "$reason → previous"
        return dispatchGesture(gesture, null, null)
    }
}
