package com.github.blueboytm.flutter_v2ray;

import android.annotation.SuppressLint;
import android.Manifest;
import android.content.pm.PackageManager;
import android.app.Activity;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.net.VpnService;
import android.os.Build;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.core.app.ActivityCompat;

import com.github.blueboytm.flutter_v2ray.v2ray.V2rayController;
import com.github.blueboytm.flutter_v2ray.v2ray.V2rayReceiver;
import com.github.blueboytm.flutter_v2ray.v2ray.utils.AppConfigs;

import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.PluginRegistry;

/**
 * FlutterV2rayPlugin
 */
public class FlutterV2rayPlugin implements FlutterPlugin, ActivityAware, PluginRegistry.ActivityResultListener,
        PluginRegistry.RequestPermissionsResultListener {

    private static final int REQUEST_CODE_VPN_PERMISSION = 24;
    private static final int REQUEST_CODE_NOTIFICATION_PERMISSION = 25;
    private final ExecutorService executor = Executors.newSingleThreadExecutor();
    private MethodChannel vpnControlMethod;
    private EventChannel vpnStatusEvent;
    private EventChannel.EventSink vpnStatusSink;
    private Activity activity;
    private ActivityPluginBinding activityBinding;
    private Context applicationContext;
    private BroadcastReceiver v2rayBroadCastReceiver;
    private MethodChannel.Result pendingResult;
    private boolean statusReceiverRegistered = false;

    @SuppressLint("DiscouragedApi")
    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
        applicationContext = binding.getApplicationContext();
        vpnControlMethod = new MethodChannel(binding.getBinaryMessenger(), "flutter_v2ray");
        vpnStatusEvent = new EventChannel(binding.getBinaryMessenger(), "flutter_v2ray/status");

        vpnStatusEvent.setStreamHandler(new EventChannel.StreamHandler() {
            @Override
            public void onListen(Object arguments, EventChannel.EventSink events) {
                vpnStatusSink = events;
                V2rayReceiver.vpnStatusSink = events;
                registerStatusReceiver();
            }

            @Override
            public void onCancel(Object arguments) {
                vpnStatusSink = null;
                V2rayReceiver.vpnStatusSink = null;
                unregisterStatusReceiver();
            }
        });

        vpnControlMethod.setMethodCallHandler((call, result) -> {
            switch (call.method) {
                case "startV2Ray":
                    AppConfigs.NOTIFICATION_DISCONNECT_BUTTON_NAME = call.argument("notificationDisconnectButtonName");
                    // Explicitly select the mode for every start request. Otherwise,
                    // switching from Proxy Only back to VPN leaves the old mode active.
                    AppConfigs.V2RAY_CONNECTION_MODES requestedMode =
                            Boolean.TRUE.equals(call.argument("proxy_only"))
                                    ? AppConfigs.V2RAY_CONNECTION_MODES.PROXY_ONLY
                                    : AppConfigs.V2RAY_CONNECTION_MODES.VPN_TUN;
                    V2rayController.StartV2ray(binding.getApplicationContext(),
                            call.argument("remark"), call.argument("config"),
                            call.argument("blocked_apps"), call.argument("bypass_subnets"),
                            requestedMode);
                    result.success(null);
                    break;
                case "stopV2Ray":
                    V2rayController.StopV2ray(binding.getApplicationContext());
                    result.success(null);
                    break;
                case "initializeV2Ray":
                    String iconResourceName = call.argument("notificationIconResourceName");
                    String iconResourceType = call.argument("notificationIconResourceType");
                    V2rayController.init(binding.getApplicationContext(), binding.getApplicationContext().getResources().getIdentifier(iconResourceName, iconResourceType, binding.getApplicationContext().getPackageName()), "Flutter V2ray");
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
                            result.success(V2rayController.getConnectedV2rayServerDelay(binding.getApplicationContext(), call.argument("url")));
                        } catch (Exception e) {
                            result.success(-1);
                        }
                    });
                    break;
                case "getCoreVersion":
                    result.success(V2rayController.getCoreVersion());
                    break;
                case "requestPermission":
                    if (activity == null) {
                        result.error("NO_ACTIVITY", "VPN permission requires an attached Activity", null);
                        break;
                    }
                    if (pendingResult != null) {
                        result.error("PERMISSION_IN_PROGRESS", "A permission request is already pending", null);
                        break;
                    }
                    pendingResult = result;
                    // Request notification access first, then VPN permission. These
                    // must be separate dialogs, never requested concurrently.
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                            ActivityCompat.checkSelfPermission(activity, Manifest.permission.POST_NOTIFICATIONS)
                                    != PackageManager.PERMISSION_GRANTED) {
                        try {
                            ActivityCompat.requestPermissions(activity,
                                    new String[]{Manifest.permission.POST_NOTIFICATIONS},
                                    REQUEST_CODE_NOTIFICATION_PERMISSION);
                        } catch (RuntimeException e) {
                            // Notification permission is optional; VPN can still work.
                            requestVpnPermission();
                        }
                    } else {
                        requestVpnPermission();
                    }
                    break;
                default:
                    break;
            }
        });
    }


    private void requestVpnPermission() {
        MethodChannel.Result callback = pendingResult;
        if (callback == null) return;
        if (activity == null) {
            pendingResult = null;
            callback.error("NO_ACTIVITY", "Activity detached during VPN permission request", null);
            return;
        }
        try {
            Intent request = VpnService.prepare(activity);
            if (request == null) {
                pendingResult = null;
                callback.success(true);
            } else {
                activity.startActivityForResult(request, REQUEST_CODE_VPN_PERMISSION);
            }
        } catch (RuntimeException e) {
            pendingResult = null;
            callback.error("VPN_PERMISSION_FAILED", e.getMessage(), null);
        }
    }

    @Override
    public boolean onRequestPermissionsResult(int requestCode, @NonNull String[] permissions,
                                              @NonNull int[] grantResults) {
        if (requestCode != REQUEST_CODE_NOTIFICATION_PERMISSION) return false;
        // Notification permission may be denied; this must not deny VPN access.
        requestVpnPermission();
        return true;
    }

    private void registerStatusReceiver() {
        if (applicationContext == null || vpnStatusSink == null || statusReceiverRegistered) return;
        if (v2rayBroadCastReceiver == null) v2rayBroadCastReceiver = new V2rayReceiver();
        IntentFilter filter = new IntentFilter("V2RAY_CONNECTION_INFO");
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            applicationContext.registerReceiver(v2rayBroadCastReceiver, filter, Context.RECEIVER_NOT_EXPORTED);
        } else {
            applicationContext.registerReceiver(v2rayBroadCastReceiver, filter);
        }
        statusReceiverRegistered = true;
    }

    private void unregisterStatusReceiver() {
        if (!statusReceiverRegistered || applicationContext == null) return;
        applicationContext.unregisterReceiver(v2rayBroadCastReceiver);
        statusReceiverRegistered = false;
        v2rayBroadCastReceiver = null;
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        unregisterStatusReceiver();
        vpnStatusSink = null;
        V2rayReceiver.vpnStatusSink = null;
        if (pendingResult != null) {
            pendingResult.error("ENGINE_DETACHED", "Flutter engine detached during VPN permission request", null);
            pendingResult = null;
        }
        vpnControlMethod.setMethodCallHandler(null);
        vpnStatusEvent.setStreamHandler(null);
        applicationContext = null;
        executor.shutdown();
    }

    @Override
    public void onAttachedToActivity(@NonNull ActivityPluginBinding binding) {
        activityBinding = binding;
        activity = binding.getActivity();
        binding.addActivityResultListener(this);
        binding.addRequestPermissionsResultListener(this);
    }

    @Override
    public void onDetachedFromActivityForConfigChanges() {
        // Retain pendingResult: the new Activity can deliver the in-flight result.
        detachActivity();
    }

    @Override
    public void onReattachedToActivityForConfigChanges(@NonNull ActivityPluginBinding binding) {
        onAttachedToActivity(binding);
    }

    @Override
    public void onDetachedFromActivity() {
        detachActivity();
        if (pendingResult != null) {
            pendingResult.error("ACTIVITY_DETACHED", "Activity detached during VPN permission request", null);
            pendingResult = null;
        }
    }

    private void detachActivity() {
        if (activityBinding != null) {
            activityBinding.removeActivityResultListener(this);
            activityBinding.removeRequestPermissionsResultListener(this);
        }
        activityBinding = null;
        activity = null;
    }

    @Override
    public boolean onActivityResult(int requestCode, int resultCode, @Nullable Intent data) {
        if (requestCode != REQUEST_CODE_VPN_PERMISSION) return false;
        MethodChannel.Result callback = pendingResult;
        pendingResult = null;
        // Some Android devices deliver the result again after Activity recreation.
        if (callback != null) callback.success(resultCode == Activity.RESULT_OK);
        return true;
    }
}
