package com.mixpanel.flutter_session_replay

import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.io.ByteArrayOutputStream
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class MixpanelSessionReplayPlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel
    private var executor: ExecutorService? = null
    private var applicationContext: Context? = null

    // Cached resources reused across captures — only accessed from the single executor thread
    private var cachedBitmap: Bitmap? = null
    private var cachedPixels: IntArray? = null
    private var cachedOutputStream: ByteArrayOutputStream? = null

    companion object {
        private const val REGISTER_ACTION = "com.mixpanel.properties.register"
        private const val UNREGISTER_ACTION = "com.mixpanel.properties.unregister"
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "com.mixpanel.flutter_session_replay")
        channel.setMethodCallHandler(this)
        executor = Executors.newSingleThreadExecutor()
        applicationContext = binding.applicationContext
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        executor?.shutdown()
        executor = null
        applicationContext = null
        clearCache()
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "compressImage" -> compressImage(call, result)
            "disposeCache" -> {
                executor?.execute { clearCache() }
                result.success(null)
            }
            "registerSuperProperties" -> {
                registerSuperProperties(call)
                result.success(null)
            }
            "unregisterSuperProperty" -> {
                unregisterSuperProperty(call)
                result.success(null)
            }
            "beginBackgroundTask" -> result.success(null)
            "endBackgroundTask" -> result.success(null)
            else -> result.notImplemented()
        }
    }

    private fun registerSuperProperties(call: MethodCall) {
        val context = applicationContext ?: return
        val data = call.arguments as? Map<*, *> ?: return

        val intent = Intent(REGISTER_ACTION)
        intent.putExtra("data", HashMap(data.mapKeys { it.key.toString() }))
        intent.setPackage(context.packageName)
        context.sendBroadcast(intent)
    }

    private fun unregisterSuperProperty(call: MethodCall) {
        val context = applicationContext ?: return
        val key = call.argument<String>("key") ?: return

        val intent = Intent(UNREGISTER_ACTION)
        intent.putExtra(key, "")
        intent.setPackage(context.packageName)
        context.sendBroadcast(intent)
    }

    private fun clearCache() {
        cachedBitmap?.recycle()
        cachedBitmap = null
        cachedPixels = null
        cachedOutputStream = null
    }

    private fun compressImage(call: MethodCall, result: Result) {
        val rgbaBytes = call.argument<ByteArray>("rgbaBytes")
        val width = call.argument<Int>("width")
        val height = call.argument<Int>("height")
        val quality = call.argument<Int>("quality")

        if (rgbaBytes == null || width == null || height == null || quality == null) {
            result.error("INVALID_ARGS", "Missing required arguments", null)
            return
        }

        val currentExecutor = executor
        if (currentExecutor == null || currentExecutor.isShutdown) {
            result.error("NOT_INITIALIZED", "Plugin not initialized", null)
            return
        }

        currentExecutor.execute {
            try {
                val pixelCount = width * height
                val expectedSize = pixelCount * 4
                if (rgbaBytes.size != expectedSize) {
                    result.error(
                        "INVALID_DATA",
                        "Expected $expectedSize bytes, got ${rgbaBytes.size}",
                        null
                    )
                    return@execute
                }

                // Reuse IntArray if dimensions haven't changed
                var pixels = cachedPixels
                if (pixels == null || pixels.size != pixelCount) {
                    pixels = IntArray(pixelCount)
                    cachedPixels = pixels
                }

                // Convert RGBA bytes to packed RGB ints (alpha ignored — screenshots are opaque)
                // Flutter rawRgba: [R, G, B, A] per pixel → packed 0xFFRRGGBB
                for (i in 0 until pixelCount) {
                    val offset = i * 4
                    val r = rgbaBytes[offset].toInt() and 0xFF
                    val g = rgbaBytes[offset + 1].toInt() and 0xFF
                    val b = rgbaBytes[offset + 2].toInt() and 0xFF
                    pixels[i] = (0xFF shl 24) or (r shl 16) or (g shl 8) or b
                }

                // Reuse bitmap if dimensions match (RGB_565: 2 bytes/pixel, no alpha needed)
                var bitmap = cachedBitmap
                if (bitmap == null || bitmap.isRecycled ||
                    bitmap.width != width || bitmap.height != height
                ) {
                    bitmap?.recycle()
                    bitmap = try {
                        Bitmap.createBitmap(width, height, Bitmap.Config.RGB_565)
                    } catch (e: OutOfMemoryError) {
                        result.error("OOM", "Failed to allocate bitmap", null)
                        return@execute
                    }
                    cachedBitmap = bitmap
                }

                // Write pixels into reused bitmap (overwrites all pixels, no erase needed)
                bitmap.setPixels(pixels, 0, width, 0, 0, width, height)

                // Reuse output stream
                var outputStream = cachedOutputStream
                if (outputStream == null) {
                    outputStream = ByteArrayOutputStream()
                    cachedOutputStream = outputStream
                } else {
                    outputStream.reset()
                }

                bitmap.compress(Bitmap.CompressFormat.JPEG, quality, outputStream)

                // Bitmap stays cached for next capture — not recycled
                result.success(outputStream.toByteArray())
            } catch (e: Exception) {
                result.error("COMPRESSION_ERROR", e.message, null)
            }
        }
    }
}
