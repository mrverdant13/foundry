import 'dart:io';

import 'package:foundry_core/foundry_core.dart';
import 'package:path/path.dart' as p;

Future<void> main() async {
  final exampleRoot = File(Platform.script.toFilePath()).parent.path;
  final moldPath = p.join(exampleRoot, 'mold');
  final outputPath = p.join(exampleRoot, 'output');

  stdout
    ..writeln('Inspecting mold at $moldPath')
    ..writeln();

  final report = await inspectMold(moldPath);
  if (!report.isValid) {
    stderr.writeln('Inspection failed:');
    for (final issue in report.issues) {
      stderr.writeln('  $issue');
    }
    exitCode = 1;
    return;
  }

  stdout
    ..writeln('Inspection passed.')
    ..writeln();

  final mold = report.mold!;
  final outputDirectory = Directory(outputPath);
  if (outputDirectory.existsSync()) {
    await outputDirectory.delete(recursive: true);
  }

  stdout
    ..writeln('Casting mold to $outputPath')
    ..writeln();

  final outcome = await castMold(
    mold: mold,
    outputPath: outputPath,
    values: const {'project_name': 'hello_foundry'},
    force: true,
    noHooks: true,
  );

  stdout
    ..writeln(
      'Cast completed: ${outcome.artifactCount} file(s) written.',
    )
    ..writeln();

  final readme = File(p.join(outputPath, 'README.md'));
  if (readme.existsSync()) {
    stdout
      ..writeln('Generated README.md:')
      ..writeln(readme.readAsStringSync());
  }
}
