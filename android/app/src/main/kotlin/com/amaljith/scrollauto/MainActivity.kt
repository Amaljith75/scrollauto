package com.amaljith.scrollauto

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val main = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "scrollauto/control")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "getStatus" -> result.success(status())
                        "setSettings" -> {
                            val args = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
                            Prefs.update(this, args)
                            if (args.containsKey(Prefs.GESTURE_MODE)) GestureService.sync(this)
                            result.success(null)
                        }
                        "openAccessibilitySettings" -> {
                            startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                            result.success(null)
                        }
                        "openAppSettings" -> {
                            startActivity(
                                Intent(
                                    Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                                    Uri.parse("package:$packageName")
                                )
                            )
                            result.success(null)
                        }
                        "requestCameraPermission" -> {
                            requestPerm(Manifest.permission.CAMERA, 1)
                            result.success(null)
                        }
                        "requestNotificationPermission" -> {
                            if (Build.VERSION.SDK_INT >= 33) {
                                requestPerm(Manifest.permission.POST_NOTIFICATIONS, 2)
                            }
                            result.success(null)
                        }
                        "togglePause" -> {
                            ScrollAccessibilityService.instance?.togglePause()
                            result.success(null)
                        }
                        "testScroll" -> {
                            main.postDelayed({
                                ScrollAccessibilityService.instance?.requestTestSwipe()
                            }, 5000)
                            result.success(ScrollAccessibilityService.instance != null)
                        }
                        else -> result.notImplemented()
                    }
                } catch (t: Throwable) {
                    result.error("native_error", t.message, null)
                }
            }
    }

    override fun onResume() {
        super.onResume()
        // Re-start the gesture listener while we're in the foreground
        // (Android only grants camera access to services started from the foreground).
        GestureService.sync(this)
    }

    private fun requestPerm(permission: String, code: Int) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
            checkSelfPermission(permission) != PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(permission), code)
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        GestureService.sync(this)
    }

    private fun granted(permission: String): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.M ||
            checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED

    private fun status(): Map<String, Any> {
        val m = HashMap<String, Any>(Prefs.toMap(this))
        val svc = ScrollAccessibilityService.instance
        m["serviceEnabled"] = svc != null
        m["paused"] = svc?.paused ?: false
        val gestureStatus = GestureService.status
        m["lastEvent"] = if (svc == null) {
            "Accessibility service is off"
        } else if (Prefs.gestureMode(this) != "off" && gestureStatus.isNotEmpty()) {
            "${ScrollAccessibilityService.lastEvent}\nGesture: $gestureStatus"
        } else {
            ScrollAccessibilityService.lastEvent
        }
        m["gestureRunning"] = GestureService.running
        m["cameraGranted"] = granted(Manifest.permission.CAMERA)
        m["notificationsGranted"] =
            Build.VERSION.SDK_INT < 33 || granted(Manifest.permission.POST_NOTIFICATIONS)
        return m
    }
}
