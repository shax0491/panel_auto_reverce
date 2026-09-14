package com.antizapret.autoswitch

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import com.antizapret.autoswitch.databinding.ActivityMainBinding

class MainActivity : AppCompatActivity() {

    private lateinit var binding: ActivityMainBinding
    private lateinit var prefs: Prefs

    private val notificationPermissionLauncher =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
            if (granted) startService() else
                binding.textStatus.text = "Без разрешения на уведомления сервис всё равно запустится, но статус не будет виден в шторке."
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)
        prefs = Prefs(this)

        loadFromPrefs()

        binding.buttonStart.setOnClickListener {
            saveToPrefs()
            ensureNotificationPermissionThenStart()
        }
        binding.buttonStop.setOnClickListener {
            AutoSwitchService.stop(this)
            binding.textStatus.text = "Остановлено"
        }
    }

    private fun loadFromPrefs() {
        binding.editTunnelNames.setText(prefs.tunnelNamesRaw)
        binding.editRemoteKey.setText(prefs.remoteKey)
        binding.editHealthUrl.setText(prefs.healthCheckUrl)
        binding.editInterval.setText(prefs.intervalSeconds.toString())
        binding.editDownThreshold.setText(prefs.downThreshold.toString())
        binding.checkAutostart.isChecked = prefs.autoStartOnBoot
    }

    private fun saveToPrefs() {
        prefs.tunnelNamesRaw = binding.editTunnelNames.text.toString()
        prefs.remoteKey = binding.editRemoteKey.text.toString().trim()
        prefs.healthCheckUrl = binding.editHealthUrl.text.toString().trim().ifBlank { Prefs.DEFAULT_HEALTH_URL }
        prefs.intervalSeconds = binding.editInterval.text.toString().toIntOrNull() ?: Prefs.DEFAULT_INTERVAL_S
        prefs.downThreshold = binding.editDownThreshold.text.toString().toIntOrNull() ?: Prefs.DEFAULT_DOWN_THRESHOLD
        prefs.autoStartOnBoot = binding.checkAutostart.isChecked
    }

    private fun ensureNotificationPermissionThenStart() {
        if (prefs.tunnelNames().size < 2) {
            binding.textStatus.text = "Нужно минимум 2 туннеля (основной + резервный), по одному имени на строку"
            return
        }
        if (prefs.remoteKey.isBlank()) {
            binding.textStatus.text = "Укажите Remote Control key — тот же, что задан в WG Tunnel"
            return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS)
            != PackageManager.PERMISSION_GRANTED
        ) {
            notificationPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
            return
        }
        startService()
    }

    private fun startService() {
        AutoSwitchService.start(this)
        binding.textStatus.text = "Запущено — статус смотрите в уведомлении"
    }
}
