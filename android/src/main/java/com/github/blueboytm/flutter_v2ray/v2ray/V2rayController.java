package com.github.blueboytm.flutter_v2ray.v2ray;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.os.Build;

import com.github.blueboytm.flutter_v2ray.v2ray.core.V2rayCoreManager;
import com.github.blueboytm.flutter_v2ray.v2ray.services.V2rayProxyOnlyService;
import com.github.blueboytm.flutter_v2ray.v2ray.services.V2rayVPNService;
import com.github.blueboytm.flutter_v2ray.v2ray.utils.AppConfigs;
import com.github.blueboytm.flutter_v2ray.v2ray.utils.Utilities;

import java.util.ArrayList;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;

import libv2ray.Libv2ray;

public class V2rayController {

    public static void init(final Context context, final int app_icon, final String app_name) {
        Utilities.copyAssets(context);
        AppConfigs.APPLICATION_ICON = app_icon;
        AppConfigs.APPLICATION_NAME = app_name;

        BroadcastReceiver receiver = new BroadcastReceiver() {
            @Override
            public void onReceive(Context arg0, Intent arg1) {
                AppConfigs.V2RAY_STATE = (AppConfigs.V2RAY_STATES) arg1.getExtras().getSerializable("STATE");
            }
        };
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.registerReceiver(receiver, new IntentFilter("V2RAY_CONNECTION_INFO"), Context.RECEIVER_EXPORTED);
        } else {
            context.registerReceiver(receiver, new IntentFilter("V2RAY_CONNECTION_INFO"));
        }
    }

    public static void changeConnectionMode(final AppConfigs.V2RAY_CONNECTION_MODES connection_mode) {
        if (getConnectionState() == AppConfigs.V2RAY_STATES.V2RAY_DISCONNECTED) {
            AppConfigs.V2RAY_CONNECTION_MODE = connection_mode;
        }
    }

    public static void StartV2ray(final Context context, final String remark, final String config, final ArrayList<String> blocked_apps, final ArrayList<String> bypass_subnets) {
        AppConfigs.V2RAY_CONFIG = Utilities.parseV2rayJsonFile(remark, config, blocked_apps, bypass_subnets);
        if (AppConfigs.V2RAY_CONFIG == null) {
            return;
        }
        Intent start_intent;
        if (AppConfigs.V2RAY_CONNECTION_MODE == AppConfigs.V2RAY_CONNECTION_MODES.PROXY_ONLY) {
            start_intent = new Intent(context, V2rayProxyOnlyService.class);
        } else if (AppConfigs.V2RAY_CONNECTION_MODE == AppConfigs.V2RAY_CONNECTION_MODES.VPN_TUN) {
            start_intent = new Intent(context, V2rayVPNService.class);
        } else {
            return;
        }
        start_intent.putExtra("COMMAND", AppConfigs.V2RAY_SERVICE_COMMANDS.START_SERVICE);
        start_intent.putExtra("V2RAY_CONFIG", AppConfigs.V2RAY_CONFIG);
        if (Build.VERSION.SDK_INT > Build.VERSION_CODES.N_MR1) {
            context.startForegroundService(start_intent);
        } else {
            context.startService(start_intent);
        }
    }

    public static void StopV2ray(final Context context) {
        Intent stop_intent;
        if (AppConfigs.V2RAY_CONNECTION_MODE == AppConfigs.V2RAY_CONNECTION_MODES.PROXY_ONLY) {
            stop_intent = new Intent(context, V2rayProxyOnlyService.class);
        } else if (AppConfigs.V2RAY_CONNECTION_MODE == AppConfigs.V2RAY_CONNECTION_MODES.VPN_TUN) {
            stop_intent = new Intent(context, V2rayVPNService.class);
        } else {
            return;
        }
        stop_intent.putExtra("COMMAND", AppConfigs.V2RAY_SERVICE_COMMANDS.STOP_SERVICE);
        context.startService(stop_intent);
        AppConfigs.V2RAY_CONFIG = null;
    }

    public static long getConnectedV2rayServerDelay(Context context) {
        if (getConnectionState() != AppConfigs.V2RAY_STATES.V2RAY_CONNECTED) {
            return -1;
        }

        Intent checkDelay;
        if (AppConfigs.V2RAY_CONNECTION_MODE == AppConfigs.V2RAY_CONNECTION_MODES.PROXY_ONLY) {
            checkDelay = new Intent(context, V2rayProxyOnlyService.class);
        } else if (AppConfigs.V2RAY_CONNECTION_MODE == AppConfigs.V2RAY_CONNECTION_MODES.VPN_TUN) {
            checkDelay = new Intent(context, V2rayVPNService.class);
        } else {
            return -1;
        }

        final long[] delay = {-1};
        final CountDownLatch latch = new CountDownLatch(1);
        BroadcastReceiver receiver = new BroadcastReceiver() {
            @Override
            public void onReceive(Context receiverContext, Intent intent) {
                try {
                    delay[0] = Long.parseLong(intent.getStringExtra("DELAY"));
                } catch (Exception ignored) {
                    delay[0] = -1;
                }
                latch.countDown();
            }
        };

        // Register before starting the service; otherwise a fast reply is lost.
        IntentFilter filter = new IntentFilter("CONNECTED_V2RAY_SERVER_DELAY");
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED);
        } else {
            context.registerReceiver(receiver, filter);
        }

        try {
            checkDelay.putExtra("COMMAND", AppConfigs.V2RAY_SERVICE_COMMANDS.MEASURE_DELAY);
            context.startService(checkDelay);
            // Native Xray delay measurement can take up to 12 seconds.
            if (!latch.await(15, TimeUnit.SECONDS)) {
                return -1;
            }
            return delay[0];
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            return -1;
        } finally {
            context.unregisterReceiver(receiver);
        }
    }

    public static long getV2rayServerDelay(final String config, final String url) {
        return V2rayCoreManager.getInstance().getV2rayServerDelay(config, url);
    }

    public static AppConfigs.V2RAY_CONNECTION_MODES getConnectionMode() {
        return AppConfigs.V2RAY_CONNECTION_MODE;
    }

    public static AppConfigs.V2RAY_STATES getConnectionState() {
        return AppConfigs.V2RAY_STATE;
    }

    public static String getCoreVersion() {
        return Libv2ray.checkVersionX();
    }


}
