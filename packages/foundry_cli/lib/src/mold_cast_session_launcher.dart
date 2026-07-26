import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:foundry_cli/src/exit_code.dart';
import 'package:foundry_cli/src/mold_cast_session_helper.dart';
import 'package:foundry_cli/src/version.dart';
import 'package:foundry_core/foundry_core.dart';
import 'package:path/path.dart' as p;

/// Outcome of [launchBatchMoldCastSession].
sealed class MoldCastSessionLaunchResult {
  const MoldCastSessionLaunchResult();

  /// Whether the child session completed successfully.
  bool get isSuccess;

  /// Child process exit code.
  int get exitCode;
}

/// Successful batch cast session launched via the synthetic helper package.
final class MoldCastSessionLaunchSuccess extends MoldCastSessionLaunchResult {
  /// Creates a successful launch result.
  const MoldCastSessionLaunchSuccess({
    required this.artifactCount,
    required this.vars,
    required this.writtenFilePaths,
    required this.outputDirectory,
    required this.exitCode,
  });

  /// Number of files rendered into [outputDirectory].
  final int artifactCount;

  /// JSON-encodable variable projection from the session.
  final Map<String, Object?> vars;

  /// Absolute paths of files written by template rendering.
  final List<String> writtenFilePaths;

  /// Absolute path of the cast `--output` directory.
  final String outputDirectory;

  @override
  final int exitCode;

  @override
  bool get isSuccess => true;
}

/// Failed batch cast session launch or child-session failure.
final class MoldCastSessionLaunchFailure extends MoldCastSessionLaunchResult {
  /// Creates a launch / session failure result.
  const MoldCastSessionLaunchFailure({
    required this.kind,
    required this.message,
    required this.exitCode,
  });

  /// Failure category (`resolve`, `load`, `parse`, `hook`, `render`,
  /// `context`, or `internal`).
  final String kind;

  /// Human-readable failure description.
  final String message;

  @override
  final int exitCode;

  @override
  bool get isSuccess => false;

  @override
  String toString() => 'MoldCastSessionLaunchFailure($kind: $message)';
}

/// Launches a batch cast inside a synthetic helper package process.
///
/// Creates a temporary package that depends on `foundry_cli` and the target
/// mold (path), runs `dart pub get`, then `dart run`s a generated bridge that
/// imports the mold's root `variables.dart` (and hooks) by file URI so
/// callbacks stay live. Helper directories are deleted on success and failure
/// unless [keepHelperForDebug] is `true`.
///
/// Stdio from the child process is inherited so session logs surface on the
/// host terminal.
Future<MoldCastSessionLaunchResult> launchBatchMoldCastSession({
  required String moldPath,
  required String outputPath,
  Map<String, Object?>? varsFileValues,
  String? varsFlag,
  bool force = false,
  bool noHooks = false,
  bool keepHelperForDebug = false,
  Directory? tempParent,
  FoundryCliHelperDependency? foundryCliDependency,
  String? foundryCoreOverridePath,
}) async {
  final moldDirectory = Directory(moldPath);
  if (!moldDirectory.existsSync()) {
    return MoldCastSessionLaunchFailure(
      kind: 'load',
      message: 'Mold directory does not exist: $moldPath',
      exitCode: FoundryExitCode.userError.code,
    );
  }

  final resolvedMoldDirectory = moldDirectory.absolute;
  final pubspecFile = File(
    p.join(resolvedMoldDirectory.path, 'pubspec.yaml'),
  );
  if (!pubspecFile.existsSync()) {
    return MoldCastSessionLaunchFailure(
      kind: 'load',
      message: 'Missing required file "pubspec.yaml".',
      exitCode: FoundryExitCode.userError.code,
    );
  }

  final variablesFile = File(
    p.join(resolvedMoldDirectory.path, 'variables.dart'),
  );
  if (!variablesFile.existsSync()) {
    return MoldCastSessionLaunchFailure(
      kind: 'load',
      message: 'Missing required file "variables.dart".',
      exitCode: FoundryExitCode.userError.code,
    );
  }

  final MoldPubspec pubspec;
  try {
    pubspec = parseMoldPubspec(
      yamlContent: await pubspecFile.readAsString(),
      sourcePath: pubspecFile.path,
    );
  } on MoldLoadException catch (exception) {
    return MoldCastSessionLaunchFailure(
      kind: 'load',
      message: '$exception',
      exitCode: FoundryExitCode.userError.code,
    );
  }

  final resolvedFoundryCli =
      foundryCliDependency ?? await resolveFoundryCliHelperDependency();
  final String? resolvedCoreOverride;
  if (foundryCoreOverridePath != null) {
    resolvedCoreOverride = foundryCoreOverridePath;
  } else {
    resolvedCoreOverride = switch (resolvedFoundryCli) {
      FoundryCliPathDependency() =>
        (await resolvePackageRoot('foundry_core')).path,
      FoundryCliHostedDependency() => null,
    };
  }

  final helperRoot = await (tempParent ?? Directory.systemTemp).createTemp(
    moldCastSessionHelperTempPrefix,
  );

  try {
    await _materializeHelperPackage(
      helperRoot: helperRoot,
      moldPackageName: pubspec.name,
      moldPath: resolvedMoldDirectory.path,
      foundryCli: resolvedFoundryCli,
      foundryCoreOverridePath: resolvedCoreOverride,
      variablesFile: variablesFile,
      moldDirectory: resolvedMoldDirectory,
    );

    final resolveResult = await Process.run(
      Platform.resolvedExecutable,
      ['pub', 'get'],
      workingDirectory: helperRoot.path,
    );
    if (resolveResult.exitCode != 0) {
      final output =
          '${resolveResult.stdout}${resolveResult.stderr}'.trim();
      return MoldCastSessionLaunchFailure(
        kind: 'resolve',
        message: output.isEmpty
            ? 'dart pub get failed for the mold cast session helper.'
            : 'dart pub get failed: $output',
        exitCode: FoundryExitCode.userError.code,
      );
    }

    final requestFile = File(p.join(helperRoot.path, 'request.json'));
    final resultFile = File(p.join(helperRoot.path, 'result.json'));
    await requestFile.writeAsString(
      jsonEncode({
        'moldPath': resolvedMoldDirectory.path,
        'outputPath': Directory(outputPath).absolute.path,
        'resultPath': resultFile.path,
        'force': force,
        'noHooks': noHooks,
        if (varsFlag != null) 'varsFlag': varsFlag,
        if (varsFileValues != null) 'varsFileValues': varsFileValues,
      }),
    );

    final entrypoint = File(
      p.join(helperRoot.path, moldCastSessionHelperEntrypointRelativePath),
    );
    final process = await Process.start(
      Platform.resolvedExecutable,
      ['run', entrypoint.path, requestFile.path],
      workingDirectory: helperRoot.path,
      mode: ProcessStartMode.inheritStdio,
    );
    final childExitCode = await process.exitCode;

    if (!resultFile.existsSync()) {
      return MoldCastSessionLaunchFailure(
        kind: 'internal',
        message: 'Session process did not produce a result payload '
            '(exit code $childExitCode).',
        exitCode: childExitCode == 0
            ? FoundryExitCode.internalError.code
            : childExitCode,
      );
    }

    return _decodeLaunchResult(
      resultFile: resultFile,
      fallbackExitCode: childExitCode,
    );
  } finally {
    if (!keepHelperForDebug && helperRoot.existsSync()) {
      await helperRoot.delete(recursive: true);
    }
  }
}

/// Resolves whether the running `foundry_cli` should be path- or hosted-linked.
Future<FoundryCliHelperDependency> resolveFoundryCliHelperDependency() async {
  final packageRoot = await resolvePackageRoot('foundry_cli');
  if (_isInsidePubCache(packageRoot.path)) {
    return const FoundryCliHostedDependency(foundryCliVersion);
  }
  return FoundryCliPathDependency(packageRoot.path);
}

/// Resolves the filesystem package root for [packageName].
Future<Directory> resolvePackageRoot(String packageName) async {
  final libraryUri = await Isolate.resolvePackageUri(
    Uri.parse('package:$packageName/$packageName.dart'),
  );
  if (libraryUri == null || libraryUri.scheme != 'file') {
    throw StateError(
      'Could not resolve package:$packageName/$packageName.dart '
      'to a filesystem path.',
    );
  }
  // package:<name>/<name>.dart → <root>/lib/<name>.dart → package root.
  return File.fromUri(libraryUri).parent.parent;
}

Future<void> _materializeHelperPackage({
  required Directory helperRoot,
  required String moldPackageName,
  required String moldPath,
  required FoundryCliHelperDependency foundryCli,
  required String? foundryCoreOverridePath,
  required File variablesFile,
  required Directory moldDirectory,
}) async {
  await File(p.join(helperRoot.path, 'pubspec.yaml')).writeAsString(
    buildMoldCastSessionHelperPubspec(
      moldPackageName: moldPackageName,
      moldPath: moldPath,
      foundryCli: foundryCli,
    ),
  );

  final overrides = buildMoldCastSessionHelperPubspecOverrides(
    foundryCoreOverridePath: foundryCoreOverridePath,
  );
  if (overrides != null) {
    await File(
      p.join(helperRoot.path, 'pubspec_overrides.yaml'),
    ).writeAsString(overrides);
  }

  final hooks = MoldCastSessionHelperHookImports(
    prepareUri: _existingHookUri(moldDirectory, MoldHooks.preparePath),
    shapeUri: _existingHookUri(moldDirectory, MoldHooks.shapePath),
    finishUri: _existingHookUri(moldDirectory, MoldHooks.finishPath),
  );

  final entrypoint = File(
    p.join(helperRoot.path, moldCastSessionHelperEntrypointRelativePath),
  );
  await entrypoint.parent.create(recursive: true);
  await entrypoint.writeAsString(
    buildMoldCastSessionBridgeSource(
      variablesUri: variablesFile.absolute.uri,
      hooks: hooks,
    ),
  );
}

Uri? _existingHookUri(Directory moldDirectory, String relativePath) {
  final file = File(p.join(moldDirectory.path, relativePath));
  return file.existsSync() ? file.absolute.uri : null;
}

MoldCastSessionLaunchResult _decodeLaunchResult({
  required File resultFile,
  required int fallbackExitCode,
}) {
  Object? decoded;
  try {
    decoded = jsonDecode(resultFile.readAsStringSync());
  } on FormatException catch (error) {
    return MoldCastSessionLaunchFailure(
      kind: 'internal',
      message: 'Session result payload was not valid JSON: $error',
      exitCode: FoundryExitCode.internalError.code,
    );
  }

  if (decoded is! Map) {
    return MoldCastSessionLaunchFailure(
      kind: 'internal',
      message: 'Session result payload must be a JSON object.',
      exitCode: FoundryExitCode.internalError.code,
    );
  }

  final map = <String, Object?>{
    for (final entry in decoded.entries)
      if (entry.key is String) entry.key as String: entry.value,
  };

  if (map['ok'] == true) {
    final artifactCount = map['artifactCount'];
    final vars = map['vars'];
    final writtenFiles = map['writtenFiles'];
    final outputDirectory = map['outputDirectory'];
    if (artifactCount is! int ||
        vars is! Map ||
        writtenFiles is! List ||
        outputDirectory is! String) {
      return MoldCastSessionLaunchFailure(
        kind: 'internal',
        message: 'Session success payload was missing required fields.',
        exitCode: FoundryExitCode.internalError.code,
      );
    }
    return MoldCastSessionLaunchSuccess(
      artifactCount: artifactCount,
      vars: <String, Object?>{
        for (final entry in vars.entries)
          if (entry.key is String) entry.key as String: entry.value,
      },
      writtenFilePaths: [
        for (final path in writtenFiles)
          if (path is String) path,
      ],
      outputDirectory: outputDirectory,
      exitCode: fallbackExitCode == 0
          ? FoundryExitCode.success.code
          : fallbackExitCode,
    );
  }

  final kind = map['kind'];
  final message = map['message'];
  return MoldCastSessionLaunchFailure(
    kind: kind is String && kind.isNotEmpty ? kind : 'internal',
    message: message is String && message.isNotEmpty
        ? message
        : 'Session failed without a message.',
    exitCode: fallbackExitCode == 0
        ? FoundryExitCode.userError.code
        : fallbackExitCode,
  );
}

bool _isInsidePubCache(String path) {
  final absolute = p.normalize(p.absolute(path));
  final candidates = <String>[
    if (Platform.environment['PUB_CACHE'] case final pubCache?) pubCache,
    if (Platform.environment['HOME'] case final home?)
      p.join(home, '.pub-cache'),
    if (Platform.environment['LOCALAPPDATA'] case final localAppData?)
      p.join(localAppData, 'Pub', 'Cache'),
  ];

  for (final candidate in candidates) {
    final cacheRoot = p.normalize(p.absolute(candidate));
    if (absolute == cacheRoot || p.isWithin(cacheRoot, absolute)) {
      return true;
    }
  }
  return false;
}
