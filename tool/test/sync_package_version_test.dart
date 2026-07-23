import 'dart:io';

import 'package:test/test.dart';

import '../sync_package_version.dart';

void main() {
  late Directory packageDir;

  setUp(() {
    packageDir =
        Directory.systemTemp.createTempSync('foundry_sync_package_version_');
    Directory('${packageDir.path}/lib/src').createSync(recursive: true);
  });

  tearDown(() {
    try {
      if (packageDir.existsSync()) {
        packageDir.deleteSync(recursive: true);
      }
    } on PathNotFoundException {
      // Already removed — can race on macOS CI runners.
    }
  });

  test('updates version const when pubspec version differs', () {
    File('${packageDir.path}/pubspec.yaml').writeAsStringSync('''
name: example
version: 1.2.3
''');
    File('${packageDir.path}/lib/src/version.dart').writeAsStringSync('''
const exampleVersion = '1.0.0';
''');

    final exitCode = syncPackageVersion(packageDir);

    expect(exitCode, 0);
    expect(
      File('${packageDir.path}/lib/src/version.dart').readAsStringSync(),
      contains("const exampleVersion = '1.2.3';"),
    );
  });

  test('is a no-op when version const already matches pubspec', () {
    File('${packageDir.path}/pubspec.yaml').writeAsStringSync('''
name: example
version: 1.2.3
''');
    final versionDartPath = '${packageDir.path}/lib/src/version.dart';
    const versionDartContents = "const exampleVersion = '1.2.3';\n";
    File(versionDartPath).writeAsStringSync(versionDartContents);

    final exitCode = syncPackageVersion(packageDir);

    expect(exitCode, 0);
    expect(File(versionDartPath).readAsStringSync(), versionDartContents);
  });

  test('fails when pubspec.yaml is missing', () {
    File('${packageDir.path}/lib/src/version.dart').writeAsStringSync('''
const exampleVersion = '1.0.0';
''');

    final exitCode = syncPackageVersion(packageDir);

    expect(exitCode, 1);
  });

  test('fails when no semver-shaped version const exists', () {
    File('${packageDir.path}/pubspec.yaml').writeAsStringSync('''
name: example
version: 1.2.3
''');
    File('${packageDir.path}/lib/src/version.dart').writeAsStringSync('''
const packageName = 'example';
''');

    final exitCode = syncPackageVersion(packageDir);

    expect(exitCode, 1);
  });

  test('discovers packageVersion when packageName is also a const', () {
    File('${packageDir.path}/pubspec.yaml').writeAsStringSync('''
name: example
version: 2.0.0-dev.1
''');
    File('${packageDir.path}/lib/src/version.dart').writeAsStringSync('''
const packageName = 'example';
const packageVersion = '1.0.0';
''');

    final exitCode = syncPackageVersion(packageDir);

    expect(exitCode, 0);
    expect(
      File('${packageDir.path}/lib/src/version.dart').readAsStringSync(),
      contains("const packageVersion = '2.0.0-dev.1';"),
    );
  });

  test('honors explicit --version-const name', () {
    File('${packageDir.path}/pubspec.yaml').writeAsStringSync('''
name: example
version: 1.2.3
''');
    File('${packageDir.path}/lib/src/version.dart').writeAsStringSync('''
const customVersion = '1.0.0';
const otherVersion = '9.9.9';
''');

    final exitCode = syncPackageVersion(
      packageDir,
      versionConstName: 'customVersion',
    );

    expect(exitCode, 0);
    expect(
      File('${packageDir.path}/lib/src/version.dart').readAsStringSync(),
      contains("const customVersion = '1.2.3';"),
    );
  });

  group('discoverVersionConstName', () {
    test('returns single semver const', () {
      final result = discoverVersionConstName(
        "const exampleVersion = '1.2.3';\n",
      );

      expect(result?.name, 'exampleVersion');
      expect(result?.errorMessage, isNull);
    });

    test(
      'prefers identifier containing version when multiple semver consts',
      () {
        final result = discoverVersionConstName('''
const packageName = 'foundry';
const packageVersion = '1.0.0';
''');

        expect(result?.name, 'packageVersion');
        expect(result?.errorMessage, isNull);
      },
    );

    test('returns error when no semver const exists', () {
      final result = discoverVersionConstName(
        "const packageName = 'foundry';\n",
      );

      expect(result?.name, isNull);
      expect(result?.errorMessage, isNotNull);
    });
  });
}
