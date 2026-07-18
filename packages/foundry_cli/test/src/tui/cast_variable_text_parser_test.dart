import 'package:foundry_cli/src/tui/cast_variable_text_parser.dart';
import 'package:foundry_core/foundry_core.dart';
import 'package:test/test.dart';

void main() {
  group('parseCastVariableText', () {
    group('FoundryStringVariable', () {
      const variable = FoundryStringVariable(label: 'Name');

      test('preserves the raw text, including spaces', () {
        final result = parseCastVariableText(variable, '  hello  ');

        expect(result, isA<CastVariableTextParseSuccess>());
        expect((result as CastVariableTextParseSuccess).value, '  hello  ');
      });

      test('preserves an empty string', () {
        final result = parseCastVariableText(variable, '');

        expect(result, isA<CastVariableTextParseSuccess>());
        expect((result as CastVariableTextParseSuccess).value, '');
      });
    });

    group('FoundryBooleanVariable', () {
      const variable = FoundryBooleanVariable(label: 'Enabled');

      test('parses true-like tokens', () {
        for (final text in ['true', 'TRUE', 'yes', 'Y', '1']) {
          final result = parseCastVariableText(variable, text);
          expect(result, isA<CastVariableTextParseSuccess>());
          expect((result as CastVariableTextParseSuccess).value, isTrue);
        }
      });

      test('parses false-like tokens', () {
        for (final text in ['false', 'FALSE', 'no', 'N', '0']) {
          final result = parseCastVariableText(variable, text);
          expect(result, isA<CastVariableTextParseSuccess>());
          expect((result as CastVariableTextParseSuccess).value, isFalse);
        }
      });

      test('treats blank input as null', () {
        final result = parseCastVariableText(variable, '  ');

        expect(result, isA<CastVariableTextParseSuccess>());
        expect((result as CastVariableTextParseSuccess).value, isNull);
      });

      test('rejects unrecognized text', () {
        final result = parseCastVariableText(variable, 'maybe');

        expect(result, isA<CastVariableTextParseFailure>());
        expect(
          (result as CastVariableTextParseFailure).message,
          'Enter yes/no or true/false',
        );
      });
    });

    group('FoundryIntVariable', () {
      const variable = FoundryIntVariable(label: 'Port');

      test('parses integers', () {
        final result = parseCastVariableText(variable, ' 42 ');

        expect(result, isA<CastVariableTextParseSuccess>());
        expect((result as CastVariableTextParseSuccess).value, 42);
      });

      test('treats blank input as null', () {
        final result = parseCastVariableText(variable, '');

        expect(result, isA<CastVariableTextParseSuccess>());
        expect((result as CastVariableTextParseSuccess).value, isNull);
      });

      test('rejects non-integers without throwing', () {
        final result = parseCastVariableText(variable, '3.14');

        expect(result, isA<CastVariableTextParseFailure>());
        expect(
          (result as CastVariableTextParseFailure).message,
          'Enter a valid integer',
        );
      });
    });

    group('FoundryDoubleVariable', () {
      const variable = FoundryDoubleVariable(label: 'Ratio');

      test('parses decimals', () {
        final result = parseCastVariableText(variable, ' 3.14 ');

        expect(result, isA<CastVariableTextParseSuccess>());
        expect((result as CastVariableTextParseSuccess).value, 3.14);
      });

      test('treats blank input as null', () {
        final result = parseCastVariableText(variable, ' ');

        expect(result, isA<CastVariableTextParseSuccess>());
        expect((result as CastVariableTextParseSuccess).value, isNull);
      });

      test('rejects non-numbers without throwing', () {
        final result = parseCastVariableText(variable, 'pi');

        expect(result, isA<CastVariableTextParseFailure>());
        expect(
          (result as CastVariableTextParseFailure).message,
          'Enter a valid number',
        );
      });
    });

    group('choice variables', () {
      test('rejects typed text for single-choice variables', () {
        final variable = FoundrySingleChoiceVariable<String>(
          label: 'Project type',
          options: const ['app', 'package'],
          displayLabel: (value) => value,
        );

        final result = parseCastVariableText(variable, 'app');

        expect(result, isA<CastVariableTextParseFailure>());
        expect(
          (result as CastVariableTextParseFailure).message,
          'Choice values are selected from options, not typed',
        );
      });

      test('rejects typed text for multiple-choice variables', () {
        final variable = FoundryMultipleChoiceVariable<String>(
          label: 'Platforms',
          options: const ['android', 'ios'],
          displayLabel: (value) => value,
        );

        final result = parseCastVariableText(variable, 'android,ios');

        expect(result, isA<CastVariableTextParseFailure>());
        expect(
          (result as CastVariableTextParseFailure).message,
          'Choice values are selected from options, not typed',
        );
      });
    });
  });
}
