package com.mixpanel.mixpanel_flutter

import android.util.Log
import com.mixpanel.android.eventbridge.MixpanelEventBridge
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch
import kotlinx.coroutines.plus
import kotlinx.coroutines.withContext
import org.json.JSONException
import org.json.JSONObject

/**
 * Subscribes to the native Mixpanel SDK's [MixpanelEventBridge] (a Kotlin
 * `SharedFlow`) and forwards each event to the Dart side via the existing
 * Flutter MethodChannel.
 *
 * Lifecycle is driven from Dart: [start] runs when the plugin receives a
 * `startEventBridge` MethodChannel call (issued the first time a Dart
 * consumer subscribes to `MixpanelEventBridge.events`), and [stop] runs
 * on `stopEventBridge` (last cancel) and on `onDetachedFromEngine`.
 *
 * This object is a singleton because the native SharedFlow itself is a
 * singleton — we never want more than one active collector per process.
 */
object EventBridgeSubscriber {

    // Collect on Default so the per-event JSONObject → Map conversion
    // (which can be expensive for fat property payloads) runs off the main
    // thread; only the MethodChannel dispatch itself, which requires the
    // platform thread, is hopped back to Main.
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private var job: Job? = null

    @JvmStatic
    fun start(channel: MethodChannel) {
        if (job != null) return
        job = scope.launch {
            MixpanelEventBridge.events().collect { event ->
                val properties = event.properties?.let { safelyConvert(it) }
                val args = mapOf(
                    "eventName" to event.eventName,
                    "properties" to properties,
                )
                withContext(Dispatchers.Main) {
                    channel.invokeMethod("onMixpanelEvent", args)
                }
            }
        }
    }

    @JvmStatic
    fun stop() {
        job?.cancel()
        job = null
    }

    private fun safelyConvert(json: JSONObject): Map<String, Any?>? = try {
        MixpanelFlutterHelper.toMap(json)
    } catch (e: JSONException) {
        // A malformed properties payload should not abort the whole
        // subscription — drop this event's properties and keep collecting.
        Log.w("EventBridgeSubscriber", "Failed to convert event properties", e)
        null
    }
}
