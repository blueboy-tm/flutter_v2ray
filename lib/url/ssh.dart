import 'dart:convert';

class SSHURL {
  SSHURL({required this.url}) {
    if (!url.startsWith('ssh://')) {
      throw ArgumentError('URL is invalid');
    }
    final temp = Uri.tryParse(url);
    if (temp == null) {
      throw ArgumentError('URL is invalid');
    }
    uri = temp;

    if (uri.userInfo.isNotEmpty) {
      final userpass = utf8.decode(base64Decode(uri.userInfo));
      username = userpass.split(':')[0];
      password = userpass.substring(username!.length + 1);
    } else {
      username = null;
      password = null;
    }
  }

  late final String? username;
  late final String? password;
  late final Uri uri;

  String get address => uri.host;

  int get port => uri.hasPort ? uri.port : 22; // Default SSH port is 22

  String get remark => Uri.decodeFull(uri.fragment.replaceAll('+', '%20'));

  Map<String, dynamic> get config => {
        "protocol": "ssh",
        "settings": {
          "servers": [
            {
              "address": address,
              "port": port,
              "username": username,
              "password": password,
              "remark": remark,
            }
          ]
        },
      };
}
