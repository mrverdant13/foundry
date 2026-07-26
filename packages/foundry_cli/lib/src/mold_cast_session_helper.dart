import 'dart:convert';

/// Pub package name for the synthetic mold cast-session helper.
const moldCastSessionHelperPackageName = 'foundry_mold_cast_session_helper';

/// Temp-directory prefix for synthetic mold cast-session helpers.
const moldCastSessionHelperTempPrefix = 'foundry_mold_session_';

/// Relative path of the generated session entrypoint inside the helper package.
const moldCastSessionHelperEntrypointRelativePath = 'bin/cast_session.dart';

/// How the helper package depends on `foundry_cli`.
sealed class FoundryCliHelperDependency {
  const FoundryCliHelperDependency();
}

/// Path dependency on a local `foundry_cli` package root (monorepo / path install).
final class FoundryCliPathDependency extends FoundryCliHelperDependency {
  /// Creates a path dependency on [packageRoot].
  const FoundryCliPathDependency(this.packageRoot);

  /// Absolute path to the `foundry_cli` package root.
  final String packageRoot;
}

/// Hosted dependency on a published `foundry_cli` version.
final class FoundryCliHostedDependency extends FoundryCliHelperDependency {
  /// Creates a hosted dependency constrained to [version].
  const FoundryCliHostedDependency(this.version);

  /// Exact `foundry_cli` version to depend on (typically the running CLI
  /// version).
  final String version;
}

/// Builds `pubspec.yaml` for the synthetic cast-session helper package.
///
/// The helper depends on `foundry_cli` (path or hosted) and on the target mold
/// as a path dependency so `dart pub get` composes one package config that can
/// execute root-level `variables.dart` / `hooks/*.dart` via file URI imports.
String buildMoldCastSessionHelperPubspec({
  required String moldPackageName,
  required String moldPath,
  required FoundryCliHelperDependency foundryCli,
}) {
  final foundryCliDescriptor = switch (foundryCli) {
    FoundryCliPathDependency(:final packageRoot) =>
      '    path: ${_yamlQuoted(packageRoot)}',
    FoundryCliHostedDependency(:final version) =>
      '    version: ${_yamlQuoted(version)}',
  };

  return '''
name: $moldCastSessionHelperPackageName
description: Synthetic helper that runs a Foundry mold cast session.
publish_to: none

environment:
  sdk: ">=3.5.0 <4.0.0"

dependencies:
  foundry_cli:
$foundryCliDescriptor
  $moldPackageName:
    path: ${_yamlQuoted(moldPath)}
''';
}

/// Builds optional `pubspec_overrides.yaml` that forces a single
/// `foundry_core`.
///
/// Required when the helper path-depends on monorepo `foundry_cli` (which pins
/// hosted `foundry_core`) so the live mold and session share one core package.
String? buildMoldCastSessionHelperPubspecOverrides({
  String? foundryCoreOverridePath,
}) {
  if (foundryCoreOverridePath == null) {
    return null;
  }
  return '''
dependency_overrides:
  foundry_core:
    path: ${_yamlQuoted(foundryCoreOverridePath)}
''';
}

/// Hook file URIs to import into the generated session bridge.
final class MoldCastSessionHelperHookImports {
  /// Creates hook import URIs; omit a phase when that hook file is absent.
  const MoldCastSessionHelperHookImports({
    this.prepareUri,
    this.shapeUri,
    this.finishUri,
  });

  /// Absolute file URI for `hooks/prepare.dart`, if present.
  final Uri? prepareUri;

  /// Absolute file URI for `hooks/shape.dart`, if present.
  final Uri? shapeUri;

  /// Absolute file URI for `hooks/finish.dart`, if present.
  final Uri? finishUri;
}

/// Builds the generated `bin/cast_session.dart` bridge source.
///
/// Imports [variablesUri] (mold root `variables.dart`) and any present hook
/// files by file URI, then runs a batch `CastSession` against the live
/// `moldVariables` group in the helper isolate.
String buildMoldCastSessionBridgeSource({
  required Uri variablesUri,
  required MoldCastSessionHelperHookImports hooks,
}) {
  final importLines = <String>[
    "import '$variablesUri' as mold_variables;",
    if (hooks.prepareUri != null)
      "import '${hooks.prepareUri}' as prepare_hook;",
    if (hooks.shapeUri != null) "import '${hooks.shapeUri}' as shape_hook;",
    if (hooks.finishUri != null) "import '${hooks.finishUri}' as finish_hook;",
  ];

  final hookArgs = <String>[
    if (hooks.prepareUri != null) 'prepare: prepare_hook.run,',
    if (hooks.shapeUri != null) 'shape: shape_hook.run,',
    if (hooks.finishUri != null) 'finish: finish_hook.run,',
  ];

  final hooksLiteral = hookArgs.isEmpty
      ? 'const CastSessionHooks()'
      : '''
      CastSessionHooks(
${hookArgs.map((line) => '        $line').join('\n')}
      )''';

  return '''
import 'dart:convert';
import 'dart:io';

import 'package:foundry_cli/foundry_cli.dart';
import 'package:foundry_core/foundry_core.dart';

${importLines.join('\n')}

Future<void> main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln(
      'Usage: cast_session.dart <request.json>',
    );
    exitCode = FoundryExitCode.internalError.code;
    return;
  }

  final requestFile = File(args.single);
  if (!requestFile.existsSync()) {
    stderr.writeln('Missing session request file: \${requestFile.path}');
    exitCode = FoundryExitCode.internalError.code;
    return;
  }

  late final Map<String, Object?> request;
  try {
    final decoded = jsonDecode(await requestFile.readAsString());
    if (decoded is! Map) {
      throw const FormatException('Request root must be a JSON object.');
    }
    request = <String, Object?>{
      for (final entry in decoded.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
  } on Object catch (error) {
    stderr.writeln('Invalid session request: \$error');
    exitCode = FoundryExitCode.internalError.code;
    return;
  }

  final resultPath = request['resultPath'];
  if (resultPath is! String || resultPath.isEmpty) {
    stderr.writeln('Session request missing resultPath.');
    exitCode = FoundryExitCode.internalError.code;
    return;
  }

  final moldPath = request['moldPath'];
  final outputPath = request['outputPath'];
  if (moldPath is! String || moldPath.isEmpty) {
    stderr.writeln('Session request missing moldPath.');
    exitCode = FoundryExitCode.internalError.code;
    return;
  }
  if (outputPath is! String || outputPath.isEmpty) {
    stderr.writeln('Session request missing outputPath.');
    exitCode = FoundryExitCode.internalError.code;
    return;
  }

  final force = request['force'] == true;
  final noHooks = request['noHooks'] == true;
  final varsFlag = request['varsFlag'];
  if (varsFlag != null && varsFlag is! String) {
    stderr.writeln('Session request varsFlag must be a string when present.');
    exitCode = FoundryExitCode.internalError.code;
    return;
  }

  Map<String, Object?>? varsFileValues;
  final rawVarsFileValues = request['varsFileValues'];
  if (rawVarsFileValues != null) {
    if (rawVarsFileValues is! Map) {
      stderr.writeln(
        'Session request varsFileValues must be a JSON object when present.',
      );
      exitCode = FoundryExitCode.internalError.code;
      return;
    }
    varsFileValues = <String, Object?>{
      for (final entry in rawVarsFileValues.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
  }

  final moldDirectory = Directory(moldPath);
  final pubspecFile = File('\$moldPath/pubspec.yaml');
  if (!pubspecFile.existsSync()) {
    await _writeFailureResult(
      resultPath: resultPath,
      kind: 'load',
      message: 'Missing required file "pubspec.yaml".',
    );
    exitCode = FoundryExitCode.userError.code;
    return;
  }

  final MoldPubspec pubspec;
  try {
    pubspec = parseMoldPubspec(
      yamlContent: await pubspecFile.readAsString(),
      sourcePath: pubspecFile.path,
    );
  } on MoldLoadException catch (exception) {
    await _writeFailureResult(
      resultPath: resultPath,
      kind: 'load',
      message: '\$exception',
    );
    exitCode = FoundryExitCode.userError.code;
    return;
  }

  final mold = Mold(
    directory: moldDirectory.absolute,
    pubspec: pubspec,
    variableGroup: mold_variables.moldVariables,
  );

  final result = await CastSession(
    mold: mold,
    outputPath: outputPath,
    hooks: $hooksLiteral,
  ).runBatch(
    varsFileValues: varsFileValues,
    varsFlag: varsFlag as String?,
    force: force,
    noHooks: noHooks,
  );

  switch (result) {
    case BatchCastSessionSuccess(
      :final artifactCount,
      :final vars,
      :final writtenFiles,
      :final outputDirectory,
    ):
      await File(resultPath).writeAsString(
        jsonEncode({
          'ok': true,
          'artifactCount': artifactCount,
          'vars': vars,
          'writtenFiles': [
            for (final file in writtenFiles) file.path,
          ],
          'outputDirectory': outputDirectory.path,
        }),
      );
      exitCode = FoundryExitCode.success.code;
    case BatchCastSessionParseFailure(:final message):
      await _writeFailureResult(
        resultPath: resultPath,
        kind: 'parse',
        message: message,
      );
      exitCode = FoundryExitCode.userError.code;
    case BatchCastSessionHookFailure(:final message):
      await _writeFailureResult(
        resultPath: resultPath,
        kind: 'hook',
        message: message,
      );
      exitCode = FoundryExitCode.userError.code;
    case BatchCastSessionRenderFailure(:final message):
      await _writeFailureResult(
        resultPath: resultPath,
        kind: 'render',
        message: message,
      );
      exitCode = FoundryExitCode.userError.code;
    case BatchCastSessionContextFailure(:final message):
      await _writeFailureResult(
        resultPath: resultPath,
        kind: 'context',
        message: message,
      );
      exitCode = FoundryExitCode.userError.code;
  }
}

Future<void> _writeFailureResult({
  required String resultPath,
  required String kind,
  required String message,
}) async {
  await File(resultPath).writeAsString(
    jsonEncode({
      'ok': false,
      'kind': kind,
      'message': message,
    }),
  );
}
''';
}

String _yamlQuoted(String value) => jsonEncode(value);
