import 'dart:io';

import 'package:foundry_core/src/mold/mold_issue.dart';
import 'package:foundry_core/src/mold/mold_pub_get.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('verifyMoldPackageConfig throws when package config is missing', () {
    final tempDir =
        Directory.systemTemp.createTempSync('foundry_no_pkg_config_');
    addTearDown(() => tempDir.deleteSync(recursive: true));

    expect(
      () => verifyMoldPackageConfig(tempDir),
      throwsA(
        isA<MoldLoadException>().having(
          (error) => error.issues.single.message,
          'message',
          contains('package config'),
        ),
      ),
    );
  });

  test('describePubGetFailure prefers combined process output', () {
    expect(
      describePubGetFailure(stdout: 'out\n', stderr: 'err\n'),
      'dart pub get failed: out\nerr',
    );
  });

  test('describePubGetFailure uses a fallback when output is empty', () {
    expect(
      describePubGetFailure(stdout: '  ', stderr: '\n'),
      'dart pub get failed for the mold package.',
    );
  });

  test('ensureMoldDependencies throws when dart pub get fails', () async {
    final tempDir =
        await Directory.systemTemp.createTemp('foundry_bad_pub_get_');
    addTearDown(() => tempDir.deleteSync(recursive: true));

    await File(p.join(tempDir.path, 'pubspec.yaml')).writeAsString('''
name: broken
description: Broken mold dependencies
version: 0.0.1
publish_to: none

environment:
  sdk: ">=3.5.0 <4.0.0"

dependencies:
  foundry_core:
    path: ./does_not_exist
''');

    await expectLater(
      ensureMoldDependencies(tempDir),
      throwsA(
        isA<MoldLoadException>().having(
          (error) => error.issues.single.message,
          'message',
          contains('pub get failed'),
        ),
      ),
    );
  });
}
