import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakuga/core/images/artwork_cache.dart';
import 'package:sakuga/data/ugreen/ugreen_playback_proxy.dart';
import 'package:sakuga/data/ugreen/ugreen_transport.dart';

void main() {
  test('normalizes SHA-256 fingerprints and rejects malformed input', () {
    expect(normalizeUgreenFingerprint('  '), '');
    expect(
      normalizeUgreenFingerprint(List.filled(32, 'A1').join(':')),
      'a1' * 32,
    );
    expect(normalizeUgreenFingerprint('F' * 64), 'f' * 64);
    for (final value in ['AB', 'X' * 64, ':${'a' * 64}', 'a' * 65]) {
      expect(() => normalizeUgreenFingerprint(value), throwsFormatException);
    }
  });

  test('normalizes Ugreen HTTPS root URLs and refuses ambiguous origins', () {
    expect(normalizeUgreenBaseUrl(' NAS.local '), 'https://nas.local:9443');
    expect(
      normalizeUgreenBaseUrl('HTTPS://NAS.local:443/'),
      'https://nas.local:443',
    );
    expect(normalizeUgreenBaseUrl('[::1]:1234'), 'https://[::1]:1234');
    for (final value in [
      '',
      'http://nas.local',
      '//nas.local',
      'https://user@nas.local',
      'https://nas.local/./',
      'https://nas.local//',
      'https://nas.local/?',
      'https://nas.local/#',
      'https://nas.local:0',
      'https://nas.local:99999',
      'https://nas.local:',
      'https://nas..local',
      'https://%6Eas.local',
    ]) {
      expect(
        () => normalizeUgreenBaseUrl(value),
        throwsFormatException,
        reason: value,
      );
    }
  });

  group('loopback HTTPS', () {
    late HttpServer upstream;
    late String base;
    late int hits;
    late List<Uri> seen;
    late List<Map<String, String>> seenHeaders;
    final pin = sha256
        .convert(
          base64.decode(
            _certificate.replaceAll(RegExp(r'-----[^-]+-----|\s'), ''),
          ),
        )
        .toString();

    setUp(() async {
      final context = SecurityContext()
        ..useCertificateChainBytes(utf8.encode(_certificate))
        ..usePrivateKeyBytes(utf8.encode(_privateKey));
      upstream = await HttpServer.bindSecure(
        InternetAddress.loopbackIPv4,
        0,
        context,
      );
      base = 'https://127.0.0.1:${upstream.port}';
      hits = 0;
      seen = [];
      seenHeaders = [];
      upstream.listen((request) async {
        hits++;
        seen.add(request.uri);
        final headers = <String, String>{};
        request.headers.forEach(
          (name, values) => headers[name] = values.join(', '),
        );
        seenHeaders.add(headers);
        final response = request.response;
        switch (request.uri.path) {
          case '/redirect-external':
            response.statusCode = HttpStatus.found;
            response.headers.set(
              HttpHeaders.locationHeader,
              'https://localhost:${upstream.port}/leak',
            );
          case '/redirect-local':
            response.statusCode = HttpStatus.temporaryRedirect;
            response.headers.set(
              HttpHeaders.locationHeader,
              '/poster?size=2&api_key=replace',
            );
          case '/poster':
            response.headers.contentType = ContentType('image', 'png');
            response.headers.set(HttpHeaders.etagHeader, 'poster-one');
            if (request.headers.value(HttpHeaders.ifNoneMatchHeader) ==
                'poster-one') {
              response.statusCode = HttpStatus.notModified;
            } else {
              response.write('poster');
            }
          case '/movie':
            response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
            if (request.headers.value(HttpHeaders.rangeHeader) == 'bytes=1-3') {
              response.statusCode = HttpStatus.partialContent;
              response.headers.set(
                HttpHeaders.contentRangeHeader,
                'bytes 1-3/6',
              );
              response.contentLength = 3;
              response.write('bcd');
            } else {
              response.contentLength = 6;
              if (request.method != 'HEAD') response.write('abcdef');
            }
          default:
            response.write('ok');
        }
        await response.close();
      });
      addTearDown(() => upstream.close(force: true));
    });

    test(
      'checks the leaf before sending HTTP and refuses other origins',
      () async {
        for (final wrongPin in ['', '0' * 64]) {
          final client = createUgreenHttpClient(base, wrongPin);
          addTearDown(() => client.close(force: true));
          await expectLater(
            client.getUrl(Uri.parse('$base/ok')),
            throwsA(isA<HandshakeException>()),
          );
        }
        expect(hits, 0);
        final client = createUgreenHttpClient(base, pin);
        addTearDown(() => client.close(force: true));
        for (final wrong in [
          'https://localhost:${upstream.port}/ok',
          'http://127.0.0.1:${upstream.port}/ok',
          'https://u@127.0.0.1:${upstream.port}/ok',
        ]) {
          await expectLater(
            client.getUrl(Uri.parse(wrong)),
            throwsFormatException,
          );
        }
        final request = await client.getUrl(Uri.parse('$base/ok'));
        expect(
          await (await request.close()).transform(utf8.decoder).join(),
          'ok',
        );
        expect(hits, 1);
        final redirect = await client.getUrl(
          Uri.parse('$base/redirect-external'),
        );
        await expectLater(redirect.close(), throwsFormatException);
        expect(hits, 2);
      },
    );

    test(
      'Dio shares pin and origin constraints and defaults to no following',
      () async {
        final dio = createUgreenDio(base, pin);
        addTearDown(() => dio.close(force: true));
        expect((await dio.get<String>('/ok')).data, 'ok');
        await expectLater(
          dio.get<String>('http://127.0.0.1:${upstream.port}/ok'),
          throwsA(isA<DioException>()),
        );
        await expectLater(
          dio.get<String>('/redirect-external'),
          throwsA(
            isA<DioException>().having(
              (e) => e.response?.statusCode,
              'status',
              302,
            ),
          ),
        );
        expect(seen.map((uri) => uri.path), ['/ok', '/redirect-external']);
      },
    );

    test('signs only artwork requests, partitions keys, and preserves revalidation', () async {
      Map<String, String> headers(String profile, String token) =>
          ugreenArtworkHeaders(
            baseUrl: base,
            fingerprint: pin,
            profileId: profile,
            token: token,
          );
      const token = 'A+b & c';
      final artwork = '$base/redirect-local?view=all';
      final key = artworkCacheKey(artwork, headers('profileA', token))!;
      expect(key, isNot(contains(token)));
      expect(key, artworkCacheKey(artwork, headers('profileA', 'new token')));
      expect(key, isNot(artworkCacheKey(artwork, headers('profileB', token))));
      final fileService = ArtworkFileService();
      final response = await fileService.get(
        artwork,
        headers: headers('profileA', token),
      );
      expect(await response.content.transform(utf8.decoder).join(), 'poster');
      expect(seen.map((uri) => uri.queryParameters['api_key']), [token, token]);
      expect(seen.last.queryParameters['size'], '2');
      expect(
        seenHeaders
            .expand((h) => h.keys)
            .where((k) => k.startsWith('x-sakuga')),
        isEmpty,
      );
      final unchanged = await fileService.get(
        '$base/poster',
        headers: {
          ...headers('profileA', token),
          HttpHeaders.ifNoneMatchHeader: 'poster-one',
        },
      );
      expect(unchanged.statusCode, HttpStatus.notModified);
      await expectLater(
        fileService.get(
          '$base/redirect-external',
          headers: headers('profileA', token),
        ),
        throwsA(isA<HttpException>().having((e) => e.uri, 'uri', isNull)),
      );
      expect(hits, 4);
    });

    test(
      'playback retains upstream query and streams GET ranges and HEAD',
      () async {
        final proxy = await UgreenPlaybackProxy.start(
          baseUrl: base,
          fingerprint: pin,
          upstream: Uri.parse('$base/movie?api_key=secret'),
        );
        addTearDown(proxy.close);
        final url = Uri.parse(proxy.url);
        expect(url.host, '127.0.0.1');
        expect(url.hasQuery, isFalse);
        expect(proxy.url, isNot(contains('secret')));
        final local = HttpClient();
        addTearDown(() => local.close(force: true));
        final range = await local.getUrl(url);
        range.headers.set(HttpHeaders.rangeHeader, 'bytes=1-3');
        final result = await range.close();
        expect(result.statusCode, HttpStatus.partialContent);
        expect(
          result.headers.value(HttpHeaders.contentRangeHeader),
          'bytes 1-3/6',
        );
        expect(await result.transform(utf8.decoder).join(), 'bcd');
        final head = await (await local.headUrl(url)).close();
        expect(head.contentLength, 6);
        expect(await head.transform(utf8.decoder).join(), isEmpty);
        final unrelated = await (await local.getUrl(
          url.replace(path: '/other'),
        )).close();
        expect(unrelated.statusCode, HttpStatus.notFound);
        await unrelated.drain<void>();
        expect(seen.map((uri) => uri.queryParameters['api_key']), [
          'secret',
          'secret',
        ]);
        await proxy.close();
      },
    );

    test(
      'playback rejects another origin and hides redirect destinations',
      () async {
        await expectLater(
          UgreenPlaybackProxy.start(
            baseUrl: base,
            fingerprint: pin,
            upstream: Uri.parse('https://localhost:${upstream.port}/leak'),
          ),
          throwsFormatException,
        );
        final proxy = await UgreenPlaybackProxy.start(
          baseUrl: base,
          fingerprint: pin,
          upstream: Uri.parse('$base/redirect-external?api_key=secret'),
        );
        addTearDown(proxy.close);
        final local = HttpClient();
        addTearDown(() => local.close(force: true));
        final result = await (await local.getUrl(Uri.parse(proxy.url))).close();
        expect(result.statusCode, HttpStatus.badGateway);
        expect(result.headers.value(HttpHeaders.locationHeader), isNull);
        expect(await result.transform(utf8.decoder).join(), isEmpty);
        expect(hits, 1);
      },
    );
  });
}

// Self-signed localhost fixture. This key must never be used outside tests.
const _privateKey = '''-----BEGIN PRIVATE KEY-----
MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQgia5cOV+Y/KO1XT9k
fvTZ0hb0rz86axfXrzu8RgMkyV+hRANCAATh7Ote763xkqRtB08Y3mxlfx75IqcX
KhgodU4EKk++1CEq6C2nk7oB7u0PSYnhqZdEx8h4EYJeJmXkdtd05MYr
-----END PRIVATE KEY-----
''';

const _certificate = '''-----BEGIN CERTIFICATE-----
MIIBmTCCAT+gAwIBAgIUTXe3L2ie6ieUHhlhlBSU1wISaB8wCgYIKoZIzj0EAwIw
FDESMBAGA1UEAwwJbG9jYWxob3N0MB4XDTI2MTExODAzMTk1MVoXDTQ2MTExMzAz
MTk1MVowFDESMBAGA1UEAwwJbG9jYWxob3N0MFkwEwYHKoZIzj0CAQYIKoZIzj0D
AQcDQgAE4ezrXu+t8ZKkbQdPGN5sZX8e+SKnFyoYKHVOBCpPvtQhKugtp5O6Ae7t
D0mJ4amXRMfIeBGCXiZl5HbXdOTGK6NvMG0wHQYDVR0OBBYEFCGRxNgV6x7g/EmH
SmiPoRPELZU7MB8GA1UdIwQYMBaAFCGRxNgV6x7g/EmHSmiPoRPELZU7MA8GA1Ud
EwEB/wQFMAMBAf8wGgYDVR0RBBMwEYIJbG9jYWxob3N0hwR/AAABMAoGCCqGSM49
BAMCA0gAMEUCIA5teX7auJFcHXSKB64wY5Hak2syCwRrX0GBkwyNX8d6AiEA5iHe
AS/Dhi8nPQ5fMW29eKZc1lMXiblNhsHPB/1riqU=
-----END CERTIFICATE-----
''';
