package com.antizapret.autoswitch

import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Отправка команд приложению WG Tunnel (github.com/wgtunnel/android) через его
 * RemoteControlReceiver — единственный на сегодня Android WireGuard/AmneziaWG-клиент
 * с рабочим внешним API для переключения туннелей (официальный клиент проекта,
 * "AmneziaWG", больше не поддерживается и такого API не имеет вовсе).
 *
 * Точные action/extra-строки взяты из исходников WG Tunnel
 * (core/broadcast/RemoteControlReceiver.kt, util/Constants.kt) — не из документации,
 * которой на момент написания не было. Если WG Tunnel обновит эту часть API, это
 * первое место, которое нужно поверить.
 *
 * Важно: в самом WG Tunnel нужно один раз включить Settings -> Remote Control и
 * задать там ключ (Remote Control Key) — тот же ключ вписывается в настройки
 * этого приложения (Prefs.remoteKey). Без совпадения ключей WG Tunnel команду
 * молча проигнорирует (защита от чужих приложений).
 */
object WgTunnelController {

    private const val TAG = "WgTunnelController"
    const val WG_TUNNEL_PACKAGE = "com.zaneschepke.wireguardautotunnel"

    // Полное имя класса — адресуем broadcast явно на него (не полагаемся на то, что в
    // манифесте WG Tunnel обязательно объявлен <intent-filter> с этими action для implicit
    // доставки; explicit-таргетинг по компоненту работает независимо от этого).
    private const val RECEIVER_CLASS =
        "com.zaneschepke.wireguardautotunnel.core.broadcast.RemoteControlReceiver"
    private const val BASE_ACTION = WG_TUNNEL_PACKAGE
    private const val EXTRA_TUNNEL_NAME = "tunnelName"
    private const val EXTRA_KEY = "key"

    fun startTunnel(context: Context, tunnelName: String, remoteKey: String) {
        send(context, "$BASE_ACTION.START_TUNNEL", tunnelName, remoteKey)
    }

    fun stopTunnel(context: Context, tunnelName: String?, remoteKey: String) {
        send(context, "$BASE_ACTION.STOP_TUNNEL", tunnelName, remoteKey)
    }

    private fun send(context: Context, action: String, tunnelName: String?, remoteKey: String) {
        if (remoteKey.isBlank()) {
            Log.w(TAG, "Remote Control key не задан — команда не отправлена")
            return
        }
        val intent = Intent(action).apply {
            setClassName(WG_TUNNEL_PACKAGE, RECEIVER_CLASS)
            if (tunnelName != null) putExtra(EXTRA_TUNNEL_NAME, tunnelName)
            putExtra(EXTRA_KEY, remoteKey)
        }
        Log.i(TAG, "-> $action tunnelName=$tunnelName")
        context.sendBroadcast(intent)
    }
}
