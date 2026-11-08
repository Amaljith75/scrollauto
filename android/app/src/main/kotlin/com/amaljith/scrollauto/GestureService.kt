package com.amaljith.scrollauto

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.SystemClock

/**
 * Foreground service that turns hand gestures into swipes.
 *
 *  - "proximity": wave over the proximity sensor -> next reel,
 *                 cover it ~1.5 s -> pause / resume auto-scroll.
 *  - "camera":    hand moving up / down in front of the selfie camera ->
 *                 next / previous reel (see [CameraMotionDetector]).
 */
class GestureService : Service(), SensorEventListener {

    companion object {
        private const val CHANNEL_ID = "scrollauto_gesture"
        private const val NOTIF_ID = 42
        private const val HOLD_MS = 1500L
        private const val WAVE_MIN_MS = 30L
        private const val WAVE_MAX_MS = 900L

        @Volatile
        var running = false
            private set

        @Volatile
        var status: String = ""

        /** Start, restart or stop the service to match the saved gesture mode. */
        fun sync(ctx: Context) {
            val intent = Intent(ctx, GestureService::class.java)
            if (Prefs.gestureMode(ctx) == "off") {
                ctx.stopService(intent)
                return
            }
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    ctx.startForegroundService(intent)
                } else {
                    ctx.startService(intent)
                }
            } catch (t: Throwable) {
                status = "Could not start gesture service: ${t.javaClass.simpleName}"
            }
        }

        fun hasCameraPermission(ctx: Context): Boolean =
            Build.VERSION.SDK_INT < Build.VERSION_CODES.M ||
                ctx.checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED
    }

    private val main = Handler(Looper.getMainLooper())
    private var sensorManager: SensorManager? = null
    private var proximityRange = 5f
    private var camera: CameraMotionDetector? = null
    private var currentMode = "off"

    // proximity state
    private var isNear = false
    private var nearAt = 0L
    private var holdFired = false
    private val holdRunnable = Runnable {
        holdFired = true
        val svc = ScrollAccessibilityService.instance
        if (svc != null) svc.togglePause() else status = "Accessibility service is off"
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val mode = Prefs.gestureMode(this)
        val useCamera = startInForeground(mode == "camera" && hasCameraPermission(this))
        if (mode == "off") {
            stopSelf()
            return START_NOT_STICKY
        }
        if (mode != currentMode || (mode == "camera" && camera == null)) {
            stopListeners()
            currentMode = mode
            when (mode) {
                "proximity" -> startProximity()
                "camera" -> if (useCamera) {
                    startCamera()
                } else if (!hasCameraPermission(this)) {
                    status = "Camera permission not granted"
                }
            }
        }
        running = true
        return START_STICKY
    }

    override fun onDestroy() {
        stopListeners()
        running = false
        currentMode = "off"
        super.onDestroy()
    }

    // ---------------------------------------------------------------- foreground

    /** @return true if started with camera access. */
    private fun startInForeground(camera: Boolean): Boolean {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "Gesture control", NotificationManager.IMPORTANCE_LOW)
            )
        }
        val openApp = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val text = if (camera) "Air-swipe (camera) gestures active" else "Hand-wave gestures active"
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        val notification = builder
            .setContentTitle("ScrollAuto")
            .setContentText(text)
            .setSmallIcon(android.R.drawable.ic_menu_view)
            .setContentIntent(openApp)
            .setOngoing(true)
            .build()

        if (camera) {
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    startForeground(NOTIF_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA)
                } else {
                    startForeground(NOTIF_ID, notification)
                }
                return true
            } catch (t: Throwable) {
                // e.g. Android 14 refuses camera FGS when restarted from the background.
                status = "Open ScrollAuto once to re-enable the camera"
            }
        }
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(NOTIF_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIF_ID, notification)
        }
        return false
    }

    private fun stopListeners() {
        sensorManager?.unregisterListener(this)
        sensorManager = null
        main.removeCallbacks(holdRunnable)
        camera?.stop()
        camera = null
    }

    // ---------------------------------------------------------------- proximity

    private fun startProximity() {
        val sm = getSystemService(Context.SENSOR_SERVICE) as SensorManager
        val sensor = sm.getDefaultSensor(Sensor.TYPE_PROXIMITY)
        if (sensor == null) {
            status = "This phone has no proximity sensor"
            return
        }
        proximityRange = sensor.maximumRange
        sensorManager = sm
        isNear = false
        sm.registerListener(this, sensor, SensorManager.SENSOR_DELAY_GAME)
        status = "Wave over the top of the phone"
    }

    override fun onSensorChanged(event: SensorEvent?) {
        val e = event ?: return
        val value = e.values[0]
        val near = value < proximityRange && value < 5f
        val t = SystemClock.elapsedRealtime()
        if (near && !isNear) {
            isNear = true
            nearAt = t
            holdFired = false
            main.postDelayed(holdRunnable, HOLD_MS)
        } else if (!near && isNear) {
            isNear = false
            main.removeCallbacks(holdRunnable)
            val d = t - nearAt
            if (!holdFired && d in WAVE_MIN_MS..WAVE_MAX_MS) {
                swipe(next = true, reason = "Hand wave")
            }
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}

    // ---------------------------------------------------------------- camera

    private fun startCamera() {
        val detector = CameraMotionDetector(this) { handUp ->
            val invert = Prefs.get(this).getBoolean(Prefs.INVERT_CAMERA, false)
            val next = handUp != invert
            swipe(next, if (handUp) "Air swipe up" else "Air swipe down")
        }
        val err = detector.start()
        if (err != null) {
            status = err
        } else {
            camera = detector
            status = "Move your hand up/down in front of the selfie camera"
        }
    }

    private fun swipe(next: Boolean, reason: String) {
        val svc = ScrollAccessibilityService.instance
        if (svc == null) {
            status = "Accessibility service is off"
            return
        }
        svc.requestSwipe(next, reason)
    }
}
