import 'dart:io';

import 'package:flutter_v2ray/flutter_v2ray.dart';

/// Creates Android example-ready JSON configurations for two share links.
///
/// Usage:
///   dart run tool/multi_outbound_smoke.dart /path/to/nodes.txt
///
/// nodes.txt contains exactly two share links, one per line. The links and
/// generated configurations are never uploaded or embedded in this tool.
void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln('Usage: dart run tool/multi_outbound_smoke.dart nodes.txt');
    exitCode = 64;
    return;
  }

  try {
    final inputFile = File(args.single);
    if (!inputFile.existsSync()) {
      throw const FormatException('Input file does not exist');
    }
    final links = inputFile
        .readAsLinesSync()
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    if (links.length != 2) {
      throw const FormatException(
          'Expected exactly two share links, one per line');
    }

    final servers = links.map(FlutterV2ray.parseFromURL).toList();
    final directory = Directory('build/multi_outbound_smoke')
      ..createSync(recursive: true);

    for (final target in ['server-a', 'server-b', 'round-robin']) {
      final builder = V2RayConfigBuilder.fromUrls(
        servers,
        tags: ['server-a', 'server-b'],
      );
      if (target == 'round-robin') {
        builder
          ..addBalancer(
            tag: 'auto',
            selector: ['server-'],
            strategy: 'roundRobin',
          )
          ..route(
            inboundTags: ['in_proxy'],
            balancerTag: 'auto',
          );
      } else {
        builder.route(
          inboundTags: ['in_proxy'],
          outboundTag: target,
        );
      }

      // Makes selected outbound tags visible in Xray routing logcat output.
      builder.setSection('log', {'loglevel': 'info'});

      final file = File('${directory.path}/$target.json');
      file.writeAsStringSync(builder.buildJson());
      stdout.writeln('Generated ${file.path}');
    }
    stdout.writeln('Use one JSON at a time in the example app.');
    stdout.writeln('Do NOT commit or share the generated JSON: it contains');
    stdout.writeln('the original VLESS credentials from nodes.txt.');
  } on Object catch (error) {
    stderr.writeln('Unable to generate smoke configs: $error');
    exitCode = 1;
  }
}
