package com.github.blueboytm.flutter_v2ray;

import androidx.annotation.NonNull;
import android.content.Context;
import android.app.Activity;
import android.net.VpnService;
import android.content.Intent;
import android.content.BroadcastReceiver;
import android.content.IntentFilter;

import java.util.ArrayList;


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
                    if (call.argument("proxy_only")){
                        V2rayController.changeConnectionMode(AppConfigs.V2RAY_CONNECTION_MODES.PROXY_ONLY);
                    } 
                    V2rayController.StartV2ray(binding.getApplicationContext(), call.argument("remark"),  call.argument("config"), call.argument("blocked_apps"));
                    result.success(null);
                    break;
                case "stopV2Ray":
                    V2rayController.StopV2ray(binding.getApplicationContext());
                    result.success(null);
                    break;
                case "initializeV2Ray":
                    V2rayController.init(binding.getApplicationContext(), 0, "Flutter V2ray");
                    result.success(null);
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
        vpnControlMethod.setMethodCallHandler(null);
        vpnStatusEvent.setStreamHandler(null);
        activity.unregisterReceiver(v2rayBroadCastReceiver);
    }

    @Override
    public void onAttachedToActivity(@NonNull ActivityPluginBinding binding) {
        activity = binding.getActivity();
        v2rayBroadCastReceiver = new BroadcastReceiver() {
            @Override
            public void onReceive(Context context, Intent intent) {
                ArrayList<String> list = new ArrayList<String>();
                list.add(intent.getExtras().getString("DURATION"));
                list.add(intent.getExtras().getString("UPLOAD_SPEED"));
                list.add(intent.getExtras().getString("DOWNLOAD_SPEED"));
                list.add(intent.getExtras().getString("UPLOAD_TRAFFIC"));
                list.add(intent.getExtras().getString("DOWNLOAD_TRAFFIC"));
                list.add(intent.getExtras().getSerializable("STATE").toString().substring(6));
                vpnStatusSink.success(list);
            }
        };
        activity.registerReceiver(v2rayBroadCastReceiver, new IntentFilter("V2RAY_CONNECTION_INFO"));
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
                ArrayList<String> list = new ArrayList<String>();
                list.add(intent.getExtras().getString("DURATION"));
                list.add(intent.getExtras().getString("UPLOAD_SPEED"));
                list.add(intent.getExtras().getString("DOWNLOAD_SPEED"));
                list.add(intent.getExtras().getString("UPLOAD_TRAFFIC"));
                list.add(intent.getExtras().getString("DOWNLOAD_TRAFFIC"));
                list.add(intent.getExtras().getSerializable("STATE").toString().substring(6));
                vpnStatusSink.success(list);
            }
        };
        activity.registerReceiver(v2rayBroadCastReceiver, new IntentFilter("V2RAY_CONNECTION_INFO"));
    }

    @Override
    public void onDetachedFromActivity() {
    }
}
