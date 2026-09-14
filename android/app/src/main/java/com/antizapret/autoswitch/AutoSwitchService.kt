package com.antizapret.autoswitch

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.lifecycle.LifecycleService
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Основной watcher: раз в Prefs.intervalSeconds проверяет здоровье текущего
 * туннеля (HealthChecker) и, если он "упал" downThreshold проверок подряд,
 * переключает WG Tunnel на следующий по приоритету туннель из списка
 * (Prefs.tunnelNames(), циклически).
 *
 * Гистерезис: после переключения счётчик неудач обнуляется и даётся
 * downThreshold "успешных попыток на удачу" новому туннелю прежде, чем на
 * него самого начнут засчитываться неудачи — простыми словами, сразу после
 * смены сервера не долбим его повторным переключением при первой же
 * заминке, даём разумное время на установление хендшейка.
 */
class AutoSwitchService : LifecycleService() {

    private var loopJob: Job? = null
    private lateinit var prefs: Prefs

    override fun onCreate() {
        super.onCreate()
        prefs = Prefs(this)
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        super.onStartCommand(intent, flags, startId)
        startForeground(NOTIFICATION_ID, buildNotification("Запущено", "Ожидание первой проверки…"))
        startLoop()
        return START_STICKY
    }

    private fun startLoop() {
        if (loopJob?.isActive == true) return
        loopJob = lifecycleScope.launch {
            var consecutiveFailures = 0
            var settleAfterSwitch = 0

            while (isActive) {
                val tunnels = prefs.tunnelNames()
                if (tunnels.isEmpty()) {
                    updateNotification("Не настроено", "Добавьте туннели в настройках приложения")
                    delay(prefs.intervalSeconds * 1000L)
                    continue
                }

                val currentIndex = prefs.currentTunnelIndex.coerceIn(0, tunnels.lastIndex)
                val currentName = tunnels[currentIndex]

                val healthy = withContext(Dispatchers.IO) {
                    HealthChecker.isHealthy(prefs.healthCheckUrl, prefs.timeoutSeconds)
                }

                if (healthy) {
                    consecutiveFailures = 0
                    if (settleAfterSwitch > 0) settleAfterSwitch--
                    updateNotification("Всё в порядке", "Активен: $currentName")
                } else if (settleAfterSwitch > 0) {
                    // Только что переключились — даём новому туннелю время на хендшейк,
                    // не считаем эти проверки как повод переключаться снова.
                    updateNotification("Устанавливается: $currentName", "Ожидание хендшейка…")
                } else {
                    consecutiveFailures++
                    updateNotification(
                        "Нет связи ($consecutiveFailures/${prefs.downThreshold}): $currentName",
                        "Проверка через ${prefs.intervalSeconds} с",
                    )
                    if (consecutiveFailures >= prefs.downThreshold) {
                        val nextIndex = (currentIndex + 1) % tunnels.size
                        val nextName = tunnels[nextIndex]
                        WgTunnelController.startTunnel(this@AutoSwitchService, nextName, prefs.remoteKey)
                        prefs.currentTunnelIndex = nextIndex
                        consecutiveFailures = 0
                        settleAfterSwitch = prefs.downThreshold
                        updateNotification("Переключение -> $nextName", "$currentName не отвечает")
                    }
                }

                delay(prefs.intervalSeconds * 1000L)
            }
        }
    }

    override fun onDestroy() {
        loopJob?.cancel()
        super.onDestroy()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(
            CHANNEL_ID,
            "AZ AutoSwitch",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Статус автопереключения VPN-сервера"
        }
        manager.createNotificationChannel(channel)
    }

    private fun buildNotification(title: String, text: String): Notification {
        val openApp = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE,
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(android.R.drawable.ic_menu_compass)
            .setContentIntent(openApp)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .build()
    }

    private fun updateNotification(title: String, text: String) {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(NOTIFICATION_ID, buildNotification(title, text))
    }

    companion object {
        private const val CHANNEL_ID = "az_autoswitch_status"
        private const val NOTIFICATION_ID = 1

        fun start(context: Context) {
            context.startForegroundService(Intent(context, AutoSwitchService::class.java))
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, AutoSwitchService::class.java))
        }
    }
}
