package com.mixpanel.mixpanel_flutter;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.Iterator;
import java.util.List;
import java.util.Map;

public class MixpanelFlutterHelper {

    static public JSONObject getMergedProperties(JSONObject properties, JSONObject mixpanelProperties) throws JSONException {
        if (mixpanelProperties != null) {
            for (Iterator<String> keys = mixpanelProperties.keys(); keys.hasNext(); ) {
                String key = keys.next();
                properties.put(key, mixpanelProperties.get(key));
            }
        }
        return properties;
    }

    static public Map<String, Object> toMap(JSONObject object) throws JSONException {
        Map<String, Object> map = new HashMap();
        Iterator keys = object.keys();
        while (keys.hasNext()) {
            String key = (String) keys.next();
            map.put(key, fromJson(object.get(key)));
        }
        return map;
    }

    static public List toList(JSONArray array) throws JSONException {
        List list = new ArrayList();
        for (int i = 0; i < array.length(); i++) {
            list.add(fromJson(array.get(i)));
        }
        return list;
    }

    static public Object fromJson(Object json) throws JSONException {
        if (json == JSONObject.NULL) {
            return null;
        } else if (json instanceof JSONObject) {
            return toMap((JSONObject) json);
        } else if (json instanceof JSONArray) {
            return toList((JSONArray) json);
        } else {
            return json;
        }
    }


}
