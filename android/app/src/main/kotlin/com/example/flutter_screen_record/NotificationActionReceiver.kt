package com.example.flutter_screen_record

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import io.flutter.plugin.common.MethodChannel
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.FlutterEngine

class NotificationActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val engine = FlutterEngineCache.getInstance().get("main_engine")
            ?: FlutterEngine(context.applicationContext)
        val channel = MethodChannel(engine.dartExecutor.binaryMessenger, "floating_button_channel")
        when (intent.action) {
            "com.example.flutter_screen_record.ACTION_NOTIFICATION_START" -> channel.invokeMethod("onNotificationStart", null)
            "com.example.flutter_screen_record.ACTION_NOTIFICATION_STOP" -> channel.invokeMethod("onNotificationStop", null)
            "com.example.flutter_screen_record.ACTION_NOTIFICATION_SCREENSHOT" -> channel.invokeMethod("onNotificationScreenshot", null)
        }
    }
}
