package com.example.felpz_xit

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

object PanelShortcutNotification {
    private const val CHANNEL_ID = "felpz_xit_panel_shortcut"
    private const val NOTIFICATION_ID = 7412

    fun show(context: Context) {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "Atalho do painel",
                    NotificationManager.IMPORTANCE_LOW
                ).apply {
                    description = "Atalho para reabrir o painel do Felpz Xit durante o jogo."
                    setShowBadge(false)
                }
            )
        }

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }

        builder
            .setSmallIcon(android.R.drawable.ic_menu_view)
            .setContentTitle("Felpz Xit — atalho ativo")
            .setContentText("Use Abrir painel para voltar ao painel sem sair do jogo.")
            .setVisibility(Notification.VISIBILITY_PRIVATE)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .addAction(
                android.R.drawable.ic_menu_view,
                "Abrir painel",
                actionPendingIntent(context, ShortcutActionReceiver.ACTION_OPEN, 7413)
            )
            .addAction(
                android.R.drawable.ic_menu_close_clear_cancel,
                "Fechar painel",
                actionPendingIntent(context, ShortcutActionReceiver.ACTION_CLOSE, 7414)
            )
            .addAction(
                android.R.drawable.ic_delete,
                "Desativar atalho",
                actionPendingIntent(context, ShortcutActionReceiver.ACTION_DISABLE, 7415)
            )

        try {
            manager.notify(NOTIFICATION_ID, builder.build())
        } catch (_: SecurityException) {
            // Notifications may be denied by the user on Android 13+.
        }
    }

    fun hide(context: Context) {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.cancel(NOTIFICATION_ID)
    }

    private fun actionPendingIntent(context: Context, action: String, requestCode: Int): PendingIntent {
        val intent = Intent(context, ShortcutActionReceiver::class.java).setAction(action)
        return PendingIntent.getBroadcast(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }
}

class ShortcutActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        when (intent?.action) {
            ACTION_OPEN -> MainActivity.dispatchShortcutAction("openPanel")
            ACTION_CLOSE -> MainActivity.dispatchShortcutAction("closePanel")
            ACTION_DISABLE -> {
                PanelShortcutNotification.hide(context)
                MainActivity.dispatchShortcutAction("disableShortcut")
            }
        }
    }

    companion object {
        const val ACTION_OPEN = "com.example.felpz_xit.action.OPEN_PANEL"
        const val ACTION_CLOSE = "com.example.felpz_xit.action.CLOSE_PANEL"
        const val ACTION_DISABLE = "com.example.felpz_xit.action.DISABLE_SHORTCUT"
    }
}
