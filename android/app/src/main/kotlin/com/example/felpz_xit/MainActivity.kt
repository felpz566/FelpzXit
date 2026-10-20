package com.example.felpz_xit

import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
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
                else -> result.notImplemented()
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        shortcutChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    companion object {
        private const val SHORTCUT_CHANNEL = "felpz_xit/shortcut"

        @Volatile
        private var shortcutChannel: MethodChannel? = null

        fun dispatchShortcutAction(action: String) {
            Handler(Looper.getMainLooper()).post {
                shortcutChannel?.invokeMethod(action, null)
            }
        }
    }
}
