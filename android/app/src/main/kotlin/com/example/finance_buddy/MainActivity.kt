package com.example.finance_buddy

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.ComponentName
import android.content.Intent
import android.provider.Settings

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "finance_buddy/notifications")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "enabled" -> {
                        val listeners = Settings.Secure.getString(contentResolver, "enabled_notification_listeners") ?: ""
                        val component = ComponentName(this, TransactionNotificationListener::class.java)
                        val granted = listeners.split(':').any { ComponentName.unflattenFromString(it) == component }
                        result.success(granted && NotificationQueue.enabled(this))
                    }
                    "setEnabled" -> {
                        val enabled = call.arguments as? Boolean ?: false
                        getSharedPreferences("transaction_alerts", MODE_PRIVATE).edit().putBoolean("enabled", enabled).commit()
                        if (enabled) startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
                        result.success(null)
                    }
                    "pending" -> result.success(NotificationQueue.pending(this))
                    "acknowledge" -> {
                        NotificationQueue.acknowledge(this, call.arguments as String)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
    override fun onResume() {
        super.onResume()
        TransactionNotificationListener.foreground = true
    }
    override fun onPause() {
        TransactionNotificationListener.foreground = false
        super.onPause()
    }
}
