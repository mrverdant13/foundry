import 'dart:io';

import 'package:pub_semver/pub_semver.dart';

import 'lib/pubspec.dart' as pubspec_fields;

final _versionConstPattern = RegExp(
  r"const\s+(\w+)\s*=\s*'([^']*)';",
);

void main(List<String> arguments) {
  final cwd = _readCwdArgument(arguments);
  if (cwd == null) {
    _printUsage();
    exit(64);
  }

  final versionConstName = _readVersionConstArgument(arguments);
  exit(syncPackageVersion(Directory(cwd), versionConstName: versionConstName));
}

/// Syncs `lib/src/version.dart` in [packageCwd] from its `pubspec.yaml`.
///
/// When [versionConstName] is omitted, discovers a single semver-shaped
/// `const` in `lib/src/version.dart`. Returns `0` on success (including when
/// already in sync) and `1` on failure.
int syncPackageVersion(
  Directory packageCwd, {
  String? versionConstName,
}) {
  final resolvedCwd = packageCwd.absolute;
  final pubspecFile = File('${resolvedCwd.path}/pubspec.yaml');
  if (!pubspecFile.existsSync()) {
    stderr.writeln('Missing pubspec.yaml: ${pubspecFile.path}');
    return 1;
  }

  final versionResult = pubspec_fields.readPubspecVersion(pubspecFile);
  if (versionResult.errorMessage != null) {
    stderr.writeln(versionResult.errorMessage);
    return 1;
  }
  final version = versionResult.version!;
  final versionDartFile = File('${resolvedCwd.path}/lib/src/version.dart');
  if (!versionDartFile.existsSync()) {
    stderr.writeln('Missing version.dart: ${versionDartFile.path}');
    return 1;
  }

  final currentContents = versionDartFile.readAsStringSync();
  final String resolvedConstName;
  if (versionConstName != null) {
    resolvedConstName = versionConstName;
  } else {
    final discovery = discoverVersionConstName(currentContents);
    if (discovery?.name == null) {
      stderr.writeln(
        discovery?.errorMessage ??
            'Could not discover a version const in ${versionDartFile.path}',
      );
      return 1;
    }
    resolvedConstName = discovery!.name!;
  }

  final pattern = RegExp(
    "const $resolvedConstName = '[^']*';",
  );
  final match = pattern.firstMatch(currentContents);
  if (match == null) {
    stderr.writeln(
      'Could not find const $resolvedConstName in ${versionDartFile.path}',
    );
    return 1;
  }

  final updatedConst = "const $resolvedConstName = '$version';";
  if (match.group(0) == updatedConst) {
    stdout.writeln(
      '${resolvedCwd.path}: $resolvedConstName already matches '
      'pubspec.yaml ($version)',
    );
    return 0;
  }

  final updatedContents = currentContents.replaceFirst(pattern, updatedConst);
  versionDartFile.writeAsStringSync(updatedContents);
  stdout.writeln(
    'Updated ${versionDartFile.path}: $resolvedConstName -> $version',
  );
  return 0;
}

/// Discovers the version `const` name in [versionDartContents].
///
/// Returns a structured error when zero or multiple semver-shaped consts are
/// found without a unique `version` substring in the identifier.
({String? name, String? errorMessage})? discoverVersionConstName(
  String versionDartContents,
) {
  final semverConsts = <String>[];
  for (final match in _versionConstPattern.allMatches(versionDartContents)) {
    final name = match.group(1)!;
    final value = match.group(2)!;
    if (_looksLikeVersion(value)) {
      semverConsts.add(name);
    }
  }

  if (semverConsts.isEmpty) {
    return (
      name: null,
      errorMessage: 'No semver-shaped version const found in version.dart',
    );
  }

  if (semverConsts.length == 1) {
    return (name: semverConsts.single, errorMessage: null);
  }

  final versionNamed = semverConsts
      .where((name) => name.toLowerCase().contains('version'))
      .toList();
  if (versionNamed.length == 1) {
    return (name: versionNamed.single, errorMessage: null);
  }

  return (
    name: null,
    errorMessage:
        'Multiple semver-shaped version consts found in version.dart: '
        '${semverConsts.join(', ')}. Pass --version-const to select one.',
  );
}

bool _looksLikeVersion(String value) {
  try {
    Version.parse(value);
    return true;
  } on FormatException {
    return false;
  }
}

String? _readCwdArgument(List<String> arguments) {
  for (var index = 0; index < arguments.length; index++) {
    final argument = arguments[index];
    if (argument == '--cwd') {
      if (index + 1 >= arguments.length) {
        stderr.writeln('Missing value for --cwd');
        return null;
      }
      return arguments[index + 1];
    }

    const prefix = '--cwd=';
    if (argument.startsWith(prefix)) {
      final value = argument.substring(prefix.length);
      if (value.isEmpty) {
        stderr.writeln('Missing value for --cwd');
        return null;
      }
      return value;
    }
  }

  stderr.writeln('Missing required --cwd argument');
  return null;
}

String? _readVersionConstArgument(List<String> arguments) {
  for (var index = 0; index < arguments.length; index++) {
    final argument = arguments[index];
    if (argument == '--version-const') {
      if (index + 1 >= arguments.length) {
        stderr.writeln('Missing value for --version-const');
        return null;
      }
      return arguments[index + 1];
    }

    const prefix = '--version-const=';
    if (argument.startsWith(prefix)) {
      final value = argument.substring(prefix.length);
      if (value.isEmpty) {
        stderr.writeln('Missing value for --version-const');
        return null;
      }
      return value;
    }
  }

  return null;
}

void _printUsage() {
  stderr
    ..writeln(
      'Usage: dart run tool/sync_package_version.dart --cwd <package-dir> '
      '[--version-const <name>]',
    )
    ..writeln()
    ..writeln(
      'Syncs lib/src/version.dart from pubspec.yaml in the package directory.',
    );
}
