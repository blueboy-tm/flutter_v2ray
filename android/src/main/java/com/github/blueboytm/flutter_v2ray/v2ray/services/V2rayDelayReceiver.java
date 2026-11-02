package com.github.blueboytm.flutter_v2ray.v2ray.services;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.util.Log;

import com.github.blueboytm.flutter_v2ray.v2ray.V2rayController;
import com.github.blueboytm.flutter_v2ray.v2ray.core.V2rayCoreManager;
import com.github.blueboytm.flutter_v2ray.v2ray.utils.AppConfigs;

/**
 * Receives latency requests only while a VPN/proxy service already exists.
 * Unlike startService(MEASURE_DELAY), this never resurrects a stopped daemon.
 */
final class V2rayDelayReceiver extends BroadcastReceiver {
    private final AppConfigs.V2RAY_CONNECTION_MODES mode;

    V2rayDelayReceiver(AppConfigs.V2RAY_CONNECTION_MODES mode) {
        this.mode = mode;
    }

    @Override
    public void onReceive(Context context, Intent intent) {
        if (intent == null || !mode.name().equals(intent.getStringExtra("MODE"))) return;
        String url = intent.getStringExtra("DELAY_URL");
        if (url == null || url.isEmpty()) return;
        final String requestId = intent.getStringExtra("REQUEST_ID");
        final Context appContext = context.getApplicationContext();
        new Thread(() -> {
            long delay = V2rayCoreManager.getInstance().getConnectedV2rayServerDelay(url);
            Intent response = new Intent("CONNECTED_V2RAY_SERVER_DELAY");
            response.setPackage(appContext.getPackageName());
            response.putExtra("DELAY", String.valueOf(delay));
            response.putExtra("REQUEST_ID", requestId);
            appContext.sendBroadcast(response);
            Log.i("V2RAY_DELAY", "Delivered delay from active " + mode + " service: " + delay);
        }, "V2Ray_MeasureDelay").start();
    }
}
