# Mold lifecycle hooks

Foundry molds may define optional **Dart lifecycle hooks** under `hooks/`. Hooks run
during `foundry cast` and `foundry recast` (unless `--no-hooks` is passed). The
`foundry finish` command runs only the **finish** hook against the last cast output.

Hooks are **not** declared in `pubspec.yaml`. Foundry discovers them at conventional
paths relative to the mold root:

| Phase   | Path                 | When it runs                                      |
| ------- | -------------------- | ------------------------------------------------- |
| prepare | `hooks/prepare.dart` | Before variable resolution                        |
| shape   | `hooks/shape.dart`   | After variables are gathered, before rendering    |
| finish  | `hooks/finish.dart`  | After template rendering (also via `foundry finish`) |

Missing hook files are **no-ops** for that phase.

## Mold package dependency

Each mold is a **Dart package**. The mold's root `pubspec.yaml` must declare a
`foundry_core` dependency so `variables.dart` and hook files can import the shared
API:

```yaml
dependencies:
  foundry_core: ^0.0.1-dev.1
```

Foundry runs `dart pub get` in the mold directory during **inspect** and **cast**
before loading variables or spawning hooks.

Hook files live under `hooks/` but resolve imports through the **mold root package**
(the directory containing `pubspec.yaml`). There is no separate `hooks/pubspec.yaml`.

## Entry point

Every hook file must export a top-level function with this signature:

```dart
import 'package:foundry_core/foundry_core.dart';

Future<void> run(FoundryContext context) async {
  // ...
}
```

- The function name must be **`run`**.
- The parameter type must be **`FoundryContext`** (not `HookContext`).
- Return type must be `Future<void>`.

Foundry spawns each hook as a separate `dart run` process from the mold's package
config, then merges any context changes back into the cast pipeline.

## Context API

Hooks receive a mutable **`FoundryContext`**, which extends the read-only
`SnapshotFoundryContext` used by variable callbacks in `variables.dart`.

### Read accessors

Use strict accessors to read cast values (same API as variable callbacks):

```dart
context.requiredString('project_name');
context.optionalString('package_name');
context.requiredBool('use_riverpod');
context.contains('extra');
```

`required*` accessors throw `FoundryContextException` when a key is missing, null, or
the wrong type. `optional*` accessors return `null` for absent or null keys.

### Mutation

Hooks may seed or reshape values before template rendering:

```dart
context.set('greeting', 'Hello');
context.merge({'a': 1, 'b': 2});
context.remove('temporary');
```

### Hook environment

`FoundryContext` also exposes:

| Field              | Type        | Description                          |
| ------------------ | ----------- | ------------------------------------ |
| `logger`           | `Logger`    | Info, warn, error, and progress output |
| `moldDirectory`    | `Directory` | Root of the mold package             |
| `outputDirectory`  | `Directory` | The `--output` artifact directory    |

The hook process **working directory** is `outputDirectory`. File paths in hook code
are relative to the artifact being generated, not the mold source tree.

## Aborting a cast

Throw **`FoundryHookException`** to abort the cast with a user-facing message:

```dart
import 'package:foundry_core/foundry_core.dart';

Future<void> run(FoundryContext context) async {
  if (!context.contains('project_name')) {
    throw FoundryHookException('project_name is required before shaping.');
  }
}
```

Uncaught exceptions from a hook also fail the cast.

## Example hooks

**prepare** — seed values before the TUI gathers variables:

```dart
import 'package:foundry_core/foundry_core.dart';

Future<void> run(FoundryContext context) async {
  context.set('seed', 'from-prepare');
}
```

**shape** — adjust values after the user confirms the form:

```dart
import 'package:foundry_core/foundry_core.dart';

Future<void> run(FoundryContext context) async {
  context.set(
    'package_name',
    toSnakeCase(context.requiredString('project_name')),
  );
}
```

**finish** — run post-generation tasks in the output directory:

```dart
import 'dart:io';

import 'package:foundry_core/foundry_core.dart';

Future<void> run(FoundryContext context) async {
  await Process.run('dart', ['pub', 'get'], runInShell: true);
  context.logger.info('Dependencies resolved in output.');
}
```

## Cast pipeline order

During `foundry cast` / `foundry recast`, hooks run in this order:

1. **prepare** — optional context seeding
2. Variable resolution (interactive TUI in the CLI)
3. **shape** — optional context shaping
4. Template rendering (`template/` → `--output`)
5. **finish** — optional post-render tasks

`foundry finish` skips steps 1–4 and runs only the **finish** hook against the stored
output path from `.foundry/last_cast.json`.

Pass **`--no-hooks`** to skip all hook phases for a command.

## Related documentation

- [Mold pubspec schema](mold-pubspec.schema.json) — JSON Schema for the mold root
  `pubspec.yaml`
- [README](../README.md) — CLI command reference and quick start
