package com.github.blueboytm.flutter_v2ray.v2ray.services;

import android.app.Service;
import android.content.Intent;
import android.content.IntentFilter;
import android.net.LocalSocket;
import android.net.LocalSocketAddress;
import android.net.VpnService;
import android.os.Build;
import android.os.ParcelFileDescriptor;
import android.util.Log;

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
import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.util.ArrayList;
import java.util.Arrays;

public class V2rayVPNService extends VpnService implements V2rayServicesListener {
    private V2rayDelayReceiver delayReceiver;

    private ParcelFileDescriptor mInterface;
    private Process process;
    private V2rayConfig v2rayConfig;
    private volatile boolean isRunning = false;
    private volatile boolean tunProcessStarted = false;
    private boolean stoppingAllProcesses = false;
    private static final String TAG = "VPN_SERVICE";

    @Override
    public void onCreate() {
        super.onCreate();
        V2rayCoreManager.getInstance().setUpListener(this);
        delayReceiver = new V2rayDelayReceiver(AppConfigs.V2RAY_CONNECTION_MODES.VPN_TUN);
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
            Log.w("VPN_SERVICE", "Ignoring service restart with null Intent");
            stopSelfResult(startId);
            return START_NOT_STICKY;
        }
        AppConfigs.V2RAY_SERVICE_COMMANDS startCommand =
                (AppConfigs.V2RAY_SERVICE_COMMANDS) intent.getSerializableExtra("COMMAND");
        if (startCommand == null) {
            Log.w("VPN_SERVICE", "Ignoring missing service command");
            stopSelfResult(startId);
            return START_NOT_STICKY;
        }
        if (startCommand == AppConfigs.V2RAY_SERVICE_COMMANDS.START_SERVICE) {
            v2rayConfig = (V2rayConfig) intent.getSerializableExtra("V2RAY_CONFIG");
            if (v2rayConfig == null) {
                Log.e(TAG, "Missing V2Ray configuration");
                stopSelfResult(startId);
                return START_NOT_STICKY;
            }
            if (V2rayCoreManager.getInstance().isV2rayCoreRunning()) {
                // Android can redeliver START_SERVICE or Flutter can issue a
                // duplicate request. Never tear down the service while starting.
                Log.i("VPN_SERVICE", "Core already running; ignoring duplicate start");
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
                Log.i("V2RAY_DELAY", "VPN service measure delay url=" + url);
                Intent sendB = new Intent("CONNECTED_V2RAY_SERVER_DELAY");
                sendB.setPackage(getPackageName());
                sendB.putExtra("DELAY", String.valueOf(V2rayCoreManager.getInstance().getConnectedV2rayServerDelay(url)));
                sendBroadcast(sendB);
            }, "MEASURE_CONNECTED_V2RAY_SERVER_DELAY").start();
        } else {
            Log.w("VPN_SERVICE", "Unknown service command: " + startCommand);
            return START_NOT_STICKY;
        }
        return START_NOT_STICKY;
    }

    private synchronized void stopAllProcess() {
        if (stoppingAllProcesses) return;
        stoppingAllProcesses = true;
        Log.i(TAG, "Stopping VPN: closing TUN and tun2socks before native core");

        // Revoke the actual Android VPN immediately. Calling stopLoop() first
        // can block for pending native delay requests, leaving the VPN icon and
        // interface active long after the user pressed Disconnect.
        isRunning = false;
        tunProcessStarted = false;
        if (process != null) {
            process.destroy();
            process = null;
        }
        if (mInterface != null) {
            try {
                mInterface.close();
            } catch (Exception e) {
                Log.w(TAG, "Failed to close TUN interface", e);
            } finally {
                mInterface = null;
            }
        }
        stopForeground(true);
        stopSelf();

        // Do not block the Android service main thread inside Go stopLoop().
        // The next session waits for DAEMON_STOPPED after cleanup completes.
        new Thread(() -> {
            try {
                V2rayCoreManager manager = V2rayCoreManager.getInstance();
                if (manager.v2rayServicesListener == V2rayVPNService.this) {
                    manager.stopCore();
                }
            } catch (Exception e) {
                Log.e(TAG, "Native core stop failed", e);
            } finally {
                Log.i(TAG, "VPN cleanup finished; reporting daemon stopped");
                com.github.blueboytm.flutter_v2ray.v2ray.V2rayConnectionCoordinator.notifyDaemonStopped(
                        getApplicationContext(),
                        com.github.blueboytm.flutter_v2ray.v2ray.V2rayConnectionCoordinator.DAEMON_VPN);
            }
        }, "V2Ray_VpnShutdown").start();
    }

    private void setup() {
        Intent prepare_intent = prepare(this);
        if (prepare_intent != null) {
            return;
        }
        Builder builder = new Builder();
        builder.setSession(v2rayConfig.REMARK);
        builder.setMtu(1500);
        builder.addAddress("26.26.26.1", 30);

        // Xray's Go sockets must use the underlying network rather than
        // entering our own VPN tunnel, which otherwise creates a routing loop.
        // This also excludes the host application's own traffic from the VPN.
        try {
            builder.addDisallowedApplication(getPackageName());
            Log.i("VPN_SERVICE", "Excluded host package from VPN routes: " + getPackageName());
        } catch (android.content.pm.PackageManager.NameNotFoundException e) {
            Log.e("VPN_SERVICE", "Unable to exclude host app from VPN", e);
        }

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
                String server = serversArray.getString(i);
                builder.addDnsServer(server);
            }
        } catch (JSONException e) {
            e.printStackTrace();
        }
        try {
            mInterface.close();
        } catch (Exception e) {
            //ignore
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            builder.setMetered(false);
        }

        try {
            mInterface = builder.establish();
            if (mInterface == null) {
                Log.e("VPN_SERVICE", "VpnService.Builder.establish returned null");
                stopAllProcess();
                return;
            }
            Log.i("VPN_SERVICE", "TUN established, fd=" + mInterface.getFd()
                    + ", socksPort=" + v2rayConfig.LOCAL_SOCKS5_PORT);
            isRunning = true;
            runTun2socks();
        } catch (Exception e) {
            stopAllProcess();
        }

    }

    private void runTun2socks() {
        if (tunProcessStarted) {
            Log.w(TAG, "tun2socks start already requested");
            return;
        }
        tunProcessStarted = true;

        final File executable = new File(getApplicationInfo().nativeLibraryDir, "libtun2socks.so");
        Log.i(TAG, "tun2socks executable=" + executable +
                ", exists=" + executable.exists() +
                ", executable=" + executable.canExecute() +
                ", bytes=" + executable.length());

        if (!executable.isFile() || !executable.canExecute()) {
            Log.e(TAG, "tun2socks binary is not an extracted executable");
            stopAllProcess();
            return;
        }

        ArrayList<String> cmd = new ArrayList<>(Arrays.asList(executable.getAbsolutePath(),
                "--netif-ipaddr", "26.26.26.2",
                "--netif-netmask", "255.255.255.252",
                "--socks-server-addr", "127.0.0.1:" + v2rayConfig.LOCAL_SOCKS5_PORT,
                "--tunmtu", "1500",
                "--sock-path", "sock_path",
                "--enable-udprelay",
                "--loglevel", "error"));
        try {
            ProcessBuilder pb = new ProcessBuilder(cmd);
            pb.directory(getApplicationContext().getFilesDir());
            pb.redirectErrorStream(true);
            final Process startedProcess = pb.start();
            process = startedProcess;

            // One supervisor per VPN session. Never recursively restart a rapidly
            // exiting binary: that used to create hundreds of threads in seconds.
            new Thread(() -> {
                try (BufferedReader reader = new BufferedReader(
                        new InputStreamReader(startedProcess.getInputStream()))) {
                    String line;
                    while ((line = reader.readLine()) != null) {
                        Log.i(TAG, "tun2socks: " + line);
                    }
                } catch (Exception e) {
                    Log.w(TAG, "Failed to read tun2socks output", e);
                }
            }, "Tun2socks_Output").start();

            new Thread(() -> {
                try {
                    int exitCode = startedProcess.waitFor();
                    Log.e(TAG, "tun2socks exited with code=" + exitCode);
                    if (isRunning && process == startedProcess) {
                        stopAllProcess();
                    }
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                }
            }, "Tun2socks_Wait").start();

            sendFileDescriptor();
        } catch (Exception e) {
            Log.e(TAG, "Failed to launch tun2socks", e);
            stopAllProcess();
        }
    }

    private void sendFileDescriptor() {
        final String socketPath = new File(getApplicationContext().getFilesDir(),
                "sock_path").getAbsolutePath();
        final FileDescriptor tunFd = mInterface.getFileDescriptor();
        new Thread(() -> {
            for (int attempt = 0; attempt < 20 && isRunning; attempt++) {
                try (LocalSocket socket = new LocalSocket()) {
                    socket.connect(new LocalSocketAddress(
                            socketPath, LocalSocketAddress.Namespace.FILESYSTEM));
                    socket.setFileDescriptorsForSend(new FileDescriptor[]{tunFd});
                    socket.getOutputStream().write(32);
                    socket.getOutputStream().flush();
                    socket.setFileDescriptorsForSend(null);
                    Log.i(TAG, "TUN file descriptor delivered to tun2socks");
                    return;
                } catch (Exception e) {
                    if (attempt == 19) {
                        Log.e(TAG, "Unable to send TUN fd after 20 attempts", e);
                        if (isRunning) stopAllProcess();
                        return;
                    }
                    try {
                        Thread.sleep(100);
                    } catch (InterruptedException interrupted) {
                        Thread.currentThread().interrupt();
                        return;
                    }
                }
            }
        }, "Tun2socks_SendFd").start();
    }

    @Override
    public void onDestroy() {
        // No Go stopLoop() on the Android main thread.
        stopAllProcess();
        if (delayReceiver != null) {
            unregisterReceiver(delayReceiver);
            delayReceiver = null;
        }
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
}
