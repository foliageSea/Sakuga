class ServerProbeResult {
  const ServerProbeResult({
    required this.name,
    required this.version,
    required this.id,
  });
  final String name;
  final String version;
  final String id;
}

abstract interface class ServerProbe {
  Future<ServerProbeResult> probe(String rawUrl, {String apiKey = ''});
}

String normalizeBaseUrl(String input) {
  var value = input.trim();
  if (value.isEmpty) throw const FormatException('empty URL');
  if (!value.startsWith('http://') && !value.startsWith('https://')) {
    value = 'http://$value';
  }
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.host.isEmpty ||
      (uri.scheme != 'http' && uri.scheme != 'https')) {
    throw const FormatException('invalid URL');
  }
  return value.replaceAll(RegExp(r'/+$'), '');
}

/// Resolves [input] (an IP, domain, or bare address) into a full base URL.
///
/// An explicit `http(s)://` prefix typed into [input] is respected so pasted
/// URLs keep working; otherwise [secure] decides between HTTPS and HTTP.
String composeBaseUrl(String input, {required bool secure}) {
  final value = input.trim();
  if (value.startsWith('http://') || value.startsWith('https://')) {
    return normalizeBaseUrl(value);
  }
  return normalizeBaseUrl('${secure ? 'https' : 'http'}://$value');
}

/// Hides the scheme of [baseUrl] so the editor can show only host and port.
String stripBaseUrlScheme(String baseUrl) =>
    baseUrl.trim().replaceFirst(RegExp(r'^[a-zA-Z][a-zA-Z0-9+.\-]*://'), '');

bool isSecureBaseUrl(String baseUrl) =>
    baseUrl.trim().toLowerCase().startsWith('https://');
