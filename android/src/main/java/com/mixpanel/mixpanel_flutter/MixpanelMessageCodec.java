package com.mixpanel.mixpanel_flutter;

import io.flutter.plugin.common.StandardMessageCodec;

import java.io.ByteArrayOutputStream;
import java.net.URI;
import java.net.URISyntaxException;
import java.nio.ByteBuffer;
import java.nio.charset.Charset;
import java.util.Date;

public class MixpanelMessageCodec extends StandardMessageCodec {
    static final MixpanelMessageCodec instance = new MixpanelMessageCodec();
    static final Charset UTF8 = Charset.forName("UTF8");
    static final int DATE_TIME = 128;
    static final int URI = 129;

    @Override
    protected void writeValue(ByteArrayOutputStream stream, Object value) {
        if (value instanceof Date) {
            stream.write(DATE_TIME);
            writeLong(stream, ((Date) value).getTime());
        } else if (value instanceof java.net.URI) {
            stream.write(URI);
            writeBytes(stream, ((java.net.URI) value).toString().getBytes(UTF8));
        } else {
            super.writeValue(stream, value);
        }
    }

    @Override
    protected Object readValueOfType(byte type, ByteBuffer buffer) {
        switch (type) {
            case (byte) DATE_TIME:
                return new Date(buffer.getLong());
            case (byte) URI:
                final byte[] urlBytes = readBytes(buffer);
                final String url = new String(urlBytes, UTF8);
                try {
                    return new URI(url);
                } catch (URISyntaxException e) {
                }
            default:
                return super.readValueOfType(type, buffer);
        }
    }
}
