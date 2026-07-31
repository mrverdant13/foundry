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
        // Uses an unclosed Liquid tag (rather than an invalid filter) to
        // trigger a parse failure, since the raw source file name must stay
        // valid on every OS the test suite runs on (e.g. "|" is not a legal
        // Windows filename character).
        await _writeFile(
          p.join(templateDirectory.path, '{{ name.txt'),
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
              contains('{{ name.txt'),
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

    test(
      'resolves {% render %} via filesystem Root and skips .partial outputs',
      () async {
        await _writeFile(
          p.join(templateDirectory.path, 'header.partial'),
          'Hello {{ name }}!\n',
        );
        await _writeFile(
          p.join(templateDirectory.path, 'README.md'),
          // Bare render tags receive cast context via renderTemplate expansion.
          "{% render 'header.partial' %}\n"
          "Static {% render 'footer.partial' %}\n",
        );
        await _writeFile(
          p.join(templateDirectory.path, 'footer.partial'),
          'footer',
        );

        final writtenFiles = await renderTemplate(
          templateDirectory: templateDirectory,
          outputDirectory: outputDirectory,
          context: SnapshotFoundryContext({'name': 'Foundry'}),
        );

        expect(writtenFiles, hasLength(1));
        expect(
          await File(p.join(outputDirectory.path, 'README.md')).readAsString(),
          'Hello Foundry!\n'
          '\n'
          'Static footer\n',
        );
        expect(
          File(p.join(outputDirectory.path, 'header.partial')).existsSync(),
          isFalse,
        );
        expect(
          File(p.join(outputDirectory.path, 'footer.partial')).existsSync(),
          isFalse,
        );
      },
    );

    test('resolves nested {% render %} paths under template Root', () async {
      await _writeFile(
        p.join(templateDirectory.path, 'components', 'badge.partial'),
        '[{{ label }}]',
      );
      await _writeFile(
        p.join(templateDirectory.path, 'page.txt'),
        "{% render 'components/badge.partial' %}\n",
      );

      final writtenFiles = await renderTemplate(
        templateDirectory: templateDirectory,
        outputDirectory: outputDirectory,
        context: SnapshotFoundryContext({'label': 'ok'}),
      );

      expect(writtenFiles, hasLength(1));
      expect(
        await File(p.join(outputDirectory.path, 'page.txt')).readAsString(),
        '[ok]\n',
      );
      expect(
        Directory(p.join(outputDirectory.path, 'components')).existsSync(),
        isFalse,
      );
    });

    test(
      'leaves render tags that already pass arguments unchanged',
      () async {
        await _writeFile(
          p.join(templateDirectory.path, 'greet.partial'),
          '{{ greeting }}, {{ name }}!',
        );
        await _writeFile(
          p.join(templateDirectory.path, 'page.txt'),
          """{% render 'greet.partial', greeting: greeting, name: 'explicit' %}\n""",
        );

        final writtenFiles = await renderTemplate(
          templateDirectory: templateDirectory,
          outputDirectory: outputDirectory,
          context: SnapshotFoundryContext({
            'greeting': 'Hi',
            'name': 'from-context',
          }),
        );

        expect(writtenFiles, hasLength(1));
        expect(
          await File(p.join(outputDirectory.path, 'page.txt')).readAsString(),
          'Hi, explicit!\n',
        );
      },
    );

    test(
      'forwards cast context through nested bare {% render %} in partials',
      () async {
        await _writeFile(
          p.join(templateDirectory.path, 'inner.partial'),
          'Inner: {{ name }}',
        );
        await _writeFile(
          p.join(templateDirectory.path, 'outer.partial'),
          "Outer wraps: {% render 'inner.partial' %}",
        );
        await _writeFile(
          p.join(templateDirectory.path, 'page.txt'),
          "{% render 'outer.partial' %}\n",
        );

        final writtenFiles = await renderTemplate(
          templateDirectory: templateDirectory,
          outputDirectory: outputDirectory,
          context: SnapshotFoundryContext({'name': 'Foundry'}),
        );

        expect(writtenFiles, hasLength(1));
        expect(
          await File(p.join(outputDirectory.path, 'page.txt')).readAsString(),
          'Outer wraps: Inner: Foundry\n',
        );
        expect(
          File(p.join(outputDirectory.path, 'outer.partial')).existsSync(),
          isFalse,
        );
        expect(
          File(p.join(outputDirectory.path, 'inner.partial')).existsSync(),
          isFalse,
        );
      },
    );

    test('renders dotted fields from a FoundryLiquidView', () async {
      await _writeFile(
        p.join(templateDirectory.path, 'README.md'),
        '{{ repo.name }} / {{ repo.default_branch }}\n',
      );

      final writtenFiles = await renderTemplate(
        templateDirectory: templateDirectory,
        outputDirectory: outputDirectory,
        context: SnapshotFoundryContext({
          'repo': _RepoSummary(name: 'foundry', defaultBranch: 'main'),
        }),
      );

      expect(writtenFiles, hasLength(1));
      expect(
        await File(p.join(outputDirectory.path, 'README.md')).readAsString(),
        'foundry / main\n',
      );
    });

    test(
      'throws before writes when context holds an unknown class',
      () async {
        await _writeFile(
          p.join(templateDirectory.path, 'README.md'),
          '{{ token }}\n',
        );

        await expectLater(
          renderTemplate(
            templateDirectory: templateDirectory,
            outputDirectory: outputDirectory,
            context: SnapshotFoundryContext({'token': _OpaqueToken()}),
          ),
          throwsA(
            isA<TemplateRenderException>().having(
              (e) => e.message,
              'message',
              allOf(
                contains('Failed to project cast context'),
                contains('token'),
                contains('_OpaqueToken'),
              ),
            ),
          ),
        );

        expect(outputDirectory.listSync(), isEmpty);
      },
    );

    test(
      'throws before writes when context holds a plain Enum',
      () async {
        await _writeFile(
          p.join(templateDirectory.path, 'README.md'),
          '{{ flavor }}\n',
        );

        await expectLater(
          renderTemplate(
            templateDirectory: templateDirectory,
            outputDirectory: outputDirectory,
            context: SnapshotFoundryContext({'flavor': _Flavor.vanilla}),
          ),
          throwsA(
            isA<TemplateRenderException>().having(
              (e) => e.message,
              'message',
              allOf(
                contains('Failed to project cast context'),
                contains('flavor'),
                contains('_Flavor'),
              ),
            ),
          ),
        );

        expect(outputDirectory.listSync(), isEmpty);
      },
    );
  });
}

enum _Flavor { vanilla }

final class _RepoSummary implements FoundryLiquidView {
  _RepoSummary({required this.name, required this.defaultBranch});

  final String name;
  final String defaultBranch;

  @override
  Object? toLiquid() => {
        'name': name,
        'default_branch': defaultBranch,
      };
}

final class _OpaqueToken {}
