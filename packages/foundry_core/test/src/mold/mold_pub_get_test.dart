import 'dart:io';

import 'package:foundry_core/src/mold/mold_issue.dart';
import 'package:foundry_core/src/mold/mold_pub_get.dart';
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
}
