package com.aquamoon.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import android.os.Bundle
import com.aquamoon.app.notification.CustomNotificationActionReceiver
import com.aquamoon.app.notification.CustomNotificationManager
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    private var customNotificationManager: CustomNotificationManager? = null
    private var methodChannel: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createNotificationChannels()
        customNotificationManager = CustomNotificationManager(this)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.aquamoon.app/custom_notification")
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "update" -> {
                    val title = call.argument<String>("title") ?: "水月音"
                    val artist = call.argument<String>("artist") ?: "禅意音乐"
                    val albumArtPath = call.argument<String>("albumArtUri")
                    val isPlaying = call.argument<Boolean>("isPlaying") ?: false
                    val positionMs = (call.argument<Number>("positionMs"))?.toLong() ?: 0L
                    val durationMs = (call.argument<Number>("durationMs"))?.toLong() ?: 0L
                    customNotificationManager?.showOrUpdate(title, artist, albumArtPath, isPlaying, positionMs, durationMs)
                    result.success(true)
                }
                "cancel" -> {
                    customNotificationManager?.cancel()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        CustomNotificationActionReceiver.onActionListener = { action ->
            runOnUiThread {
                when (action) {
                    CustomNotificationActionReceiver.ACTION_PLAY_PAUSE -> methodChannel?.invokeMethod("onPlayPause", null)
                    CustomNotificationActionReceiver.ACTION_PREV -> methodChannel?.invokeMethod("onPrev", null)
                    CustomNotificationActionReceiver.ACTION_NEXT -> methodChannel?.invokeMethod("onNext", null)
                    CustomNotificationActionReceiver.ACTION_CLOSE -> methodChannel?.invokeMethod("onClose", null)
                }
            }
        }
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

            // 彻底清理旧的低优先级渠道
            notificationManager.deleteNotificationChannel("com.aquamoon.app.channel.audio")

            // 创建原生播放渠道
            val channelId = "com.aquamoon.app.channel.playback"
            val channelName = "播放控制"
            val channelDescription = "音乐后台播放控制、锁屏与通知栏操作"
            val importance = NotificationManager.IMPORTANCE_HIGH

            val channel = NotificationChannel(channelId, channelName, importance).apply {
                description = channelDescription
                setShowBadge(false)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                setSound(null, null)
                enableVibration(false)
            }

            notificationManager.createNotificationChannel(channel)
        }
    }
}
