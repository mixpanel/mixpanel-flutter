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
import org.json.JSONException
import org.json.JSONObject

/**
 * Subscribes to the native Mixpanel SDK's [MixpanelEventBridge] (a Kotlin
 * `SharedFlow`) and forwards each event to the Dart side via the existing
 * Flutter MethodChannel.
 *
 * The Java plugin calls [start] from `onAttachedToEngine` and [stop] from
 * `onDetachedFromEngine`. This object is a singleton because the native
 * SharedFlow itself is a singleton — we never want more than one active
 * subscription per process.
 */
object EventBridgeSubscriber {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var job: Job? = null

    @JvmStatic
    fun start(channel: MethodChannel) {
        if (job != null) return
        job = scope.launch {
            MixpanelEventBridge.events().collect { event ->
                val properties = event.properties?.let { safelyConvert(it) }
                channel.invokeMethod(
                    "onMixpanelEvent",
                    mapOf(
                        "eventName" to event.eventName,
                        "properties" to properties,
                    )
                )
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
