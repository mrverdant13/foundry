# Foundry

**Foundry** is a Dart CLI for scaffolding and code generation. Authors define **Molds**
(Dart packages with Liquid templates, variables, and hooks); users **cast** a mold to
produce an **Artifact** — a generated project or file tree at `--output`.

> [!WARNING]
> **Under development.** Foundry is pre-release and has not published to pub.dev yet.
> The CLI and library API may still change before the first stable release.

| Item | Value |
| --- | --- |
| Repository | Standalone monorepo (Melos workspace) |
| Pub packages | [`foundry_core`](packages/foundry_core/), [`foundry_cli`](packages/foundry_cli/) |
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

After the first pub.dev release:

```bash
dart install foundry_cli
```

The global binary is **`foundry`** (`executables: foundry:` in `foundry_cli`), even
though the pub.dev package is **`foundry_cli`**.

During local development in this repository, run the CLI via Melos or `dart run`
(see [Contributing](CONTRIBUTING.md)).

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

Foundry runs lifecycle hooks, gathers variables through an interactive TUI, renders
files under `template/` into `--output`, and writes `.foundry/last_cast.json` in the
process working directory on success.

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
| `foundry mold init` | Scaffold a new mold in the current directory |
| `foundry mold import git` | Import a mold from a git repository |
| `foundry mold import local` | Import a mold from a local path |
| `foundry mold inspect` | Validate and analyze a mold |
| `foundry cast` | Cast a mold to an artifact at `--output` |
| `foundry recast` | Re-run the last cast |
| `foundry finish` | Run the finish hook for the last cast |

#### `foundry mold init`

```
foundry mold init [--name=<name>]
```

| Option | Description |
| --- | --- |
| `--name` | Mold package name (defaults to the current directory basename) |

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
```

| Argument / option | Description |
| --- | --- |
| `<mold-path>` | **Required.** Path to the mold directory |
| `--output` | **Required.** Directory to write generated artifacts |
| `--force` | Allow casting into a non-empty output directory |
| `--no-hooks` | Skip prepare, shape, and finish hooks |

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
├── pubspec.yaml                 # Melos workspace root
├── packages/
│   ├── foundry_core/            # Core library (mold parsing, cast pipeline)
│   │   └── e2e/                 # Library integration tests
│   └── foundry_cli/             # Publishable CLI package
│       └── e2e/                 # CLI integration tests
└── analysis_options.yaml
```

Monorepo setup, Melos scripts, CI/CD, and release workflows are covered in
[Contributing](CONTRIBUTING.md).

---

## Programmatic API

Core logic lives in the [`foundry_core`](packages/foundry_core/) library package.
Public APIs for mold loading, variable resolution, template rendering, and cast
orchestration are exported from `package:foundry_core/foundry_core.dart`.

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

See [CONTRIBUTING.md](CONTRIBUTING.md) for local setup, Melos commands, testing
expectations, commit conventions, and pull request guidelines.

---

## Related links

| Resource | URL |
| --- | --- |
| liquify (Liquid for Dart) | [pub.dev/packages/liquify](https://pub.dev/packages/liquify) |
| Melos | [melos.invertase.dev](https://melos.invertase.dev/) |
