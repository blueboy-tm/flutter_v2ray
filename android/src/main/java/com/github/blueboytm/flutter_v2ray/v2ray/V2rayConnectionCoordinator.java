package com.github.blueboytm.flutter_v2ray.v2ray;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;

import com.github.blueboytm.flutter_v2ray.v2ray.services.V2rayProxyOnlyService;
import com.github.blueboytm.flutter_v2ray.v2ray.services.V2rayVPNService;
import com.github.blueboytm.flutter_v2ray.v2ray.utils.AppConfigs;
import com.github.blueboytm.flutter_v2ray.v2ray.utils.V2rayConfig;

/**
 * Coordinates session transitions in the Flutter process. Android services run
 * in a separate process; their onDestroy() must finish before the next core
 * can start. Commands are serialized on the main looper and duplicate starts
 * are ignored.
 */
public final class V2rayConnectionCoordinator {
    public static final String ACTION_DAEMON_STOPPED =
            "com.github.blueboytm.flutter_v2ray.DAEMON_STOPPED";
    public static final String EXTRA_DAEMON = "DAEMON";
    public static final String DAEMON_VPN = "VPN";
    public static final String DAEMON_PROXY = "PROXY";

    private static final String TAG = "V2RAY_SESSION";
    private static final Handler HANDLER = new Handler(Looper.getMainLooper());
    private static final long STOP_TIMEOUT_MS = 5000L;

    private static volatile boolean requestedRunning;
    private static String requestedSignature;
    private static volatile AppConfigs.V2RAY_CONNECTION_MODES requestedMode;
    private static boolean awaitingVpn;
    private static boolean awaitingProxy;
    private static BroadcastReceiver stoppedReceiver;
    private static Context receiverContext;
    private static Runnable pendingStart;
    private static Runnable stopTimeout;

    private V2rayConnectionCoordinator() {}

    public static boolean isRequestedRunning() {
        return requestedRunning;
    }

    public static void start(Context context, V2rayConfig config,
                             AppConfigs.V2RAY_CONNECTION_MODES mode,
                             String signature) {
        final Context appContext = context.getApplicationContext();
        HANDLER.post(() -> {
            if (requestedRunning && mode == requestedMode &&
                    signature.equals(requestedSignature)) {
                Log.i(TAG, "Duplicate connect ignored for " + mode);
                return;
            }
            requestedRunning = true;
            requestedMode = mode;
            requestedSignature = signature;
            Log.i(TAG, "Starting transition to " + mode);

            // Do not use a stale, broadcast-backed connected state to decide
            // which daemon is active. Stop both possible daemon services.
            stopBothAndThen(appContext, () -> {
                if (!requestedRunning || requestedMode != mode ||
                        !signature.equals(requestedSignature)) return;
                AppConfigs.V2RAY_CONNECTION_MODE = mode;
                AppConfigs.V2RAY_CONFIG = config;
                Intent startIntent = new Intent(appContext,
                        mode == AppConfigs.V2RAY_CONNECTION_MODES.VPN_TUN
                                ? V2rayVPNService.class : V2rayProxyOnlyService.class);
                startIntent.putExtra("COMMAND", AppConfigs.V2RAY_SERVICE_COMMANDS.START_SERVICE);
                startIntent.putExtra("V2RAY_CONFIG", config);
                try {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        appContext.startForegroundService(startIntent);
                    } else {
                        appContext.startService(startIntent);
                    }
                    Log.i(TAG, "Start request dispatched for " + mode);
                } catch (RuntimeException e) {
                    Log.e(TAG, "Unable to start service for " + mode, e);
                    requestedRunning = false;
                    requestedSignature = null;
                    AppConfigs.V2RAY_CONFIG = null;
                    AppConfigs.V2RAY_STATE = AppConfigs.V2RAY_STATES.V2RAY_DISCONNECTED;
                }
            });
        });
    }

    public static void stop(Context context) {
        final Context appContext = context.getApplicationContext();
        HANDLER.post(() -> {
            requestedRunning = false;
            requestedSignature = null;
            requestedMode = null;
            pendingStart = null;
            clearStopWait();
            AppConfigs.V2RAY_CONFIG = null;
            Log.i(TAG, "Stopping both daemon services");
            appContext.stopService(new Intent(appContext, V2rayVPNService.class));
            appContext.stopService(new Intent(appContext, V2rayProxyOnlyService.class));
        });
    }

    public static boolean acceptsStatusFrom(String serviceMode) {
        AppConfigs.V2RAY_CONNECTION_MODES current = requestedMode;
        return current == null || serviceMode == null || current.name().equals(serviceMode);
    }

    public static void onConnectionState(AppConfigs.V2RAY_STATES state, String serviceMode) {
        if (state != AppConfigs.V2RAY_STATES.V2RAY_DISCONNECTED) return;
        HANDLER.post(() -> {
            // Late DISCONNECTED events from the old VPN must not reset a new
            // proxy-only session (and vice versa).
            if (!acceptsStatusFrom(serviceMode)) return;
            if (pendingStart == null && stoppedReceiver == null) {
                requestedRunning = false;
                requestedSignature = null;
            }
        });
    }

    private static void stopBothAndThen(Context context, Runnable startAction) {
        clearStopWait();
        pendingStart = startAction;
        receiverContext = context;
        stoppedReceiver = new BroadcastReceiver() {
            @Override
            public void onReceive(Context ignored, Intent intent) {
                if (intent == null) return;
                String daemon = intent.getStringExtra(EXTRA_DAEMON);
                if (DAEMON_VPN.equals(daemon)) awaitingVpn = false;
                if (DAEMON_PROXY.equals(daemon)) awaitingProxy = false;
                completeStopWaitIfReady();
            }
        };
        IntentFilter filter = new IntentFilter(ACTION_DAEMON_STOPPED);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.registerReceiver(stoppedReceiver, filter, Context.RECEIVER_NOT_EXPORTED);
        } else {
            context.registerReceiver(stoppedReceiver, filter);
        }

        // Both services share a daemon process. Wait for onDestroy() signals so
        // an old core's cleanup cannot tear down the replacement core.
        awaitingVpn = context.stopService(new Intent(context, V2rayVPNService.class));
        awaitingProxy = context.stopService(new Intent(context, V2rayProxyOnlyService.class));
        Log.i(TAG, "Awaiting service teardown: vpn=" + awaitingVpn +
                ", proxy=" + awaitingProxy);
        if (!awaitingVpn && !awaitingProxy) {
            completeStopWaitIfReady();
        } else {
            stopTimeout = () -> {
                Log.w(TAG, "Daemon stop acknowledgement timeout; checking service state");
                boolean vpnStillRunning =
                        context.stopService(new Intent(context, V2rayVPNService.class));
                boolean proxyStillRunning =
                        context.stopService(new Intent(context, V2rayProxyOnlyService.class));
                if (vpnStillRunning || proxyStillRunning) {
                    // Never launch a new core on top of a daemon that has not
                    // completed teardown; doing so can leave the VPN stuck.
                    Log.e(TAG, "Daemon still running after stop timeout; canceling start");
                    requestedRunning = false;
                    requestedMode = null;
                    requestedSignature = null;
                    AppConfigs.V2RAY_CONFIG = null;
                    clearStopWait();
                    return;
                }
                awaitingVpn = false;
                awaitingProxy = false;
                completeStopWaitIfReady();
            };
            HANDLER.postDelayed(stopTimeout, STOP_TIMEOUT_MS);
        }
    }

    private static void completeStopWaitIfReady() {
        if (awaitingVpn || awaitingProxy) return;
        Runnable continuation = pendingStart;
        clearStopWait();
        if (continuation != null) continuation.run();
    }

    private static void clearStopWait() {
        if (stopTimeout != null) HANDLER.removeCallbacks(stopTimeout);
        stopTimeout = null;
        if (stoppedReceiver != null && receiverContext != null) {
            try {
                receiverContext.unregisterReceiver(stoppedReceiver);
            } catch (IllegalArgumentException ignored) {
                // The receiver was already unregistered.
            }
        }
        stoppedReceiver = null;
        receiverContext = null;
        pendingStart = null;
        awaitingVpn = false;
        awaitingProxy = false;
    }

    public static void notifyDaemonStopped(Context context, String daemon) {
        Intent intent = new Intent(ACTION_DAEMON_STOPPED);
        intent.setPackage(context.getPackageName());
        intent.putExtra(EXTRA_DAEMON, daemon);
        context.sendBroadcast(intent);
    }
}
