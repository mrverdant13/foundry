/// Core library for Foundry — molds, variables, templates, and cast.
library;

export 'src/cast/cast_outcome.dart';
export 'src/cast/cast_runner.dart' show castMold;
export 'src/cast/cast_state.dart';
export 'src/cast/cast_state_not_found_exception.dart';
export 'src/cast/cast_state_store.dart'
    show castStateFile, readCastState, writeCastState;
export 'src/cast/cast_variable_inputs.dart' show parseCastVariableInputs;
export 'src/cast/cast_variable_inputs_result.dart';
export 'src/cast/cast_variables_invalid_exception.dart';
export 'src/context/foundry_context.dart';
export 'src/context/foundry_context_exception.dart';
export 'src/context/foundry_hook_exception.dart';
export 'src/context/snapshot_foundry_context.dart';
export 'src/logging/logger.dart';
export 'src/mold/mold.dart';
export 'src/mold/mold_derive.dart' show deriveMoldFromPattern;
export 'src/mold/mold_derive_exception.dart';
export 'src/mold/mold_git_import.dart' show importMoldFromGit;
export 'src/mold/mold_hook_exception.dart';
export 'src/mold/mold_hook_runner.dart' show runMoldHook;
export 'src/mold/mold_hooks.dart';
export 'src/mold/mold_import_exception.dart';
export 'src/mold/mold_inspector.dart';
export 'src/mold/mold_issue.dart';
export 'src/mold/mold_loader.dart' show loadMold;
export 'src/mold/mold_local_import.dart' show importMoldFromLocal;
export 'src/mold/mold_pubspec.dart';
export 'src/mold/mold_pubspec_parser.dart' show parseMoldPubspec;
export 'src/mold/mold_scaffold.dart'
    show
        defaultMoldNameFromPath,
        isValidMoldName,
        moldScaffoldPubspecContents,
        moldScaffoldVariablesContents,
        sanitizeMoldName,
        scaffoldFoundryCoreConstraint;
export 'src/pattern/pattern_inspector.dart';
export 'src/pattern/pattern_issue.dart';
export 'src/pattern/pattern_marker.dart';
export 'src/rendering/template_render_exception.dart';
export 'src/rendering/template_renderer.dart' show renderTemplate;
export 'src/variables/foundry_variable.dart';
export 'src/variables/foundry_variable_evaluation.dart';
export 'src/variables/foundry_variable_group.dart';
export 'src/variables/foundry_variable_group_validation.dart';
export 'src/version.dart' show foundryCoreVersion, readFoundryCoreVersion;
