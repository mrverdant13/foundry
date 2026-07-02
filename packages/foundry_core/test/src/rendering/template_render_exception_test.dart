import 'package:foundry_core/foundry_core.dart';
import 'package:test/test.dart';

void main() {
  group('TemplateRenderException', () {
    test('implements Exception', () {
      expect(
        const TemplateRenderException('boom'),
        isA<Exception>(),
      );
    });

    test('toString includes the message', () {
      const exception = TemplateRenderException('boom');

      expect(exception.toString(), 'TemplateRenderException: boom');
    });
  });
}
