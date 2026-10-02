import 'package:flutter_test/flutter_test.dart';

import 'package:aquamoon/core/utils/version_utils.dart';

void main() {
  group('VersionUtils.compareVersions', () {
    test('identical versions are equal', () {
      expect(VersionUtils.compareVersions('1.0.2', '1.0.2'), 0);
    });

    test('patch / minor / major increments compare correctly', () {
      expect(VersionUtils.compareVersions('1.0.3', '1.0.2'), greaterThan(0));
      expect(VersionUtils.compareVersions('1.1.0', '1.0.9'), greaterThan(0));
      expect(VersionUtils.compareVersions('2.0.0', '1.9.9'), greaterThan(0));
      expect(VersionUtils.compareVersions('1.0.2', '1.0.10'), lessThan(0));
      expect(VersionUtils.compareVersions('1.9.0', '2.0.0'), lessThan(0));
    });

    test('build metadata from pubspec versions is ignored', () {
      expect(VersionUtils.compareVersions('1.0.2+3', '1.0.2'), 0);
      expect(VersionUtils.compareVersions('1.0.2+3', 'v1.0.2'), 0);
      expect(VersionUtils.compareVersions('1.0.3+4', '1.0.2+3'), greaterThan(0));
    });

    test('v prefix is tolerated', () {
      expect(VersionUtils.compareVersions('v1.0.2', '1.0.2'), 0);
      expect(VersionUtils.compareVersions('V1.1.0', '1.0.9'), greaterThan(0));
    });

    test('pre-release does not outrank the plain release of same number', () {
      expect(
        VersionUtils.compareVersions('1.1.0-beta.1', '1.1.0'),
        isNot(greaterThan(0)),
      );
      expect(VersionUtils.compareVersions('v1.1.0-beta', '1.0.9'), greaterThan(0));
    });

    test('missing segments count as zero', () {
      expect(VersionUtils.compareVersions('1.0', '1.0.0'), 0);
      expect(VersionUtils.compareVersions('1.0.1', '1.0'), greaterThan(0));
    });

    test('non-numeric segments fall back to zero instead of throwing', () {
      expect(VersionUtils.compareVersions('abc', '0.0.0'), 0);
      expect(VersionUtils.compareVersions('1.x.2', '1.0.2'), 0);
    });

    test('extra segments beyond three still compare', () {
      expect(VersionUtils.compareVersions('1.0.2.1', '1.0.2'), greaterThan(0));
    });
  });

  group('VersionUtils.normalize', () {
    test('strips v prefix, pre-release, and build metadata', () {
      expect(VersionUtils.normalize('v1.0.2'), '1.0.2');
      expect(VersionUtils.normalize('1.0.2+3'), '1.0.2');
      expect(VersionUtils.normalize('v1.1.0-beta.1'), '1.1.0');
      expect(VersionUtils.normalize(' V1.0.2 '), '1.0.2');
    });
  });
}
