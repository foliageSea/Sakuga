import '../media_server/server_probe.dart';

String embyApiBaseUrl(String rawUrl) {
  final uri = Uri.parse(normalizeBaseUrl(rawUrl));
  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  while (segments.isNotEmpty && segments.last.toLowerCase() == 'emby') {
    segments.removeLast();
  }
  return Uri(
    scheme: uri.scheme,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    pathSegments: [...segments, 'emby'],
  ).toString();
}

Map<String, String> embyAuthHeaders({
  String accessToken = '',
  String deviceId = 'sakuga',
}) {
  String quote(String value) =>
      value.replaceAll(RegExp(r'[\x00-\x1f\x7f"\\]'), '_');
  return {
    'X-Emby-Authorization':
        'Emby Client="Sakuga", Device="Sakuga", DeviceId="${quote(deviceId)}", Version="0.1.0"',
    if (accessToken.isNotEmpty) 'X-Emby-Token': accessToken,
  };
}

bool embySameOrigin(String baseUrl, String url) {
  final base = Uri.parse(baseUrl);
  final target = Uri.parse(url);
  return base.scheme == target.scheme &&
      base.host == target.host &&
      base.port == target.port;
}

/// Keep reverse proxy prefixes and consume a server-provided /emby prefix once.
String resolveEmbyUrl(String baseUrl, String path) {
  final base = Uri.parse(embyApiBaseUrl(baseUrl));
  final target = Uri.parse(path);
  if (target.hasScheme) {
    if (target.scheme != 'https' && target.scheme != 'http') {
      throw const FormatException('Unsupported media URL scheme');
    }
    return path;
  }
  if (target.hasAuthority) {
    return target.replace(scheme: base.scheme).toString();
  }
  final basePath = base.path.replaceFirst(RegExp(r'/+$'), '');
  final proxyPath = basePath.substring(0, basePath.length - '/emby'.length);
  var relative = target.path.replaceFirst(RegExp(r'^/+'), '');
  String result;
  if (target.path == basePath || target.path.startsWith('$basePath/')) {
    result = target.path;
  } else if (relative.toLowerCase().startsWith('emby/')) {
    while (relative.toLowerCase().startsWith('emby/')) {
      relative = relative.substring(5);
    }
    result = '$proxyPath/emby/$relative';
  } else {
    result = '$basePath/$relative';
  }
  return base
      .replace(
        path: result,
        query: target.hasQuery ? target.query : null,
        fragment: target.hasFragment ? target.fragment : null,
      )
      .toString();
}
