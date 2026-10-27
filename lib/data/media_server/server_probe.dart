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
