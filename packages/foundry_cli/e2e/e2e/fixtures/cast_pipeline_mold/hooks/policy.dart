import 'package:foundry_core/foundry_core.dart';

/// Finish is required for this fixture mold; skipping it must fail.
Future<Set<MoldHookPhase>> get requiredHooks async => {
      MoldHookPhase.finish,
    };
