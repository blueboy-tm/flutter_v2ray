import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_v2ray/flutter_v2ray.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter V2Ray',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
      ),
      home: const Scaffold(
        body: HomePage(),
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final FlutterV2ray flutterV2ray = FlutterV2ray(
    onStatusChanged: (status) {
      v2rayStatus.value = status;
    },
  );
  final config = TextEditingController();
  bool proxyOnly = false;
  var v2rayStatus = ValueNotifier<V2RayStatus>(V2RayStatus());

  String remark = "Default Remark";

  @override
  void initState() {
    super.initState();
    flutterV2ray.initializeV2Ray();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 5),
            const Text(
              'V2Ray Config (json):',
              style: TextStyle(
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 5),
            TextFormField(
              controller: config,
              maxLines: 10,
              minLines: 10,
            ),
            const SizedBox(height: 10),
            ValueListenableBuilder(
              valueListenable: v2rayStatus,
              builder: (context, value, child) {
                return Column(
                  children: [
                    Text(value.state),
                    const SizedBox(height: 10),
                    Text(value.duration),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('Speed:'),
                        const SizedBox(width: 10),
                        Text(value.uploadSpeed),
                        const Text('↑'),
                        const SizedBox(width: 10),
                        Text(value.downloadSpeed),
                        const Text('↓'),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('Traffic:'),
                        const SizedBox(width: 10),
                        Text(value.upload),
                        const Text('↑'),
                        const SizedBox(width: 10),
                        Text(value.download),
                        const Text('↓'),
                      ],
                    )
                  ],
                );
              },
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.all(5.0),
              child: Wrap(
                spacing: 5,
                runSpacing: 5,
                children: [
                  ElevatedButton(
                    onPressed: () async {
                      if (await flutterV2ray.requestPermission()) {
                        flutterV2ray.startV2Ray(
                          remark: remark,
                          config: config.text,
                          proxyOnly: proxyOnly,
                        );
                      } else {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Permission Denied'),
                            ),
                          );
                        }
                      }
                    },
                    child: const Text('Connect'),
                  ),
                  ElevatedButton(
                    onPressed: () => flutterV2ray.stopV2Ray(),
                    child: const Text('Disconnect'),
                  ),
                  ElevatedButton(
                    onPressed: () => setState(() => proxyOnly = !proxyOnly),
                    child: Text(proxyOnly ? 'Proxy Only' : 'VPN Mode'),
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      if (await Clipboard.hasStrings()) {
                        try {
                          final String link =
                              (await Clipboard.getData('text/plain'))
                                      ?.text
                                      ?.trim() ??
                                  '';
                          final V2RayURL v2rayURL =
                              FlutterV2ray.parseFromURL(link);
                          remark = v2rayURL.remark;
                          config.text = v2rayURL.getFullConfiguration();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Success',
                                ),
                              ),
                            );
                          }
                        } catch (error) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Error: $error',
                                ),
                              ),
                            );
                          }
                        }
                      }
                    },
                    child: const Text(
                      'Import from v2ray share link (clipboard)',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
