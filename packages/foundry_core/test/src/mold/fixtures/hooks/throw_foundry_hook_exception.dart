import 'package:foundry_core/foundry_core.dart';

/// Fixture hook that aborts with [FoundryHookException].
Future<void> run(FoundryContext context) async {
  throw const FoundryHookException('nope');
}
