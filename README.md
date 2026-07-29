# Foundry

**Foundry** is a Dart CLI for scaffolding and code generation. Authors define **Molds**
(Dart packages with Liquid templates, variables, and hooks); users **cast** a mold to
produce an **Artifact** — a generated project or file tree at `--output`.

> [!NOTE]
> **Pre-release.** Packages are published on pub.dev as `0.0.1-dev.x`. The CLI and
> library API may still change before the first stable release.

| Item | Value |
| --- | --- |
| Repository | Standalone monorepo (Ripple scripts) |
| Pub packages | [`foundry_core`](https://pub.dev/packages/foundry_core), [`foundry_cli`](https://pub.dev/packages/foundry_cli) |
| Executable | `foundry` |
| License | MIT |

---

## Why Foundry?

Foundry renders mold **templates** with **Liquid** — file contents and dynamic path
segments — while interactive variable behavior (`defaultValue`, `visibleWhen`,
validators) and hook logic live in **Dart** (`variables.dart` and `hooks/`), not in
the mold manifest.

Inspired by [Mason](https://pub.dev/packages/mason).

---

## Typical mold layout

Each mold is a **Dart package**. The root `pubspec.yaml` is the mold manifest;
variable definitions live in `variables.dart`. See
[`doc/mold-pubspec.schema.json`](doc/mold-pubspec.schema.json) for editor validation.

```
flutter_app/
├── pubspec.yaml       # name, description, version, foundry_core dependency
├── variables.dart     # FoundryVariableGroup for interactive input
├── lib/               # optional shared Dart code
├── template/          # Liquid templates (file contents and path segments)
└── hooks/             # optional lifecycle hooks (see doc/hooks.md)
    ├── prepare.dart
    ├── shape.dart
    └── finish.dart
```

---

## Quick start

### Install the CLI

```bash
dart install foundry_cli
foundry --version
```

The global binary is **`foundry`** (`executables: foundry:` in `foundry_cli`), even
though the pub.dev package is **`foundry_cli`**.

During local development in this repository, run the CLI via `dart run`
(see [Contributing](CONTRIBUTING.md)).

### Scaffold a pattern

```bash
foundry pattern init --name=demo_pattern
```

Creates `.foundry/pattern.yaml` and a README stub in the current directory. A
pattern is a reference project tree used to inspect structure and seed molds.
Annotate pattern files with comment markers, and optionally declare
`replacements` / `lineDeletions` in `.foundry/pattern.yaml`, so derive/sync can
produce a parametrized Liquid `template/` — see
[`doc/annotations.md`](doc/annotations.md).

### Inspect a pattern

```bash
foundry pattern inspect
```

Reports pattern name, file count, top-level entries, ignore globs, and ignored
paths. Defaults to the current directory when no path is given.

### Derive a mold from a pattern

```bash
foundry mold derive --pattern=./demo_pattern --output=./flutter_app
```

Generates a starter mold package (Liquidized `template/`, stub `variables.dart`,
root `pubspec.yaml`, empty `hooks/`) from a pattern directory. Content
transforms honor pattern annotations and `.foundry/pattern.yaml`
`replacements` / `lineDeletions` (see [`doc/annotations.md`](doc/annotations.md)).
Defaults to the current directory when `--output` is omitted; because that path
already exists, omitting `--output` always requires `--force`. Use `--force` to
overwrite any existing destination.

### Sync a mold template from a pattern

```bash
foundry mold sync --pattern=./demo_pattern
```

Refreshes `template/` in the current mold from a pattern directory while
preserving root `pubspec.yaml`, `variables.dart`, `hooks/`, and other
non-`template/` author edits. Uses the same annotation and
`replacements` / `lineDeletions` rules as derive (see
[`doc/annotations.md`](doc/annotations.md)). Use `--force` to replace
`template/` wholesale (orphan template files that no longer exist in the
pattern are removed).

### Scaffold a new mold

```bash
foundry mold init --name=flutter_app
```

Creates `pubspec.yaml`, `variables.dart`, `template/`, and `hooks/` in the current
directory.

### Inspect a mold

```bash
foundry mold inspect
```

Validates the mold package, `template/` directory, and optional hook files, and
reports variable metadata from a live describe session over `variables.dart`.
Defaults to the current directory when no path is given.

### Import a mold

```bash
foundry mold import git \
  --git-url=https://github.com/example/molds.git \
  --path=flutter_app

foundry mold import local --path=../shared-molds/api
```

Copies the mold into `./<name>/` under the current working directory, where `<name>`
comes from the mold's root `pubspec.yaml` `name` field.

### Cast a mold

```bash
foundry cast ./flutter_app --output=./my_app
```

Cast runs inside a **mold cast session**: Foundry composes a short-lived helper
package that depends on the CLI and your mold, then runs prepare → gather → shape →
render → finish in one process that imports the mold's live `variables.dart` and
in-process hooks. Callbacks such as `visibleWhen` / `defaultValue` / validators
execute as real Dart; prepare can seed rich context values that gather, shape, and
finish see on the same `FoundryContext` (see [`doc/hooks.md`](doc/hooks.md)).

By default Foundry gathers variables through an interactive TUI inside that session,
renders files under `template/` into `--output`, and on success writes
`.foundry/last_cast.json` in the process working directory. That file stores an
**encodable projection** of resolved values (JSON primitives, lists, and
string-keyed maps only) — not arbitrary Dart objects seeded during the cast.

Pass `--vars` and/or `--vars-file` to supply values in batch and skip the TUI:

```bash
foundry cast ./flutter_app --output=./my_app --vars=project_name=MyApp
foundry cast ./flutter_app --output=./my_app --vars-file=./vars.json
```

Use `--force` to cast into a non-empty output directory. Use `--no-hooks` to skip all
hook phases.

### Recast and finish

```bash
foundry recast
foundry finish
```

`recast` and `finish` also launch a mold cast session against the last successful
cast. `recast` re-runs the full pipeline using paths and the **encodable** `vars`
projection from `.foundry/last_cast.json` (JSON-safe values only; non-encodable
prepare seeds from the original cast are not restored). `finish` runs only the
finish hook against the stored output path without re-rendering templates.

---

## CLI reference

### Invocation

```
foundry [--version] <command> [arguments] [options]
```

### Global flags

| Flag | Description |
| --- | --- |
| `--version` | Print the CLI version and exit |

### Exit codes

| Code | Meaning |
| --- | --- |
| `0` | Success |
| `1` | User-facing error (invalid input, mold load failure, hook abort, etc.) |
| `2` | Unexpected internal error |

### Commands

| Command | Description |
| --- | --- |
| `foundry pattern init` | Scaffold a pattern marker and README in the current directory |
| `foundry pattern inspect` | Analyze a pattern directory |
| `foundry mold init` | Scaffold a new mold in the current directory |
| `foundry mold derive` | Derive a starter mold from a pattern directory |
| `foundry mold sync` | Sync an existing mold template from a pattern directory |
| `foundry mold import git` | Import a mold from a git repository |
| `foundry mold import local` | Import a mold from a local path |
| `foundry mold inspect` | Validate and analyze a mold |
| `foundry cast` | Cast a mold to an artifact at `--output` |
| `foundry recast` | Re-run the last cast |
| `foundry finish` | Run the finish hook for the last cast |

#### `foundry pattern init`

```
foundry pattern init [--name=<name>]
```

| Option | Description |
| --- | --- |
| `--name` | Pattern name (defaults to the current directory basename) |

Creates `.foundry/pattern.yaml` (name + starter ignore globs) and a README
stub that describes the pattern layout. Authors may later add `replacements`
and `lineDeletions` to the marker, or comment markers in pattern files — see
[`doc/annotations.md`](doc/annotations.md).

#### `foundry pattern inspect`

```
foundry pattern inspect [<path>]
```

Analyzes a pattern directory and prints a human-readable report (name, marker
presence, file count, ignore globs, top-level entries, and ignored paths).
Defaults to the current directory when `<path>` is omitted. Exits with code
`1` when the path is missing or not a directory.

#### `foundry mold init`

```
foundry mold init [--name=<name>]
```

| Option | Description |
| --- | --- |
| `--name` | Mold package name (defaults to the current directory basename) |

#### `foundry mold derive`

```
foundry mold derive --pattern=<path> [--output=<dir>] [--force]
```

| Option | Description |
| --- | --- |
| `--pattern` | **Required.** Pattern directory to derive from |
| `--output` | Destination for the derived mold (defaults to the current directory; requires `--force` when omitted, since cwd already exists) |
| `--force` | Overwrite the destination directory if it already exists |

Resolves pattern annotations and `.foundry/pattern.yaml` `replacements` /
`lineDeletions` into the mold `template/` (see
[`doc/annotations.md`](doc/annotations.md)).

#### `foundry mold sync`

```
foundry mold sync --pattern=<path> [--force]
```

| Option | Description |
| --- | --- |
| `--pattern` | **Required.** Pattern directory to sync from |
| `--force` | Replace `template/` wholesale (remove orphans); author edits outside `template/` are still preserved |

Syncs the mold in the current directory. Refreshes `template/` from the pattern
(same annotation / `replacements` / `lineDeletions` rules as derive; see
[`doc/annotations.md`](doc/annotations.md)) while preserving root
`pubspec.yaml`, `variables.dart`, `hooks/`, and other non-`template/` files.

#### `foundry mold import git`

```
foundry mold import git --git-url=<url> [--path=<relative/path>] [--force]
```

| Option | Description |
| --- | --- |
| `--git-url` | **Required.** Git repository URL to shallow-clone |
| `--path` | Relative path to the mold within the repository |
| `--force` | Overwrite the destination directory if it already exists |

#### `foundry mold import local`

```
foundry mold import local --path=<dir> [--force]
```

| Option | Description |
| --- | --- |
| `--path` | **Required.** Local directory containing the mold |
| `--force` | Overwrite the destination directory if it already exists |

#### `foundry mold inspect`

```
foundry mold inspect [<path>]
```

| Argument | Description |
| --- | --- |
| `<path>` | Mold directory (defaults to the current directory) |

#### `foundry cast`

```
foundry cast <mold-path> --output=<dir> [--force] [--no-hooks]
  [--vars=<k=v,…>] [--vars-file=<path>]
```

Runs a mold cast session (live `variables.dart` + in-process hooks). On success,
writes `.foundry/last_cast.json` with an encodable `vars` projection only.

| Argument / option | Description |
| --- | --- |
| `<mold-path>` | **Required.** Path to the mold directory |
| `--output` | **Required.** Directory to write generated artifacts |
| `--force` | Allow casting into a non-empty output directory |
| `--no-hooks` | Skip prepare, shape, and finish hooks |
| `--vars` | Comma-separated `key=value` pairs (skips the TUI) |
| `--vars-file` | Path to a JSON object of variable values (skips the TUI) |

#### `foundry recast`

```
foundry recast [--force] [--no-hooks]
```

Replays the last cast via a mold cast session seeded from `.foundry/last_cast.json`.
Stored `vars` are an encodable projection only.

| Option | Description |
| --- | --- |
| `--force` | Allow casting into a non-empty output directory |
| `--no-hooks` | Skip prepare, shape, and finish hooks |

#### `foundry finish`

```
foundry finish [--no-hooks]
```

Runs a finish-only mold cast session for the last cast (requires
`hooks/finish.dart`). Seeds context from the encodable `vars` projection in
`.foundry/last_cast.json`.

| Option | Description |
| --- | --- |
| `--no-hooks` | Skip the finish hook |

---

## Repository layout

```
foundry/
├── README.md                    # This file
├── CONTRIBUTING.md              # Contributor guide
├── doc/
│   ├── mold-pubspec.schema.json # JSON Schema for mold pubspec.yaml
│   ├── hooks.md                 # Mold lifecycle hooks reference
│   └── annotations.md           # Pattern annotations and pattern.yaml
├── pubspec.yaml                 # Root tooling package
├── ripple.yaml                  # Ripple package discovery and scripts
├── packages/
│   ├── foundry_core/            # Core library (mold parsing, cast pipeline)
│   │   └── e2e/                 # Library integration tests
│   └── foundry_cli/             # Publishable CLI package
│       └── e2e/                 # CLI integration tests
└── analysis_options.yaml
```

Monorepo setup, Ripple scripts, CI/CD, and release workflows are covered in
[Contributing](CONTRIBUTING.md).

---

## Programmatic API

Core logic lives in the [`foundry_core`](https://pub.dev/packages/foundry_core)
library package. Public APIs for mold loading, variable resolution, template
rendering, and cast orchestration are exported from
`package:foundry_core/foundry_core.dart`.

Mold hooks depend on **`foundry_core`** (not `foundry_cli`). The CLI runs them
inside a mold cast session so prepare, gather, shape, and finish share one live
context — see [`doc/hooks.md`](doc/hooks.md). Pattern derive/sync transforms are
documented in [`doc/annotations.md`](doc/annotations.md).

```dart
import 'package:foundry_core/foundry_core.dart';

Future<void> run(FoundryContext context) async {
  context.logger.info('…');
  context.set('extra', 'value');
}
```

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for local setup, Ripple commands, testing
expectations, commit conventions, and pull request guidelines.

---

## Related links

| Resource | URL |
| --- | --- |
| foundry_core | [pub.dev/packages/foundry_core](https://pub.dev/packages/foundry_core) |
| foundry_cli | [pub.dev/packages/foundry_cli](https://pub.dev/packages/foundry_cli) |
| liquify (Liquid for Dart) | [pub.dev/packages/liquify](https://pub.dev/packages/liquify) |
| Ripple | [github.com/mrverdant13/ripple](https://github.com/mrverdant13/ripple) |
