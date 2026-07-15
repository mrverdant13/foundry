import 'dart:convert';
import 'dart:io';

import 'package:foundry_cli/src/commands/cast_command.dart';
import 'package:foundry_core/foundry_core.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory workDir;

  setUp(() {
    workDir = Directory.systemTemp.createTempSync('foundry_cast_state_reader_');
  });

  tearDown(() {
    if (workDir.existsSync()) {
      workDir.deleteSync(recursive: true);
    }
  });

  group('readCastStateOrReportError', () {
    test('returns cast state when last_cast.json is valid', () async {
      final foundryDir = Directory(p.join(workDir.path, '.foundry'))
        ..createSync();
      await File(p.join(foundryDir.path, 'last_cast.json')).writeAsString(
        jsonEncode({
          'moldPath': 'mold',
          'outputPath': 'out',
          'vars': {'project_name': 'Ada'},
          'timestamp': '2026-01-01T00:00:00.000Z',
        }),
      );
      final errorMessages = <String>[];

      final state = await readCastStateOrReportError(
        logger: Logger(onError: errorMessages.add),
        workingDirectory: workDir,
      );

      expect(state, isNotNull);
      expect(state!.moldPath, 'mold');
      expect(state.outputPath, 'out');
      expect(errorMessages, isEmpty);
    });

    test('logs and returns null when cast state is missing', () async {
      final errorMessages = <String>[];

      final state = await readCastStateOrReportError(
        logger: Logger(onError: errorMessages.add),
        workingDirectory: workDir,
      );

      expect(state, isNull);
      expect(errorMessages, contains(contains('Run `foundry cast` first')));
    });

    test('logs and returns null when cast state is not valid JSON', () async {
      final foundryDir = Directory(p.join(workDir.path, '.foundry'))
        ..createSync();
      await File(p.join(foundryDir.path, 'last_cast.json'))
          .writeAsString('not json');
      final errorMessages = <String>[];

      final state = await readCastStateOrReportError(
        logger: Logger(onError: errorMessages.add),
        workingDirectory: workDir,
      );

      expect(state, isNull);
      expect(errorMessages, contains(contains('invalid or corrupted')));
      expect(errorMessages, contains(contains('foundry cast')));
    });

    test('logs and returns null when cast state has an unexpected shape', () async {
      final foundryDir = Directory(p.join(workDir.path, '.foundry'))
        ..createSync();
      await File(p.join(foundryDir.path, 'last_cast.json')).writeAsString(
        jsonEncode({'moldPath': 'mold'}),
      );
      final errorMessages = <String>[];

      final state = await readCastStateOrReportError(
        logger: Logger(onError: errorMessages.add),
        workingDirectory: workDir,
      );

      expect(state, isNull);
      expect(errorMessages, contains(contains('invalid or corrupted')));
      expect(errorMessages, contains(contains('foundry cast')));
    });
  });
}
