package com.amaljith.scrollauto

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.ImageFormat
import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CaptureRequest
import android.media.Image
import android.media.ImageReader
import android.os.Handler
import android.os.HandlerThread
import android.os.SystemClock
import kotlin.math.abs

/**
 * Very light "air swipe" detector using the front camera.
 *
 * Frames are reduced to a 32x24 brightness grid. Cells that change a lot
 * between frames are "motion". The centre of motion is tracked over time;
 * if it travels far enough vertically within ~0.7 s we report a swipe.
 * No ML model, no extra dependencies, low CPU.
 *
 * @param onSwipe called on a background thread with `true` for hand moving up.
 */
class CameraMotionDetector(
    private val ctx: Context,
    private val onSwipe: (handUp: Boolean) -> Unit,
) {
    private companion object {
        const val GW = 32
        const val GH = 24
        const val CELL_DIFF = 28
        const val MIN_MOTION_FRACTION = 0.03f
        const val MAX_MOTION_FRACTION = 0.60f // above this it's a lighting change
        const val TRACK_WINDOW_MS = 700L
        const val TRACK_GAP_MS = 350L
        const val TRAVEL = 0.35f
        const val COOLDOWN_MS = 1200L
    }

    private data class Pt(val t: Long, val y: Float)

    private var thread: HandlerThread? = null
    private var handler: Handler? = null
    private var device: CameraDevice? = null
    private var session: CameraCaptureSession? = null
    private var reader: ImageReader? = null

    private var sensorOrientation = 270
    private var prev: IntArray? = null
    private val track = ArrayList<Pt>()
    private var lastMotionAt = 0L
    private var lastFireAt = 0L

    /** @return null on success, otherwise an error message. */
    @SuppressLint("MissingPermission")
    fun start(): String? {
        if (!GestureService.hasCameraPermission(ctx)) return "Camera permission not granted"
        return try {
            val cm = ctx.getSystemService(Context.CAMERA_SERVICE) as CameraManager
            val id = cm.cameraIdList.firstOrNull {
                cm.getCameraCharacteristics(it).get(CameraCharacteristics.LENS_FACING) ==
                    CameraCharacteristics.LENS_FACING_FRONT
            } ?: return "No front camera found"

            val chars = cm.getCameraCharacteristics(id)
            sensorOrientation = chars.get(CameraCharacteristics.SENSOR_ORIENTATION) ?: 270
            val map = chars.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
                ?: return "Camera config unavailable"
            val sizes = map.getOutputSizes(ImageFormat.YUV_420_888)
            if (sizes.isNullOrEmpty()) return "Camera has no YUV output"
            val size = sizes.filter { it.width >= 160 && it.height >= 120 }
                .minByOrNull { it.width * it.height }
                ?: sizes.minByOrNull { it.width * it.height }!!

            val th = HandlerThread("scrollauto-camera").also { it.start() }
            val h = Handler(th.looper)
            thread = th
            handler = h

            val r = ImageReader.newInstance(size.width, size.height, ImageFormat.YUV_420_888, 2)
            r.setOnImageAvailableListener({ rd ->
                val img = try { rd.acquireLatestImage() } catch (_: Throwable) { null }
                if (img != null) {
                    try { process(img) } catch (_: Throwable) { } finally { img.close() }
                }
            }, h)
            reader = r

            cm.openCamera(id, object : CameraDevice.StateCallback() {
                override fun onOpened(d: CameraDevice) {
                    device = d
                    createSession(d, r)
                }

                override fun onDisconnected(d: CameraDevice) {
                    d.close()
                    device = null
                }

                override fun onError(d: CameraDevice, error: Int) {
                    d.close()
                    device = null
                    GestureService.status = "Camera error $error (in use by another app?)"
                }
            }, h)
            null
        } catch (t: Throwable) {
            stop()
            "Camera failed: ${t.javaClass.simpleName}"
        }
    }

    @Suppress("DEPRECATION")
    private fun createSession(d: CameraDevice, r: ImageReader) {
        try {
            d.createCaptureSession(listOf(r.surface), object : CameraCaptureSession.StateCallback() {
                override fun onConfigured(s: CameraCaptureSession) {
                    session = s
                    try {
                        val req = d.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW).apply {
                            addTarget(r.surface)
                        }.build()
                        s.setRepeatingRequest(req, null, handler)
                    } catch (_: Throwable) {
                        GestureService.status = "Camera could not start streaming"
                    }
                }

                override fun onConfigureFailed(s: CameraCaptureSession) {
                    GestureService.status = "Camera session failed"
                }
            }, handler)
        } catch (_: Throwable) {
            GestureService.status = "Camera session failed"
        }
    }

    fun stop() {
        try { session?.close() } catch (_: Throwable) {}
        try { device?.close() } catch (_: Throwable) {}
        try { reader?.close() } catch (_: Throwable) {}
        thread?.quitSafely()
        session = null; device = null; reader = null; thread = null; handler = null
        prev = null
        track.clear()
    }

    private fun process(img: Image) {
        val plane = img.planes[0]
        val buf = plane.buffer
        val rowStride = plane.rowStride
        val pixStride = plane.pixelStride
        val w = img.width
        val h = img.height

        val grid = IntArray(GW * GH)
        for (gy in 0 until GH) {
            for (gx in 0 until GW) {
                var sum = 0
                for (sy in 0..1) {
                    val y = ((gy * 2 + sy) * h) / (GH * 2) + h / (GH * 4)
                    for (sx in 0..1) {
                        val x = ((gx * 2 + sx) * w) / (GW * 2) + w / (GW * 4)
                        sum += buf.get(y * rowStride + x * pixStride).toInt() and 0xFF
                    }
                }
                grid[gy * GW + gx] = sum / 4
            }
        }

        val p = prev
        prev = grid
        if (p == null) return

        var count = 0
        var sx = 0f
        var sy = 0f
        for (i in grid.indices) {
            if (abs(grid[i] - p[i]) > CELL_DIFF) {
                count++
                sx += (i % GW + 0.5f) / GW
                sy += (i / GW + 0.5f) / GH
            }
        }
        val fraction = count.toFloat() / grid.size
        if (fraction < MIN_MOTION_FRACTION || fraction > MAX_MOTION_FRACTION) return

        val cx = sx / count
        val cy = sy / count
        // Convert sensor coordinates to "upright portrait screen" vertical position.
        val uprightY = when (sensorOrientation) {
            90 -> cx
            180 -> 1f - cy
            270 -> 1f - cx
            else -> cy
        }

        val t = SystemClock.elapsedRealtime()
        if (t - lastMotionAt > TRACK_GAP_MS) track.clear()
        lastMotionAt = t
        track.add(Pt(t, uprightY))
        while (track.isNotEmpty() && t - track[0].t > TRACK_WINDOW_MS) track.removeAt(0)

        if (t - lastFireAt < COOLDOWN_MS || track.size < 3) return
        val dy = track.last().y - track.first().y
        if (abs(dy) >= TRAVEL) {
            lastFireAt = t
            track.clear()
            onSwipe(dy < 0) // y decreasing = hand moving up
        }
    }
}
