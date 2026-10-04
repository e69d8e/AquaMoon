import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:aquamoon/services/update_service.dart';

http.Response _releaseResponse(Map<String, dynamic> release) =>
    http.Response(json.encode(release), 200, headers: {
      'content-type': 'application/json; charset=utf-8',
    });

const _mockRelease = {
  'tag_name': 'v1.1.0',
  'name': '水月音 v1.1.0',
  'body': '## 更新内容\n- 新增检查更新功能',
  'html_url': 'https://github.com/e69d8e/AquaMoon/releases/tag/v1.1.0',
};

void main() {
  group('UpdateService.checkForUpdate', () {
    test('returns update info when remote tag is newer', () async {
      final service = UpdateService(
        client: MockClient((request) async => _releaseResponse(_mockRelease)),
      );

      final info = await service.checkForUpdate(currentVersion: '1.0.2+3');

      expect(info, isNotNull);
      expect(info!.latestVersion, '1.1.0');
      expect(info.currentVersion, '1.0.2');
      expect(info.releaseTitle, '水月音 v1.1.0');
      expect(info.releaseNotes, contains('检查更新'));
      expect(info.releaseUrl, contains('releases/tag/v1.1.0'));
    });

    test('sends GitHub API accept header', () async {
      String? acceptHeader;
      final service = UpdateService(
        client: MockClient((request) async {
          acceptHeader = request.headers['Accept'];
          return _releaseResponse(_mockRelease);
        }),
      );

      await service.checkForUpdate(currentVersion: '1.0.2');

      expect(acceptHeader, 'application/vnd.github+json');
    });

    test('returns null when versions are equal (build number ignored)',
        () async {
      final service = UpdateService(
        client: MockClient(
          (request) async => _releaseResponse(
            {..._mockRelease, 'tag_name': 'v1.0.2'},
          ),
        ),
      );

      final info = await service.checkForUpdate(currentVersion: '1.0.2+3');

      expect(info, isNull);
    });

    test('returns null when remote tag is older', () async {
      final service = UpdateService(
        client: MockClient(
          (request) async => _releaseResponse(
            {..._mockRelease, 'tag_name': 'v0.9.0'},
          ),
        ),
      );

      final info = await service.checkForUpdate(currentVersion: '1.0.0');

      expect(info, isNull);
    });

    test('throws on non-200 response', () async {
      final service = UpdateService(
        client: MockClient((request) async => http.Response('rate limited', 403)),
      );

      await expectLater(
        service.checkForUpdate(currentVersion: '1.0.2'),
        throwsException,
      );
    });

    test('throws on network error', () async {
      final service = UpdateService(
        client: MockClient((request) async => throw Exception('offline')),
      );

      await expectLater(
        service.checkForUpdate(currentVersion: '1.0.2'),
        throwsException,
      );
    });

    test('throws when response body is not a JSON object', () async {
      final service = UpdateService(
        client: MockClient(
          (request) async =>
              http.Response(json.encode(['not', 'an', 'object']), 200),
        ),
      );

      await expectLater(
        service.checkForUpdate(currentVersion: '1.0.2'),
        throwsException,
      );
    });

    test('falls back to releases page when html_url is missing', () async {
      final service = UpdateService(
        client: MockClient(
          (request) async => _releaseResponse({
            'tag_name': 'v2.0.0',
            'name': 'v2.0.0',
          }),
        ),
      );

      final info = await service.checkForUpdate(currentVersion: '1.0.2');

      expect(info!.releaseUrl,
          'https://github.com/e69d8e/AquaMoon/releases');
    });

    test('prefers the Universal APK over per-ABI builds regardless of order',
        () async {
      final service = UpdateService(
        client: MockClient(
          (request) async => _releaseResponse({
            ..._mockRelease,
            'assets': [
              {
                'name': 'AquaMoon-Android-arm64-v8a.apk',
                'browser_download_url': 'https://example.com/arm64.apk',
              },
              {
                'name': 'AquaMoon-Android-Universal.apk',
                'browser_download_url': 'https://example.com/universal.apk',
              },
              {
                'name': 'checksums.txt',
                'browser_download_url': 'https://example.com/checksums.txt',
              },
            ],
          }),
        ),
      );

      final info = await service.checkForUpdate(currentVersion: '1.0.2');

      expect(info!.apkUrl, 'https://example.com/universal.apk');
    });

    test('falls back to the first .apk when no Universal asset exists',
        () async {
      final service = UpdateService(
        client: MockClient(
          (request) async => _releaseResponse({
            ..._mockRelease,
            'assets': [
              {
                'name': 'AquaMoon-Android-arm64-v8a.apk',
                'browser_download_url': 'https://example.com/arm64.apk',
              },
            ],
          }),
        ),
      );

      final info = await service.checkForUpdate(currentVersion: '1.0.2');

      expect(info!.apkUrl, 'https://example.com/arm64.apk');
    });
  });
}
