import 'dart:convert';
import 'dart:io';

import 'package:foundry_core/foundry_core.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory cwd;

  setUp(() async {
    cwd = await Directory.systemTemp.createTemp('foundry_cast_state_');
  });

  tearDown(() => cwd.delete(recursive: true));

  group('writeCastState / readCastState', () {
    test('writes state to .foundry/last_cast.json under cwd', () async {
      final state = CastState(
        moldPath: './flutter_app',
        outputPath: './my_app',
        vars: const {'project_name': 'MyApp'},
        timestamp: DateTime.utc(2026, 6, 26, 12),
      );

      await writeCastState(state, cwd: cwd);

      final file = File(p.join(cwd.path, '.foundry', 'last_cast.json'));
      expect(file.existsSync(), isTrue);
      final decoded =
          json.decode(await file.readAsString()) as Map<String, Object?>;
      expect(decoded['moldPath'], './flutter_app');
      expect(decoded['outputPath'], './my_app');
      expect(decoded['vars'], {'project_name': 'MyApp'});
      expect(decoded['timestamp'], matches('^2026-06-26T12:00:00'));
    });

    test('creates the .foundry directory when it does not exist', () async {
      expect(Directory(p.join(cwd.path, '.foundry')).existsSync(), isFalse);

      await writeCastState(
        CastState(
          moldPath: './mold',
          outputPath: './out',
          vars: const {},
          timestamp: DateTime.utc(2026),
        ),
        cwd: cwd,
      );

      expect(Directory(p.join(cwd.path, '.foundry')).existsSync(), isTrue);
    });

    test('readCastState returns the previously written state', () async {
      final written = CastState(
        moldPath: './flutter_app',
        outputPath: './my_app',
        vars: const {'project_name': 'MyApp', 'project_type': 'app'},
        timestamp: DateTime.utc(2026, 6, 26, 12),
      );
      await writeCastState(written, cwd: cwd);

      final read = await readCastState(cwd: cwd);

      expect(read.moldPath, written.moldPath);
      expect(read.outputPath, written.outputPath);
      expect(read.vars, written.vars);
      expect(read.timestamp, written.timestamp);
    });

    test('writeCastState overwrites previously persisted state', () async {
      await writeCastState(
        CastState(
          moldPath: './first',
          outputPath: './first-out',
          vars: const {},
          timestamp: DateTime.utc(2026),
        ),
        cwd: cwd,
      );

      await writeCastState(
        CastState(
          moldPath: './second',
          outputPath: './second-out',
          vars: const {},
          timestamp: DateTime.utc(2026, 6, 26),
        ),
        cwd: cwd,
      );

      final read = await readCastState(cwd: cwd);
      expect(read.moldPath, './second');
      expect(read.outputPath, './second-out');
    });

    test(
      'readCastState throws CastStateNotFoundException when missing',
      () async {
        await expectLater(
          readCastState(cwd: cwd),
          throwsA(
            isA<CastStateNotFoundException>().having(
              (e) => e.path,
              'path',
              p.join(cwd.path, '.foundry', 'last_cast.json'),
            ),
          ),
        );
      },
    );

    test('CastStateNotFoundException toString is actionable', () {
      const exception = CastStateNotFoundException('/tmp/.foundry/x.json');

      expect(exception, isA<Exception>());
      expect(exception.toString(), contains('/tmp/.foundry/x.json'));
      expect(exception.toString(), contains('foundry cast'));
    });
  });

  group('castStateFile', () {
    test('defaults to the process cwd when none is given', () {
      final file = castStateFile();

      expect(
        file.path,
        p.join(Directory.current.path, '.foundry', 'last_cast.json'),
      );
    });
  });
}
