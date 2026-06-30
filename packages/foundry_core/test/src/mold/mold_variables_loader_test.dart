import 'dart:io';

import 'package:foundry_core/src/mold/mold_issue.dart';
import 'package:foundry_core/src/mold/mold_variables_loader.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

Future<File> _writeWrapper(String contents) async {
  final tempDir =
      await Directory.systemTemp.createTemp('foundry_wrapper_test_');
  final wrapper = File(p.join(tempDir.path, 'wrapper.dart'));
  await wrapper.writeAsString(contents);
  addTearDown(() => tempDir.deleteSync(recursive: true));
  return wrapper;
}

String _packageConfigPath() {
  var current = Directory.current;
  while (true) {
    final config =
        File(p.join(current.path, '.dart_tool', 'package_config.json'));
    if (config.existsSync()) {
      return config.path;
    }

    final parent = current.parent;
    if (parent.path == current.path) {
      fail('Could not locate package_config.json');
    }
    current = parent;
  }
}

void main() {
  tearDown(() {
    moldVariablesLoaderTimeout = const Duration(seconds: 30);
  });

  test('throws StateError when package config cannot be resolved', () async {
    final previous = Directory.current;
    final emptyDir = await Directory.systemTemp.createTemp(
      'foundry_no_package_config_',
    );
    final variablesFile = File('${emptyDir.path}/variables.dart');
    await variablesFile.writeAsString('const moldVariables = null;');

    try {
      Directory.current = emptyDir;
      expect(
        () => loadMoldVariableGroup(variablesFile: variablesFile),
        throwsA(isA<StateError>()),
      );
    } finally {
      Directory.current = previous;
      await emptyDir.delete(recursive: true);
    }
  });

  test('spawn wrapper reports string errors from the child isolate', () async {
    final wrapper = await _writeWrapper('''
import 'dart:isolate';

void main(List<String> args, Object? message) {
  final sendPort = message! as SendPort;
  sendPort.send('custom loader error');
}
''');

    await expectLater(
      spawnMoldVariablesWrapperForTesting(
        wrapper: wrapper,
        packageConfigPath: _packageConfigPath(),
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

    await expectLater(
      spawnMoldVariablesWrapperForTesting(
        wrapper: wrapper,
        packageConfigPath: _packageConfigPath(),
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

    await expectLater(
      spawnMoldVariablesWrapperForTesting(
        wrapper: wrapper,
        packageConfigPath: _packageConfigPath(),
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
