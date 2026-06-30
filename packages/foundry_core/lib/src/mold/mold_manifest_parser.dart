import 'package:foundry_core/src/mold/mold_hooks.dart';
import 'package:foundry_core/src/mold/mold_issue.dart';
import 'package:foundry_core/src/mold/mold_manifest.dart';
import 'package:yaml/yaml.dart';

/// Parses a `mold.yaml` manifest from [yamlContent].
///
/// Returns a [MoldManifest] on success or throws [MoldLoadException] with
/// structured [MoldIssue]s when required fields are missing or invalid.
MoldManifest parseMoldManifest({
  required String yamlContent,
  required String sourcePath,
}) {
  final issues = <MoldIssue>[];

  final dynamic document;
  try {
    document = loadYaml(yamlContent);
  } on YamlException catch (error) {
    throw MoldLoadException([
      MoldIssue(
        severity: MoldIssueSeverity.error,
        path: sourcePath,
        message: 'Invalid YAML: $error',
      ),
    ]);
  }

  if (document is! YamlMap) {
    throw MoldLoadException([
      MoldIssue(
        severity: MoldIssueSeverity.error,
        path: sourcePath,
        message: 'Expected a YAML map at the document root.',
      ),
    ]);
  }

  final name = _readRequiredString(
    document,
    field: 'name',
    sourcePath: sourcePath,
    issues: issues,
  );
  final description = _readRequiredString(
    document,
    field: 'description',
    sourcePath: sourcePath,
    issues: issues,
  );

  if (issues.isNotEmpty) {
    throw MoldLoadException(issues);
  }

  final hooks = _parseHooks(
    document['hooks'],
    sourcePath: sourcePath,
    issues: issues,
  );

  if (issues.isNotEmpty) {
    throw MoldLoadException(issues);
  }

  return MoldManifest(
    name: name!,
    description: description!,
    hooks: hooks,
  );
}

String? _readRequiredString(
  YamlMap document, {
  required String field,
  required String sourcePath,
  required List<MoldIssue> issues,
}) {
  final value = document[field];
  if (value == null) {
    issues.add(
      MoldIssue(
        severity: MoldIssueSeverity.error,
        path: sourcePath,
        message: 'Missing required field "$field".',
      ),
    );
    return null;
  }

  final stringValue = value.toString().trim();
  if (stringValue.isEmpty) {
    issues.add(
      MoldIssue(
        severity: MoldIssueSeverity.error,
        path: sourcePath,
        message: 'Field "$field" must be a non-empty string.',
      ),
    );
    return null;
  }

  return stringValue;
}

MoldHooks _parseHooks(
  Object? hooksNode, {
  required String sourcePath,
  required List<MoldIssue> issues,
}) {
  if (hooksNode == null) {
    return const MoldHooks();
  }

  if (hooksNode is! YamlMap) {
    issues.add(
      MoldIssue(
        severity: MoldIssueSeverity.error,
        path: sourcePath,
        message: 'Field "hooks" must be a YAML map.',
      ),
    );
    return const MoldHooks();
  }

  String? readHookPath(String phase) {
    final value = hooksNode[phase];
    if (value == null) {
      return null;
    }

    final path = value.toString().trim();
    if (path.isEmpty) {
      issues.add(
        MoldIssue(
          severity: MoldIssueSeverity.error,
          path: sourcePath,
          message: 'Hook path "$phase" must be a non-empty string.',
        ),
      );
      return null;
    }

    return path;
  }

  return MoldHooks(
    prepare: readHookPath('prepare'),
    shape: readHookPath('shape'),
    finish: readHookPath('finish'),
  );
}
