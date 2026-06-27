# Foundry

**Foundry** is a Dart CLI for scaffolding and code generation. Authors define **Molds**
(Liquid templates with variables and hooks); users **cast** a mold with `--vars` to
produce an **Artifact** — a generated project or file tree at `--output`.

> [!WARNING]
> **Under development.** Foundry is pre-release and has not published to pub.dev yet.
> The CLI, library API, and `mold.yaml` schema are still evolving — **breaking
> changes may be introduced** before the first stable release.

| Item | Value |
| --- | --- |
| Repository | Standalone monorepo (Melos workspace) |
| Pub packages | [`foundry_core`](packages/foundry_core/), [`foundry_cli`](packages/foundry_cli/) |
| Executable | `foundry` |
| License | MIT |

---

## Why Foundry?

Foundry is inspired by [Mason](https://pub.dev/packages/mason) but targets authors who
want **Liquid everywhere** — in file templates, computed defaults, and conditional
variable visibility — with validation and business rules in **hooks** instead of
`mold.yaml`.

| Mason | Foundry |
| --- | --- |
| Brick | Mold |
| `brick.yaml` | `mold.yaml` |
| Mustache templates | Liquid templates |
| `pre_gen` / `post_gen` | `prepare` / `shape` / `finish` hooks |

See [REQUIREMENTS.md](REQUIREMENTS.md) for the full product specification.

---

## Typical mold layout

Foundry does not mandate a directory layout beyond what a mold declares in
`mold.yaml`. A common convention:

```
my_mold/
├── mold.yaml          # name, description, variables, optional hook paths
├── template/          # Liquid templates (file contents and path segments)
└── hooks/
    ├── pubspec.yaml   # depends on foundry_core
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
though the pub.dev package is **`foundry_cli`** — the same pattern as Clay
(`dart install clay_cli` → `clay` binary).

During local development in this repository, run the CLI via Melos or `dart run`
(see [Contributing](CONTRIBUTING.md)).

### Cast a mold

> **Planned.** The commands below are specified for v1 but not yet implemented in
> the CLI. They are documented here so authors know the intended workflow.

```bash
foundry cast ./my_mold \
  --output=./my_app \
  --vars project_name=MyApp \
  --vars project_type=app
```

Foundry resolves variables (including Liquid `when` and `default` expressions), runs
hook phases, and renders files under `template/` into `--output`.

### Scaffold a new mold

```bash
foundry mold init --name=my_mold
```

Creates `mold.yaml`, `template/`, and `hooks/` in the current directory.

### Inspect a mold

```bash
foundry mold inspect
```

Analyzes variable dependencies, hook paths, and template layout. Defaults to the
current directory when no path is given.

### Import a mold

```bash
foundry mold import git --git-url=https://github.com/example/molds.git --path=flutter_app
foundry mold import local --path=../shared-molds/api
```

Copies the mold into `./<name>/` under the current working directory, where `<name>`
comes from the mold manifest.

### Recast and finish

```bash
foundry recast
foundry finish
```

`recast` repeats the last successful cast using state stored in
`.foundry/last_cast.json`. `finish` runs only the finish hook against the last cast
output.

---

## CLI reference (planned)

Global flags and exit codes will align with common Dart CLI conventions once the
command runner lands. Planned top-level commands:

| Command | Description |
| --- | --- |
| `foundry mold init` | Scaffold a new mold in cwd |
| `foundry mold import git` | Import a mold from a git repository |
| `foundry mold import local` | Import a mold from a local path |
| `foundry mold inspect` | Validate and analyze a mold |
| `foundry cast` | Cast a mold to an artifact at `--output` |
| `foundry recast` | Re-run the last cast |
| `foundry finish` | Run the finish hook for the last cast |

Command flags (`--vars`, `--output`, `--force`, `--no-hooks`) are defined in
[REQUIREMENTS.md §3](REQUIREMENTS.md#3-cli-commands).

---

## Repository layout

```
foundry/
├── README.md                    # This file
├── CONTRIBUTING.md              # Contributor guide
├── pubspec.yaml                 # Melos workspace root
├── packages/
│   ├── foundry_core/            # Core library (mold parsing, cast pipeline)
│   │   └── e2e/                 # Library integration tests
│   └── foundry_cli/             # Publishable CLI package
│       └── e2e/                 # CLI integration tests
└── analysis_options.yaml
```

Monorepo setup, Melos scripts, CI/CD, and release workflows are documented in
[SETUP.md](SETUP.md).

---

## Programmatic API

Core logic lives in the [`foundry_core`](packages/foundry_core/) library package.
Public APIs for mold loading, variable resolution, template rendering, and cast
orchestration will be exported from `package:foundry_core/foundry_core.dart` as
features land.

Mold hooks depend on **`foundry_core`** (not `foundry_cli`):

```dart
import 'package:foundry_core/foundry_core.dart';

Future<void> run(HookContext context) async {
  context.logger.info('…');
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
| Mason | [pub.dev/packages/mason](https://pub.dev/packages/mason) |
| liquify (Liquid for Dart) | [pub.dev/packages/liquify](https://pub.dev/packages/liquify) |
| Melos | [melos.invertase.dev](https://melos.invertase.dev/) |
