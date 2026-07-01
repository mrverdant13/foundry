import 'package:foundry_core/src/logging/logger.dart';
import 'package:test/test.dart';

void main() {
  group('Logger', () {
    test('info forwards the message unchanged', () {
      final messages = <String>[];
      Logger(onInfo: messages.add).info('Loading mold…');

      expect(messages, ['Loading mold…']);
    });

    test('warn prefixes the message', () {
      final messages = <String>[];
      Logger(onWarn: messages.add).warn('Deprecated field.');

      expect(messages, ['[WARN] Deprecated field.']);
    });

    test('error prefixes the message', () {
      final messages = <String>[];
      Logger(onError: messages.add).error('Hook crashed.');

      expect(messages, ['[ERROR] Hook crashed.']);
    });

    test('progress reports the starting message immediately', () {
      final messages = <String>[];
      Logger(onProgress: messages.add).progress('Rendering template…');

      expect(messages, ['Rendering template…']);
    });

    test('default sinks do not throw', () {
      final logger = Logger();

      expect(() => logger.info('hi'), returnsNormally);
      expect(() => logger.warn('hi'), returnsNormally);
      expect(() => logger.error('hi'), returnsNormally);
      expect(() => logger.progress('hi'), returnsNormally);
    });
  });

  group('Progress', () {
    test('update reports intermediate status verbatim', () {
      final messages = <String>[];
      Logger(
        onProgress: messages.add,
      ).progress('Copying files…').update('50%…');

      expect(messages, ['Copying files…', '50%…']);
    });

    test('complete without a message reuses the starting message', () {
      final messages = <String>[];
      final logger = Logger(onProgress: messages.add);

      logger.progress('Copying files…').complete();

      expect(messages, ['Copying files…', '[DONE] Copying files…']);
    });

    test('complete with a message reports it instead', () {
      final messages = <String>[];
      final logger = Logger(onProgress: messages.add);

      logger.progress('Copying files…').complete('Copied 12 files.');

      expect(messages, ['Copying files…', '[DONE] Copied 12 files.']);
    });

    test('fail without a message reuses the starting message', () {
      final messages = <String>[];
      final logger = Logger(onProgress: messages.add);

      logger.progress('Copying files…').fail();

      expect(messages, ['Copying files…', '[FAIL] Copying files…']);
    });

    test('fail with a message reports it instead', () {
      final messages = <String>[];
      final logger = Logger(onProgress: messages.add);

      logger.progress('Copying files…').fail('Disk full.');

      expect(messages, ['Copying files…', '[FAIL] Disk full.']);
    });

    test('cancel without a message reuses the starting message', () {
      final messages = <String>[];
      final logger = Logger(onProgress: messages.add);

      logger.progress('Copying files…').cancel();

      expect(messages, ['Copying files…', '[CANCELLED] Copying files…']);
    });

    test('cancel with a message reports it instead', () {
      final messages = <String>[];
      final logger = Logger(onProgress: messages.add);

      logger.progress('Copying files…').cancel('Interrupted by user.');

      expect(messages, ['Copying files…', '[CANCELLED] Interrupted by user.']);
    });
  });
}
