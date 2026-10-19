package com.example.felpz_xit

import android.content.Intent
import android.os.Bundle
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var gestureChannel: MethodChannel? = null
    private val channelName = "felpz_xit/gesture"
    private val prefsName = "felpz_xit_gesture"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        gestureChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        gestureChannel?.setMethodCallHandler { call, result ->
            val prefs = getSharedPreferences(prefsName, MODE_PRIVATE)
            when (call.method) {
                "setAuthorized" -> {
                    val authorized = call.arguments as? Boolean ?: false
                    prefs.edit().putBoolean("authorized", authorized).apply()
                    result.success(null)
                }
                "consumePendingGesture" -> {
                    val pending = prefs.getBoolean("pending_gesture", false)
                    prefs.edit().putBoolean("pending_gesture", false).apply()
                    result.success(pending && prefs.getBoolean("authorized", false))
                }
                "openAccessibilitySettings" -> {
                    startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (intent.getBooleanExtra("open_overlay_from_gesture", false)) {
            getSharedPreferences(prefsName, MODE_PRIVATE)
                .edit().putBoolean("pending_gesture", false).apply()
            gestureChannel?.invokeMethod("openOverlay", null)
        }
    }
}
