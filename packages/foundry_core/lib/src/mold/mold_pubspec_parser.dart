import 'package:foundry_core/src/mold/mold_issue.dart';
import 'package:foundry_core/src/mold/mold_pubspec.dart';
import 'package:yaml/yaml.dart';

/// Parses a mold root `pubspec.yaml` from [yamlContent].
///
/// Returns a [MoldPubspec] on success or throws [MoldLoadException] with
/// structured [MoldIssue]s when required fields are missing or invalid.
MoldPubspec parseMoldPubspec({
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
  final version = _readRequiredString(
    document,
    field: 'version',
    sourcePath: sourcePath,
    issues: issues,
  );

  _validateFoundryCoreDependency(
    document,
    sourcePath: sourcePath,
    issues: issues,
  );

  if (issues.isNotEmpty) {
    throw MoldLoadException(issues);
  }

  return MoldPubspec(
    name: name!,
    description: description!,
    version: version!,
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

void _validateFoundryCoreDependency(
  YamlMap document, {
  required String sourcePath,
  required List<MoldIssue> issues,
}) {
  final dependencies = document['dependencies'];
  if (dependencies is! YamlMap || !dependencies.containsKey('foundry_core')) {
    issues.add(
      MoldIssue(
        severity: MoldIssueSeverity.error,
        path: sourcePath,
        message: 'Mold pubspec must declare a foundry_core dependency so '
            'variables.dart and hooks can import package:foundry_core.',
      ),
    );
  }
}
