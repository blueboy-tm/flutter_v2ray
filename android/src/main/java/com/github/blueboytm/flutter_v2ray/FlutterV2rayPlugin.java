package com.github.blueboytm.flutter_v2ray;

import androidx.annotation.NonNull;

import android.annotation.SuppressLint;
import android.content.Context;
import android.app.Activity;
import android.net.VpnService;
import android.content.Intent;
import android.os.Build;
import android.content.BroadcastReceiver;
import android.content.IntentFilter;

import java.util.ArrayList;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodChannel;

import com.github.blueboytm.flutter_v2ray.v2ray.V2rayController;
import com.github.blueboytm.flutter_v2ray.v2ray.utils.AppConfigs;

/**
 * FlutterV2rayPlugin
 */
public class FlutterV2rayPlugin implements FlutterPlugin, ActivityAware {

    private MethodChannel vpnControlMethod;
    private EventChannel vpnStatusEvent;
    private EventChannel.EventSink vpnStatusSink;
    private Activity activity;
    private BroadcastReceiver v2rayBroadCastReceiver;
    private final ExecutorService executor = Executors.newSingleThreadExecutor();

    @SuppressLint("DiscouragedApi")
    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
        vpnControlMethod = new MethodChannel(binding.getBinaryMessenger(), "flutter_v2ray");
        vpnStatusEvent = new EventChannel(binding.getBinaryMessenger(), "flutter_v2ray/status");
        
        vpnStatusEvent.setStreamHandler(new EventChannel.StreamHandler() {
            @Override
            public void onListen(Object arguments, EventChannel.EventSink events) {
                vpnStatusSink = events;
            }

            @Override
            public void onCancel(Object arguments) {
                if (vpnStatusSink != null) vpnStatusSink.endOfStream();
            }
        });
        vpnControlMethod.setMethodCallHandler((call, result) -> {
            switch (call.method) {
                case "startV2Ray":
                    if (Boolean.TRUE.equals(call.argument("proxy_only"))){
                        V2rayController.changeConnectionMode(AppConfigs.V2RAY_CONNECTION_MODES.PROXY_ONLY);
                    } 
                    V2rayController.StartV2ray(binding.getApplicationContext(), call.argument("remark"),  call.argument("config"), call.argument("blocked_apps"), call.argument("bypass_subnets"));
                    result.success(null);
                    break;
                case "stopV2Ray":
                    V2rayController.StopV2ray(binding.getApplicationContext());
                    result.success(null);
                    break;
                case "initializeV2Ray":
                    V2rayController.init(binding.getApplicationContext(), binding.getApplicationContext().getResources().getIdentifier("ic_launcher", "mipmap", binding.getApplicationContext().getPackageName()), "Flutter V2ray");
                    result.success(null);
                    break;
                case "getServerDelay":
                    executor.submit(() -> {
                        try {
                            result.success(V2rayController.getV2rayServerDelay(call.argument("config"), call.argument("url")));
                        } catch (Exception e) {
                            result.success(-1);
                        }
                    });
                    break;
                case "getConnectedServerDelay":
                    executor.submit(() -> {
                        try {
                            AppConfigs.DELAY_URL = call.argument("url");
                            result.success(V2rayController.getConnectedV2rayServerDelay(binding.getApplicationContext()));
                        } catch (Exception e) {
                            result.success(-1);
                        }
                    });
                    break;
                case "getCoreVersion":
                    result.success(V2rayController.getCoreVersion());
                    break;
                case "requestPermission":
                    final Intent request = VpnService.prepare(activity);
                    if (request != null) {
                        activity.startActivityForResult(request, 24);
                        result.success(false);
                        break;
                    }
                    result.success(true);
                    break;
                default:
                    break;
            }
        });
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        if (v2rayBroadCastReceiver != null) {
            vpnControlMethod.setMethodCallHandler(null);
            vpnStatusEvent.setStreamHandler(null);
            activity.unregisterReceiver(v2rayBroadCastReceiver);
            executor.shutdown();
        }
    }

    @Override
    public void onAttachedToActivity(@NonNull ActivityPluginBinding binding) {
        activity = binding.getActivity();
        v2rayBroadCastReceiver = new BroadcastReceiver() {
            @Override
            public void onReceive(Context context, Intent intent) {
                try {
                    ArrayList<String> list = new ArrayList<>();
                    list.add(intent.getExtras().getString("DURATION"));
                    list.add(String.valueOf(intent.getLongExtra("UPLOAD_SPEED", 0)));
                    list.add(String.valueOf(intent.getLongExtra("DOWNLOAD_SPEED", 0)));
                    list.add(String.valueOf(intent.getLongExtra("UPLOAD_TRAFFIC", 0)));
                    list.add(String.valueOf(intent.getLongExtra("DOWNLOAD_TRAFFIC", 0)));
                    list.add(intent.getExtras().getSerializable("STATE").toString().substring(6));
                    vpnStatusSink.success(list);
                } catch (Exception ignored) {}
            }
        };
        IntentFilter filter = new IntentFilter("V2RAY_CONNECTION_INFO");
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            activity.registerReceiver(v2rayBroadCastReceiver, filter, Context.RECEIVER_EXPORTED);
        } else {
            activity.registerReceiver(v2rayBroadCastReceiver, filter);
        }
    }


    @Override
    public void onDetachedFromActivityForConfigChanges() {

    }

    @Override
    public void onReattachedToActivityForConfigChanges(@NonNull ActivityPluginBinding binding) {
        activity = binding.getActivity();
        v2rayBroadCastReceiver = new BroadcastReceiver() {
            @Override
            public void onReceive(Context context, Intent intent) {
                try {
                    ArrayList<String> list = new ArrayList<>();
                    list.add(intent.getExtras().getString("DURATION"));
                    list.add(String.valueOf(intent.getLongExtra("UPLOAD_SPEED", 0)));
                    list.add(String.valueOf(intent.getLongExtra("DOWNLOAD_SPEED", 0)));
                    list.add(String.valueOf(intent.getLongExtra("UPLOAD_TRAFFIC", 0)));
                    list.add(String.valueOf(intent.getLongExtra("DOWNLOAD_TRAFFIC", 0)));
                    list.add(intent.getExtras().getSerializable("STATE").toString().substring(6));
                    vpnStatusSink.success(list);
                } 
                catch (Exception ignored) {}
            }
        };
        IntentFilter filter = new IntentFilter("V2RAY_CONNECTION_INFO");
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            activity.registerReceiver(v2rayBroadCastReceiver, filter, Context.RECEIVER_EXPORTED);
        } else {
            activity.registerReceiver(v2rayBroadCastReceiver, filter);
        }
    }

    @Override
    public void onDetachedFromActivity() {
    }
}
