package com.iconformatter.icon_formatter

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

/**
 * Foreground service (dataSync) that keeps a batch alive in the background and
 * shows an ongoing "Processing icons n/m" notification. Started, updated and
 * stopped from Dart through MainActivity; stop is safe at any time.
 */
class ProcessingService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            running = false
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return START_NOT_STICKY
        }
        running = true
        val n = notification(this, 0, intent?.getIntExtra(EXTRA_TOTAL, 0) ?: 0)
        if (Build.VERSION.SDK_INT >= 29) {
            startForeground(NOTIF_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        } else {
            startForeground(NOTIF_ID, n)
        }
        return START_NOT_STICKY
    }

    // Android 15 caps dataSync services per day: stop cleanly instead of being killed.
    override fun onTimeout(startId: Int, fgsType: Int) {
        running = false
        stopSelf()
    }

    override fun onDestroy() {
        running = false
        super.onDestroy()
    }

    companion object {
        private const val NOTIF_ID = 5104
        private const val CHANNEL = "processing"
        private const val ACTION_STOP = "com.iconformatter.icon_formatter.PROCESSING_STOP"
        private const val EXTRA_TOTAL = "total"
        @Volatile private var running = false

        /** False when Android refuses the foreground start (for example the app is in the background). */
        fun start(c: Context, total: Int): Boolean {
            return try {
                running = true
                c.startForegroundService(Intent(c, ProcessingService::class.java).putExtra(EXTRA_TOTAL, total))
                true
            } catch (_: Exception) {
                running = false
                false
            }
        }

        /** Refreshes the ongoing notification; nothing happens when the service is not running. */
        fun update(c: Context, done: Int, total: Int) {
            if (!running) return
            c.getSystemService(NotificationManager::class.java).notify(NOTIF_ID, notification(c, done, total))
        }

        /** Stops the service. Safe when it is not running. */
        fun stop(c: Context) {
            running = false
            try {
                c.startService(Intent(c, ProcessingService::class.java).setAction(ACTION_STOP))
            } catch (_: Exception) {
                // not running and the system refuses a background start: nothing to stop
            }
        }

        private fun notification(c: Context, done: Int, total: Int): Notification {
            val b = if (Build.VERSION.SDK_INT >= 26) {
                c.getSystemService(NotificationManager::class.java).createNotificationChannel(
                    NotificationChannel(CHANNEL, AppText.get(c, R.string.processing_channel), NotificationManager.IMPORTANCE_LOW),
                )
                Notification.Builder(c, CHANNEL)
            } else {
                @Suppress("DEPRECATION") Notification.Builder(c)
            }
            return b.setSmallIcon(R.mipmap.ic_launcher_foreground)
                .setContentTitle(AppText.get(c, R.string.processing_title, done, total))
                .setProgress(total, done, total <= 0)
                .setOngoing(true)
                .build()
        }
    }
}
