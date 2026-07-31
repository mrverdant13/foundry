import 'package:foundry_core/foundry_core.dart';
import 'package:liquify/liquify.dart';
import 'package:test/test.dart';

enum _Flavor { vanilla }

final class _RepoSummary implements FoundryLiquidView {
  _RepoSummary({
    required this.name,
    required this.defaultBranch,
    this.owner,
  });

  final String name;
  final String defaultBranch;
  final _OwnerSummary? owner;

  @override
  Object? toLiquid() => {
        'name': name,
        'default_branch': defaultBranch,
        if (owner != null) 'owner': owner,
      };
}

final class _OwnerSummary implements FoundryLiquidView {
  _OwnerSummary({required this.login});

  final String login;

  @override
  Object? toLiquid() => {'login': login};
}

final class _CyclicView implements FoundryLiquidView {
  _CyclicView();

  late final Object? payload;

  @override
  Object? toLiquid() => payload;
}

final class _NamedDrop extends Drop {
  _NamedDrop(this.label) {
    attrs['label'] = label;
  }

  final String label;
}

final class _OpaqueToken {}

void main() {
  group('projectLiquidView', () {
    test('projects null and primitives unchanged', () {
      expect(
        projectLiquidView({
          'none': null,
          'flag': true,
          'name': 'foundry',
          'count': 3,
          'ratio': 1.5,
        }),
        {
          'none': null,
          'flag': true,
          'name': 'foundry',
          'count': 3,
          'ratio': 1.5,
        },
      );
    });

    test('projects nested string-keyed maps and lists', () {
      expect(
        projectLiquidView({
          'repo': {
            'name': 'foundry',
            'tags': ['cli', 'mold'],
            'meta': {'private': false},
          },
        }),
        {
          'repo': {
            'name': 'foundry',
            'tags': ['cli', 'mold'],
            'meta': {'private': false},
          },
        },
      );
    });

    test('projects FoundryLiquidView via toLiquid', () {
      expect(
        projectLiquidView({
          'repo': _RepoSummary(name: 'foundry', defaultBranch: 'main'),
        }),
        {
          'repo': {
            'name': 'foundry',
            'default_branch': 'main',
          },
        },
      );
    });

    test('projects nested FoundryLiquidView values', () {
      expect(
        projectLiquidView({
          'repo': _RepoSummary(
            name: 'foundry',
            defaultBranch: 'main',
            owner: _OwnerSummary(login: 'mrverdant13'),
          ),
        }),
        {
          'repo': {
            'name': 'foundry',
            'default_branch': 'main',
            'owner': {'login': 'mrverdant13'},
          },
        },
      );
    });

    test('passes liquify Drop through unchanged', () {
      final drop = _NamedDrop('badge');
      final projected = projectLiquidView({'badge': drop});
      expect(projected['badge'], same(drop));
    });

    test('rejects maps with non-string keys', () {
      expect(
        () => projectLiquidView({
          'config': {1: 'bad'},
        }),
        throwsA(
          isA<LiquidViewProjectionException>().having(
            (e) => e.message,
            'message',
            allOf(contains('config'), contains('int'), contains('String')),
          ),
        ),
      );
    });

    test('rejects unknown types with path and runtime type', () {
      expect(
        () => projectLiquidView({'token': _OpaqueToken()}),
        throwsA(
          isA<LiquidViewProjectionException>().having(
            (e) => e.message,
            'message',
            allOf(contains('token'), contains('_OpaqueToken')),
          ),
        ),
      );
    });

    test('rejects plain Enum values', () {
      expect(
        () => projectLiquidView({'flavor': _Flavor.vanilla}),
        throwsA(
          isA<LiquidViewProjectionException>().having(
            (e) => e.message,
            'message',
            allOf(contains('flavor'), contains('_Flavor')),
          ),
        ),
      );
    });

    test('detects identity cycles through maps', () {
      final cyclic = <String, Object?>{};
      cyclic['self'] = cyclic;

      expect(
        () => projectLiquidView({'root': cyclic}),
        throwsA(
          isA<LiquidViewProjectionException>().having(
            (e) => e.message,
            'message',
            allOf(contains('Cycle detected'), contains('root.self')),
          ),
        ),
      );
    });

    test('detects identity cycles through nested views', () {
      final cyclic = _CyclicView();
      cyclic.payload = {'again': cyclic};

      expect(
        () => projectLiquidView({'node': cyclic}),
        throwsA(
          isA<LiquidViewProjectionException>().having(
            (e) => e.message,
            'message',
            allOf(contains('Cycle detected'), contains('node.again')),
          ),
        ),
      );
    });

    test('detects identity cycles through lists', () {
      final cyclic = <Object?>[];
      cyclic.add(cyclic);

      expect(
        () => projectLiquidView({'items': cyclic}),
        throwsA(
          isA<LiquidViewProjectionException>().having(
            (e) => e.message,
            'message',
            allOf(contains('Cycle detected'), contains('items[0]')),
          ),
        ),
      );
    });
  });
}
