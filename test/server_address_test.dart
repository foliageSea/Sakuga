import 'package:flutter_test/flutter_test.dart';
import 'package:sakuga/data/media_server/server_probe.dart';

void main() {
  group('composeBaseUrl', () {
    test('adds http for insecure addresses without a scheme', () {
      expect(
        composeBaseUrl('192.168.1.2:8096', secure: false),
        'http://192.168.1.2:8096',
      );
    });

    test('adds https for secure addresses and keeps subpaths', () {
      expect(
        composeBaseUrl(' media.example/jellyfin/ ', secure: true),
        'https://media.example/jellyfin',
      );
    });

    test('respects a scheme that is already present', () {
      expect(
        composeBaseUrl('https://media.example', secure: false),
        'https://media.example',
      );
    });

    test('rejects empty input', () {
      expect(() => composeBaseUrl('  ', secure: true), throwsFormatException);
    });
  });

  test('splits stored base URLs into scheme and address', () {
    expect(isSecureBaseUrl('https://media.test/jellyfin/'), isTrue);
    expect(isSecureBaseUrl('http://192.168.1.2:8096'), isFalse);
    expect(
      stripBaseUrlScheme('https://media.test/jellyfin/'),
      'media.test/jellyfin/',
    );
  });
}
