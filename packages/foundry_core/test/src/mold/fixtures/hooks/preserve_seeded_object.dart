import 'package:foundry_core/foundry_core.dart';

/// Fixture hook that re-stores a seeded non-JSON object under a new key.
Future<void> run(FoundryContext context) async {
  final seeded = context.required<_SeedToken>('seed');
  context
    ..set('seen', seeded)
    ..set('seen_type', seeded.runtimeType.toString());
}

/// Opaque token used only by in-process hook tests.
final class _SeedToken {}

/// Builds a fresh seed token for tests that seed non-JSON context values.
Object createSeedToken() => _SeedToken();
