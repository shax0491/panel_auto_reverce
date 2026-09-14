package com.antizapret.autoswitch

import java.net.HttpURLConnection
import java.net.URL

/**
 * Проверка "интернет реально работает через текущий туннель прямо сейчас".
 *
 * Намеренно НЕ пингуем сам VPN-сервер (ICMP на серверах отключен в конфиге —
 * см. README) и не лезем во внутренности WG Tunnel за состоянием хендшейка —
 * как только его VPN-туннель активен, весь трафик приложения (в том числе этот
 * запрос) идёт через него по умолчанию (стандартное поведение Android
 * VpnService). Так что простой HTTP-запрос к надёжному внешнему адресу —
 * честная проверка сквозь весь стек, а не только "интерфейс поднят".
 */
object HealthChecker {

    fun isHealthy(url: String, timeoutSeconds: Int): Boolean {
        var connection: HttpURLConnection? = null
        return try {
            connection = (URL(url).openConnection() as HttpURLConnection).apply {
                connectTimeout = timeoutSeconds * 1000
                readTimeout = timeoutSeconds * 1000
                requestMethod = "HEAD"
                instanceFollowRedirects = true
            }
            val code = connection.responseCode
            // 2xx/3xx — считаем сеть живой; 204 (generate_204) — штатный успешный ответ.
            code in 200..399
        } catch (_: Exception) {
            false
        } finally {
            connection?.disconnect()
        }
    }
}
