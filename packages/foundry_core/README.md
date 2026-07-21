# foundry_core

Core Dart library for **Foundry** — mold manifests, variable resolution,
template rendering, and cast orchestration.

> **Preview release.** APIs may change before `1.0.0`.

## What it does

Foundry molds are Dart packages with a `variables.dart` manifest, a `template/`
tree, and optional lifecycle hooks. This library provides:

- **Mold loading** — parse root `pubspec.yaml`, resolve dependencies, and load
  `moldVariables` from `variables.dart`
- **Inspection** — validate mold layout (`template/`, conventional hook paths)
- **Variable resolution** — evaluate `visibleWhen`, `defaultValue`, and
  validators against a read-only [`SnapshotFoundryContext`](https://pub.dev/documentation/foundry_core/latest/foundry_core/SnapshotFoundryContext-class.html)
- **Template rendering** — render Liquid templates to an output directory
- **Hook execution** — spawn prepare/shape/finish hooks with a mutable
  [`FoundryContext`](https://pub.dev/documentation/foundry_core/latest/foundry_core/FoundryContext-class.html)
- **Cast orchestration** — end-to-end `castMold` pipeline and
  `.foundry/last_cast.json` persistence
- **Import** — copy molds from a local path or shallow git clone
- **Pattern inspect / mold derive** — summarize pattern directories and
  best-effort derive a starter mold (`template/` liquidized from pattern files)

For day-to-day use, install the [`foundry_cli`](https://pub.dev/packages/foundry_cli)
package (`foundry mold init`, `foundry cast`, and related commands). Use this
library when embedding Foundry in tools or automation.

## Installation

Add `foundry_core` to your `pubspec.yaml`:

```yaml
dependencies:
  foundry_core: ^0.0.1-dev.1
```

Requires Dart SDK `>=3.5.0 <4.0.0`.

## Usage

Load a mold, inspect it, and cast with pre-gathered variable values:

```dart
import 'dart:io';

import 'package:foundry_core/foundry_core.dart';

Future<void> main() async {
  final moldPath = 'path/to/my_mold';
  final outputPath = 'path/to/output';

  final report = await inspectMold(moldPath);
  if (!report.isValid) {
    for (final issue in report.issues) {
      stderr.writeln(issue);
    }
    exitCode = 1;
    return;
  }

  final mold = report.mold!;
  final outcome = await castMold(
    mold: mold,
    outputPath: outputPath,
    values: {'project_name': 'my_app'},
    force: true,
    noHooks: true,
  );

  stdout.writeln(
    'Cast completed: ${outcome.artifactCount} file(s) written.',
  );
}
```

See the [`example/`](example/) directory for a runnable program against a
bundled fixture mold.

## Public API

Import `package:foundry_core/foundry_core.dart`.

| Area | Key symbols |
| ---- | ----------- |
| Mold | `loadMold`, `parseMoldPubspec`, `inspectMold`, `Mold`, `FoundryVariableGroup` |
| Derive | `deriveMoldFromPattern`, `MoldDeriveException` |
| Pattern | `inspectPattern`, `PatternInspectionReport`, `PatternMarker` |
| Context | `SnapshotFoundryContext`, `FoundryContext`, `FoundryContextException` |
| Cast | `castMold`, `CastOutcome`, `readCastState`, `writeCastState` |
| Render | `renderTemplate` |
| Hooks | `runMoldHook`, `FoundryHookException` |
| Import | `importMoldFromLocal`, `importMoldFromGit` |

## Resources

- [Hook authoring guide](https://github.com/mrverdant13/foundry/blob/main/doc/hooks.md)
- [Repository](https://github.com/mrverdant13/foundry/tree/main/packages/foundry_core)
- [Issue tracker](https://github.com/mrverdant13/foundry/issues)
- [Changelog](CHANGELOG.md)

## License

MIT — see [LICENSE](LICENSE).
