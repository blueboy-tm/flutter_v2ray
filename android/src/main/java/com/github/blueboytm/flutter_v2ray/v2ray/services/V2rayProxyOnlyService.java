package com.github.blueboytm.flutter_v2ray.v2ray.services;

import android.app.Service;
import android.content.Intent;
import android.os.IBinder;
import android.util.Log;

import androidx.annotation.Nullable;

import com.github.blueboytm.flutter_v2ray.v2ray.core.V2rayCoreManager;
import com.github.blueboytm.flutter_v2ray.v2ray.interfaces.V2rayServicesListener;
import com.github.blueboytm.flutter_v2ray.v2ray.utils.AppConfigs;
import com.github.blueboytm.flutter_v2ray.v2ray.utils.V2rayConfig;


public class V2rayProxyOnlyService extends Service implements V2rayServicesListener {


    @Override
    public void onCreate() {
        super.onCreate();
        V2rayCoreManager.getInstance().setUpListener(this);
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
            if (V2rayCoreManager.getInstance().isV2rayCoreRunning()) {
                // Android can redeliver START_SERVICE or Flutter can issue a
                // duplicate request. Never tear down the service while starting.
                Log.i("V2RAY_PROXY_SERVICE", "Core already running; ignoring duplicate start");
                return START_NOT_STICKY;
            }
            if (V2rayCoreManager.getInstance().startCore(v2rayConfig)) {
                Log.e(V2rayProxyOnlyService.class.getSimpleName(), "onStartCommand success => v2ray core started.");
            } else {
                stopSelfResult(startId);
                return START_NOT_STICKY;
            }
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
        // stopService() does not deliver STOP_SERVICE. Release the native core
        // here, but never stop a newer service that replaced this listener.
        V2rayCoreManager manager = V2rayCoreManager.getInstance();
        if (manager.v2rayServicesListener == this && manager.isV2rayCoreRunning()) {
            manager.stopCore();
        }
        super.onDestroy();
        com.github.blueboytm.flutter_v2ray.v2ray.V2rayConnectionCoordinator.notifyDaemonStopped(
                getApplicationContext(),
                com.github.blueboytm.flutter_v2ray.v2ray.V2rayConnectionCoordinator.DAEMON_PROXY);
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
