package com.mixpanel.mixpanel_flutter;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.isNull;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.mixpanel.android.mpmetrics.MixpanelAPI;

import org.json.JSONException;
import org.json.JSONObject;
import org.junit.Before;
import org.junit.Test;

import java.lang.reflect.Field;
import java.util.HashMap;
import java.util.Map;

import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

/**
 * Regression tests for method handlers that replied to Dart more than once,
 * which throws "IllegalStateException: Reply already submitted" on a real channel.
 * See https://github.com/mixpanel/mixpanel-flutter/issues/151.
 */
public class MixpanelFlutterPluginTest {

    private MixpanelFlutterPlugin plugin;
    private MixpanelAPI mixpanel;
    private MethodChannel.Result result;

    @Before
    public void setUp() throws Exception {
        plugin = new MixpanelFlutterPlugin();
        mixpanel = mock(MixpanelAPI.class);
        result = mock(MethodChannel.Result.class);

        Field field = MixpanelFlutterPlugin.class.getDeclaredField("mixpanel");
        field.setAccessible(true);
        field.set(plugin, mixpanel);
    }

    @Test
    public void setFlushBatchSize_repliesOnceAndDoesNotCallIdentify() {
        Map<String, Object> args = new HashMap<>();
        args.put("flushBatchSize", 50);

        plugin.onMethodCall(new MethodCall("setFlushBatchSize", args), result);

        verify(mixpanel).setFlushBatchSize(50);
        verify(mixpanel, never()).identify(any());
        verify(result, times(1)).success(null);
        verify(result, never()).error(anyString(), any(), any());
    }

    @Test
    public void getSuperProperties_repliesOnlyWithErrorWhenConversionFails() throws JSONException {
        JSONObject superProperties = mock(JSONObject.class);
        when(superProperties.keys()).thenReturn(java.util.Collections.singletonList("key").iterator());
        when(superProperties.get("key")).thenThrow(new JSONException("boom"));
        when(mixpanel.getSuperProperties()).thenReturn(superProperties);

        plugin.onMethodCall(new MethodCall("getSuperProperties", null), result);

        verify(result, times(1)).error(anyString(), any(), isNull());
        verify(result, never()).success(any());
    }
}
