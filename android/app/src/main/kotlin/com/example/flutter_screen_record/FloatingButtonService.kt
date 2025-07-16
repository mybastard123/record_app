package com.example.flutter_screen_record

import android.app.Service
import android.content.Intent
import android.graphics.PixelFormat
import android.os.IBinder
import android.view.Gravity
import android.view.LayoutInflater
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.ImageView
import android.widget.Toast
import com.example.flutter_screen_record.R

class FloatingButtonService : Service() {
    private var windowManager: WindowManager? = null
    private var floatingView: View? = null
    private var layoutParams: WindowManager.LayoutParams? = null
    private var lastTouchDown: Long = 0
    private var initialX: Int = 0
    private var initialY: Int = 0
    private var initialTouchX: Float = 0f
    private var initialTouchY: Float = 0f

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        // Check SYSTEM_ALERT_WINDOW permission before adding overlay
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
            if (!android.provider.Settings.canDrawOverlays(this)) {
                Toast.makeText(this, "Overlay permission not granted", Toast.LENGTH_LONG).show()
                stopSelf()
                return
            }
        }
        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
        addFloatingButton()
        // Start as foreground service with notification for Android O+
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            val channelId = "floating_button_service"
            val channelName = "Floating Button Service"
            val notificationManager = getSystemService(android.content.Context.NOTIFICATION_SERVICE) as android.app.NotificationManager
            val channel = android.app.NotificationChannel(channelId, channelName, android.app.NotificationManager.IMPORTANCE_LOW)
            notificationManager.createNotificationChannel(channel)
            val notification = androidx.core.app.NotificationCompat.Builder(this, channelId)
                .setContentTitle("Screen Recorder Floating Button")
                .setContentText("Floating controls are active")
                .setSmallIcon(android.R.drawable.ic_menu_camera)
                .setOngoing(true)
                .build()
            if (android.os.Build.VERSION.SDK_INT >= 34) {
                // 0x40000000 is FOREGROUND_SERVICE_TYPE_SPECIAL_USE for overlays
                startForeground(2001, notification, 0x40000000)
            } else {
                startForeground(2001, notification)
            }
        }
    }

    private fun isClick(event: MotionEvent): Boolean {
        val timeDiff = event.eventTime - lastTouchDown
        val touchSlop = 20 // pixels
        val moved = Math.abs(event.rawX - initialTouchX) > touchSlop || 
                   Math.abs(event.rawY - initialTouchY) > touchSlop
        return timeDiff < 200 && !moved // Less than 200ms and hasn't moved much
    }

    private fun handleButtonClick(event: MotionEvent) {
        if (!isClick(event)) return

        floatingView?.let { view ->
            val btnStart = view.findViewById<ImageView>(R.id.btn_start)
            val btnStop = view.findViewById<ImageView>(R.id.btn_stop)
            val btnScreenshot = view.findViewById<ImageView>(R.id.btn_screenshot)

            val x = event.rawX
            val y = event.rawY

            // Check which button was clicked
            when {
                isViewClicked(btnStart, x, y) -> {
                    val intent = Intent("com.example.flutter_screen_record.ACTION_START_RECORD")
                    sendBroadcast(intent)
                }
                isViewClicked(btnStop, x, y) -> {
                    val intent = Intent("com.example.flutter_screen_record.ACTION_STOP_RECORD")
                    sendBroadcast(intent)
                }
                isViewClicked(btnScreenshot, x, y) -> {
                    val intent = Intent("com.example.flutter_screen_record.ACTION_SCREENSHOT")
                    sendBroadcast(intent)
                }
            }
        }
    }

    private fun isViewClicked(view: View?, x: Float, y: Float): Boolean {
        if (view == null) return false
        val location = IntArray(2)
        view.getLocationOnScreen(location)
        val viewX = location[0]
        val viewY = location[1]
        return (x >= viewX && x <= viewX + view.width &&
                y >= viewY && y <= viewY + view.height)
    }

    private fun addFloatingButton() {
        val inflater = LayoutInflater.from(this)
        floatingView = inflater.inflate(R.layout.layout_floating_button, null)

        layoutParams = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = 100
            y = 300
        }

        windowManager?.addView(floatingView, layoutParams)

        floatingView?.setOnTouchListener { _, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    lastTouchDown = event.eventTime
                    initialX = layoutParams?.x ?: 0
                    initialY = layoutParams?.y ?: 0
                    initialTouchX = event.rawX
                    initialTouchY = event.rawY
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    layoutParams?.x = initialX + (event.rawX - initialTouchX).toInt()
                    layoutParams?.y = initialY + (event.rawY - initialTouchY).toInt()
                    windowManager?.updateViewLayout(floatingView, layoutParams)
                    true
                }
                MotionEvent.ACTION_UP -> {
                    handleButtonClick(event)
                    true
                }
                else -> false
            }
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        windowManager?.removeView(floatingView)
    }
}
