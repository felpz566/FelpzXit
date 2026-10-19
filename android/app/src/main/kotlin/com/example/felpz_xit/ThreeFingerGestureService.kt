package com.example.felpz_xit

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.os.Build
import android.view.accessibility.AccessibilityEvent

class ThreeFingerGestureService : AccessibilityService() {
    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // Não lê conteúdo de janelas nem coleta eventos de texto.
    }

    override fun onInterrupt() = Unit

    override fun onGesture(gestureId: Int): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return false
        if (gestureId != GESTURE_3_FINGER_DOUBLE_TAP) return false

        val prefs = getSharedPreferences("felpz_xit_gesture", MODE_PRIVATE)
        if (!prefs.getBoolean("authorized", false)) return false

        prefs.edit().putBoolean("pending_gesture", true).apply()
        val intent = Intent(this, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            putExtra("open_overlay_from_gesture", true)
        }
        startActivity(intent)
        return true
    }
}
