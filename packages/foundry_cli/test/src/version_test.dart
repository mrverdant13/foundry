import 'dart:io';

import 'package:foundry_cli/src/version.dart' show foundryCliVersion;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

final _foundryCliPackageNamePattern =
    RegExp(r'^name:\s+foundry_cli\s*$', multiLine: true);

Directory _packageRoot() {
  var current = Directory.current;
  while (true) {
    final pubspec = File(p.join(current.path, 'pubspec.yaml'));
    if (pubspec.existsSync() &&
        _foundryCliPackageNamePattern.hasMatch(pubspec.readAsStringSync())) {
      return current;
    }

    final parent = current.parent;
    if (parent.path == current.path) {
      fail(
        'Could not locate foundry_cli package root from '
        '${Directory.current.path}',
      );
    }
    current = parent;
  }
}

String _readPubspecVersion(Directory packageRoot) {
  final pubspecPath = p.join(packageRoot.path, 'pubspec.yaml');
  final pubspec = loadYaml(File(pubspecPath).readAsStringSync());
  if (pubspec is! YamlMap) {
    fail('Expected pubspec.yaml at $pubspecPath to parse as a map');
  }

  final version = pubspec['version'];
  if (version is! String || version.isEmpty) {
    fail('Expected pubspec.yaml version to be a non-empty string');
  }

  return version;
}

void main() {
  test('pubspec.yaml version matches foundryCliVersion', () {
    final pubspecVersion = _readPubspecVersion(_packageRoot());

    expect(
      foundryCliVersion,
      pubspecVersion,
      reason: 'foundryCliVersion ($foundryCliVersion) must match '
          'pubspec.yaml version ($pubspecVersion). '
          'Update lib/src/version.dart after bumping pubspec.yaml, or run '
          'dart run tool/sync_package_version.dart --cwd packages/foundry_cli '
          'once the sync script is available.',
    );
  });
}
