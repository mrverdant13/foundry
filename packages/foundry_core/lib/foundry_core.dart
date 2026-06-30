/// Core library for Foundry — molds, variables, templates, and cast.
library;

export 'src/mold/mold.dart';
export 'src/mold/mold_hooks.dart';
export 'src/mold/mold_issue.dart';
export 'src/mold/mold_loader.dart' show loadMold;
export 'src/mold/mold_manifest.dart';
export 'src/mold/mold_manifest_parser.dart' show parseMoldManifest;
export 'src/variables/foundry_variable.dart';
export 'src/variables/foundry_variable_group.dart';
export 'src/version.dart' show foundryCoreVersion, readFoundryCoreVersion;
