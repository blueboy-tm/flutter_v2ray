package com.github.blueboytm.flutter_v2ray.v2ray;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.util.Log;

import java.util.ArrayList;

import io.flutter.plugin.common.EventChannel;

public class V2rayReceiver extends BroadcastReceiver {
    public static EventChannel.EventSink vpnStatusSink;

    @Override
    public void onReceive(Context context, Intent intent) {
        try {
            if (intent == null || !V2rayConnectionCoordinator.acceptsStatusFrom(
                    intent.getStringExtra("SERVICE_MODE"))) return;
            if (vpnStatusSink == null) return;
            ArrayList<String> list = new ArrayList<>();
            list.add(intent.getExtras().getString("DURATION"));
            list.add(String.valueOf(intent.getLongExtra("UPLOAD_SPEED", 0)));
            list.add(String.valueOf(intent.getLongExtra("DOWNLOAD_SPEED", 0)));
            list.add(String.valueOf(intent.getLongExtra("UPLOAD_TRAFFIC", 0)));
            list.add(String.valueOf(intent.getLongExtra("DOWNLOAD_TRAFFIC", 0)));
            list.add(intent.getExtras().getSerializable("STATE").toString().substring(6));
            vpnStatusSink.success(list);
        } catch (Exception e) {
            Log.e("V2rayReceiver", "onReceive failed", e);
        }
    }

}
