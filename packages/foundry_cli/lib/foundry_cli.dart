/// Foundry command-line interface.
///
/// Programmatic consumers should use `package:foundry_core/foundry_core.dart`
/// for the underlying mold, variable, and cast APIs.
library;

export 'src/cast_session.dart';
export 'src/cast_session_vars.dart' show projectEncodableCastVars;
export 'src/exit_code.dart';
export 'src/foundry_command_runner.dart';
export 'src/mold_cast_session_helper.dart'
    show
        FoundryCliHelperDependency,
        FoundryCliHostedDependency,
        FoundryCliPathDependency,
        moldCastSessionHelperPackageName,
        moldCastSessionHelperTempPrefix;
export 'src/mold_cast_session_launcher.dart';
export 'src/version.dart' show foundryCliVersion, readFoundryCliVersion;
