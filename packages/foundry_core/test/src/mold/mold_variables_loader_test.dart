import 'dart:io';

import 'package:foundry_core/src/mold/mold_issue.dart';
import 'package:foundry_core/src/mold/mold_variables_loader.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'mold_test_support.dart';

Future<File> _writeWrapper(String contents) async {
  final tempDir =
      await Directory.systemTemp.createTemp('foundry_wrapper_test_');
  final wrapper = File(p.join(tempDir.path, 'wrapper.dart'));
  await wrapper.writeAsString(contents);
  addTearDown(() => tempDir.deleteSync(recursive: true));
  return wrapper;
}

void main() {
  tearDown(() {
    moldVariablesLoaderTimeout = const Duration(seconds: 30);
  });

  test('throws when package config is missing', () async {
    final tempDir = await Directory.systemTemp.createTemp('foundry_no_config_');
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final variablesFile = File(p.join(tempDir.path, 'variables.dart'));
    await variablesFile.writeAsString('const moldVariables = null;');

    expect(
      () => loadMoldVariableGroup(
        variablesFile: variablesFile,
        packageConfigPath:
            p.join(tempDir.path, '.dart_tool', 'package_config.json'),
      ),
      throwsA(
        isA<MoldLoadException>().having(
          (error) => error.issues.first.message,
          'message',
          contains('package config'),
        ),
      ),
    );
  });

  test('spawn wrapper reports string errors from the child isolate', () async {
    final wrapper = await _writeWrapper('''
import 'dart:isolate';

void main(List<String> args, Object? message) {
  final sendPort = message! as SendPort;
  sendPort.send('custom loader error');
}
''');

    final packageConfigPath = workspacePackageConfigPath();

    await expectLater(
      spawnMoldVariablesWrapperForTesting(
        wrapper: wrapper,
        packageConfigPath: packageConfigPath,
        variablesPath: 'variables.dart',
      ),
      throwsA(
        isA<MoldLoadException>().having(
          (error) => error.issues.single.message,
          'message',
          'custom loader error',
        ),
      ),
    );
  });

  test('spawn wrapper reports unexpected isolate responses', () async {
    final wrapper = await _writeWrapper('''
import 'dart:isolate';

void main(List<String> args, Object? message) {
  final sendPort = message! as SendPort;
  sendPort.send(42);
}
''');

    final packageConfigPath = workspacePackageConfigPath();

    await expectLater(
      spawnMoldVariablesWrapperForTesting(
        wrapper: wrapper,
        packageConfigPath: packageConfigPath,
        variablesPath: 'variables.dart',
      ),
      throwsA(
        isA<MoldLoadException>().having(
          (error) => error.issues.single.message,
          'message',
          contains('Unexpected response'),
        ),
      ),
    );
  });

  test('spawn wrapper times out when the child isolate never responds',
      () async {
    moldVariablesLoaderTimeout = const Duration(milliseconds: 50);

    final wrapper = await _writeWrapper('''
import 'dart:isolate';

Future<void> main(List<String> args, Object? message) async {
  await Future<void>.delayed(const Duration(seconds: 5));
}
''');

    final packageConfigPath = workspacePackageConfigPath();

    await expectLater(
      spawnMoldVariablesWrapperForTesting(
        wrapper: wrapper,
        packageConfigPath: packageConfigPath,
        variablesPath: 'variables.dart',
      ),
      throwsA(
        isA<MoldLoadException>().having(
          (error) => error.issues.single.message,
          'message',
          contains('Timed out'),
        ),
      ),
    );
  });
}
