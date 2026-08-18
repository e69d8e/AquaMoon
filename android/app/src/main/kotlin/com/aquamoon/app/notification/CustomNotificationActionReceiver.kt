package com.aquamoon.app.notification

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class CustomNotificationActionReceiver : BroadcastReceiver() {
    companion object {
        const val ACTION_PLAY_PAUSE = "com.aquamoon.app.ACTION_PLAY_PAUSE"
        const val ACTION_PREV = "com.aquamoon.app.ACTION_PREV"
        const val ACTION_NEXT = "com.aquamoon.app.ACTION_NEXT"
        const val ACTION_CLOSE = "com.aquamoon.app.ACTION_CLOSE"

        var onActionListener: ((String) -> Unit)? = null
    }

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        onActionListener?.invoke(action)
    }
}
