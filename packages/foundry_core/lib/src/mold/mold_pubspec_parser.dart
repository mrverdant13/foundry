import 'package:checked_yaml/checked_yaml.dart';
import 'package:foundry_core/src/mold/mold_issue.dart';
import 'package:foundry_core/src/mold/mold_pubspec.dart';
import 'package:pubspec_parse/pubspec_parse.dart';

/// Parses a mold root `pubspec.yaml` from [yamlContent].
///
/// Returns a [MoldPubspec] on success or throws [MoldLoadException] with
/// structured [MoldIssue]s when required fields are missing or invalid.
MoldPubspec parseMoldPubspec({
  required String yamlContent,
  required String sourcePath,
}) {
  final Pubspec pubspec;
  try {
    pubspec = Pubspec.parse(
      yamlContent,
      sourceUrl: Uri.file(sourcePath),
    );
  } on ParsedYamlException catch (error) {
    throw MoldLoadException([
      MoldIssue(
        severity: MoldIssueSeverity.error,
        path: sourcePath,
        message: _describeParseFailure(error),
      ),
    ]);
  }

  final issues = <MoldIssue>[];

  if (pubspec.name.trim().isEmpty) {
    issues.add(
      MoldIssue(
        severity: MoldIssueSeverity.error,
        path: sourcePath,
        message: 'Field "name" must be a non-empty string.',
      ),
    );
  }

  final description = pubspec.description?.trim();
  if (description == null || description.isEmpty) {
    issues.add(
      MoldIssue(
        severity: MoldIssueSeverity.error,
        path: sourcePath,
        message: 'Missing required field "description".',
      ),
    );
  }

  final version = pubspec.version;
  if (version == null) {
    issues.add(
      MoldIssue(
        severity: MoldIssueSeverity.error,
        path: sourcePath,
        message: 'Missing required field "version".',
      ),
    );
  }

  if (!pubspec.dependencies.containsKey('foundry_core')) {
    issues.add(
      MoldIssue(
        severity: MoldIssueSeverity.error,
        path: sourcePath,
        message: 'Mold pubspec must declare a foundry_core dependency so '
            'variables.dart and hooks can import package:foundry_core.',
      ),
    );
  }

  if (issues.isNotEmpty) {
    throw MoldLoadException(issues);
  }

  return MoldPubspec(
    name: pubspec.name,
    description: description!,
    version: version!.toString(),
  );
}

String _describeParseFailure(ParsedYamlException error) {
  final message = error.message;
  if (message.contains('Missing key "name"')) {
    return 'Missing required field "name".';
  }

  return 'Could not parse pubspec.yaml: $message';
}
