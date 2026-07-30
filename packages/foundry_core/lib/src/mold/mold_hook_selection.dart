import 'dart:io';

import 'package:foundry_core/src/mold/mold.dart';
import 'package:foundry_core/src/mold/mold_hook_exception.dart';
import 'package:foundry_core/src/mold/mold_hook_selection_exception.dart';
import 'package:foundry_core/src/mold/mold_hooks.dart';

/// Validates [skipHooks] and [requiredHooks] against [mold]'s on-disk hooks.
///
/// Throws [MoldHookSelectionException] when:
/// - any phase is both skipped and required, or
/// - a required phase has no `hooks/<phase>.dart` file.
///
/// Callers supply [requiredHooks] (for example after awaiting
/// `hooks/policy.dart`). Core does not execute policy itself.
void validateMoldHookSelection({
  required Mold mold,
  Set<MoldHookPhase> skipHooks = const {},
  Set<MoldHookPhase> requiredHooks = const {},
}) {
  final skippedRequired = skipHooks.intersection(requiredHooks);
  if (skippedRequired.isNotEmpty) {
    final names = _sortedPhaseNames(skippedRequired);
    throw MoldHookSelectionException(
      message: 'Cannot skip required hook phase(s): ${names.join(', ')}',
      skippedRequiredPhases: Set<MoldHookPhase>.unmodifiable(skippedRequired),
    );
  }

  final missing = <MoldHookPhase>{};
  for (final phase in requiredHooks) {
    if (_hookFileFor(mold, phase) == null) {
      missing.add(phase);
    }
  }
  if (missing.isNotEmpty) {
    final paths = missing.map(moldHookPathForPhase).toList()..sort();
    throw MoldHookSelectionException(
      message: 'Required hook file(s) missing: ${paths.join(', ')}',
      missingRequiredPhases: Set<MoldHookPhase>.unmodifiable(missing),
    );
  }
}

/// Relative mold path for the lifecycle hook of [phase].
String moldHookPathForPhase(MoldHookPhase phase) {
  return switch (phase) {
    MoldHookPhase.prepare => MoldHooks.preparePath,
    MoldHookPhase.shape => MoldHooks.shapePath,
    MoldHookPhase.finish => MoldHooks.finishPath,
  };
}

File? _hookFileFor(Mold mold, MoldHookPhase phase) {
  return switch (phase) {
    MoldHookPhase.prepare => mold.prepareHook,
    MoldHookPhase.shape => mold.shapeHook,
    MoldHookPhase.finish => mold.finishHook,
  };
}

List<String> _sortedPhaseNames(Set<MoldHookPhase> phases) {
  final names = phases.map((phase) => phase.name).toList()..sort();
  return names;
}
