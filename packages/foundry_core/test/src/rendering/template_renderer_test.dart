import 'dart:io';

import 'package:foundry_core/foundry_core.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

Future<void> _writeFile(String path, String contents) async {
  final file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsString(contents);
}

void main() {
  late Directory tempRoot;
  late Directory templateDirectory;
  late Directory outputDirectory;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('foundry_render_');
    templateDirectory = Directory(p.join(tempRoot.path, 'template'))
      ..createSync();
    outputDirectory = Directory(p.join(tempRoot.path, 'output'))..createSync();
  });

  tearDown(() async {
    if (tempRoot.existsSync()) {
      await tempRoot.delete(recursive: true);
    }
  });

  group('renderTemplate', () {
    test('renders file contents and applies filters', () async {
      await _writeFile(
        p.join(templateDirectory.path, 'README.md'),
        '# {{ project_name | pascal_case }}\n\n'
        'Package: {{ project_name | snake_case }}\n',
      );

      final writtenFiles = await renderTemplate(
        templateDirectory: templateDirectory,
        outputDirectory: outputDirectory,
        context: SnapshotFoundryContext({'project_name': 'my project'}),
      );

      expect(writtenFiles, hasLength(1));
      final readme = File(p.join(outputDirectory.path, 'README.md'));
      expect(readme.existsSync(), isTrue);
      expect(
        await readme.readAsString(),
        '# MyProject\n\nPackage: my_project\n',
      );
    });

    test('renders nested directories preserving structure', () async {
      await _writeFile(
        p.join(templateDirectory.path, 'lib', 'src', 'greeter.dart'),
        'String greet() => "{{ greeting }}";\n',
      );

      final writtenFiles = await renderTemplate(
        templateDirectory: templateDirectory,
        outputDirectory: outputDirectory,
        context: SnapshotFoundryContext({'greeting': 'hello'}),
      );

      expect(writtenFiles, hasLength(1));
      final generated = File(
        p.join(outputDirectory.path, 'lib', 'src', 'greeter.dart'),
      );
      expect(generated.existsSync(), isTrue);
      expect(await generated.readAsString(), 'String greet() => "hello";\n');
    });

    test('renders dynamic Liquid expressions in path segments', () async {
      await _writeFile(
        p.join(templateDirectory.path, '{{ file_name }}.dart'),
        'const name = "{{ project_name }}";\n',
      );

      final writtenFiles = await renderTemplate(
        templateDirectory: templateDirectory,
        outputDirectory: outputDirectory,
        context: SnapshotFoundryContext({
          'file_name': 'config',
          'project_name': 'demo',
        }),
      );

      expect(writtenFiles, hasLength(1));
      expect(
        File(p.join(outputDirectory.path, 'config.dart')).existsSync(),
        isTrue,
      );
    });

    test(
      'throws and writes nothing when a destination exists without force',
      () async {
        await _writeFile(
          p.join(templateDirectory.path, 'a.txt'),
          'A: {{ value }}',
        );
        await _writeFile(
          p.join(templateDirectory.path, 'b.txt'),
          'B: {{ value }}',
        );
        await _writeFile(p.join(outputDirectory.path, 'b.txt'), 'existing');

        await expectLater(
          renderTemplate(
            templateDirectory: templateDirectory,
            outputDirectory: outputDirectory,
            context: SnapshotFoundryContext({'value': 'x'}),
          ),
          throwsA(isA<TemplateRenderException>()),
        );

        expect(
          File(p.join(outputDirectory.path, 'a.txt')).existsSync(),
          isFalse,
        );
        expect(
          await File(p.join(outputDirectory.path, 'b.txt')).readAsString(),
          'existing',
        );
      },
    );

    test(
      'overwrites conflicting files but leaves unrelated files untouched '
      'when force is true',
      () async {
        await _writeFile(
          p.join(templateDirectory.path, 'a.txt'),
          'A: {{ value }}',
        );
        await _writeFile(
          p.join(outputDirectory.path, 'a.txt'),
          'stale contents',
        );
        await _writeFile(
          p.join(outputDirectory.path, 'unrelated.txt'),
          'do not touch',
        );

        final writtenFiles = await renderTemplate(
          templateDirectory: templateDirectory,
          outputDirectory: outputDirectory,
          context: SnapshotFoundryContext({'value': 'fresh'}),
          force: true,
        );

        expect(writtenFiles, hasLength(1));
        expect(
          await File(p.join(outputDirectory.path, 'a.txt')).readAsString(),
          'A: fresh',
        );
        expect(
          await File(
            p.join(outputDirectory.path, 'unrelated.txt'),
          ).readAsString(),
          'do not touch',
        );
      },
    );

    test(
      'throws and writes nothing when a rendered path segment traverses '
      'outside the output directory',
      () async {
        await _writeFile(
          p.join(templateDirectory.path, '{{ segment }}', 'file.txt'),
          'contents',
        );

        await expectLater(
          renderTemplate(
            templateDirectory: templateDirectory,
            outputDirectory: outputDirectory,
            context: SnapshotFoundryContext({'segment': '..'}),
          ),
          throwsA(
            isA<TemplateRenderException>().having(
              (e) => e.message,
              'message',
              contains('escapes the output directory'),
            ),
          ),
        );

        expect(outputDirectory.listSync(), isEmpty);
      },
    );

    test(
      'throws and writes nothing when a rendered path segment is absolute',
      () async {
        await _writeFile(
          p.join(templateDirectory.path, '{{ segment }}file.txt'),
          'contents',
        );

        await expectLater(
          renderTemplate(
            templateDirectory: templateDirectory,
            outputDirectory: outputDirectory,
            context: SnapshotFoundryContext({
              'segment': Platform.isWindows ? r'C:\Windows\' : '/etc/',
            }),
          ),
          throwsA(isA<TemplateRenderException>()),
        );

        expect(outputDirectory.listSync(), isEmpty);
      },
    );

    test(
      'throws and writes nothing when two template files render to the '
      'same destination path',
      () async {
        await _writeFile(
          p.join(templateDirectory.path, '{{ a }}.txt'),
          'from a',
        );
        await _writeFile(
          p.join(templateDirectory.path, '{{ b }}.txt'),
          'from b',
        );

        await expectLater(
          renderTemplate(
            templateDirectory: templateDirectory,
            outputDirectory: outputDirectory,
            context: SnapshotFoundryContext({'a': 'same', 'b': 'same'}),
          ),
          throwsA(
            isA<TemplateRenderException>().having(
              (e) => e.message,
              'message',
              contains('both render to destination'),
            ),
          ),
        );

        expect(outputDirectory.listSync(), isEmpty);
      },
    );

    test(
      'wraps content-rendering failures in a TemplateRenderException',
      () async {
        await _writeFile(
          p.join(templateDirectory.path, 'broken.txt'),
          '{{ value | unknown_filter_xyz }}',
        );

        await expectLater(
          renderTemplate(
            templateDirectory: templateDirectory,
            outputDirectory: outputDirectory,
            context: SnapshotFoundryContext({'value': 'x'}),
          ),
          throwsA(
            isA<TemplateRenderException>().having(
              (e) => e.message,
              'message',
              contains('broken.txt'),
            ),
          ),
        );

        expect(outputDirectory.listSync(), isEmpty);
      },
    );

    test(
      'wraps path segment rendering failures in a TemplateRenderException',
      () async {
        await _writeFile(
          p.join(
            templateDirectory.path,
            '{{ name | unknown_filter_xyz }}.txt',
          ),
          'contents',
        );

        await expectLater(
          renderTemplate(
            templateDirectory: templateDirectory,
            outputDirectory: outputDirectory,
            context: SnapshotFoundryContext({'name': 'demo'}),
          ),
          throwsA(
            isA<TemplateRenderException>().having(
              (e) => e.message,
              'message',
              contains('unknown_filter_xyz'),
            ),
          ),
        );

        expect(outputDirectory.listSync(), isEmpty);
      },
    );

    test('throws when the template directory does not exist', () async {
      final missing = Directory(p.join(tempRoot.path, 'missing_template'));

      await expectLater(
        renderTemplate(
          templateDirectory: missing,
          outputDirectory: outputDirectory,
          context: SnapshotFoundryContext({}),
        ),
        throwsA(
          isA<TemplateRenderException>().having(
            (e) => e.message,
            'message',
            contains('does not exist'),
          ),
        ),
      );
    });

    test('returns an empty list for an empty template directory', () async {
      final writtenFiles = await renderTemplate(
        templateDirectory: templateDirectory,
        outputDirectory: outputDirectory,
        context: SnapshotFoundryContext({}),
      );

      expect(writtenFiles, isEmpty);
    });
  });
}
