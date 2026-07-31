# Mold lifecycle hooks

Foundry molds may define optional **Dart lifecycle hooks** under `hooks/`. Hooks run
during `foundry cast` and `foundry recast`. Skip individual phases with repeatable
`--skip-hooks=<phase>` (`prepare`, `shape`, or `finish`). The `foundry finish`
command runs only the **finish** hook against the last cast output; pass
`--skip-hooks=finish` to skip it when the mold's optional hook policy allows.

Hooks are **not** declared in `pubspec.yaml`. Foundry discovers them at conventional
paths relative to the mold root:

| Phase   | Path                 | When it runs                                      |
| ------- | -------------------- | ------------------------------------------------- |
| prepare | `hooks/prepare.dart` | Before variable resolution                        |
| shape   | `hooks/shape.dart`   | After variables are gathered, before rendering    |
| finish  | `hooks/finish.dart`  | After template rendering (also via `foundry finish`) |

Missing prepare/shape/finish hook files are **no-ops** during `foundry cast` /
`foundry recast` unless a phase is **required** by `hooks/policy.dart` (see
[Required hook policy](#required-hook-policy)). Plain `foundry finish` fails if
`hooks/finish.dart` is absent. With `--skip-hooks=finish` and finish not required,
the command succeeds without needing that file.

## Mold cast session

`foundry cast`, `foundry recast`, and `foundry finish` each launch a **mold cast
session**: a short-lived helper package that depends on `foundry_cli` and the target
mold, then runs the pipeline in one Dart process.

That process imports the mold's root `variables.dart` and any present lifecycle
hook files (`prepare` / `shape` / `finish`) by file URI. When `hooks/policy.dart`
exists, it is imported as well so the session can await `requiredHooks` before
running the pipeline. Variable callbacks (`visibleWhen`, `defaultValue`,
validators, and so on) therefore run as live Dart. Hooks run **in-process**
against one shared `FoundryContext` — mutations are visible to later phases in
the same cast with **no JSON round-trip** between prepare, gather, shape, and
finish.

Within a single cast, prepare may seed non-encodable Dart values (for example custom
objects). Gather, shape, and finish in that same session see those values.
Persistence across commands is different — see
[Cast state and recast / finish seeds](#cast-state-and-recast--finish-seeds).

`foundry mold inspect` uses the same helper composition in a describe-only mode to
report live variable metadata; it does not run hooks or write cast state.

## Mold package dependency

Each mold is a **Dart package**. The mold's root `pubspec.yaml` must declare a
`foundry_core` dependency so `variables.dart` and hook files can import the shared
API:

```yaml
dependencies:
  foundry_core: ^0.0.1-dev.1
```

Molds depend on **`foundry_core` only** — they do not need a `foundry_cli`
dependency. The CLI session helper supplies the cast runtime.

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

Values do not need to be JSON-encodable for later phases of the **same** cast.
Only the encodable projection is written to `.foundry/last_cast.json`.

### Seeding values for Liquid templates

Hooks keep whatever you put on `FoundryContext` — including rich Dart objects —
for later phases and callbacks. Template rendering is different: every context
entry is projected into a Liquid-compatible map before path segments and file
contents are rendered. That projection does not change the live context.

Accepted values include JSON-safe leaves (`null`, `bool`, `String`, finite
numbers), lists, string-keyed maps, liquify `Drop` instances (passed through
unchanged), and objects that implement **`FoundryLiquidView`**:

```dart
class RepoSummary implements FoundryLiquidView {
  RepoSummary({required this.name, required this.defaultBranch});

  final String name;
  final String defaultBranch;

  @override
  Object? toLiquid() => {
        'name': name,
        'default_branch': defaultBranch,
      };
}

Future<void> run(FoundryContext context) async {
  context.set(
    'repo',
    RepoSummary(name: 'foundry', defaultBranch: 'main'),
  );
}
```

Templates can then use dotted access such as `{{ repo.name }}` or
`{{ repo.default_branch }}`. Nested views, maps, and lists are projected
recursively.

Unknown types fail loudly at render time (the error names the context path and
runtime type). Dart **enums are not auto-projected** — store a string (or wrap
the value in a view) when templates need them:

```dart
context.set('flavor', Flavor.vanilla.name); // OK for templates
context.set('flavor', Flavor.vanilla);      // fails at render unless wrapped
```

Hook-only private objects must not sit under keys templates need, or must be
replaced/wrapped before render. Persistable cast state remains JSON-only — see
[Cast state and recast / finish seeds](#cast-state-and-recast--finish-seeds).

### Hook environment

`FoundryContext` also exposes:

| Field              | Type        | Description                          |
| ------------------ | ----------- | ------------------------------------ |
| `logger`           | `Logger`    | Info, warn, error, and progress output |
| `moldDirectory`    | `Directory` | Root of the mold package             |
| `outputDirectory`  | `Directory` | The `--output` artifact directory    |

While a hook runs, the process **working directory** is `outputDirectory`. File paths
in hook code are relative to the artifact being generated, not the mold source tree.

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

During `foundry cast` / `foundry recast`, the mold cast session runs hooks in this
order:

1. **prepare** — optional context seeding
2. Variable resolution (interactive TUI or batch `--vars` / `--vars-file`, inside
   the session process)
3. **shape** — optional context shaping
4. Template rendering (`template/` → `--output`)
5. **finish** — optional post-render tasks

`foundry finish` skips steps 1–4 and runs only the **finish** hook against the stored
output path from `.foundry/last_cast.json`.

### Skipping hook phases

Pass **`--skip-hooks=<phase>`** once per phase to skip (`prepare`, `shape`, and/or
`finish`). Duplicate values are treated as a set. Invalid phase names are rejected
as usage errors.

```bash
foundry cast ./my_mold --output=./out --skip-hooks=prepare --skip-hooks=finish
foundry recast --skip-hooks=shape
foundry finish --skip-hooks=finish
```

There is no skip-all shorthand. `foundry finish` accepts only `--skip-hooks=finish`.

Skipped phases do not run. Skipping a phase that the mold marks as required fails
early — see [Required hook policy](#required-hook-policy).

## Required hook policy

Mold authors may optionally add `hooks/policy.dart` to declare which lifecycle
phases must run. The file is not scaffolded by `mold init` / `mold derive`; omit
it when every present hook remains skippable.

When the file exists, the mold cast session imports it by file URI and awaits a
top-level getter:

```dart
import 'package:foundry_core/foundry_core.dart';

/// Phases that callers must not skip, and that must have a hook file on disk.
Future<Set<MoldHookPhase>> get requiredHooks async => {
      MoldHookPhase.finish,
    };
```

- The getter name must be **`requiredHooks`**.
- Return type must be `Future<Set<MoldHookPhase>>` (async is required).
- If `hooks/policy.dart` is absent, the required set is empty — all present hooks
  are skippable, and missing prepare/shape/finish files remain no-ops for cast /
  recast.

Before the pipeline runs, Foundry validates the caller's `--skip-hooks` selection
against that set:

1. If any skipped phase is also required → fail early (names the required phases).
2. If a required phase has no `hooks/<phase>.dart` → fail early (lists missing
   paths).
3. Otherwise run the pipeline, skipping only phases listed in `--skip-hooks`.

`foundry finish` evaluates policy for the **finish** phase only (it never runs
prepare or shape). With `--skip-hooks=finish`:

- finish **not** required → success no-op (finish file not required)
- finish **required** → fail early

## Cast state and recast / finish seeds

Successful casts write `.foundry/last_cast.json` with an **encodable projection** of
resolved variables (JSON primitives, lists, and string-keyed maps). Non-encodable
values that prepare (or other hooks) may set on `FoundryContext` during a single cast
are **not** restored on `foundry recast` or `foundry finish` — those commands seed
context from the stored projection only.

Authors can rely on rich prepare seeds for gather/shape/finish **within one cast**,
and should treat `.foundry/last_cast.json` as a JSON-safe snapshot for later
`recast` / `finish` runs.

## Related documentation

- [Mold pubspec schema](mold-pubspec.schema.json) — JSON Schema for the mold root
  `pubspec.yaml`
- [README](../README.md) — CLI command reference and quick start
