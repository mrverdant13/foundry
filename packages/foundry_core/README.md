# foundry_core

Core Dart library for **Foundry** — mold manifests, variable resolution,
template rendering, and cast orchestration.

> **Preview release.** APIs may change before `1.0.0`.

## What it does

Foundry molds are Dart packages with a `variables.dart` manifest, a `template/`
tree, and optional lifecycle hooks. This library provides:

- **Mold model** — parse root `pubspec.yaml` and build a [`Mold`](https://pub.dev/documentation/foundry_core/latest/foundry_core/Mold-class.html)
  with an in-memory live [`FoundryVariableGroup`](https://pub.dev/documentation/foundry_core/latest/foundry_core/FoundryVariableGroup-class.html)
  (callbacks such as `visibleWhen` / `defaultValue` stay intact)
- **Inspection** — validate mold layout (`template/`, conventional hook paths);
  structural only — does not import `variables.dart`
- **Variable resolution** — evaluate `visibleWhen`, `defaultValue`, and
  validators against a read-only [`SnapshotFoundryContext`](https://pub.dev/documentation/foundry_core/latest/foundry_core/SnapshotFoundryContext-class.html)
- **Template rendering** — render Liquid templates to an output directory
- **Hook execution** — run prepare/shape/finish hooks against a mutable
  [`FoundryContext`](https://pub.dev/documentation/foundry_core/latest/foundry_core/FoundryContext-class.html).
  Prefer [`runMoldHookInProcess`](https://pub.dev/documentation/foundry_core/latest/foundry_core/runMoldHookInProcess.html)
  when the hook's `run` is already imported in the current isolate (live
  context, no JSON round-trip). [`runMoldHook`](https://pub.dev/documentation/foundry_core/latest/foundry_core/runMoldHook.html)
  still spawns a `dart run` subprocess for host-side callers.
- **Cast orchestration** — end-to-end `castMold` pipeline and
  `.foundry/last_cast.json` persistence
- **Import** — copy molds from a local path or shallow git clone
- **Pattern inspect / mold derive / mold sync** — summarize pattern directories,
  best-effort derive a starter mold, and refresh an existing mold's `template/`
  while preserving `variables.dart` and `hooks/`. Derive/sync resolve pattern
  comment annotations and `.foundry/pattern.yaml` `replacements` /
  `lineDeletions` into Liquid templates.

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

Inspect a mold structurally, then cast with an in-memory live variable group:

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

  final mold = Mold(
    directory: report.mold!.directory,
    pubspec: report.mold!.pubspec,
    variableGroup: FoundryVariableGroup(
      variables: {
        'project_name': FoundryStringVariable(label: 'Project name'),
      },
    ),
  );
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

## Lifecycle hooks

Mold hooks are top-level Dart files under `hooks/`
(`prepare.dart`, `shape.dart`, `finish.dart`). Each file that exists must
export:

```dart
Future<void> run(FoundryContext context) async {
  // Mutate context with set / merge / remove as needed.
}
```

Missing hook files are no-ops. Relative file I/O inside a hook uses the cast
output directory as the process working directory.

When a host already imports the hook (for example via a file URI and
`moldHookFileUriImport`), call `runMoldHookInProcess` with that `run` as
`entryPoint`. Mutations stay on the same `FoundryContext` instance — including
non-JSON `Object` values seeded by prepare — with no JSON round-trip between
phases. Prefer that path whenever prepare, gather/shape, and finish must share
a live heap. Use `runMoldHook` only when the host cannot import the hook and
must spawn `dart run` (values are JSON-encoded across the process boundary).

Do not invoke overlapping `runMoldHookInProcess` calls concurrently in the same
process: `Directory.current` is process-wide for the duration of each hook.

## Public API

Import `package:foundry_core/foundry_core.dart`.

| Area | Key symbols |
| ---- | ----------- |
| Mold | `parseMoldPubspec`, `inspectMold`, `Mold`, `FoundryVariableGroup` |
| Derive | `deriveMoldFromPattern`, `MoldDeriveException` |
| Sync | `syncMoldFromPattern`, `MoldSyncException` |
| Pattern | `inspectPattern`, `PatternInspectionReport`, `PatternMarker` |
| Context | `SnapshotFoundryContext`, `FoundryContext`, `FoundryContextException` |
| Cast | `castMold`, `prepareCastContext`, `completeCast`, `parseCastVariableInputs` (supports dotted object `--vars` paths such as `publish.host=`), `CastOutcome`, `readCastState`, `writeCastState` |
| Render | `renderTemplate` |
| Hooks | `runMoldHook`, `runMoldHookInProcess`, `MoldHookEntryPoint`, `moldHookFileUriImport`, `FoundryHookException` |
| Import | `importMoldFromLocal`, `importMoldFromGit` |

## Resources

- [Hook authoring guide](https://github.com/mrverdant13/foundry/blob/main/doc/hooks.md)
- [Pattern annotations and `.foundry/pattern.yaml`](https://github.com/mrverdant13/foundry/blob/main/doc/annotations.md)
- [Repository](https://github.com/mrverdant13/foundry/tree/main/packages/foundry_core)
- [Issue tracker](https://github.com/mrverdant13/foundry/issues)
- [Changelog](CHANGELOG.md)

## License

MIT — see [LICENSE](LICENSE).
