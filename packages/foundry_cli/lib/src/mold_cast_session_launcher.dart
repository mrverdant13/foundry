import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:foundry_cli/src/cast_session_describe.dart';
import 'package:foundry_cli/src/exit_code.dart';
import 'package:foundry_cli/src/mold_cast_session_helper.dart';
import 'package:foundry_cli/src/mold_cast_session_helper_cache.dart';
import 'package:foundry_cli/src/version.dart';
import 'package:foundry_core/foundry_core.dart';
import 'package:path/path.dart' as p;

/// Receives helper-resolve cache lifecycle events (`hit`, `miss`,
/// `resolve-failed`) for tests and optional debug logging.
typedef MoldCastSessionHelperCacheEventSink = void Function(String event);

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

/// Successful describe-only session launched via the synthetic helper package.
final class MoldCastSessionDescribeSuccess extends MoldCastSessionLaunchResult {
  /// Creates a successful describe result.
  const MoldCastSessionDescribeSuccess({
    required this.variables,
    required this.exitCode,
  });

  /// Live variable metadata reported by the session.
  final List<MoldVariableDescription> variables;

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

  /// Failure category (`resolve`, `load`, `parse`, `gather`, `validation`,
  /// `hook`, `render`, `context`, `cancel`, or `internal`).
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

/// Runs `dart pub get` for a materialized session helper package.
typedef MoldCastSessionPubGetRunner = Future<ProcessResult> Function(
  Directory helperRoot,
);

/// Runs the generated session bridge and returns the child exit code.
typedef MoldCastSessionChildRunner = Future<int> Function({
  required Directory helperRoot,
  required File entrypoint,
  required File requestFile,
  Map<String, String>? environment,
});

/// Launches a mold cast session inside a synthetic helper package process.
///
/// Creates (or reuses) a helper package that depends on `foundry_cli` and the
/// target mold (path), runs `dart pub get` when needed, then `dart run`s a
/// generated bridge that imports the mold's root `variables.dart` (and hooks)
/// by file URI so callbacks stay live.
///
/// Mode selection (via the request payload):
/// - [finishOnly] `true` → finish-only session seeded from [varsFileValues]
/// - [seededValues] → seeded session (recast; keeps non-variable keys)
/// - [varsFlag] and/or [varsFileValues] → batch session
/// - otherwise → interactive gather (Nocterm, or `FOUNDRY_E2E_VARS` when set)
///
/// When [cacheHelperResolve] is `true` (default), helper package resolution is
/// cached under [helperCacheRoot] (or the system-temp cache root) keyed by
/// absolute mold path, mold pubspec/lock digest, and `foundry_cli` linkage.
/// Cached helpers are retained across launches. Ephemeral helpers (cache off)
/// are deleted on success and failure unless [keepHelperForDebug] is `true`.
///
/// Stdio from the child process is inherited so the interactive TUI and
/// session logs surface on the host terminal.
///
/// [pubGetRunner] and [childRunner] are seam points for unit tests.
/// [onHelperCacheEvent] receives `hit` / `miss` / `resolve-failed` events.
///
/// For variable metadata without cast/render, use
/// [launchDescribeMoldCastSession] instead.
Future<MoldCastSessionLaunchResult> launchBatchMoldCastSession({
  required String moldPath,
  required String outputPath,
  Map<String, Object?>? varsFileValues,
  Map<String, Object?>? seededValues,
  String? varsFlag,
  bool force = false,
  Set<MoldHookPhase> skipHooks = const {},
  bool finishOnly = false,
  bool keepHelperForDebug = false,
  bool cacheHelperResolve = true,
  Directory? helperCacheRoot,
  Directory? tempParent,
  FoundryCliHelperDependency? foundryCliDependency,
  String? foundryCoreOverridePath,
  Map<String, String>? environment,
  MoldCastSessionPubGetRunner? pubGetRunner,
  MoldCastSessionChildRunner? childRunner,
  MoldCastSessionHelperCacheEventSink? onHelperCacheEvent,
}) async {
  if (finishOnly && varsFileValues == null) {
    return MoldCastSessionLaunchFailure(
      kind: 'internal',
      message: 'finishOnly session launch requires varsFileValues.',
      exitCode: FoundryExitCode.internalError.code,
    );
  }
  if (seededValues != null && (varsFlag != null || varsFileValues != null)) {
    return MoldCastSessionLaunchFailure(
      kind: 'internal',
      message:
          'seededValues cannot be combined with varsFlag or varsFileValues.',
      exitCode: FoundryExitCode.internalError.code,
    );
  }

  return _launchMoldCastSession(
    moldPath: moldPath,
    keepHelperForDebug: keepHelperForDebug,
    cacheHelperResolve: cacheHelperResolve,
    helperCacheRoot: helperCacheRoot,
    tempParent: tempParent,
    foundryCliDependency: foundryCliDependency,
    foundryCoreOverridePath: foundryCoreOverridePath,
    environment: environment,
    pubGetRunner: pubGetRunner,
    childRunner: childRunner,
    onHelperCacheEvent: onHelperCacheEvent,
    buildRequest: ({
      required resolvedMoldPath,
      required resultPath,
    }) {
      return {
        'moldPath': resolvedMoldPath,
        'outputPath': Directory(outputPath).absolute.path,
        'resultPath': resultPath,
        'force': force,
        'skipHooks': [
          for (final phase in skipHooks) phase.name,
        ],
        if (finishOnly) 'finishOnly': true,
        if (varsFlag != null) 'varsFlag': varsFlag,
        if (varsFileValues != null) 'varsFileValues': varsFileValues,
        if (seededValues != null) 'seededValues': seededValues,
      };
    },
  );
}

/// Launches a describe-only mold session via the synthetic helper package.
///
/// Uses the same helper composition as [launchBatchMoldCastSession] so live
/// `variables.dart` callbacks (for example choice `displayLabel`) match cast,
/// but does not create an output directory, run hooks, render templates, or
/// write cast state.
///
/// See [launchBatchMoldCastSession] for helper resolve caching behavior.
Future<MoldCastSessionLaunchResult> launchDescribeMoldCastSession({
  required String moldPath,
  bool keepHelperForDebug = false,
  bool cacheHelperResolve = true,
  Directory? helperCacheRoot,
  Directory? tempParent,
  FoundryCliHelperDependency? foundryCliDependency,
  String? foundryCoreOverridePath,
  Map<String, String>? environment,
  MoldCastSessionPubGetRunner? pubGetRunner,
  MoldCastSessionChildRunner? childRunner,
  MoldCastSessionHelperCacheEventSink? onHelperCacheEvent,
}) {
  return _launchMoldCastSession(
    moldPath: moldPath,
    keepHelperForDebug: keepHelperForDebug,
    cacheHelperResolve: cacheHelperResolve,
    helperCacheRoot: helperCacheRoot,
    tempParent: tempParent,
    foundryCliDependency: foundryCliDependency,
    foundryCoreOverridePath: foundryCoreOverridePath,
    environment: environment,
    pubGetRunner: pubGetRunner,
    childRunner: childRunner,
    onHelperCacheEvent: onHelperCacheEvent,
    buildRequest: ({
      required resolvedMoldPath,
      required resultPath,
    }) {
      return {
        'moldPath': resolvedMoldPath,
        'resultPath': resultPath,
        'describeOnly': true,
      };
    },
  );
}

Future<MoldCastSessionLaunchResult> _launchMoldCastSession({
  required String moldPath,
  required bool keepHelperForDebug,
  required bool cacheHelperResolve,
  required Directory? helperCacheRoot,
  required Directory? tempParent,
  required FoundryCliHelperDependency? foundryCliDependency,
  required String? foundryCoreOverridePath,
  required Map<String, String>? environment,
  required MoldCastSessionPubGetRunner? pubGetRunner,
  required MoldCastSessionChildRunner? childRunner,
  required MoldCastSessionHelperCacheEventSink? onHelperCacheEvent,
  required Map<String, Object?> Function({
    required String resolvedMoldPath,
    required String resultPath,
  }) buildRequest,
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

  final cacheInputs = await readMoldCastSessionHelperCacheInputs(
    moldDirectory: resolvedMoldDirectory,
  );

  final MoldPubspec pubspec;
  try {
    pubspec = parseMoldPubspec(
      yamlContent: cacheInputs.pubspec,
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

  final cacheKey = buildMoldCastSessionHelperCacheKey(
    moldPath: resolvedMoldDirectory.path,
    moldPubspecContents: cacheInputs.pubspec,
    moldPubspecLockContents: cacheInputs.lock,
    foundryCli: resolvedFoundryCli,
    foundryCoreOverridePath: resolvedCoreOverride,
  );

  final prepared = await prepareMoldCastSessionHelperRoot(
    cacheKey: cacheKey,
    cacheHelperResolve: cacheHelperResolve,
    helperCacheRoot: helperCacheRoot,
    tempParent: tempParent,
  );
  final helperRoot = prepared.helperRoot;

  Future<MoldCastSessionLaunchResult> runSession() async {
    await _materializeHelperPackage(
      helperRoot: helperRoot,
      moldPackageName: pubspec.name,
      moldPath: resolvedMoldDirectory.path,
      foundryCli: resolvedFoundryCli,
      foundryCoreOverridePath: resolvedCoreOverride,
      variablesFile: variablesFile,
      moldDirectory: resolvedMoldDirectory,
    );

    final resolveCached = cacheHelperResolve &&
        isMoldCastSessionHelperResolveCached(
          helperRoot: helperRoot,
          cacheKey: cacheKey,
        );
    if (resolveCached) {
      onHelperCacheEvent?.call('hit');
      final debugEnv = environment ?? Platform.environment;
      if (debugEnv['FOUNDRY_DEBUG_HELPER_CACHE'] == '1') {
        stderr.writeln(
          'Reusing cached mold cast session helper resolve '
          '(${helperRoot.path})',
        );
      }
    } else {
      onHelperCacheEvent?.call('miss');
      final resolveResult =
          await (pubGetRunner ?? _runHelperPubGet)(helperRoot);
      if (resolveResult.exitCode != 0) {
        onHelperCacheEvent?.call('resolve-failed');
        await clearMoldCastSessionHelperResolveCache(helperRoot: helperRoot);
        final output = '${resolveResult.stdout}${resolveResult.stderr}'.trim();
        return MoldCastSessionLaunchFailure(
          kind: 'resolve',
          message: output.isEmpty
              ? 'dart pub get failed for the mold cast session helper.'
              : 'dart pub get failed: $output',
          exitCode: FoundryExitCode.userError.code,
        );
      }
      if (cacheHelperResolve) {
        await markMoldCastSessionHelperResolveCached(
          helperRoot: helperRoot,
          cacheKey: cacheKey,
        );
      }
    }

    final requestFile = File(p.join(helperRoot.path, 'request.json'));
    final resultFile = File(p.join(helperRoot.path, 'result.json'));
    if (resultFile.existsSync()) {
      await resultFile.delete();
    }
    await requestFile.writeAsString(
      jsonEncode(
        buildRequest(
          resolvedMoldPath: resolvedMoldDirectory.path,
          resultPath: resultFile.path,
        ),
      ),
    );

    final entrypoint = File(
      p.join(helperRoot.path, moldCastSessionHelperEntrypointRelativePath),
    );
    final childExitCode = await (childRunner ?? _runHelperChild)(
      helperRoot: helperRoot,
      entrypoint: entrypoint,
      requestFile: requestFile,
      environment: environment,
    );

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

    return decodeMoldCastSessionLaunchResult(
      resultFile: resultFile,
      fallbackExitCode: childExitCode,
    );
  }

  try {
    if (cacheHelperResolve) {
      return await withMoldCastSessionHelperCacheLock(
        helperRoot: helperRoot,
        action: runSession,
      );
    }
    return await runSession();
  } finally {
    final shouldDelete =
        prepared.ephemeral && !keepHelperForDebug && helperRoot.existsSync();
    if (shouldDelete) {
      await helperRoot.delete(recursive: true);
    }
  }
}

/// Resolves whether the running `foundry_cli` should be path- or hosted-linked.
Future<FoundryCliHelperDependency> resolveFoundryCliHelperDependency({
  Map<String, String>? environment,
}) async {
  final packageRoot = await resolvePackageRoot('foundry_cli');
  if (isPathInsidePubCache(packageRoot.path, environment: environment)) {
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

Future<ProcessResult> _runHelperPubGet(Directory helperRoot) {
  return Process.run(
    Platform.resolvedExecutable,
    ['pub', 'get'],
    workingDirectory: helperRoot.path,
  );
}

Future<int> _runHelperChild({
  required Directory helperRoot,
  required File entrypoint,
  required File requestFile,
  Map<String, String>? environment,
}) async {
  final process = await Process.start(
    Platform.resolvedExecutable,
    ['run', entrypoint.path, requestFile.path],
    workingDirectory: helperRoot.path,
    mode: ProcessStartMode.inheritStdio,
    environment:
        environment == null ? null : {...Platform.environment, ...environment},
  );
  return process.exitCode;
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

/// Decodes the JSON result payload written by the synthetic session bridge.
MoldCastSessionLaunchResult decodeMoldCastSessionLaunchResult({
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
    if (map['describe'] == true) {
      final variables = map['variables'];
      if (variables is! List) {
        return MoldCastSessionLaunchFailure(
          kind: 'internal',
          message: 'Describe success payload was missing variables.',
          exitCode: FoundryExitCode.internalError.code,
        );
      }
      try {
        return MoldCastSessionDescribeSuccess(
          variables: [
            for (final entry in variables)
              if (entry is Map)
                MoldVariableDescription.fromJson({
                  for (final mapEntry in entry.entries)
                    if (mapEntry.key is String)
                      mapEntry.key as String: mapEntry.value,
                }),
          ],
          exitCode: fallbackExitCode == 0
              ? FoundryExitCode.success.code
              : fallbackExitCode,
        );
      } on FormatException catch (error) {
        return MoldCastSessionLaunchFailure(
          kind: 'internal',
          message: 'Describe success payload was invalid: $error',
          exitCode: FoundryExitCode.internalError.code,
        );
      }
    }

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

/// Whether [path] resolves inside the active pub cache roots.
bool isPathInsidePubCache(
  String path, {
  Map<String, String>? environment,
}) {
  final env = environment ?? Platform.environment;
  final absolute = p.normalize(p.absolute(path));
  final candidates = <String>[
    if (env['PUB_CACHE'] case final pubCache?) pubCache,
    if (env['HOME'] case final home?) p.join(home, '.pub-cache'),
    if (env['LOCALAPPDATA'] case final localAppData?)
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
