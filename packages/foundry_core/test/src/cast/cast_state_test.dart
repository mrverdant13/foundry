import 'package:foundry_core/foundry_core.dart';
import 'package:test/test.dart';

void main() {
  group('CastState', () {
    test('round-trips through toJson/fromJson', () {
      final state = CastState(
        moldPath: './flutter_app',
        outputPath: './my_app',
        vars: const {
          'project_name': 'MyApp',
          'project_type': 'app',
          'retries': 3,
          'enabled': true,
          'nickname': null,
          'metadata': {'nested': 'value'},
        },
        timestamp: DateTime.utc(2026, 6, 26, 12),
      );

      final roundTripped = CastState.fromJson(state.toJson());

      expect(roundTripped.moldPath, state.moldPath);
      expect(roundTripped.outputPath, state.outputPath);
      expect(roundTripped.vars, state.vars);
      expect(roundTripped.timestamp, state.timestamp);
    });

    test('toJson encodes timestamp as ISO-8601', () {
      final state = CastState(
        moldPath: './flutter_app',
        outputPath: './my_app',
        vars: const {},
        timestamp: DateTime.utc(2026, 6, 26, 12),
      );

      expect(
        state.toJson()['timestamp'],
        matches(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?Z$'),
      );
    });

    test('toJson keeps vars as plain JSON primitives (no type tags)', () {
      final state = CastState(
        moldPath: './flutter_app',
        outputPath: './my_app',
        vars: const {'project_name': 'MyApp', 'project_type': 'app'},
        timestamp: DateTime.utc(2026, 6, 26, 12),
      );

      expect(
        state.toJson()['vars'],
        {'project_name': 'MyApp', 'project_type': 'app'},
      );
    });
  });
}
