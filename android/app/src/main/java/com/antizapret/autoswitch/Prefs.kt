package com.antizapret.autoswitch

import android.content.Context
import android.content.SharedPreferences

/**
 * Вся настройка watcher'а — простые SharedPreferences, без БД/DataStore,
 * чтобы не тащить лишние зависимости в первую версию.
 */
class Prefs(context: Context) {

    private val sp: SharedPreferences =
        context.getSharedPreferences("az_autoswitch", Context.MODE_PRIVATE)

    /** Имена туннелей в WG Tunnel, в порядке приоритета — по одному на строку. */
    var tunnelNamesRaw: String
        get() = sp.getString(KEY_TUNNELS, "") ?: ""
        set(value) = sp.edit().putString(KEY_TUNNELS, value).apply()

    fun tunnelNames(): List<String> =
        tunnelNamesRaw.lines().map { it.trim() }.filter { it.isNotEmpty() }

    /** Remote Control key, заданный в самом WG Tunnel (Settings -> Remote Control). */
    var remoteKey: String
        get() = sp.getString(KEY_REMOTE_KEY, "") ?: ""
        set(value) = sp.edit().putString(KEY_REMOTE_KEY, value).apply()

    /** Адрес, который пингуем СКВОЗЬ активный туннель (не сам VPN-сервер — на него ICMP отключен). */
    var healthCheckUrl: String
        get() = sp.getString(KEY_HEALTH_URL, DEFAULT_HEALTH_URL) ?: DEFAULT_HEALTH_URL
        set(value) = sp.edit().putString(KEY_HEALTH_URL, value).apply()

    var intervalSeconds: Int
        get() = sp.getInt(KEY_INTERVAL, DEFAULT_INTERVAL_S)
        set(value) = sp.edit().putInt(KEY_INTERVAL, value).apply()

    var timeoutSeconds: Int
        get() = sp.getInt(KEY_TIMEOUT, DEFAULT_TIMEOUT_S)
        set(value) = sp.edit().putInt(KEY_TIMEOUT, value).apply()

    /** Сколько подряд неудачных проверок означает "сервер лёг". */
    var downThreshold: Int
        get() = sp.getInt(KEY_DOWN_THRESHOLD, DEFAULT_DOWN_THRESHOLD)
        set(value) = sp.edit().putInt(KEY_DOWN_THRESHOLD, value).apply()

    var autoStartOnBoot: Boolean
        get() = sp.getBoolean(KEY_AUTOSTART, false)
        set(value) = sp.edit().putBoolean(KEY_AUTOSTART, value).apply()

    /** Индекс текущего активного туннеля в tunnelNames() — для циклического переключения. */
    var currentTunnelIndex: Int
        get() = sp.getInt(KEY_CURRENT_INDEX, 0)
        set(value) = sp.edit().putInt(KEY_CURRENT_INDEX, value).apply()

    companion object {
        private const val KEY_TUNNELS = "tunnel_names"
        private const val KEY_REMOTE_KEY = "remote_key"
        private const val KEY_HEALTH_URL = "health_url"
        private const val KEY_INTERVAL = "interval_s"
        private const val KEY_TIMEOUT = "timeout_s"
        private const val KEY_DOWN_THRESHOLD = "down_threshold"
        private const val KEY_AUTOSTART = "autostart_boot"
        private const val KEY_CURRENT_INDEX = "current_tunnel_index"

        const val DEFAULT_HEALTH_URL = "https://www.gstatic.com/generate_204"
        const val DEFAULT_INTERVAL_S = 15
        const val DEFAULT_TIMEOUT_S = 5
        const val DEFAULT_DOWN_THRESHOLD = 3
    }
}
