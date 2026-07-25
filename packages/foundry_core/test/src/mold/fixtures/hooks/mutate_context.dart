import 'package:foundry_core/foundry_core.dart';

/// Fixture hook that exercises `set` / `merge` / `remove` on the context.
Future<void> run(FoundryContext context) async {
  context
    ..set('greeting', 'hi ${context.requiredString('name')}')
    ..merge({'merged': true, 'count': 2})
    ..remove('name');
}
