package com.example.flutter_screen_record

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Intent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.IntentFilter
import android.os.Build
import android.provider.Settings
import android.app.Activity

class MainActivity: FlutterActivity() {
    private val NOTIF_ID = 1001
    private val NOTIF_CHANNEL_ID = "screen_record_controls"
    private val CHANNEL = "floating_button_channel"
    private var flutterMethodChannel: MethodChannel? = null
    private val floatingButtonReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            when (intent?.action) {
                "com.example.flutter_screen_record.ACTION_START_RECORD" -> {
                    flutterMethodChannel?.invokeMethod("onFloatingButtonStart", null)
                }
                "com.example.flutter_screen_record.ACTION_STOP_RECORD" -> {
                    flutterMethodChannel?.invokeMethod("onFloatingButtonStop", null)
                }
                "com.example.flutter_screen_record.ACTION_SCREENSHOT" -> {
                    flutterMethodChannel?.invokeMethod("onFloatingButtonScreenshot", null)
                }
                // For backward compatibility
                "com.example.flutter_screen_record.ACTION_FLOATING_BUTTON" -> {
                    flutterMethodChannel?.invokeMethod("onFloatingButtonPressed", null)
                }
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Register the engine in the cache for NotificationActionReceiver
        io.flutter.embedding.engine.FlutterEngineCache.getInstance().put("main_engine", flutterEngine)
        flutterMethodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        flutterMethodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "showFloatingButton" -> {
                    val intent = Intent(this, FloatingButtonService::class.java)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(intent)
                    } else {
                        startService(intent)
                    }
                    result.success(null)
                }
                "hideFloatingButton" -> {
                    val intent = Intent(this, FloatingButtonService::class.java)
                    stopService(intent)
                    result.success(null)
                }
                "showNotificationBar" -> {
                    showNotificationBar()
                    result.success(null)
                }
                "hideNotificationBar" -> {
                    hideNotificationBar()
                    result.success(null)
                }
                "checkOverlayPermission" -> {
                    val granted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        Settings.canDrawOverlays(this)
                    } else {
                        true
                    }
                    result.success(granted)
                }
                "requestOverlayPermission" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        val intent = Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION)
                        intent.data = android.net.Uri.parse("package:" + packageName)
                        startActivity(intent)
                    }
                    result.success(null)
                }
                "scanFile" -> {
                    val path = call.argument<String>("path")
                    val mimeType = call.argument<String>("mimeType")
                    if (path != null && mimeType != null) {
                        android.media.MediaScannerConnection.scanFile(
                            this,
                            arrayOf(path),
                            arrayOf(mimeType),
                            null
                        )
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        // Register broadcast receiver for all floating button actions
        val filter = IntentFilter().apply {
            addAction("com.example.flutter_screen_record.ACTION_START_RECORD")
            addAction("com.example.flutter_screen_record.ACTION_STOP_RECORD")
            addAction("com.example.flutter_screen_record.ACTION_SCREENSHOT")
            addAction("com.example.flutter_screen_record.ACTION_FLOATING_BUTTON")
        }
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(floatingButtonReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(floatingButtonReceiver, filter)
        }
    }

    private fun showNotificationBar() {
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = android.app.NotificationChannel(
                NOTIF_CHANNEL_ID,
                "Screen Record Controls",
                android.app.NotificationManager.IMPORTANCE_LOW
            )
            notificationManager.createNotificationChannel(channel)
        }

        val startIntent = Intent("com.example.flutter_screen_record.ACTION_NOTIFICATION_START")
        val stopIntent = Intent("com.example.flutter_screen_record.ACTION_NOTIFICATION_STOP")
        val screenshotIntent = Intent("com.example.flutter_screen_record.ACTION_NOTIFICATION_SCREENSHOT")

        val startPendingIntent = android.app.PendingIntent.getBroadcast(this, 10, startIntent, android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE)
        val stopPendingIntent = android.app.PendingIntent.getBroadcast(this, 11, stopIntent, android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE)
        val screenshotPendingIntent = android.app.PendingIntent.getBroadcast(this, 12, screenshotIntent, android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE)

        val builder = androidx.core.app.NotificationCompat.Builder(this, NOTIF_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setContentTitle("Screen Recorder")
            .setContentText("Control recording and screenshots")
            .addAction(android.R.drawable.ic_media_play, "Start", startPendingIntent)
            .addAction(android.R.drawable.ic_media_pause, "Stop", stopPendingIntent)
            .addAction(android.R.drawable.ic_menu_camera, "Screenshot", screenshotPendingIntent)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setPriority(androidx.core.app.NotificationCompat.PRIORITY_LOW)

        notificationManager.notify(NOTIF_ID, builder.build())
    }

    private fun hideNotificationBar() {
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager
        notificationManager.cancel(NOTIF_ID)
    }

    override fun onDestroy() {
        super.onDestroy()
        unregisterReceiver(floatingButtonReceiver)
    }
}
