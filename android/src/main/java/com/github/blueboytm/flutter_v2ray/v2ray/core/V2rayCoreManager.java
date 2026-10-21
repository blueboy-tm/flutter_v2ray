package com.github.blueboytm.flutter_v2ray.v2ray.core;

import static com.github.blueboytm.flutter_v2ray.v2ray.utils.Utilities.getUserAssetsPath;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.graphics.Color;
import android.os.Build;
import android.os.CountDownTimer;
import android.util.Log;

import androidx.annotation.RequiresApi;
import androidx.core.app.NotificationCompat;

import com.github.blueboytm.flutter_v2ray.v2ray.interfaces.V2rayServicesListener;
import com.github.blueboytm.flutter_v2ray.v2ray.services.V2rayProxyOnlyService;
import com.github.blueboytm.flutter_v2ray.v2ray.services.V2rayVPNService;
import com.github.blueboytm.flutter_v2ray.v2ray.utils.AppConfigs;
import com.github.blueboytm.flutter_v2ray.v2ray.utils.Utilities;
import com.github.blueboytm.flutter_v2ray.v2ray.utils.V2rayConfig;

import org.json.JSONObject;

import libv2ray.Libv2ray;
import libv2ray.CoreController;
import libv2ray.CoreCallbackHandler;

public final class V2rayCoreManager {
    private static final int NOTIFICATION_ID = 1;
    private volatile static V2rayCoreManager INSTANCE;
    public V2rayServicesListener v2rayServicesListener = null;
    // CoreCallbackHandler replaces the legacy V2RayVPNServiceSupportsSet binding.
    public final CoreController coreController = Libv2ray.newCoreController(new CoreCallbackHandler() {
        @Override
        public long startup() {
            if (v2rayServicesListener != null) {
                try {
                    // VPN mode starts the existing tun2socks bridge here.
                    v2rayServicesListener.startService();
                } catch (Exception e) {
                    Log.e(V2rayCoreManager.class.getSimpleName(), "startup failed", e);
                    return -1;
                }
            }
            return 0;
        }

        @Override
        public long shutdown() {
            // stopCore() owns service shutdown; calling it here would recursively
            // re-enter CoreController.stopLoop() while its Go mutex is held.
            return 0;
        }

        @Override
        public long onEmitStatus(long code, String message) {
            return 0;
        }
    });
    private boolean stoppingCore = false;
    public AppConfigs.V2RAY_STATES V2RAY_STATE = AppConfigs.V2RAY_STATES.V2RAY_DISCONNECTED;
    private boolean isLibV2rayCoreInitialized = false;
    private CountDownTimer countDownTimer;
    private int seconds, minutes, hours;
    private long totalDownload, totalUpload, uploadSpeed, downloadSpeed;
    private String SERVICE_DURATION = "00:00:00";

    public static V2rayCoreManager getInstance() {
        if (INSTANCE == null) {
            synchronized (V2rayCoreManager.class) {
                if (INSTANCE == null) {
                    INSTANCE = new V2rayCoreManager();
                }
            }
        }
        return INSTANCE;
    }

    private void makeDurationTimer(final Context context, final boolean enable_traffic_statics) {
        countDownTimer = new CountDownTimer(7200, 1000) {
            @RequiresApi(api = Build.VERSION_CODES.M)
            public void onTick(long millisUntilFinished) {
                seconds++;
                if (seconds == 59) {
                    minutes++;
                    seconds = 0;
                }
                if (minutes == 59) {
                    minutes = 0;
                    hours++;
                }
                if (hours == 23) {
                    hours = 0;
                }
                if (enable_traffic_statics) {
                    // The new binding returns a delimited batch of reset-on-read counters.
                    downloadSpeed = 0;
                    uploadSpeed = 0;
                    String counters = coreController.queryAllOutboundTrafficStats();
                    if (counters != null && !counters.isEmpty()) {
                        for (String entry : counters.split(";")) {
                            String[] fields = entry.split(",", 3);
                            if (fields.length != 3) continue;
                            try {
                                long bytes = Long.parseLong(fields[2]);
                                if ("downlink".equals(fields[1])) {
                                    downloadSpeed += bytes;
                                } else if ("uplink".equals(fields[1])) {
                                    uploadSpeed += bytes;
                                }
                            } catch (NumberFormatException ignored) {
                                // Ignore malformed counters from the native bridge.
                            }
                        }
                    }
                    totalDownload += downloadSpeed;
                    totalUpload += uploadSpeed;
                }
                SERVICE_DURATION = Utilities.convertIntToTwoDigit(hours) + ":" + Utilities.convertIntToTwoDigit(minutes) + ":" + Utilities.convertIntToTwoDigit(seconds);
                Intent connection_info_intent = new Intent("V2RAY_CONNECTION_INFO");
                connection_info_intent.setPackage(context.getPackageName());
                connection_info_intent.putExtra("STATE", V2rayCoreManager.getInstance().V2RAY_STATE);
                connection_info_intent.putExtra("DURATION", SERVICE_DURATION);
                connection_info_intent.putExtra("UPLOAD_SPEED", uploadSpeed);
                connection_info_intent.putExtra("DOWNLOAD_SPEED", downloadSpeed);
                connection_info_intent.putExtra("UPLOAD_TRAFFIC", totalUpload);
                connection_info_intent.putExtra("DOWNLOAD_TRAFFIC", totalDownload);
                context.sendBroadcast(connection_info_intent);
            }

            public void onFinish() {
                countDownTimer.cancel();
                if (V2rayCoreManager.getInstance().isV2rayCoreRunning())
                    makeDurationTimer(context, enable_traffic_statics);
            }
        }.start();
    }

    public void setUpListener(Service targetService) {
        try {
            v2rayServicesListener = (V2rayServicesListener) targetService;
            Libv2ray.initCoreEnv(getUserAssetsPath(targetService.getApplicationContext()), "");
            isLibV2rayCoreInitialized = true;
            SERVICE_DURATION = "00:00:00";
            seconds = 0;
            minutes = 0;
            hours = 0;
            uploadSpeed = 0;
            downloadSpeed = 0;
            totalDownload = 0;
            totalUpload = 0;
            Log.e(V2rayCoreManager.class.getSimpleName(), "setUpListener => new initialize from " + v2rayServicesListener.getService().getClass().getSimpleName());
        } catch (Exception e) {
            Log.e(V2rayCoreManager.class.getSimpleName(), "setUpListener failed => ", e);
            isLibV2rayCoreInitialized = false;
        }
    }

    public boolean startCore(final V2rayConfig v2rayConfig) {
        V2RAY_STATE = AppConfigs.V2RAY_STATES.V2RAY_CONNECTING;
        if (!isLibV2rayCoreInitialized) {
            Log.e(V2rayCoreManager.class.getSimpleName(), "startCore failed => LibV2rayCore should be initialize before start.");
            return false;
        }
        if (isV2rayCoreRunning()) {
            // A second start must never call stopCore(), which calls
            // stopSelf() on the active service and can tear down a replacement.
            Log.w(V2rayCoreManager.class.getSimpleName(), "Ignoring start while core is already running");
            return false;
        }
        try {
            // tunFd=0: retain the existing external tun2socks VPN pipeline.
            coreController.startLoop(v2rayConfig.V2RAY_FULL_JSON_CONFIG, 0);
            if (!isV2rayCoreRunning()) {
                V2RAY_STATE = AppConfigs.V2RAY_STATES.V2RAY_DISCONNECTED;
                return false;
            }
            V2RAY_STATE = AppConfigs.V2RAY_STATES.V2RAY_CONNECTED;
            makeDurationTimer(v2rayServicesListener.getService().getApplicationContext(),
                    v2rayConfig.ENABLE_TRAFFIC_STATICS);
            showNotification(v2rayConfig);
        } catch (Exception e) {
            Log.e(V2rayCoreManager.class.getSimpleName(), "startCore failed =>", e);
            return false;
        }
        return true;
    }

    public void stopCore() {
        if (stoppingCore) return;
        stoppingCore = true;
        try {
            V2rayServicesListener listener = v2rayServicesListener;
            if (listener != null) {
                NotificationManager notificationManager = (NotificationManager)
                        listener.getService().getSystemService(Context.NOTIFICATION_SERVICE);
                if (notificationManager != null) notificationManager.cancel(NOTIFICATION_ID);
            }
            if (isV2rayCoreRunning()) {
                coreController.stopLoop();
            }
            sendDisconnectedBroadCast();
            if (listener != null) listener.stopService();
        } catch (Exception e) {
            Log.e(V2rayCoreManager.class.getSimpleName(), "stopCore failed", e);
        } finally {
            stoppingCore = false;
        }
    }

    private void sendDisconnectedBroadCast() {
        V2RAY_STATE = AppConfigs.V2RAY_STATES.V2RAY_DISCONNECTED;
        SERVICE_DURATION = "00:00:00";
        seconds = 0;
        minutes = 0;
        hours = 0;
        uploadSpeed = 0;
        downloadSpeed = 0;
        if (v2rayServicesListener != null) {
            Intent connection_info_intent = new Intent("V2RAY_CONNECTION_INFO");
            connection_info_intent.setPackage(v2rayServicesListener.getService().getPackageName());
            connection_info_intent.putExtra("STATE", V2rayCoreManager.getInstance().V2RAY_STATE);
            connection_info_intent.putExtra("DURATION", SERVICE_DURATION);
            connection_info_intent.putExtra("UPLOAD_SPEED", uploadSpeed);
            connection_info_intent.putExtra("DOWNLOAD_SPEED", uploadSpeed);
            connection_info_intent.putExtra("UPLOAD_TRAFFIC", uploadSpeed);
            connection_info_intent.putExtra("DOWNLOAD_TRAFFIC", uploadSpeed);
            try {
                v2rayServicesListener.getService().getApplicationContext().sendBroadcast(connection_info_intent);
            } catch (Exception e) {
                //ignore
            }
        }
        if (countDownTimer != null) {
            countDownTimer.cancel();
        }
    }

    private String createNotificationChannelID(String appName) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationManager notificationManager =
                    (NotificationManager) v2rayServicesListener.getService().getSystemService(Context.NOTIFICATION_SERVICE);

            String channelId = "A_FLUTTER_V2RAY_SERVICE_CH_ID";
            String channelName = appName + " Background Service";
            NotificationChannel channel = new NotificationChannel(channelId, channelName, NotificationManager.IMPORTANCE_DEFAULT);
            channel.setDescription(channelName);
            channel.setLightColor(Color.DKGRAY);
            channel.setLockscreenVisibility(Notification.VISIBILITY_PRIVATE);

            if (notificationManager != null) {
                notificationManager.createNotificationChannel(channel);
            }

            return channelId;
        }
        return "";
    }

    private void showNotification(final V2rayConfig v2rayConfig) {
        Service context = v2rayServicesListener.getService();
        if (context == null) {
            return;
        }

        // Android 13+ permits foreground services even when the user denies
        // POST_NOTIFICATIONS. Skipping startForeground() here caused service
        // startup failures (and sometimes an ANR) after notification denial.
        Intent launchIntent = context.getPackageManager().getLaunchIntentForPackage(context.getPackageName());
        if (launchIntent != null) {
            launchIntent.setAction("FROM_DISCONNECT_BTN");
            launchIntent.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TASK);
        }
        final int flags;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            flags = PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT;
        } else {
            flags = PendingIntent.FLAG_UPDATE_CURRENT;
        }
        PendingIntent notificationContentPendingIntent = launchIntent == null ? null :
                PendingIntent.getActivity(context, 0, launchIntent, flags);

        String notificationChannelID = createNotificationChannelID(v2rayConfig.APPLICATION_NAME);

        // Connection mode is process-local, and may differ in the daemon.
        // The active service is the correct target for its own stop action.
        Intent stopIntent = new Intent(context, context.getClass());
        stopIntent.putExtra("COMMAND", AppConfigs.V2RAY_SERVICE_COMMANDS.STOP_SERVICE);

        PendingIntent pendingIntent = PendingIntent.getService(
                context, 0, stopIntent, flags);

        // Build the notification
        NotificationCompat.Builder notificationBuilder = new NotificationCompat.Builder(context, notificationChannelID)
                .setSmallIcon(v2rayConfig.APPLICATION_ICON)
                .setContentTitle(v2rayConfig.REMARK)
                .addAction(0, v2rayConfig.NOTIFICATION_DISCONNECT_BUTTON_NAME, pendingIntent)
                .setPriority(NotificationCompat.PRIORITY_MIN)
                .setShowWhen(false)
                .setOnlyAlertOnce(true)
                .setOngoing(true);
        if (notificationContentPendingIntent != null) {
            notificationBuilder.setContentIntent(notificationContentPendingIntent);
        }

        context.startForeground(NOTIFICATION_ID, notificationBuilder.build());
    }


    public boolean isV2rayCoreRunning() {
        if (coreController != null) {
            return coreController.getIsRunning();
        }
        return false;
    }

    public Long getConnectedV2rayServerDelay(final String url) {
        try {
            long result = coreController.measureDelay(url);
            Log.i("V2RAY_DELAY", "Connected core measureDelay url=" + url
                    + " result=" + result);
            return result;
        } catch (Exception e) {
            Log.e("V2RAY_DELAY", "Connected core measureDelay failed, url="
                    + url, e);
            return -1L;
        }
    }

    public Long getV2rayServerDelay(final String config, final String url) {
        try {
            try {
                JSONObject config_json = new JSONObject(config);
                JSONObject new_routing_json = config_json.getJSONObject("routing");
                new_routing_json.remove("rules");
                config_json.remove("routing");
                config_json.put("routing", new_routing_json);
                return Libv2ray.measureOutboundDelay(config_json.toString(), url);
            } catch (Exception json_error) {
                Log.e("getV2rayServerDelay", json_error.toString());
                return Libv2ray.measureOutboundDelay(config, url);
            }
        } catch (Exception e) {
            Log.e("getV2rayServerDelayCore", e.toString());
            return -1L;
        }
    }

}
