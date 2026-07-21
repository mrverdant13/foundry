import 'dart:io';

import 'package:foundry_core/foundry_core.dart';
import 'package:foundry_core/src/rendering/template_liquidize.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('liquidizeTemplateContents', () {
    test('leaves plain text unchanged', () {
      expect(liquidizeTemplateContents('Hello world'), 'Hello world');
    });

    test('wraps content that contains mustache-style braces', () {
      expect(
        liquidizeTemplateContents('Hello {{ name }}'),
        '{% raw %}Hello {{ name }}{% endraw %}',
      );
    });

    test('wraps content that contains Liquid tags', () {
      expect(
        liquidizeTemplateContents('{% if true %}yes{% endif %}'),
        '{% raw %}{% if true %}yes{% endif %}{% endraw %}',
      );
    });
  });

  group('looksLikeBinaryTemplateBytes', () {
    test('detects NUL bytes as binary', () {
      expect(looksLikeBinaryTemplateBytes([0x48, 0x00, 0x69]), isTrue);
    });

    test('treats UTF-8 text as non-binary', () {
      expect(looksLikeBinaryTemplateBytes('hello'.codeUnits), isFalse);
    });
  });

  group('liquidize + renderTemplate', () {
    late Directory tempRoot;

    setUp(() async {
      tempRoot = await Directory.systemTemp.createTemp('foundry_liquidize_');
    });

    tearDown(() async {
      if (tempRoot.existsSync()) {
        await tempRoot.delete(recursive: true);
      }
    });

    test('liquidized braces survive render as literals', () async {
      final templateDirectory = Directory(p.join(tempRoot.path, 'template'))
        ..createSync();
      final outputDirectory = Directory(p.join(tempRoot.path, 'output'))
        ..createSync();

      await File(p.join(templateDirectory.path, 'note.txt')).writeAsString(
        liquidizeTemplateContents('Keep {{ project_name }} literal'),
      );

      await renderTemplate(
        templateDirectory: templateDirectory,
        outputDirectory: outputDirectory,
        context: SnapshotFoundryContext({'project_name': 'my_app'}),
      );

      expect(
        await File(p.join(outputDirectory.path, 'note.txt')).readAsString(),
        'Keep {{ project_name }} literal',
      );
    });
  });
}
