import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'helpers/run_foundry.dart';

void main() {
  group('foundry mold init', () {
    late Directory workDir;

    setUp(() async {
      workDir = await Directory.systemTemp.createTemp('foundry_cli_init_e2e_');
    });

    tearDown(() async {
      if (workDir.existsSync()) {
        await workDir.delete(recursive: true);
      }
    });

    test(
      'scaffolds a mold in the working directory',
      () async {
        final result = await runFoundry(
          ['mold', 'init', '--name=flutter_app'],
          workingDirectory: workDir.path,
        );

        expect(result.exitCode, 0, reason: result.stderr);
        expect(
          File(p.join(workDir.path, 'pubspec.yaml')).existsSync(),
          isTrue,
        );
        expect(
          File(p.join(workDir.path, 'variables.dart')).existsSync(),
          isTrue,
        );
        expect(
          Directory(p.join(workDir.path, 'template')).existsSync(),
          isTrue,
        );
        expect(
          Directory(p.join(workDir.path, 'hooks')).existsSync(),
          isTrue,
        );
        expect(
          File(p.join(workDir.path, 'pubspec.yaml')).readAsStringSync(),
          contains('name: flutter_app'),
        );
        expect(result.stdout, contains('flutter_app'));
      },
      tags: const ['e2e'],
    );
  });
}
