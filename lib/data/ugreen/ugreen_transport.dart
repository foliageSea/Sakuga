import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';

final _hexFingerprint = RegExp(r'^[a-fA-F0-9]{64}$');
final _colonFingerprint = RegExp(r'^(?:[a-fA-F0-9]{2}:){31}[a-fA-F0-9]{2}$');
final _authority = RegExp(
  r'^(\[[0-9a-fA-F:.]+\]|[a-zA-Z0-9._-]+)(?::([0-9]{1,5}))?/?$',
);
final _dnsLabel = RegExp(r'^[a-zA-Z0-9](?:[a-zA-Z0-9_-]{0,61}[a-zA-Z0-9])?$');

/// Parses a SHA-256 leaf certificate fingerprint. Empty means system trust.
String normalizeUgreenFingerprint(String value) {
  final input = value.trim();
  if (input.isEmpty) return '';
  if (!_hexFingerprint.hasMatch(input) && !_colonFingerprint.hasMatch(input)) {
    throw const FormatException(
      'Invalid Ugreen SHA-256 certificate fingerprint',
    );
  }
  return input.replaceAll(':', '').toLowerCase();
}

/// Accepts an HTTPS root URL or host[:port] shorthand, with a default of 9443.
String normalizeUgreenBaseUrl(String value) {
  var input = value.trim();
  if (input.toLowerCase().startsWith('https://')) input = input.substring(8);
  final match = _authority.firstMatch(input);
  if (match == null) {
    throw const FormatException('Invalid Ugreen HTTPS base URL');
  }
  final host = match[1]!.toLowerCase();
  final port = match[2] == null ? 9443 : int.parse(match[2]!);
  var validHost = false;
  if (host.startsWith('[')) {
    final address = InternetAddress.tryParse(
      host.substring(1, host.length - 1),
    );
    validHost = address?.type == InternetAddressType.IPv6;
  } else {
    final labels = host.endsWith('.')
        ? host.substring(0, host.length - 1)
        : host;
    validHost =
        labels.length <= 253 && labels.split('.').every(_dnsLabel.hasMatch);
  }
  if (!validHost || port < 1 || port > 65535) {
    throw const FormatException('Invalid Ugreen HTTPS base URL');
  }
  // Uri.toString() omits the default HTTPS port, but the profile retains it.
  return 'https://$host:$port';
}

/// Reads the presented leaf's SHA-256 fingerprint without sending app data.
///
/// The result is not an identity check: verify it independently before pinning.
Future<String> fetchUgreenCertificateFingerprint(String baseUrl) async {
  final endpoint = Uri.parse(normalizeUgreenBaseUrl(baseUrl));
  const timeout = Duration(seconds: 5);
  final tcp = await RawSocket.connect(
    endpoint.host,
    endpoint.port,
    timeout: timeout,
  );
  RawSecureSocket? tls;
  try {
    tls = await RawSecureSocket.secure(
      tcp,
      host: endpoint.host,
      context: SecurityContext(withTrustedRoots: false),
      onBadCertificate: (_) => true,
    ).timeout(timeout);
    final certificate = tls.peerCertificate;
    if (certificate == null) {
      throw const HandshakeException(
        'Ugreen server did not present a certificate',
      );
    }
    return sha256.convert(certificate.der).toString();
  } finally {
    // Keep the underlying TCP socket so a stalled TLS handshake can be aborted.
    await (tls ?? tcp).close();
  }
}

void requireUgreenOrigin(Uri base, Uri target) {
  if (target.scheme != 'https' ||
      !target.hasAuthority ||
      target.host != base.host ||
      target.port != base.port ||
      target.authority.contains('@') ||
      target.hasFragment) {
    throw const FormatException('Invalid Ugreen request origin');
  }
}

/// For resource requests, never return a Location header to the local consumer.
/// Instead, resolve bounded redirects and validate the destination before use.
Uri? ugreenRedirectTarget(Uri base, Uri from, HttpClientResponse response) {
  switch (response.statusCode) {
    case HttpStatus.movedPermanently:
    case HttpStatus.found:
    case HttpStatus.seeOther:
    case HttpStatus.temporaryRedirect:
    case HttpStatus.permanentRedirect:
      final location = response.headers.value(HttpHeaders.locationHeader);
      if (location == null || location.isEmpty) {
        throw const FormatException('Invalid Ugreen resource redirect');
      }
      final target = from.resolve(location);
      requireUgreenOrigin(base, target);
      return target;
    default:
      return null;
  }
}

/// Restricts every direct request and native redirect to the configured origin.
///
/// A configured pin replaces normal trust, rather than allowing a publicly
/// trusted but differently pinned certificate to bypass the check. An empty
/// trust store forces the leaf check during TLS, before sending HTTP secrets.
HttpClient createUgreenHttpClient(String baseUrl, String fingerprint) {
  final base = Uri.parse(normalizeUgreenBaseUrl(baseUrl));
  final pin = normalizeUgreenFingerprint(fingerprint);
  final client = HttpClient();
  client.findProxy = (target) {
    requireUgreenOrigin(base, target);
    return 'DIRECT';
  };
  if (pin.isNotEmpty) {
    final context = SecurityContext(withTrustedRoots: false);
    bool matches(X509Certificate? cert) =>
        cert != null && sha256.convert(cert.der).toString() == pin;
    client.connectionFactory = (target, proxyHost, proxyPort) async {
      requireUgreenOrigin(base, target);
      if (proxyHost != null || proxyPort != null) {
        throw const FormatException(
          'Ugreen HTTPS requires a direct connection',
        );
      }
      final task = await SecureSocket.startConnect(
        target.host,
        target.port,
        context: context,
        onBadCertificate: matches,
      );
      return ConnectionTask.fromSocket(
        task.socket.then((socket) {
          // Check the leaf before delivering the socket to HttpClient, even if the
          // native TLS stack accepted a certificate without invoking the callback.
          if (!matches(socket.peerCertificate)) {
            socket.destroy();
            throw const HandshakeException(
              'Ugreen certificate fingerprint mismatch',
            );
          }
          return socket;
        }),
        task.cancel,
      );
    };
  }
  return client;
}

Dio createUgreenDio(String baseUrl, String fingerprint) {
  final base = normalizeUgreenBaseUrl(baseUrl);
  final pin = normalizeUgreenFingerprint(fingerprint);
  return Dio(BaseOptions(baseUrl: base, followRedirects: false))
    ..httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () => createUgreenHttpClient(base, pin),
    );
}

const ugreenArtworkOriginHeader = 'x-sakuga-ugreen-origin';
const ugreenArtworkFingerprintHeader = 'x-sakuga-ugreen-fingerprint';
const ugreenArtworkProfileHeader = 'x-sakuga-ugreen-profile';
const ugreenArtworkTokenHeader = 'x-sakuga-ugreen-token';

/// Local routing metadata for the artwork cache, not wire headers.
Map<String, String> ugreenArtworkHeaders({
  required String baseUrl,
  required String fingerprint,
  required String profileId,
  required String token,
}) => {
  ugreenArtworkOriginHeader: normalizeUgreenBaseUrl(baseUrl),
  ugreenArtworkFingerprintHeader: normalizeUgreenFingerprint(fingerprint),
  ugreenArtworkProfileHeader: profileId,
  ugreenArtworkTokenHeader: token,
};
