package com.deliveryapp.delivery_app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createOrderUpdatesChannel()
    }

    // Android 8+ shows notifications only on a channel. FCM delivers order
    // pushes on this one (see the default_notification_channel_id
    // meta-data in AndroidManifest.xml); its user-visible name is
    // localized via res/values*/strings.xml. Recreating an existing channel
    // is a no-op, so this is safe on every launch.
    private fun createOrderUpdatesChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            ORDER_UPDATES_CHANNEL_ID,
            getString(R.string.order_updates_channel_name),
            NotificationManager.IMPORTANCE_HIGH,
        )
        getSystemService(NotificationManager::class.java)?.createNotificationChannel(channel)
    }

    companion object {
        const val ORDER_UPDATES_CHANNEL_ID = "order_updates"
    }
}
