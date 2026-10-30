package com.foliage.sakuga

import android.content.ContentValues
import android.content.Context
import android.graphics.BitmapFactory
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import java.nio.ByteBuffer
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.zip.CRC32

/** All validation, provider operations and file IO run outside the platform thread. */
internal class ImageGallery(private val context: Context) {
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    fun savePng(bytes: ByteArray, result: MethodChannel.Result) {
        worker.execute {
            try {
                if (!isPng(bytes)) {
                    main.post { result.error("invalid_png", "Expected complete PNG image bytes.", null) }
                    return@execute
                }
                val uri = if (Build.VERSION.SDK_INT >= 29) saveMediaStore(bytes) else saveLegacy(bytes)
                main.post { result.success(uri.toString()) }
            } catch (error: Exception) {
                val code = if (error is SecurityException) "permission_denied" else "gallery_save_failed"
                main.post { result.error(code, error.message, null) }
            }
        }
    }

    fun close() {
        // Finish already accepted saves, including their rollback, before stopping the worker.
        worker.shutdown()
    }

    private fun isPng(bytes: ByteArray): Boolean {
        val signature = byteArrayOf(137.toByte(), 80, 78, 71, 13, 10, 26, 10)
        if (bytes.size < 8 || !signature.indices.all { bytes[it] == signature[it] }) return false
        // Bounds decoding alone accepts truncated PNGs. Also verify complete chunks and CRCs.
        val input = ByteBuffer.wrap(bytes)
        input.position(8)
        var first = true
        var hasImageData = false
        var ended = false
        while (input.remaining() >= 12) {
            val length = input.int
            if (length < 0 || length > input.remaining() - 8) return false
            val typeOffset = input.position()
            val type = input.int
            if (first && (type != 0x49484452 || length != 13)) return false // IHDR
            if (!first && type == 0x49484452) return false
            first = false
            input.position(input.position() + length)
            val crc = CRC32().apply { update(bytes, typeOffset, length + 4) }
            if (input.int.toLong() and 0xffffffffL != crc.value) return false
            if (type == 0x49444154) hasImageData = true // IDAT
            if (type == 0x49454e44) { // IEND
                if (length != 0 || input.hasRemaining()) return false
                ended = true
                break
            }
        }
        if (!ended || !hasImageData) return false
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        return bounds.outWidth > 0 && bounds.outHeight > 0 && bounds.outMimeType == "image/png"
    }

    @android.annotation.TargetApi(29)
    private fun saveMediaStore(bytes: ByteArray): Uri {
        val resolver = context.contentResolver
        val values = ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, "Sakuga_${UUID.randomUUID()}.png")
            put(MediaStore.Images.Media.MIME_TYPE, "image/png")
            put(MediaStore.Images.Media.RELATIVE_PATH, "${Environment.DIRECTORY_PICTURES}/Sakuga")
            put(MediaStore.Images.Media.IS_PENDING, 1)
        }
        val uri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
            ?: throw IOException("Could not create gallery image.")
        try {
            val stream = resolver.openOutputStream(uri, "w")
                ?: throw IOException("Could not open gallery image.")
            stream.use { it.write(bytes) }
            val published = resolver.update(uri, ContentValues().apply {
                put(MediaStore.Images.Media.IS_PENDING, 0)
            }, null, null)
            if (published != 1) throw IOException("Could not publish gallery image.")
            return uri
        } catch (error: Exception) {
            runCatching { resolver.delete(uri, null, null) }.exceptionOrNull()?.let(error::addSuppressed)
            throw error
        }
    }

    @Suppress("DEPRECATION")
    private fun saveLegacy(bytes: ByteArray): Uri {
        if (Environment.getExternalStorageState() != Environment.MEDIA_MOUNTED) {
            throw IOException("External storage is unavailable.")
        }
        val directory = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES), "Sakuga")
        if (!directory.isDirectory && !directory.mkdirs()) throw IOException("Could not create Sakuga album.")
        val file = File.createTempFile("Sakuga_", ".png", directory)
        val completed = CountDownLatch(1)
        val scanLock = Any()
        var scannedUri: Uri? = null
        var abandoned = false
        try {
            file.outputStream().use { it.write(bytes) }
            MediaScannerConnection.scanFile(context, arrayOf(file.absolutePath), arrayOf("image/png")) { _, uri ->
                // MediaScanner invokes this on its Binder thread, never the platform thread.
                synchronized(scanLock) {
                    if (abandoned) {
                        // A late scan must not leave a row pointing at a rolled-back file.
                        if (uri != null) runCatching { context.contentResolver.delete(uri, null, null) }
                    } else {
                        scannedUri = uri
                    }
                    completed.countDown()
                }
            }
            if (!completed.await(60, TimeUnit.SECONDS)) throw IOException("Gallery media scan timed out.")
            return synchronized(scanLock) { scannedUri }
                ?: throw IOException("Could not publish image to the gallery.")
        } catch (error: Exception) {
            synchronized(scanLock) {
                abandoned = true
                scannedUri?.let { uri ->
                    runCatching { context.contentResolver.delete(uri, null, null) }.exceptionOrNull()?.let(error::addSuppressed)
                }
            }
            runCatching {
                if (file.exists() && !file.delete()) throw IOException("Could not remove incomplete gallery image.")
            }.exceptionOrNull()?.let(error::addSuppressed)
            throw error
        }
    }
}
