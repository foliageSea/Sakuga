import 'dart:convert';
import 'dart:typed_data';

import '../ugreen/ugreen_transport.dart';
import 'server_profile.dart';

const serverConfigMaxBytes = 1024 * 1024;

class ServerConfig {
  static const _format = 'sakuga-server-config';
  static const _version = 1;

  static Uint8List encode(
    List<ServerProfile> servers, {
    required bool includeCredentials,
  }) {
    final bytes = utf8.encode(
      const JsonEncoder.withIndent('  ').convert({
        'format': _format,
        'version': _version,
        'servers': [
          for (final server in servers)
            {
              'name': server.name,
              'type': server.type.name,
              'baseUrl': _baseUrl(server.baseUrl, server.type),
              if (server.usesAccount) ...{
                'username': server.username,
                if (server.type != MediaServerType.fnmovie)
                  'userId': server.userId,
                if (includeCredentials) ...{
                  'accessToken': server.accessToken,
                  'deviceId': server.deviceId,
                  'remoteServerId': server.remoteServerId,
                },
              } else if (includeCredentials)
                'apiKey': server.apiKey,
              if (server.type == MediaServerType.ugreen &&
                  server.certificateFingerprint.isNotEmpty)
                'certificateFingerprint': server.certificateFingerprint,
            },
        ],
      }),
    );
    if (bytes.length > serverConfigMaxBytes) throw const FormatException();
    return bytes;
  }

  static List<ServerProfile> decode(Uint8List bytes) {
    if (bytes.length > serverConfigMaxBytes) throw const FormatException();
    final document = jsonDecode(utf8.decode(bytes));
    if (document is! Map<String, dynamic> ||
        document['format'] != _format ||
        document['version'] is! int ||
        document['version'] != _version ||
        document['servers'] is! List) {
      throw const FormatException();
    }
    return (document['servers'] as List).map(_decodeServer).toList();
  }

  static ServerProfile _decodeServer(Object? entry) {
    if (entry is! Map<String, dynamic>) throw const FormatException();
    String read(String key, {bool required = false}) {
      if (!required && !entry.containsKey(key)) return '';
      final value = entry[key];
      if (value is! String || (required && value.trim().isEmpty)) {
        throw const FormatException();
      }
      return value;
    }

    final typeName = read('type', required: true);
    final type = MediaServerType.values
        .where((value) => value.name == typeName)
        .firstOrNull;
    if (type == null) throw const FormatException();
    final server = ServerProfile(
      id: '',
      name: read('name', required: true).trim(),
      baseUrl: _baseUrl(read('baseUrl', required: true), type),
      type: type,
      apiKey: read('apiKey'),
      accessToken: read('accessToken'),
      username: read('username').trim(),
      userId: read('userId'),
      deviceId: read('deviceId'),
      remoteServerId: read('remoteServerId'),
      certificateFingerprint: type == MediaServerType.ugreen
          ? normalizeUgreenFingerprint(read('certificateFingerprint'))
          : '',
    );
    if (server.usesAccount && server.apiKey.isNotEmpty) {
      throw const FormatException();
    }
    return server;
  }

  static String _baseUrl(String value, MediaServerType type) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty ||
        uri.authority.contains('@') ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.port < 1 ||
        uri.port > 65535) {
      throw const FormatException();
    }
    return type == MediaServerType.ugreen
        ? normalizeUgreenBaseUrl(value)
        : uri.toString().replaceFirst(RegExp(r'/+$'), '');
  }
}

typedef ServerConfigMerge = ({
  List<ServerProfile> added,
  List<ServerProfile> skipped,
});

ServerConfigMerge previewServerConfigMerge(
  List<ServerProfile> current,
  List<ServerProfile> incoming,
) {
  ({MediaServerType type, String url, bool account, String username}) identity(
    ServerProfile server,
  ) {
    var url = server.baseUrl;
    try {
      url = ServerConfig._baseUrl(url, server.type);
    } on FormatException {
      // Older local profiles may not meet the backup format's URL rules.
    }
    return (
      type: server.type,
      url: url,
      account: server.usesAccount,
      username: server.username.trim(),
    );
  }

  final seen = current.map(identity).toSet();
  final added = <ServerProfile>[];
  final skipped = <ServerProfile>[];
  for (final server in incoming) {
    (seen.add(identity(server)) ? added : skipped).add(server);
  }
  return (added: added, skipped: skipped);
}
