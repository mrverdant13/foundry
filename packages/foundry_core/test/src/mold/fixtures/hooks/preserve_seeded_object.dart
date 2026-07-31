import 'package:foundry_core/foundry_core.dart';

/// Fixture hook that re-stores a seeded non-JSON object under a new key.
Future<void> run(FoundryContext context) async {
  final seeded = context.required<_SeedToken>('seed');
  context
    ..set('seen', seeded)
    ..set('seen_type', seeded.runtimeType.toString());
}

/// Opaque token used only by in-process hook tests.
///
/// Implements [FoundryLiquidView] so cast can render while hooks keep the
/// live object identity. Templates that accidentally reference this key get
/// `null` rather than a fail-loud unknown type.
final class _SeedToken implements FoundryLiquidView {
  @override
  Object? toLiquid() => null;
}

/// Builds a fresh seed token for tests that seed non-JSON context values.
Object createSeedToken() => _SeedToken();
