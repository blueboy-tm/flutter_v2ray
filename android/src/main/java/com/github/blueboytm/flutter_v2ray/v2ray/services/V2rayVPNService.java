package com.github.blueboytm.flutter_v2ray.v2ray.services;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Intent;
import android.net.InetAddresses;
import android.net.LocalSocket;
import android.net.LocalSocketAddress;
import android.net.VpnService;
import android.os.Build;
import android.os.ParcelFileDescriptor;
import android.util.Log;

import androidx.core.app.NotificationCompat;

import com.github.blueboytm.flutter_v2ray.v2ray.core.V2rayCoreManager;
import com.github.blueboytm.flutter_v2ray.v2ray.interfaces.V2rayServicesListener;
import com.github.blueboytm.flutter_v2ray.v2ray.utils.AppConfigs;
import com.github.blueboytm.flutter_v2ray.v2ray.utils.V2rayConfig;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.File;
import java.io.FileDescriptor;
import java.io.OutputStream;
import java.util.ArrayList;
import java.util.Arrays;

public class V2rayVPNService extends VpnService implements V2rayServicesListener {
    private static final int NOTIFICATION_ID = 10101; // 通知ID
    private static final String NOTIFICATION_CHANNEL_ID = "v2ray_vpn_channel"; // 通知渠道ID
    private ParcelFileDescriptor mInterface;
    private Process process;
    private V2rayConfig v2rayConfig;
    private boolean isRunning = true;

    @Override
    public void onCreate() {
        super.onCreate();
        V2rayCoreManager.getInstance().setUpListener(this);
        createNotificationChannel(); // 创建通知渠道
    }

    @Override
public int onStartCommand(Intent intent, int flags, int startId) {
    if (intent == null) {
        Log.e("V2rayProxyOnlyService", "Received null intent, stopping service.");
        stopSelf();
        return START_NOT_STICKY;
    }
    AppConfigs.V2RAY_SERVICE_COMMANDS startCommand = (AppConfigs.V2RAY_SERVICE_COMMANDS) intent.getSerializableExtra("COMMAND");
    if (startCommand.equals(AppConfigs.V2RAY_SERVICE_COMMANDS.START_SERVICE)) {
        v2rayConfig = (V2rayConfig) intent.getSerializableExtra("V2RAY_CONFIG");
        if (v2rayConfig == null) {
            this.onDestroy();
        }
        if (V2rayCoreManager.getInstance().isV2rayCoreRunning()) {
            V2rayCoreManager.getInstance().stopCore();
        }
        if (V2rayCoreManager.getInstance().startCore(v2rayConfig)) {
            Log.e(V2rayProxyOnlyService.class.getSimpleName(), "onStartCommand success => v2ray core started.");
        } else {
            this.onDestroy();
        }
    } else if (startCommand.equals(AppConfigs.V2RAY_SERVICE_COMMANDS.STOP_SERVICE)) {
        V2rayCoreManager.getInstance().stopCore();
        AppConfigs.V2RAY_CONFIG = null;
    } else if (startCommand.equals(AppConfigs.V2RAY_SERVICE_COMMANDS.MEASURE_DELAY)) {
        new Thread(() -> {
            Intent sendB = new Intent("CONNECTED_V2RAY_SERVER_DELAY");
            sendB.putExtra("DELAY", String.valueOf(V2rayCoreManager.getInstance().getConnectedV2rayServerDelay()));
            sendBroadcast(sendB);
        }, "MEASURE_CONNECTED_V2RAY_SERVER_DELAY").start();
    } else {
        this.onDestroy();
    }
    return START_REDELIVER_INTENT;
}

    private void stopAllProcess() {
        stopForeground(true); // 停止前台服务并移除通知
        isRunning = false;
        if (process != null) {
            process.destroy();
        }
        V2rayCoreManager.getInstance().stopCore();
        try {
            stopSelf();
        } catch (Exception e) {
            Log.e("CANT_STOP", "SELF");
        }
        try {
            if (mInterface != null) {
                mInterface.close();
            }
        } catch (Exception e) {
            // ignored
        }
    }

    private void setup() {
        Intent prepare_intent = prepare(this);
        if (prepare_intent != null) {
            return;
        }

        // 启动前台服务
        startForeground(NOTIFICATION_ID, createNotification());

        Builder builder = new Builder();
        builder.setSession("Secure Tunnel"); // 使用固定名称替代动态IP
        builder.setMtu(1500);
        builder.addAddress("26.26.26.1", 30);

        if (v2rayConfig.BYPASS_SUBNETS == null || v2rayConfig.BYPASS_SUBNETS.isEmpty()) {
            builder.addRoute("0.0.0.0", 0);
        } else {
            for (String subnet : v2rayConfig.BYPASS_SUBNETS) {
                String[] parts = subnet.split("/");
                if (parts.length == 2) {
                    String address = parts[0];
                    int prefixLength = Integer.parseInt(parts[1]);
                    builder.addRoute(address, prefixLength);
                }
            }
        }
        if (v2rayConfig.BLOCKED_APPS != null) {
            for (int i = 0; i < v2rayConfig.BLOCKED_APPS.size(); i++) {
                try {
                    builder.addDisallowedApplication(v2rayConfig.BLOCKED_APPS.get(i));
                } catch (Exception e) {
                    //ignore
                }
            }
        }
        try {
            JSONObject json = new JSONObject(v2rayConfig.V2RAY_FULL_JSON_CONFIG);
            JSONObject dnsObject = json.getJSONObject("dns");
            JSONArray serversArray = dnsObject.getJSONArray("servers");

            for (int i = 0; i < serversArray.length(); i++) {
                Object serverEntry = serversArray.get(i);
                handleDnsServerEntry(builder, serverEntry);
            }
        } catch (JSONException e) {
            Log.e("DNS Config", "JSON parsing error", e);
        }

        try {
            if (mInterface != null) {
                mInterface.close();
            }
        } catch (Exception e) {
            //ignore
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            builder.setMetered(false);
            builder.setHttpProxy(null); // 禁用代理信息显示
        }

        try {
            mInterface = builder.establish();
            isRunning = true;
            runTun2socks();
        } catch (Exception e) {
            stopAllProcess();
        }
    }

    /**
     * 处理单个DNS服务器条目
     */
    private void handleDnsServerEntry(Builder builder, Object serverEntry) {
        try {
            if (serverEntry instanceof String) {
                handleStringDnsEntry(builder, (String) serverEntry);
            } else if (serverEntry instanceof JSONObject) {
                handleObjectDnsEntry(builder, (JSONObject) serverEntry);
            } else {
                Log.w("DNS Config", "Unsupported DNS entry type: " + serverEntry.getClass().getSimpleName());
            }
        } catch (Exception e) {
            Log.e("DNS Config", "Error processing DNS entry: " + serverEntry, e);
        }
    }

    /**
     * 处理字符串类型DNS条目
     */
    private void handleStringDnsEntry(Builder builder, String entry) {
        String cleanedIp = entry.split(":")[0]; // 处理带端口的情况如"1.1.1.1:53"
        if (isValidIpAddress(cleanedIp)) {
            builder.addDnsServer(cleanedIp);
            Log.d("DNS Config", "Added simple DNS: " + cleanedIp);
        } else {
            Log.w("DNS Config", "Invalid IP format: " + entry);
        }
    }

    /**
     * 处理对象类型DNS条目
     */
    private void handleObjectDnsEntry(Builder builder, JSONObject entry) {
        try {
            String address = entry.getString("address");
            String cleanedIp = address.split(":")[0]; // 提取IP部分

            if (isValidIpAddress(cleanedIp)) {
                builder.addDnsServer(cleanedIp);
                Log.d("DNS Config", "Added object DNS: " + cleanedIp);

                // 可选：记录高级参数（实际VPN层不处理这些）
                if (entry.has("port")) {
                    Log.d("DNS Config", "DNS port config detected (handled by v2ray core): " + entry.getInt("port"));
                }
            } else {
                Log.w("DNS Config", "Invalid IP in DNS object: " + entry);
            }
        } catch (JSONException e) {
            Log.w("DNS Config", "Malformed DNS object: " + entry, e);
        }
    }

    /**
     * IP地址验证（兼容IPv4/IPv6）
     */
    private boolean isValidIpAddress(String ip) {
        if (ip == null || ip.isEmpty()) return false;

        // 使用AndroidX核心工具验证
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            return InetAddresses.isNumericAddress(ip);
        }
        return false;
    }

    private void runTun2socks() {
        ArrayList<String> cmd = new ArrayList<>(Arrays.asList(new File(getApplicationInfo().nativeLibraryDir, "libtun2socks.so").getAbsolutePath(),
                "--netif-ipaddr", "26.26.26.2",
                "--netif-netmask", "255.255.255.252",
                "--socks-server-addr", "127.0.0.1:" + v2rayConfig.LOCAL_SOCKS5_PORT,
                "--tunmtu", "1500",
                "--sock-path", "sock_path",
                "--enable-udprelay",
                "--loglevel", "error"));
        try {
            ProcessBuilder processBuilder = new ProcessBuilder(cmd);
            processBuilder.redirectErrorStream(true);
            process = processBuilder.directory(getApplicationContext().getFilesDir()).start();
            new Thread(() -> {
                try {
                    process.waitFor();
                    if (isRunning) {
                        runTun2socks();
                    }
                } catch (InterruptedException e) {
                    //ignore
                }
            }, "Tun2socks_Thread").start();
            sendFileDescriptor();
        } catch (Exception e) {
            Log.e("VPN_SERVICE", "FAILED=>", e);
            this.onDestroy();
        }
    }

    private void sendFileDescriptor() {
        String localSocksFile = new File(getApplicationContext().getFilesDir(), "sock_path").getAbsolutePath();
        FileDescriptor tunFd = mInterface.getFileDescriptor();
        new Thread(() -> {
            int tries = 0;
            long initialDelay = 100L;
            while (true) {
                try {
                    Thread.sleep(initialDelay * (1 << tries)); // 指数退避
                    LocalSocket clientLocalSocket = new LocalSocket();
                    clientLocalSocket.connect(new LocalSocketAddress(localSocksFile, LocalSocketAddress.Namespace.FILESYSTEM));
                    if (!clientLocalSocket.isConnected()) {
                        Log.e("SOCK_FILE", "Unable to connect to localSocksFile [" + localSocksFile + "]");
                    } else {
                        Log.e("SOCK_FILE", "connected to sock file [" + localSocksFile + "]");
                    }
                    OutputStream clientOutStream = clientLocalSocket.getOutputStream();
                    clientLocalSocket.setFileDescriptorsForSend(new FileDescriptor[]{tunFd});
                    clientOutStream.write(32);
                    clientLocalSocket.setFileDescriptorsForSend(null);
                    clientLocalSocket.shutdownOutput();
                    clientLocalSocket.close();
                    break;
                } catch (Exception e) {
                    Log.e(V2rayVPNService.class.getSimpleName(), "sendFd failed =>", e);
                    if (tries > 5) break;
                    tries += 1;
                }
            }
        }, "sendFd_Thread").start();
    }

    @Override
    public void onDestroy() {
        super.onDestroy();
    }

    @Override
    public void onRevoke() {
        stopAllProcess();
    }

    @Override
    public boolean onProtect(int socket) {
        return protect(socket);
    }

    @Override
    public Service getService() {
        return this;
    }

    @Override
    public void startService() {
        setup();
    }

    @Override
    public void stopService() {
        stopAllProcess();
    }

    private void createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationChannel channel = new NotificationChannel(
                    NOTIFICATION_CHANNEL_ID, // 渠道ID
                    "VPN Service",          // 渠道名称
                    NotificationManager.IMPORTANCE_LOW // 低优先级
            );
            channel.setDescription("VPN background service");
            channel.setShowBadge(false); // 不显示角标
            NotificationManager nm = getSystemService(NotificationManager.class);
            nm.createNotificationChannel(channel);
        }
    }

    private Notification createNotification() {
        // 创建一个 Intent，指向 Flutter 的主 Activity
        Intent intent = new Intent(this, io.flutter.embedding.android.FlutterActivity.class);
        // 创建 PendingIntent
        PendingIntent pendingIntent = PendingIntent.getActivity(
                this,
                0,
                intent,
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.S ? PendingIntent.FLAG_IMMUTABLE : 0
        );

        // 创建通知
        return new NotificationCompat.Builder(this, NOTIFICATION_CHANNEL_ID)
                .setSmallIcon(android.R.drawable.ic_dialog_info) // 使用系统默认图标
                .setContentTitle("VPN 已连接")                  // 静态标题
                .setContentText("流量受保护")                    // 移除动态IP/Port
                .setPriority(NotificationCompat.PRIORITY_MIN)   // 最低优先级
                .setOngoing(true)                               // 用户无法手动清除
                .setVisibility(NotificationCompat.VISIBILITY_PRIVATE) // 完全隐藏内容
                .setContentIntent(pendingIntent)
                .setShowWhen(false)                             // 隐藏时间戳
                .setCategory(Notification.CATEGORY_SERVICE)     // 归类为系统服务
                .build();
    }
}