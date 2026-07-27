import 'dart:io';

import 'package:path/path.dart' as p;

import 'fixture_paths.dart';

/// Rewrites [moldDirectory]'s `pubspec.yaml` so `foundry_core` is a path
/// dependency on the local monorepo package.
///
/// Derived molds depend on a hosted `foundry_core` constraint. Rewriting to a
/// path dependency lets `mold inspect` resolve offline in E2E.
Future<void> useLocalFoundryCore(Directory moldDirectory) async {
  final pubspec = File(p.join(moldDirectory.path, 'pubspec.yaml'));
  final contents = await pubspec.readAsString();
  final nameMatch = RegExp(
    r'^name:\s+(\S+)\s*$',
    multiLine: true,
  ).firstMatch(contents);
  final name = nameMatch?.group(1) ?? 'derived_mold';
  final corePath = foundryCorePackageRoot().absolute.path;

  await pubspec.writeAsString('''
name: $name
description: A Foundry mold.
version: 0.0.1
publish_to: none

environment:
  sdk: ">=3.5.0 <4.0.0"

dependencies:
  foundry_core:
    path: $corePath
''');
}
