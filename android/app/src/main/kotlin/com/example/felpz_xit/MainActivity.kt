package com.example.felpz_xit

import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.database.ContentObserver
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.Settings
import android.widget.Toast
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var comboReceiver: BroadcastReceiver? = null
    private var rotationObserver: ContentObserver? = null
    private var wasDndEnabled = false
    private var wasAutoRotateEnabled = false
    private var dndEnabledAt = 0L
    private var autoRotateEnabledAt = 0L
    private var comboNotificationShown = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SHORTCUT_CHANNEL
        )
        shortcutChannel = channel
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "showShortcutNotification" -> {
                    PanelShortcutNotification.show(this)
                    result.success(true)
                }
                "hideShortcutNotification" -> {
                    PanelShortcutNotification.hide(this)
                    result.success(true)
                }
                "configureComboTrigger" -> {
                    if (hasDndAccess()) {
                        startComboMonitoring()
                        result.success(true)
                    } else {
                        try {
                            startActivity(Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS))
                            result.success(false)
                        } catch (e: Exception) {
                            result.error("settings_unavailable", "Não foi possível abrir as configurações de Não Perturbe.", null)
                        }
                    }
                }
                "hasComboTriggerAccess" -> result.success(hasDndAccess())
                else -> result.notImplemented()
            }
        }
    }

    override fun onResume() {
        super.onResume()
        if (hasDndAccess()) startComboMonitoring()
    }

    override fun onDestroy() {
        stopComboMonitoring()
        super.onDestroy()
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        shortcutChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    private fun hasDndAccess(): Boolean {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            manager.isNotificationPolicyAccessGranted
        } else true
    }

    private fun startComboMonitoring() {
        if (comboReceiver != null || !hasDndAccess()) return

        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        wasDndEnabled = isDndEnabled(manager)
        wasAutoRotateEnabled = isAutoRotateEnabled()
        // An option already enabled can count as the first half, but we do not
        // trigger just because both options were already enabled at startup.
        val initialNow = SystemClock.elapsedRealtime()
        dndEnabledAt = if (wasDndEnabled) initialNow else 0L
        autoRotateEnabledAt = if (wasAutoRotateEnabled) initialNow else 0L
        comboNotificationShown = false
        if (!wasDndEnabled || !wasAutoRotateEnabled) {
            PanelShortcutNotification.hide(this)
        }

        comboReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                val current = isDndEnabled(manager)
                if (current != wasDndEnabled) {
                    wasDndEnabled = current
                    dndEnabledAt = if (current) SystemClock.elapsedRealtime() else 0L
                    evaluateCombo()
                }
            }
        }
        val filter = IntentFilter(NotificationManager.ACTION_INTERRUPTION_FILTER_CHANGED)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(comboReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("DEPRECATION")
            registerReceiver(comboReceiver, filter)
        }

        rotationObserver = object : ContentObserver(Handler(Looper.getMainLooper())) {
            override fun onChange(selfChange: Boolean, uri: Uri?) {
                val current = isAutoRotateEnabled()
                if (current != wasAutoRotateEnabled) {
                    wasAutoRotateEnabled = current
                    autoRotateEnabledAt = if (current) SystemClock.elapsedRealtime() else 0L
                    evaluateCombo()
                }
            }
        }
        contentResolver.registerContentObserver(
            Settings.System.getUriFor(Settings.System.ACCELEROMETER_ROTATION),
            false,
            rotationObserver!!
        )
    }

    private fun stopComboMonitoring() {
        comboReceiver?.let {
            try { unregisterReceiver(it) } catch (_: IllegalArgumentException) {}
        }
        comboReceiver = null
        rotationObserver?.let { contentResolver.unregisterContentObserver(it) }
        rotationObserver = null
    }

    private fun isDndEnabled(manager: NotificationManager): Boolean {
        return try {
            manager.currentInterruptionFilter != NotificationManager.INTERRUPTION_FILTER_ALL &&
                manager.currentInterruptionFilter != NotificationManager.INTERRUPTION_FILTER_UNKNOWN
        } catch (_: SecurityException) {
            false
        }
    }

    private fun isAutoRotateEnabled(): Boolean {
        return try {
            Settings.System.getInt(
                contentResolver,
                Settings.System.ACCELEROMETER_ROTATION,
                0
            ) == 1
        } catch (_: Exception) {
            false
        }
    }

    private fun evaluateCombo() {
        val bothEnabled = wasDndEnabled && wasAutoRotateEnabled
        val withinWindow = dndEnabledAt > 0L && autoRotateEnabledAt > 0L &&
            kotlin.math.abs(dndEnabledAt - autoRotateEnabledAt) <= COMBO_WINDOW_MS
        if (bothEnabled && withinWindow && !comboNotificationShown) {
            comboNotificationShown = true
            PanelShortcutNotification.show(this)
        } else if (!bothEnabled && comboNotificationShown) {
            comboNotificationShown = false
            PanelShortcutNotification.hide(this)
        }
    }

    companion object {
        private const val SHORTCUT_CHANNEL = "felpz_xit/shortcut"
        private const val COMBO_WINDOW_MS = 2_000L

        @Volatile
        private var shortcutChannel: MethodChannel? = null

        fun dispatchShortcutAction(action: String) {
            Handler(Looper.getMainLooper()).post {
                shortcutChannel?.invokeMethod(action, null)
            }
        }
    }
}
