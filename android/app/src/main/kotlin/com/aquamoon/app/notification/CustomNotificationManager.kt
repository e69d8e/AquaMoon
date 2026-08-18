package com.aquamoon.app.notification

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.Rect
import android.graphics.RectF
import android.net.Uri
import android.os.Build
import android.widget.RemoteViews
import androidx.core.app.NotificationCompat
import com.aquamoon.app.MainActivity
import com.aquamoon.app.R
import java.io.File
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URL
import kotlin.concurrent.thread

class CustomNotificationManager(private val context: Context) {
    companion object {
        const val CHANNEL_ID = "com.aquamoon.app.channel.custom_player"
        const val CHANNEL_NAME = "水月音播放控制器"
        const val CHANNEL_DESC = "水月音专属自定义通知栏音乐播放控制器"
        const val NOTIFICATION_ID = 2001
    }

    private val notificationManager =
        context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    @Volatile
    private var cachedAlbumArtPath: String? = null
    @Volatile
    private var cachedBitmap: Bitmap? = null

    init {
        createChannel()
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = CHANNEL_DESC
                setShowBadge(false)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                setSound(null, null)
                enableVibration(false)
            }
            notificationManager.createNotificationChannel(channel)
        }
    }

    fun showOrUpdate(
        title: String,
        artist: String,
        albumArtPath: String?,
        isPlaying: Boolean,
        positionMs: Long = 0L,
        durationMs: Long = 0L
    ) {
        val packageName = context.packageName

        // 1. Prepare RemoteViews
        val smallView = RemoteViews(packageName, R.layout.custom_notification_small)
        val bigView = RemoteViews(packageName, R.layout.custom_notification_big)

        // 2. Set Text
        val displayTitle = title.ifEmpty { "水月音" }
        val displayArtist = artist.ifEmpty { "禅意音乐" }

        smallView.setTextViewText(R.id.notif_title, displayTitle)
        smallView.setTextViewText(R.id.notif_artist, displayArtist)

        bigView.setTextViewText(R.id.notif_big_title, displayTitle)
        bigView.setTextViewText(R.id.notif_big_artist, displayArtist)

        // 3. Set Progress & Time for Big View
        val curTimeStr = formatTime(positionMs)
        val totTimeStr = if (durationMs > 0) formatTime(durationMs) else "00:00"
        bigView.setTextViewText(R.id.notif_big_current_time, curTimeStr)
        bigView.setTextViewText(R.id.notif_big_total_time, totTimeStr)

        val progress = if (durationMs > 0) {
            ((positionMs.toDouble() / durationMs.toDouble()) * 1000).toInt().coerceIn(0, 1000)
        } else {
            0
        }
        bigView.setProgressBar(R.id.notif_big_progress, 1000, progress, false)

        // 4. Set Play/Pause Button Icon
        val playPauseIcon = if (isPlaying) R.drawable.ic_notif_pause else R.drawable.ic_notif_play
        smallView.setImageViewResource(R.id.notif_btn_play_pause, playPauseIcon)
        bigView.setImageViewResource(R.id.notif_big_btn_play_pause, playPauseIcon)

        // 5. PendingIntents
        val pendingIntentFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }

        val prevIntent = Intent(context, CustomNotificationActionReceiver::class.java).apply {
            action = CustomNotificationActionReceiver.ACTION_PREV
        }
        val prevPending = PendingIntent.getBroadcast(context, 101, prevIntent, pendingIntentFlags)

        val playPauseIntent = Intent(context, CustomNotificationActionReceiver::class.java).apply {
            action = CustomNotificationActionReceiver.ACTION_PLAY_PAUSE
        }
        val playPausePending = PendingIntent.getBroadcast(context, 102, playPauseIntent, pendingIntentFlags)

        val nextIntent = Intent(context, CustomNotificationActionReceiver::class.java).apply {
            action = CustomNotificationActionReceiver.ACTION_NEXT
        }
        val nextPending = PendingIntent.getBroadcast(context, 103, nextIntent, pendingIntentFlags)

        val closeIntent = Intent(context, CustomNotificationActionReceiver::class.java).apply {
            action = CustomNotificationActionReceiver.ACTION_CLOSE
        }
        val closePending = PendingIntent.getBroadcast(context, 104, closeIntent, pendingIntentFlags)

        val clickIntent = Intent(context, MainActivity::class.java).apply {
            action = Intent.ACTION_MAIN
            addCategory(Intent.CATEGORY_LAUNCHER)
            setFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED)
        }
        val clickPending = PendingIntent.getActivity(context, 100, clickIntent, pendingIntentFlags)

        // Bind PendingIntents to views
        smallView.setOnClickPendingIntent(R.id.notif_btn_prev, prevPending)
        smallView.setOnClickPendingIntent(R.id.notif_btn_play_pause, playPausePending)
        smallView.setOnClickPendingIntent(R.id.notif_btn_next, nextPending)
        smallView.setOnClickPendingIntent(R.id.notif_btn_close, closePending)

        bigView.setOnClickPendingIntent(R.id.notif_big_btn_prev, prevPending)
        bigView.setOnClickPendingIntent(R.id.notif_big_btn_play_pause, playPausePending)
        bigView.setOnClickPendingIntent(R.id.notif_big_btn_next, nextPending)
        bigView.setOnClickPendingIntent(R.id.notif_big_btn_close, closePending)

        // 6. Build Notification
        val builder = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_music)
            .setContentIntent(clickPending)
            .setCustomContentView(smallView)
            .setCustomBigContentView(bigView)
            .setStyle(NotificationCompat.DecoratedCustomViewStyle())
            .setOngoing(isPlaying)
            .setAutoCancel(false)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)

        // 7. Handle Artwork with memory caching
        if (!albumArtPath.isNullOrEmpty()) {
            if (albumArtPath == cachedAlbumArtPath && cachedBitmap != null) {
                smallView.setImageViewBitmap(R.id.notif_album_art, cachedBitmap)
                bigView.setImageViewBitmap(R.id.notif_big_album_art, cachedBitmap)
                notificationManager.notify(NOTIFICATION_ID, builder.build())
            } else {
                thread {
                    val bitmap = loadRoundedBitmap(albumArtPath)
                    if (bitmap != null) {
                        cachedAlbumArtPath = albumArtPath
                        cachedBitmap = bitmap
                        smallView.setImageViewBitmap(R.id.notif_album_art, bitmap)
                        bigView.setImageViewBitmap(R.id.notif_big_album_art, bitmap)
                    }
                    notificationManager.notify(NOTIFICATION_ID, builder.build())
                }
            }
        } else {
            cachedAlbumArtPath = null
            cachedBitmap = null
            smallView.setImageViewResource(R.id.notif_album_art, R.drawable.ic_default_art)
            bigView.setImageViewResource(R.id.notif_big_album_art, R.drawable.ic_default_art)
            notificationManager.notify(NOTIFICATION_ID, builder.build())
        }
    }

    fun cancel() {
        cachedAlbumArtPath = null
        cachedBitmap = null
        notificationManager.cancel(NOTIFICATION_ID)
    }

    private fun formatTime(ms: Long): String {
        val totalSeconds = (ms / 1000).coerceAtLeast(0)
        val minutes = totalSeconds / 60
        val seconds = totalSeconds % 60
        return String.format("%02d:%02d", minutes, seconds)
    }

    private fun loadRoundedBitmap(path: String): Bitmap? {
        try {
            val rawBitmap: Bitmap = (when {
                path.startsWith("http://") || path.startsWith("https://") -> {
                    val url = URL(path)
                    val conn = url.openConnection() as HttpURLConnection
                    conn.connectTimeout = 3000
                    conn.readTimeout = 3000
                    conn.doInput = true
                    conn.connect()
                    val input: InputStream = conn.inputStream
                    BitmapFactory.decodeStream(input)
                }
                path.startsWith("content://") -> {
                    val uri = Uri.parse(path)
                    context.contentResolver.openInputStream(uri)?.use { stream ->
                        BitmapFactory.decodeStream(stream)
                    }
                }
                path.startsWith("file://") -> {
                    val uri = Uri.parse(path)
                    BitmapFactory.decodeFile(uri.path)
                }
                else -> {
                    val file = File(path)
                    if (file.exists()) {
                        BitmapFactory.decodeFile(file.absolutePath)
                    } else null
                }
            }) ?: return null

            // Use 16% of width for smooth modern corner radius
            val radius = (minOf(rawBitmap.width, rawBitmap.height) * 0.16f).coerceAtLeast(8f)
            return getRoundedCornerBitmap(rawBitmap, radius)
        } catch (e: Exception) {
            return null
        }
    }

    private fun getRoundedCornerBitmap(bitmap: Bitmap, cornerRadius: Float): Bitmap {
        val output = Bitmap.createBitmap(bitmap.width, bitmap.height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(output)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        val rect = Rect(0, 0, bitmap.width, bitmap.height)
        val rectF = RectF(rect)

        canvas.drawRoundRect(rectF, cornerRadius, cornerRadius, paint)
        paint.xfermode = PorterDuffXfermode(PorterDuff.Mode.SRC_IN)
        canvas.drawBitmap(bitmap, rect, rect, paint)
        return output
    }
}
