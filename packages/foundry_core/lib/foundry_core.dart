/// Core library for Foundry — molds, variables, templates, and cast.
library;

export 'src/cast/cast_outcome.dart';
export 'src/cast/cast_runner.dart' show castMold;
export 'src/cast/cast_state.dart';
export 'src/cast/cast_variables_invalid_exception.dart';
export 'src/context/foundry_context.dart';
export 'src/context/foundry_context_exception.dart';
export 'src/context/foundry_hook_exception.dart';
export 'src/context/snapshot_foundry_context.dart';
export 'src/logging/logger.dart';
export 'src/mold/mold.dart';
export 'src/mold/mold_hook_exception.dart';
export 'src/mold/mold_hook_runner.dart' show runMoldHook;
export 'src/mold/mold_hooks.dart';
export 'src/mold/mold_inspector.dart';
export 'src/mold/mold_issue.dart';
export 'src/mold/mold_loader.dart' show loadMold;
export 'src/mold/mold_pubspec.dart';
export 'src/mold/mold_pubspec_parser.dart' show parseMoldPubspec;
export 'src/rendering/template_render_exception.dart';
export 'src/rendering/template_renderer.dart' show renderTemplate;
export 'src/variables/foundry_variable.dart';
export 'src/variables/foundry_variable_evaluation.dart';
export 'src/variables/foundry_variable_group.dart';
export 'src/variables/foundry_variable_group_validation.dart';
export 'src/version.dart' show foundryCoreVersion, readFoundryCoreVersion;
