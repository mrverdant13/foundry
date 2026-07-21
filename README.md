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

Foundry uses **Liquid everywhere** — in file templates, computed defaults, and
conditional variable visibility — with validation and business rules in **Dart**
(`variables.dart` and hooks), not in the mold manifest.

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
root `pubspec.yaml`, empty `hooks/`) from a pattern directory. Defaults to the
current directory when `--output` is omitted; because that path already exists,
omitting `--output` always requires `--force`. Use `--force` to overwrite any
existing destination.

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

Validates the mold package, variable group, `template/` directory, and optional hook
files. Defaults to the current directory when no path is given.

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

Foundry gathers variables through an interactive TUI by default, renders files
under `template/` into `--output`, and writes `.foundry/last_cast.json` in the
process working directory on success.

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

`recast` repeats the last successful cast using state stored in
`.foundry/last_cast.json`. `finish` runs only the finish hook against the last cast
output without re-rendering templates.

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
stub that describes the pattern layout.

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

| Option | Description |
| --- | --- |
| `--force` | Allow casting into a non-empty output directory |
| `--no-hooks` | Skip prepare, shape, and finish hooks |

#### `foundry finish`

```
foundry finish [--no-hooks]
```

| Option | Description |
| --- | --- |
| `--no-hooks` | Skip the finish hook (no-op when omitted hook file) |

---

## Repository layout

```
foundry/
├── README.md                    # This file
├── CONTRIBUTING.md              # Contributor guide
├── doc/
│   ├── mold-pubspec.schema.json # JSON Schema for mold pubspec.yaml
│   └── hooks.md                 # Mold lifecycle hooks reference
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

Mold hooks depend on **`foundry_core`** (not `foundry_cli`). See
[`doc/hooks.md`](doc/hooks.md) for the full hook contract.

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
