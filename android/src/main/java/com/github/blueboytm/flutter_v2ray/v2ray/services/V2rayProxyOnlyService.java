package com.github.blueboytm.flutter_v2ray.v2ray.services;

import android.app.Service;
import android.content.Intent;
import android.content.IntentFilter;
import android.os.Build;
import android.os.IBinder;
import android.util.Log;

import androidx.annotation.Nullable;

import com.github.blueboytm.flutter_v2ray.v2ray.core.V2rayCoreManager;
import com.github.blueboytm.flutter_v2ray.v2ray.interfaces.V2rayServicesListener;
import com.github.blueboytm.flutter_v2ray.v2ray.utils.AppConfigs;
import com.github.blueboytm.flutter_v2ray.v2ray.utils.V2rayConfig;


public class V2rayProxyOnlyService extends Service implements V2rayServicesListener {
    private V2rayDelayReceiver delayReceiver;



    @Override
    public void onCreate() {
        super.onCreate();
        V2rayCoreManager.getInstance().setUpListener(this);
        delayReceiver = new V2rayDelayReceiver(AppConfigs.V2RAY_CONNECTION_MODES.PROXY_ONLY);
        IntentFilter delayFilter = new IntentFilter(
                com.github.blueboytm.flutter_v2ray.v2ray.V2rayController.ACTION_DELAY_REQUEST);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(delayReceiver, delayFilter, android.content.Context.RECEIVER_NOT_EXPORTED);
        } else {
            registerReceiver(delayReceiver, delayFilter);
        }
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        // Android may recreate a killed service with a null Intent. There is no
        // recoverable configuration in that case, so do not restart the daemon.
        if (intent == null) {
            Log.w("V2RAY_PROXY_SERVICE", "Ignoring service restart with null Intent");
            stopSelfResult(startId);
            return START_NOT_STICKY;
        }
        AppConfigs.V2RAY_SERVICE_COMMANDS startCommand =
                (AppConfigs.V2RAY_SERVICE_COMMANDS) intent.getSerializableExtra("COMMAND");
        if (startCommand == null) {
            Log.w("V2RAY_PROXY_SERVICE", "Ignoring missing service command");
            stopSelfResult(startId);
            return START_NOT_STICKY;
        }
        if (startCommand == AppConfigs.V2RAY_SERVICE_COMMANDS.START_SERVICE) {
            V2rayConfig v2rayConfig = (V2rayConfig) intent.getSerializableExtra("V2RAY_CONFIG");
            if (v2rayConfig == null) {
                Log.e("V2RAY_PROXY_SERVICE", "Missing V2Ray configuration");
                stopSelfResult(startId);
                return START_NOT_STICKY;
            }
            // A foreground service MUST call startForeground() promptly,
            // before any potentially blocking native Xray initialization.
            try {
                V2rayCoreManager.getInstance().showNotification(v2rayConfig);
            } catch (RuntimeException e) {
                Log.e("V2RAY_PROXY_SERVICE", "Foreground promotion failed", e);
                stopSelfResult(startId);
                return START_NOT_STICKY;
            }
            // Never block the Android main thread in CoreController.startLoop().
            final V2rayConfig configToStart = v2rayConfig;
            new Thread(() -> {
                try {
                    V2rayCoreManager manager = V2rayCoreManager.getInstance();
                    if (!manager.isV2rayCoreRunning() &&
                            !manager.startCore(configToStart)) {
                        Log.e("V2RAY_PROXY_SERVICE", "Native core failed to start");
                        stopSelf();
                    }
                } catch (Exception e) {
                    Log.e("V2RAY_PROXY_SERVICE", "Native core start failed", e);
                    stopSelf();
                }
            }, "V2Ray_CoreStartup").start();
        } else if (startCommand.equals(AppConfigs.V2RAY_SERVICE_COMMANDS.STOP_SERVICE)) {
            V2rayCoreManager.getInstance().stopCore();
            AppConfigs.V2RAY_CONFIG = null;
        } else if (startCommand.equals(AppConfigs.V2RAY_SERVICE_COMMANDS.MEASURE_DELAY)) {
            new Thread(() -> {
                String url = intent.getStringExtra("DELAY_URL");
                Log.i("V2RAY_DELAY", "Proxy service measure delay url=" + url);
                Intent sendB = new Intent("CONNECTED_V2RAY_SERVER_DELAY");
                sendB.setPackage(getPackageName());
                sendB.putExtra("DELAY", String.valueOf(V2rayCoreManager.getInstance().getConnectedV2rayServerDelay(url)));
                sendBroadcast(sendB);
            }, "MEASURE_CONNECTED_V2RAY_SERVER_DELAY").start();
        } else {
            Log.w("V2RAY_PROXY_SERVICE", "Unknown service command: " + startCommand);
            return START_NOT_STICKY;
        }
        return START_NOT_STICKY;
    }


    @Override
    public void onDestroy() {
        if (delayReceiver != null) {
            unregisterReceiver(delayReceiver);
            delayReceiver = null;
        }
        super.onDestroy();
        // Shutdown of Go's native loop can block behind an in-flight delay
        // request. Keep Android's service main thread responsive.
        new Thread(() -> {
            try {
                V2rayCoreManager manager = V2rayCoreManager.getInstance();
                if (manager.v2rayServicesListener == V2rayProxyOnlyService.this) {
                    manager.stopCore();
                }
            } catch (Exception e) {
                Log.e("V2RAY_PROXY_SERVICE", "Native core stop failed", e);
            } finally {
                Log.i("V2RAY_PROXY_SERVICE", "Proxy cleanup finished; reporting daemon stopped");
                com.github.blueboytm.flutter_v2ray.v2ray.V2rayConnectionCoordinator.notifyDaemonStopped(
                        getApplicationContext(),
                        com.github.blueboytm.flutter_v2ray.v2ray.V2rayConnectionCoordinator.DAEMON_PROXY);
            }
        }, "V2Ray_ProxyShutdown").start();
    }

    @Nullable
    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    @Override
    public boolean onProtect(int socket) {
        return true;
    }

    @Override
    public Service getService() {
        return this;
    }

    @Override
    public void startService() {
        //ignore
    }

    @Override
    public void stopService() {
        try {
            stopSelf();
        } catch (Exception e) {
            //ignore
        }
    }
}
