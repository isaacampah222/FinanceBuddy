package com.example.finance_buddy

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import org.json.JSONArray
import org.json.JSONObject
import java.security.MessageDigest

/** Durable handoff: Flutter acknowledges only after committing a review to SQLite. */
object NotificationQueue {
    private fun prefs(context: Context) = context.getSharedPreferences("transaction_alerts", Context.MODE_PRIVATE)
    fun enabled(context: Context) = prefs(context).getBoolean("enabled", false)

    @Synchronized fun add(context: Context, item: JSONObject): Boolean {
        val prefs = prefs(context)
        val id = item.getString("id")
        // Keep fingerprints after acknowledgement so notification updates cannot requeue a payment.
        val seen = prefs.getStringSet("seen", emptySet())!!.toMutableSet()
        if (!seen.add(id)) return false
        val queue = JSONArray(prefs.getString("queue", "[]"))
        queue.put(item)
        return prefs.edit().putString("queue", queue.toString()).putStringSet("seen", seen).commit()
    }

    @Synchronized fun pending(context: Context): List<Map<String, Any>> {
        val queue = JSONArray(prefs(context).getString("queue", "[]"))
        return (0 until queue.length()).map { index ->
            val item = queue.getJSONObject(index)
            mapOf("id" to item.getString("id"), "sender" to item.getString("sender"),
                "body" to item.getString("body"), "date" to item.getLong("date"))
        }
    }

    @Synchronized fun acknowledge(context: Context, id: String) {
        val prefs = prefs(context)
        val queue = JSONArray(prefs.getString("queue", "[]"))
        val remaining = JSONArray()
        for (index in 0 until queue.length()) {
            val item = queue.getJSONObject(index)
            if (item.getString("id") != id) remaining.put(item)
        }
        prefs.edit().putString("queue", remaining.toString()).commit()
        if (remaining.length() == 0) context.getSystemService(NotificationManager::class.java).cancel(1001)
    }
}

class TransactionNotificationListener : NotificationListenerService() {
    companion object { @Volatile var foreground = false }
    private val money = Regex("(?i)(?:GHS|GHC|GH₵|USD|EUR|GBP|KES|NGN|UGX|[$€£₵])\\s*[0-9]|[0-9]\\s*(?:GHS|GHC|USD|EUR|GBP|KES|NGN|UGX)")
    private val transaction = Regex("(?i)\\b(?:debited|deducted|spent|purchase[d]?|bought|paid|payment|withdrawn|sent|charged|transferred|credited|received|deposit(?:ed)?|refund(?:ed)?|salary|cashback|reversal)\\b")
    private val excluded = Regex("(?i)\\b(?:otp|verification|failed|declined|pending|unsuccessful|promo|promotion|eligible)\\b")

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        if (sbn.packageName == packageName || !NotificationQueue.enabled(this)) return
        val notification = sbn.notification
        if (notification.flags and Notification.FLAG_GROUP_SUMMARY != 0) return
        val extras = notification.extras
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString().orEmpty()
        val body = (extras.getCharSequence(Notification.EXTRA_BIG_TEXT)
            ?: extras.getCharSequence(Notification.EXTRA_TEXT))?.toString().orEmpty()
        if (body.isBlank() || !money.containsMatchIn(body) || !transaction.containsMatchIn(body) || excluded.containsMatchIn(body)) return
        val digest = MessageDigest.getInstance("SHA-256").digest("${sbn.key}|${notification.`when`}|$title|$body".toByteArray())
        val id = "notification:" + digest.joinToString("") { "%02x".format(it) }
        val item = JSONObject().put("id", id).put("sender", title.ifBlank { sbn.packageName })
            .put("body", body).put("date", sbn.postTime)
        if (!NotificationQueue.add(this, item) || foreground) return
        showPrompt()
    }

    private fun showPrompt() {
        if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) return
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26) manager.createNotificationChannel(NotificationChannel(
            "transaction_review", "Transaction suggestions", NotificationManager.IMPORTANCE_DEFAULT))
        val intent = Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        val pending = PendingIntent.getActivity(this, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, "transaction_review") else Notification.Builder(this)
        manager.notify(1001, builder.setSmallIcon(android.R.drawable.ic_menu_edit)
            .setContentTitle("Review a possible transaction")
            .setContentText("Tap to choose an account and confirm the details.")
            .setVisibility(Notification.VISIBILITY_PRIVATE).setAutoCancel(true).setContentIntent(pending).build())
    }
}
