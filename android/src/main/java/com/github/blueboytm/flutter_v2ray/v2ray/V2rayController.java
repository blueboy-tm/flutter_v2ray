package com.github.blueboytm.flutter_v2ray.v2ray;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.net.ConnectivityManager;
import android.net.Network;
import android.net.NetworkCapabilities;
import android.os.Build;
import android.Manifest;
import android.content.pm.PackageManager;
import android.util.Log;

import com.github.blueboytm.flutter_v2ray.v2ray.core.V2rayCoreManager;
import com.github.blueboytm.flutter_v2ray.v2ray.services.V2rayProxyOnlyService;
import com.github.blueboytm.flutter_v2ray.v2ray.services.V2rayVPNService;
import com.github.blueboytm.flutter_v2ray.v2ray.utils.AppConfigs;
import com.github.blueboytm.flutter_v2ray.v2ray.utils.Utilities;
import androidx.core.app.ActivityCompat;
import androidx.core.app.NotificationCompat;

import java.net.NetworkInterface;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
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
            if (ActivityCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS)
                    != PackageManager.PERMISSION_GRANTED) {
                        context.registerReceiver(receiver, new IntentFilter("V2RAY_CONNECTION_INFO"));
                
            }
            else{
                context.registerReceiver(receiver, new IntentFilter("V2RAY_CONNECTION_INFO"), Context.RECEIVER_EXPORTED);
            }
         
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

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (ActivityCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS)
                    != PackageManager.PERMISSION_GRANTED) {
                context.startService(start_intent);
            }
            else{
            context.startForegroundService(start_intent);

            }
        }
        else{
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
        if (V2rayController.getConnectionState() != AppConfigs.V2RAY_STATES.V2RAY_CONNECTED) {
            return -1;
        }
        Intent check_delay;
        if (AppConfigs.V2RAY_CONNECTION_MODE == AppConfigs.V2RAY_CONNECTION_MODES.PROXY_ONLY) {
            check_delay = new Intent(context, V2rayProxyOnlyService.class);
        } else if (AppConfigs.V2RAY_CONNECTION_MODE == AppConfigs.V2RAY_CONNECTION_MODES.VPN_TUN) {
            check_delay = new Intent(context, V2rayVPNService.class);
        } else {
            return -1;
        }
        final long[] delay = {-1};

        final CountDownLatch latch = new CountDownLatch(1);
        check_delay.putExtra("COMMAND", AppConfigs.V2RAY_SERVICE_COMMANDS.MEASURE_DELAY);
        context.startService(check_delay);
        BroadcastReceiver receiver = new BroadcastReceiver() {
            @Override
            public void onReceive(Context arg0, Intent arg1) {
                String delayString = arg1.getExtras().getString("DELAY");
                delay[0] = Long.parseLong(delayString);
                context.unregisterReceiver(this);
                latch.countDown();
            }
        };

        IntentFilter delayIntentFilter = new IntentFilter("CONNECTED_V2RAY_SERVER_DELAY");
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.registerReceiver(receiver, delayIntentFilter, Context.RECEIVER_EXPORTED);
        } else {
            context.registerReceiver(receiver, delayIntentFilter);
        }

        try {
            boolean received = latch.await(3000, TimeUnit.MILLISECONDS);
            if (!received) {
                return -1;
            }
        } catch (InterruptedException e) {
            e.printStackTrace();
        }
        return delay[0];
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

    public static boolean checkVPNState(Context context) {
        // 检查当前设备的 Android 版本是否大于等于 6.0 (Marshmallow)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            // 获取系统的 ConnectivityManager 服务，用于管理网络连接
            ConnectivityManager cm = (ConnectivityManager) context.getSystemService(Context.CONNECTIVITY_SERVICE);

            // 确保 ConnectivityManager 不为空
            if (cm != null) {
                // 获取当前活动的网络（即设备当前正在使用的网络）
                Network activeNetwork = cm.getActiveNetwork();

                // 确保活动网络不为空
                if (activeNetwork != null) {
                    // 获取活动网络的能力（NetworkCapabilities），用于检查网络属性
                    NetworkCapabilities caps = cm.getNetworkCapabilities(activeNetwork);
                    // 检查网络能力是否不为空，并且是否具有 VPN 传输属性
                    return caps != null && caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN);
                }
            }
        } else {
            // 对于 Android 6.0 以下的设备，使用通用方法检查 VPN 状态
            try {
                // 获取所有网络接口的列表
                List<NetworkInterface> interfaces = Collections.list(NetworkInterface.getNetworkInterfaces());

                // 遍历每个网络接口
                for (NetworkInterface intf : interfaces) {
                    // 获取接口名称并将其转换为小写
                    String name = intf.getName().toLowerCase();

                    // 检查接口名称是否包含 "tun"、"ppp" 或 "ipsec"，这些是 VPN 接口的常见标识
                    if (name.contains("tun") || name.contains("ppp") || name.contains("ipsec")) {
                        // 如果找到匹配的接口，返回 true 表示 VPN 处于活动状态
                        return true;
                    }
                }
            } catch (Exception e) {
                // 捕获并打印异常（例如权限问题或网络接口获取失败）
                e.printStackTrace();
            }
        }

        // 如果没有检测到 VPN 活动状态，返回 false
        return false;
    }
}
