import 'shadowsocks.dart';
import 'socks.dart';
import 'trojan.dart';
import 'url.dart';
import 'vless.dart';
import 'vmess.dart';

/// Parse a V2Ray share link without importing the Flutter platform API.
///
/// This utility is safe to use from a plain `dart run` command-line tool,
/// since it only depends on Dart libraries and the URL models.
V2RayURL parseV2RayURL(String url) {
  final value = url.trim();
  final schemeEnd = value.indexOf('://');
  if (schemeEnd <= 0) {
    throw ArgumentError('url is invalid');
  }
  switch (value.substring(0, schemeEnd).toLowerCase()) {
    case 'vmess':
      return VmessURL(url: value);
    case 'vless':
      return VlessURL(url: value);
    case 'trojan':
      return TrojanURL(url: value);
    case 'ss':
      return ShadowSocksURL(url: value);
    case 'socks':
      return SocksURL(url: value);
    default:
      throw ArgumentError('url is invalid');
  }
}
