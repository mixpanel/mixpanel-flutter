package com.mixpanel.mixpanel_flutter

import com.mixpanel.android.mpmetrics.MixpanelAPI
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.mockk.every
import io.mockk.mockk
import io.mockk.verify
import org.json.JSONException
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test

/**
 * Regression tests for method handlers that replied to Dart more than once, which throws
 * "IllegalStateException: Reply already submitted" on a real channel.
 * See https://github.com/mixpanel/mixpanel-flutter/issues/151.
 */
class MixpanelFlutterPluginTest {

    /** Records every reply so tests can assert exactly one was sent. */
    private class RecordingResult : MethodChannel.Result {
        val replies = mutableListOf<String>()
        override fun success(result: Any?) { replies += "success" }
        override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) { replies += "error" }
        override fun notImplemented() { replies += "notImplemented" }
    }

    // MixpanelAPI only has package-private constructors that need a live Context,
    // SharedPreferences and SQLite, so it is the one collaborator mocked here.
    private val mixpanel = mockk<MixpanelAPI>(relaxed = true)
    private val plugin = MixpanelFlutterPlugin()
    private val result = RecordingResult()

    @Before
    fun setUp() {
        MixpanelFlutterPlugin::class.java.getDeclaredField("mixpanel").apply {
            isAccessible = true
            set(plugin, mixpanel)
        }
    }

    @Test
    fun setFlushBatchSize_repliesOnceAndDoesNotCallIdentify() {
        plugin.onMethodCall(MethodCall("setFlushBatchSize", mapOf("flushBatchSize" to 50)), result)

        assertEquals(listOf("success"), result.replies)
        verify { mixpanel.setFlushBatchSize(50) }
        verify(exactly = 0) { mixpanel.identify(any()) }
    }

    @Test
    fun getSuperProperties_repliesOnlyWithErrorWhenConversionFails() {
        val unconvertible = object : JSONObject(mapOf("key" to "value")) {
            override fun get(key: String): Any = throw JSONException("boom")
        }
        every { mixpanel.superProperties } returns unconvertible

        plugin.onMethodCall(MethodCall("getSuperProperties", null), result)

        assertEquals(listOf("error"), result.replies)
    }
}
