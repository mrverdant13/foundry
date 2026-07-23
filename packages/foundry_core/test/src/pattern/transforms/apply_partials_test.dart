import 'dart:io';

import 'package:foundry_core/src/pattern/transforms/apply_partials.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('applyPartials', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('foundry_apply_partials_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('extracts and creates partials in all comment flavors', () {
      const input = '''
text
/*partial v partialA*/this is
the partial
A
/*partial ^ partialA*/
more text
#partial v partialB#this is
the partial
B
#partial ^ partialB#
yet more text
<!--partial v partialC-->this is
the partial
C
<!--partial ^ partialC-->
and even more text
''';
      const expected = '''
text
{% render 'partialA.partial' %}
more text
{% render 'partialB.partial' %}
yet more text
{% render 'partialC.partial' %}
and even more text
''';

      final result = applyPartials(
        content: input,
        targetAbsolutePath: tempDir.path,
      );

      expect(result, expected);

      for (final partialName in ['A', 'B', 'C']) {
        final partialFile = File(
          p.join(tempDir.path, 'partial$partialName.partial'),
        );
        expect(
          partialFile.existsSync(),
          isTrue,
          reason: 'partial$partialName file should exist',
        );
        expect(
          partialFile.readAsStringSync(),
          '''
this is
the partial
$partialName
''',
        );
      }
    });

    test('extracts C-style partial blocks', () {
      const input = '''
before
/*partial v header*/line one
line two
/*partial ^ header*/
after
''';

      final result = applyPartials(
        content: input,
        targetAbsolutePath: tempDir.path,
      );

      expect(result, '''
before
{% render 'header.partial' %}
after
''');

      final partialFile = File(p.join(tempDir.path, 'header.partial'));
      expect(partialFile.readAsStringSync(), '''
line one
line two
''');
    });

    test('extracts hash partial blocks', () {
      const input = '#partial v footer#footer content\n#partial ^ footer#';

      final result = applyPartials(
        content: input,
        targetAbsolutePath: tempDir.path,
      );

      expect(result, "{% render 'footer.partial' %}");

      final partialFile = File(p.join(tempDir.path, 'footer.partial'));
      expect(partialFile.readAsStringSync(), 'footer content\n');
    });

    test('extracts HTML partial blocks', () {
      const input =
          '<!--partial v sidebar--><nav>links</nav>\n<!--partial ^ sidebar-->';

      final result = applyPartials(
        content: input,
        targetAbsolutePath: tempDir.path,
      );

      expect(result, "{% render 'sidebar.partial' %}");

      final partialFile = File(p.join(tempDir.path, 'sidebar.partial'));
      expect(partialFile.readAsStringSync(), '<nav>links</nav>\n');
    });

    test('leaves content without partial blocks unchanged', () {
      const input = '''
plain text
/*not a partial block*/
#partial v missing closing marker
<!--partial ^ unmatched-->
''';

      final result = applyPartials(
        content: input,
        targetAbsolutePath: tempDir.path,
      );

      expect(result, input);
      expect(tempDir.listSync(), isEmpty);
    });

    test('trims whitespace from partial names', () {
      const input = '/*partial v  partialA  */content/*partial ^ partialA  */';

      final result = applyPartials(
        content: input,
        targetAbsolutePath: tempDir.path,
      );

      expect(result, "{% render 'partialA.partial' %}");

      final partialFile = File(p.join(tempDir.path, 'partialA.partial'));
      expect(partialFile.readAsStringSync(), 'content');
    });

    test('throws FormatException for invalid partial names', () {
      for (final name in [
        '..',
        '.',
        r'foo\bar',
        'foo:bar',
        'foo<bar',
        'foo>bar',
        'foo"bar',
        'foo|bar',
        'foo?bar',
      ]) {
        final input = '''
/*partial v $name*/payload
/*partial ^ $name*/
''';

        expect(
          () => applyPartials(
            content: input,
            targetAbsolutePath: tempDir.path,
          ),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              contains('Invalid partial name'),
            ),
          ),
          reason: 'partial name "$name" should be rejected',
        );
        expect(
          tempDir.listSync(),
          isEmpty,
          reason: 'no files should be created for "$name"',
        );
      }
    });

    test('leaves partial blocks with unmatchable names unchanged', () {
      const unmatchableNames = [
        '../evil',
        'foo/bar',
        'foo*bar',
        '   ',
      ];

      for (final name in unmatchableNames) {
        final input = '''
/*partial v $name*/payload
/*partial ^ $name*/
''';

        expect(
          applyPartials(
            content: input,
            targetAbsolutePath: tempDir.path,
          ),
          input,
          reason: 'partial name "$name" should not be resolved',
        );
        expect(
          tempDir.listSync(),
          isEmpty,
          reason: 'no files should be created for "$name"',
        );
      }
    });

    test(
      'throws ArgumentError when a partial matches with an empty target path',
      () {
        const input = '''
/*partial v header*/payload
/*partial ^ header*/
''';

        expect(
          () => applyPartials(
            content: input,
            targetAbsolutePath: '',
          ),
          throwsA(
            isA<ArgumentError>().having(
              (error) => error.message,
              'message',
              contains('targetAbsolutePath is required'),
            ),
          ),
        );
        expect(tempDir.listSync(), isEmpty);
      },
    );

    test('allows overwriting a partial when content is identical', () {
      const input =
          '/*partial v shared*/same content\n/*partial ^ shared*/';
      final partialPath = p.join(tempDir.path, 'shared.partial');
      File(partialPath)
        ..createSync(recursive: true)
        ..writeAsStringSync('same content\n');

      final result = applyPartials(
        content: input,
        targetAbsolutePath: tempDir.path,
      );

      expect(result, "{% render 'shared.partial' %}");
      expect(File(partialPath).readAsStringSync(), 'same content\n');
    });

    test(
      'throws FormatException when a partial name collides with different content',
      () {
        const input = '''
/*partial v shared*/new content
/*partial ^ shared*/
''';
        final partialPath = p.join(tempDir.path, 'shared.partial');
        File(partialPath)
          ..createSync(recursive: true)
          ..writeAsStringSync('old content');

        expect(
          () => applyPartials(
            content: input,
            targetAbsolutePath: tempDir.path,
          ),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              contains('collides'),
            ),
          ),
        );
        expect(File(partialPath).readAsStringSync(), 'old content');
      },
    );
  });
}
