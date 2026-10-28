package com.foliage.sakuga

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.graphics.BitmapFactory
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private var originalScreenBrightness: Float? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.foliage.sakuga/window_brightness",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "read" -> {
                    val brightness = window.attributes.screenBrightness
                    val current = if (brightness >= 0f) brightness else {
                        Settings.System.getInt(
                            contentResolver, Settings.System.SCREEN_BRIGHTNESS, 128,
                        ) / 255f
                    }
                    result.success(current.coerceIn(0f, 1f).toDouble())
                }
                "set" -> {
                    val value = (call.arguments as? Number)?.toFloat()
                    if (value == null || !value.isFinite() || value !in 0f..1f) {
                        result.error("invalid_brightness", "Expected brightness between 0 and 1.", null)
                    } else {
                        if (originalScreenBrightness == null) {
                            originalScreenBrightness = window.attributes.screenBrightness
                        }
                        window.attributes = window.attributes.apply { screenBrightness = value }
                        result.success(null)
                    }
                }
                "reset" -> {
                    originalScreenBrightness?.let { original ->
                        window.attributes = window.attributes.apply { screenBrightness = original }
                        originalScreenBrightness = null
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.foliage.sakuga/image_clipboard",
        ).setMethodCallHandler { call, result ->
            if (call.method != "writePng") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val bytes = call.arguments as? ByteArray
            val signature = byteArrayOf(137.toByte(), 80, 78, 71, 13, 10, 26, 10)
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            if (bytes != null) {
                BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
            }
            if (bytes == null || bytes.size < signature.size ||
                !bytes.take(signature.size).toByteArray().contentEquals(signature) ||
                bounds.outWidth <= 0 || bounds.outHeight <= 0 || bounds.outMimeType != "image/png"
            ) {
                result.error("invalid_png", "Expected PNG image bytes.", null)
                return@setMethodCallHandler
            }
            var imageFile: File? = null
            try {
                val directory = File(cacheDir, "clipboard_images")
                if (!directory.isDirectory && !directory.mkdirs()) {
                    throw java.io.IOException("Could not create clipboard image cache.")
                }
                // Keep each URI immutable; paste recipients may still be reading earlier copies.
                val file = File.createTempFile("image_", ".png", directory)
                imageFile = file
                file.writeBytes(bytes)
                val uri = FileProvider.getUriForFile(this, "$packageName.image_clipboard", file)
                val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                // ClipboardManager grants receiving apps temporary read access to this URI.
                // The provider is private and exposes only the clipboard cache directory.
                clipboard.setPrimaryClip(ClipData.newUri(contentResolver, "Sakuga image", uri))
                result.success(null)
            } catch (error: Exception) {
                imageFile?.delete()
                result.error("clipboard_write_failed", error.message, null)
            }
        }
    }
}
