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
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicLong

class CustomNotificationManager(private val context: Context) {
    companion object {
        const val CHANNEL_ID = "com.aquamoon.app.channel.custom_player"
        const val CHANNEL_NAME = "水月音播放控制器"
        const val CHANNEL_DESC = "水月音专属自定义通知栏音乐播放控制器"
        const val NOTIFICATION_ID = 2001
        private const val TARGET_ART_SIZE_PX = 256
        private const val ART_RETRY_COOLDOWN_MS = 30_000L
        private const val MAX_REMOTE_ART_BYTES = 8 * 1024 * 1024
    }

    private data class NotificationSnapshot(
        val title: String,
        val artist: String,
        val albumArtPath: String?,
        val isPlaying: Boolean,
        val positionSec: Long,
        val durationSec: Long,
    )

    private val notificationManager =
        context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    private val artExecutor = Executors.newSingleThreadExecutor()
    private val artGeneration = AtomicLong(0L)
    private val failedArtTimestamps = HashMap<String, Long>()

    @Volatile
    private var cachedAlbumArtPath: String? = null
    @Volatile
    private var cachedBitmap: Bitmap? = null
    @Volatile
    private var inFlightArtPath: String? = null
    @Volatile
    private var lastSnapshot: NotificationSnapshot? = null

    private val pendingIntentFlags: Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }

    private val prevPending: PendingIntent by lazy {
        val intent = Intent(context, CustomNotificationActionReceiver::class.java).apply {
            action = CustomNotificationActionReceiver.ACTION_PREV
        }
        PendingIntent.getBroadcast(context, 101, intent, pendingIntentFlags)
    }

    private val playPausePending: PendingIntent by lazy {
        val intent = Intent(context, CustomNotificationActionReceiver::class.java).apply {
            action = CustomNotificationActionReceiver.ACTION_PLAY_PAUSE
        }
        PendingIntent.getBroadcast(context, 102, intent, pendingIntentFlags)
    }

    private val nextPending: PendingIntent by lazy {
        val intent = Intent(context, CustomNotificationActionReceiver::class.java).apply {
            action = CustomNotificationActionReceiver.ACTION_NEXT
        }
        PendingIntent.getBroadcast(context, 103, intent, pendingIntentFlags)
    }

    private val closePending: PendingIntent by lazy {
        val intent = Intent(context, CustomNotificationActionReceiver::class.java).apply {
            action = CustomNotificationActionReceiver.ACTION_CLOSE
        }
        PendingIntent.getBroadcast(context, 104, intent, pendingIntentFlags)
    }

    private val clickPending: PendingIntent by lazy {
        val intent = Intent(context, MainActivity::class.java).apply {
            action = Intent.ACTION_MAIN
            addCategory(Intent.CATEGORY_LAUNCHER)
            setFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED)
        }
        PendingIntent.getActivity(context, 100, intent, pendingIntentFlags)
    }

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
        val displayTitle = title.ifEmpty { "水月音" }
        val displayArtist = artist.ifEmpty { "禅意音乐" }
        val positionSec = (positionMs / 1000L).coerceAtLeast(0L)
        val durationSec = (durationMs / 1000L).coerceAtLeast(0L)

        val snapshot = NotificationSnapshot(
            title = displayTitle,
            artist = displayArtist,
            albumArtPath = albumArtPath,
            isPlaying = isPlaying,
            positionSec = positionSec,
            durationSec = durationSec,
        )
        if (snapshot == lastSnapshot) {
            return
        }
        lastSnapshot = snapshot

        val artBitmapForFrame: Bitmap?
        if (albumArtPath.isNullOrEmpty()) {
            artGeneration.incrementAndGet()
            inFlightArtPath = null
            cachedAlbumArtPath = null
            cachedBitmap = null
            artBitmapForFrame = null
        } else if (albumArtPath == cachedAlbumArtPath && cachedBitmap != null) {
            artBitmapForFrame = cachedBitmap
        } else {
            artBitmapForFrame = null
            scheduleArtworkLoad(albumArtPath)
        }

        val notification = buildNotification(snapshot, artBitmapForFrame)
        notificationManager.notify(NOTIFICATION_ID, notification)
    }

    private fun buildNotification(
        snapshot: NotificationSnapshot,
        artBitmap: Bitmap?,
    ): Notification {
        val packageName = context.packageName
        val smallView = RemoteViews(packageName, R.layout.custom_notification_small)
        val bigView = RemoteViews(packageName, R.layout.custom_notification_big)

        smallView.setTextViewText(R.id.notif_title, snapshot.title)
        smallView.setTextViewText(R.id.notif_artist, snapshot.artist)
        bigView.setTextViewText(R.id.notif_big_title, snapshot.title)
        bigView.setTextViewText(R.id.notif_big_artist, snapshot.artist)

        val curTimeStr = formatTimeSec(snapshot.positionSec)
        val totTimeStr = if (snapshot.durationSec > 0) formatTimeSec(snapshot.durationSec) else "00:00"
        bigView.setTextViewText(R.id.notif_big_current_time, curTimeStr)
        bigView.setTextViewText(R.id.notif_big_total_time, totTimeStr)

        val progress = if (snapshot.durationSec > 0) {
            ((snapshot.positionSec.toDouble() / snapshot.durationSec.toDouble()) * 1000)
                .toInt()
                .coerceIn(0, 1000)
        } else {
            0
        }
        bigView.setProgressBar(R.id.notif_big_progress, 1000, progress, false)

        val playPauseIcon =
            if (snapshot.isPlaying) R.drawable.ic_notif_pause else R.drawable.ic_notif_play
        smallView.setImageViewResource(R.id.notif_btn_play_pause, playPauseIcon)
        bigView.setImageViewResource(R.id.notif_big_btn_play_pause, playPauseIcon)

        smallView.setOnClickPendingIntent(R.id.notif_btn_prev, prevPending)
        smallView.setOnClickPendingIntent(R.id.notif_btn_play_pause, playPausePending)
        smallView.setOnClickPendingIntent(R.id.notif_btn_next, nextPending)
        smallView.setOnClickPendingIntent(R.id.notif_btn_close, closePending)

        bigView.setOnClickPendingIntent(R.id.notif_big_btn_prev, prevPending)
        bigView.setOnClickPendingIntent(R.id.notif_big_btn_play_pause, playPausePending)
        bigView.setOnClickPendingIntent(R.id.notif_big_btn_next, nextPending)
        bigView.setOnClickPendingIntent(R.id.notif_big_btn_close, closePending)

        if (artBitmap != null && !artBitmap.isRecycled) {
            smallView.setImageViewBitmap(R.id.notif_album_art, artBitmap)
            bigView.setImageViewBitmap(R.id.notif_big_album_art, artBitmap)
        } else {
            smallView.setImageViewResource(R.id.notif_album_art, R.drawable.ic_default_art)
            bigView.setImageViewResource(R.id.notif_big_album_art, R.drawable.ic_default_art)
        }

        return NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_music)
            .setContentIntent(clickPending)
            .setCustomContentView(smallView)
            .setCustomBigContentView(bigView)
            .setStyle(NotificationCompat.DecoratedCustomViewStyle())
            .setOngoing(snapshot.isPlaying)
            .setOnlyAlertOnce(true)
            .setAutoCancel(false)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .build()
    }

    private fun scheduleArtworkLoad(albumArtPath: String) {
        if (inFlightArtPath == albumArtPath) return
        val now = System.currentTimeMillis()
        val failedAt = synchronized(failedArtTimestamps) {
            failedArtTimestamps[albumArtPath]
        }
        if (failedAt != null && (now - failedAt) < ART_RETRY_COOLDOWN_MS) {
            return
        }

        inFlightArtPath = albumArtPath
        val reqGen = artGeneration.incrementAndGet()
        artExecutor.execute {
            try {
                if (reqGen != artGeneration.get()) return@execute
                val bitmap = loadRoundedBitmap(albumArtPath)
                if (reqGen != artGeneration.get()) {
                    bitmap?.recycle()
                    return@execute
                }
                if (bitmap != null) {
                    cachedAlbumArtPath = albumArtPath
                    cachedBitmap = bitmap
                    synchronized(failedArtTimestamps) {
                        failedArtTimestamps.remove(albumArtPath)
                    }
                    val currentSnapshot = lastSnapshot
                    if (currentSnapshot != null &&
                        currentSnapshot.albumArtPath == albumArtPath
                    ) {
                        notificationManager.notify(
                            NOTIFICATION_ID,
                            buildNotification(currentSnapshot, bitmap),
                        )
                    }
                } else {
                    synchronized(failedArtTimestamps) {
                        if (failedArtTimestamps.size >= 64) {
                            failedArtTimestamps.clear()
                        }
                        failedArtTimestamps[albumArtPath] = System.currentTimeMillis()
                    }
                }
            } finally {
                if (inFlightArtPath == albumArtPath) {
                    inFlightArtPath = null
                }
            }
        }
    }

    fun cancel() {
        artGeneration.incrementAndGet()
        inFlightArtPath = null
        lastSnapshot = null
        cachedAlbumArtPath = null
        cachedBitmap = null
        notificationManager.cancel(NOTIFICATION_ID)
    }

    private fun formatTimeSec(totalSeconds: Long): String {
        val clamped = totalSeconds.coerceAtLeast(0L)
        val minutes = clamped / 60
        val seconds = clamped % 60
        return String.format("%02d:%02d", minutes, seconds)
    }

    private fun calculateInSampleSize(
        width: Int,
        height: Int,
        reqSize: Int,
    ): Int {
        var inSampleSize = 1
        if (height > reqSize || width > reqSize) {
            var halfHeight = height / 2
            var halfWidth = width / 2
            while ((halfHeight / inSampleSize) >= reqSize &&
                (halfWidth / inSampleSize) >= reqSize
            ) {
                inSampleSize *= 2
            }
        }
        return inSampleSize.coerceAtLeast(1)
    }

    private fun decodeSampledFile(filePath: String): Bitmap? {
        val boundsOpts = BitmapFactory.Options().apply {
            inJustDecodeBounds = true
        }
        BitmapFactory.decodeFile(filePath, boundsOpts)
        if (boundsOpts.outWidth <= 0 || boundsOpts.outHeight <= 0) return null

        val decodeOpts = BitmapFactory.Options().apply {
            inSampleSize = calculateInSampleSize(
                boundsOpts.outWidth,
                boundsOpts.outHeight,
                TARGET_ART_SIZE_PX,
            )
        }
        return BitmapFactory.decodeFile(filePath, decodeOpts)
    }

    private fun readStreamBytes(input: InputStream): ByteArray? {
        val buffer = ByteArrayOutputStream()
        val chunk = ByteArray(8192)
        var total = 0
        while (true) {
            val read = input.read(chunk)
            if (read == -1) break
            total += read
            if (total > MAX_REMOTE_ART_BYTES) {
                return null
            }
            buffer.write(chunk, 0, read)
        }
        return buffer.toByteArray()
    }

    private fun decodeSampledBytes(bytes: ByteArray): Bitmap? {
        val boundsOpts = BitmapFactory.Options().apply {
            inJustDecodeBounds = true
        }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, boundsOpts)
        if (boundsOpts.outWidth <= 0 || boundsOpts.outHeight <= 0) return null

        val decodeOpts = BitmapFactory.Options().apply {
            inSampleSize = calculateInSampleSize(
                boundsOpts.outWidth,
                boundsOpts.outHeight,
                TARGET_ART_SIZE_PX,
            )
        }
        return BitmapFactory.decodeByteArray(bytes, 0, bytes.size, decodeOpts)
    }

    private fun loadRoundedBitmap(path: String): Bitmap? {
        var rawBitmap: Bitmap? = null
        var scaledBitmap: Bitmap? = null
        try {
            rawBitmap = when {
                path.startsWith("http://") || path.startsWith("https://") -> {
                    val conn = (URL(path).openConnection() as HttpURLConnection).apply {
                        connectTimeout = 3000
                        readTimeout = 3000
                        doInput = true
                    }
                    try {
                        conn.connect()
                        val bytes = conn.inputStream.use { readStreamBytes(it) }
                        if (bytes != null) decodeSampledBytes(bytes) else null
                    } finally {
                        conn.disconnect()
                    }
                }
                path.startsWith("content://") -> {
                    val uri = Uri.parse(path)
                    val bytes = context.contentResolver.openInputStream(uri)?.use { stream ->
                        readStreamBytes(stream)
                    }
                    if (bytes != null) decodeSampledBytes(bytes) else null
                }
                path.startsWith("file://") -> {
                    val filePath = Uri.parse(path).path
                    if (!filePath.isNullOrEmpty()) decodeSampledFile(filePath) else null
                }
                else -> {
                    val file = File(path)
                    if (file.exists()) decodeSampledFile(file.absolutePath) else null
                }
            } ?: return null

            val maxDim = maxOf(rawBitmap.width, rawBitmap.height)
            val workingBitmap = if (maxDim > TARGET_ART_SIZE_PX) {
                val scale = TARGET_ART_SIZE_PX.toFloat() / maxDim.toFloat()
                val targetW = (rawBitmap.width * scale).toInt().coerceAtLeast(1)
                val targetH = (rawBitmap.height * scale).toInt().coerceAtLeast(1)
                scaledBitmap = Bitmap.createScaledBitmap(rawBitmap, targetW, targetH, true)
                scaledBitmap
            } else {
                rawBitmap
            }

            // Use 16% of width for smooth modern corner radius
            val radius = (minOf(workingBitmap.width, workingBitmap.height) * 0.16f)
                .coerceAtLeast(8f)
            return getRoundedCornerBitmap(workingBitmap, radius)
        } catch (_: Exception) {
            return null
        } finally {
            if (scaledBitmap != null && scaledBitmap !== rawBitmap && !scaledBitmap.isRecycled) {
                scaledBitmap.recycle()
            }
            if (rawBitmap != null && !rawBitmap.isRecycled) {
                rawBitmap.recycle()
            }
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
