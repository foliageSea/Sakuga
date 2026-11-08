package com.foliage.sakuga

import android.content.Context
import android.database.ContentObserver
import android.media.AudioManager
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlin.math.roundToInt

/** Exposes the device media stream, including volume changes made outside Flutter. */
class SystemVolume(context: Context, messenger: BinaryMessenger) : EventChannel.StreamHandler {
    private val resolver = context.applicationContext.contentResolver
    private val audioManager = context.applicationContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private val methods = MethodChannel(messenger, "com.foliage.sakuga/system_volume")
    private val changes = EventChannel(messenger, "com.foliage.sakuga/system_volume/changes")
    private var eventSink: EventChannel.EventSink? = null
    private var observerRegistered = false
    private var lastPercent: Double? = null
    private val observer = object : ContentObserver(Handler(Looper.getMainLooper())) {
        override fun onChange(selfChange: Boolean) {
            emitCurrentVolume()
        }
    }

    init {
        methods.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "read" -> result.success(readPercent())
                    "set" -> {
                        val percent = (call.arguments as? Number)?.toDouble()
                        if (percent == null || !percent.isFinite() || percent !in 0.0..100.0) {
                            result.error("invalid_volume", "Expected a numeric volume percent between 0 and 100.", null)
                        } else {
                            val maximum = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                            val index = (percent * maximum / 100.0).roundToInt().coerceIn(0, maximum)
                            audioManager.setStreamVolume(AudioManager.STREAM_MUSIC, index, 0)
                            result.success(readPercent())
                            emitCurrentVolume()
                        }
                    }
                    else -> result.notImplemented()
                }
            } catch (error: Exception) {
                result.error("system_volume_failed", error.message, null)
            }
        }
        changes.setStreamHandler(this)
    }

    private fun readPercent(): Double {
        val maximum = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
        if (maximum <= 0) return 0.0
        return (audioManager.getStreamVolume(AudioManager.STREAM_MUSIC) * 100.0 / maximum)
            .coerceIn(0.0, 100.0)
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        stopObserving()
        eventSink = events
        try {
            // Observe descendants: Android and OEMs may notify individual volume setting URIs.
            resolver.registerContentObserver(Settings.System.CONTENT_URI, true, observer)
            observerRegistered = true
            emitCurrentVolume()
        } catch (error: Exception) {
            events.error("system_volume_failed", error.message, null)
            stopObserving()
        }
    }

    override fun onCancel(arguments: Any?) {
        stopObserving()
    }

    private fun emitCurrentVolume() {
        val sink = eventSink ?: return
        try {
            val percent = readPercent()
            if (percent != lastPercent) {
                lastPercent = percent
                sink.success(percent)
            }
        } catch (error: Exception) {
            sink.error("system_volume_failed", error.message, null)
        }
    }

    private fun stopObserving() {
        eventSink = null
        lastPercent = null
        if (observerRegistered) {
            try {
                resolver.unregisterContentObserver(observer)
            } catch (error: Exception) {
                Log.w("SystemVolume", "Could not unregister volume observer", error)
            } finally {
                observerRegistered = false
            }
        }
    }

    fun close() {
        stopObserving()
        methods.setMethodCallHandler(null)
        changes.setStreamHandler(null)
    }
}
