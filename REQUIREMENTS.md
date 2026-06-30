# Foundry — Requirements

> Code-generation CLI inspired by [Mason](https://github.com/felangel/mason), powered by [Liquid](https://pub.dev/packages/liquify) (via `liquify`), with a richer variable system and a foundry manufacturing metaphor.

**This file is the canonical specification.** Design notes and exploration that informed it live under [`.planning/`](.planning/):

| Document | Contents |
|----------|----------|
| [`.planning/FOUNDRY.md`](.planning/FOUNDRY.md) | Foundry naming metaphor, Pattern → Mold → Artifact vocabulary, CLI command exploration |
| [`.planning/KILN.md`](.planning/KILN.md) | Mason comparison, Liquid template engine, variable system options, hooks, and component naming |
| [`CONTRIBUTING.md`](CONTRIBUTING.md) | Monorepo layout, Melos workspace, CI/CD, and contributor bootstrap |
| [`TIMELINE.md`](TIMELINE.md) | Progressive PR plan and acceptance criteria |

Where this document conflicts with the planning notes, **REQUIREMENTS.md wins**.

---

## 1. Overview

**Foundry** is a Dart CLI for scaffolding and code generation. Users apply **Molds** (Liquid templates) with **variables** to produce **Artifacts** (generated projects or files).

### Design goals

- Familiar to Mason users, but more expressive for template authors
- **Liquid for templates; Dart for variable definitions** — file templates render with Liquid, while interactive variable behavior lives in `variables.dart`
- Validation and business rules live in **Dart** (`variables.dart` and hooks), not in `pubspec.yaml` metadata
- CLI vocabulary grounded in foundry manufacturing, without requiring users to know metallurgy
- Everyday workflow optimized around **`foundry cast`**

### v1 scope

Focus on **hand-authored molds**:

| In v1 | Out of v1 scope |
|-------|-----------------|
| `foundry mold init` | `foundry mold derive` |
| `foundry mold import git` / `local` | `foundry mold sync` / `update` |
| `foundry mold inspect` | Pattern workflow (`pattern init`, `pattern inspect`) |
| `foundry cast` with Nocterm-based TUI and required `--output` | Non-interactive variable flags / batch mode |
| Hook lifecycle (prepare, shape, finish) | Template registry / hub |
| `foundry recast`, `foundry finish` | |

### Mason comparison

| Mason | Foundry |
|-------|---------|
| Mason CLI | Foundry CLI |
| Brick | Mold |
| `brick.yaml` | Root `pubspec.yaml` (mold is a Dart package) |
| BrickHub | Not in v1 — molds distributed via git and local import |
| Mustache templates | Liquid templates |
| Flat `vars` | `variables.dart` with `FoundryVariableGroup`, code-first defaults/visibility, and TUI capture |
| `pre_gen` / `post_gen` | `prepare` / `shape` / `finish` |

---

## 2. Core concepts

### 2.1 Nouns

| Term | Definition |
|------|------------|
| **Foundry** | The CLI tool (`foundry` binary) — not a workspace manifest or project type. Implemented by the **`foundry_cli`** pub package |
| **Mold** | Reusable Liquid template definition (recipe). Used with user-provided variables to generate an artifact |
| **Artifact** | Generated output — a project, directory tree, or set of files at `--output` |
| **Variables** | Inputs collected during casting from a Nocterm-based TUI, defined in root **`variables.dart`** |
| **FoundryVariableGroup** | Code-first schema object exported from `variables.dart`, describing interactive variables, defaults, visibility, and validation |

### 2.2 Verbs and transformations

| From | To | Verb | CLI |
|------|----|------|-----|
| — | Mold | `init` | `foundry mold init` |
| External source | Mold | `import` | `foundry mold import git` / `local` |
| Mold | — | `inspect` | `foundry mold inspect` |
| Mold | Artifact | `cast` | `foundry cast …` |
| Artifact | Artifact | `recast` | `foundry recast` |
| Artifact | Artifact | `finish` | `foundry finish` |

**Pipeline:** Molds describe how to generate artifacts; casting applies a mold with variables to produce an artifact at `--output`.

```
Mold
   │
   ├── init
   ├── import (git | local)
   ├── inspect
   │
   └── cast (+ TUI, --output)
         │
         ▼
     Artifact
         │
      finish
```

---

## 3. CLI commands

Commands are organized around **resources** (mold, cast), similar to Git, Docker, or Kubernetes.

### 3.1 Mold

| Command | Description |
|---------|-------------|
| `foundry mold init [--name=<name>]` | Scaffold root `pubspec.yaml`, `variables.dart`, `template/`, and `hooks/` in the **current directory** |
| `foundry mold import git --git-url=<url> [--path=<relative/path>] [--force]` | Clone or fetch a git repo and copy the mold into `./<name>/` under cwd |
| `foundry mold import local --path=<path> [--force]` | Copy a local mold directory into `./<name>/` under cwd |
| `foundry mold inspect [<path>]` | Analyze a mold. Defaults to cwd if path omitted |

**Import destination:** the mold is copied to `./<name>/` relative to cwd, where `<name>` is the `name` field from the mold's root `pubspec.yaml`. Without `--force`, import **fails** if `./<name>/` already exists.

**Import transports:** `git` and `local`.

### 3.2 Cast (primary user workflow)

| Command | Description |
|---------|-------------|
| `foundry cast <mold-path> --output=<dir> [--force] [--no-hooks]` | Cast a mold into an artifact |
| `foundry recast [--force] [--no-hooks]` | Re-run the last successful cast (see §3.3) |
| `foundry finish [--no-hooks]` | Run the mold's **finish** hook against the last cast output (see §3.3) |

**Mold path:** the positional `<mold-path>` is a **filesystem path** to a mold directory containing a root `pubspec.yaml` (absolute or relative).

**`--output`:** required on `foundry cast`. Must not exist or must be empty unless `--force` is passed.

**Variable input:** `foundry cast` always loads the mold's root `variables.dart`, evaluates its exported `moldVariables` `FoundryVariableGroup`, and launches a **Nocterm-based TUI** to gather values interactively.

**`--force` on cast:** allowed when `--output` already exists and is non-empty. Foundry writes generated files to their target paths under `--output`, **overwriting** matching paths. It does **not** delete unrelated files already in `--output`.

**`--no-hooks`:** skip all hook execution for that command.

There is **no** top-level `foundry inspect`.

**Examples:**

```bash
foundry cast ./flutter_app \
  --output=./my_app

foundry cast ../shared-molds/api \
  --output=./packages/my_api
```

### 3.3 Cast state (`recast` / `finish`)

After a **successful** `foundry cast`, Foundry writes **`.foundry/last_cast.json`** in the **process cwd** (not inside `--output`):

```json
{
  "moldPath": "./flutter_app",
  "outputPath": "./my_app",
  "vars": {
    "project_name": "MyApp",
    "project_type": "app"
  },
  "timestamp": "2026-06-26T12:00:00.000Z"
}
```

| Command | Behavior |
|---------|----------|
| `foundry recast` | Reads `.foundry/last_cast.json` and re-runs cast with the same mold path, output path, and vars. Fails with a clear error if the file is missing. Accepts `--force` and `--no-hooks` |
| `foundry finish` | Reads `.foundry/last_cast.json`, loads the mold's **finish** hook, and runs it with cwd set to the stored `outputPath`. Does not re-render templates. Fails if no prior cast or mold has no finish hook |

---

## 4. Mold structure

```
flutter_app/
├── pubspec.yaml       # Mold package manifest (name, description, dependencies)
├── variables.dart     # FoundryVariableGroup definition for interactive input
├── lib/               # Optional shared Dart code for variables and hooks
├── template/          # Liquid template files (mirror artifact paths)
└── hooks/             # Optional Dart lifecycle hooks
    ├── prepare.dart
    ├── shape.dart
    └── finish.dart
```

### 4.1 Root `pubspec.yaml`

Each mold is a **Dart package**. The root `pubspec.yaml` replaces Mason's `brick.yaml` as the mold manifest and provides package resolution for `variables.dart`, `lib/`, and hooks.

**Required fields:**

```yaml
name: flutter_app
description: Flutter application starter
version: 1.0.0

environment:
  sdk: ">=3.5.0 <4.0.0"

dependencies:
  foundry_core: ^0.0.1-dev.1
```

- **`name`** — mold identifier; also used as the import destination directory name
- **`description`** — short human-readable summary
- **`version`** — standard pub package version (use `1.0.0` for hand-authored molds)
- **`dependencies.foundry_core`** — required so `variables.dart` and hooks can `import 'package:foundry_core/foundry_core.dart'`
- **`publish_to: none`** — recommended for molds not published to pub.dev

Foundry runs **`dart pub get`** in the mold directory during **inspect** and **cast** so dependencies resolve before loading `variables.dart` or running hooks.

**Hook paths** are conventional (not declared in `pubspec.yaml`):

| Phase | Path |
|-------|------|
| prepare | `hooks/prepare.dart` |
| shape | `hooks/shape.dart` |
| finish | `hooks/finish.dart` |

Missing hook files are no-ops.

### 4.2 `variables.dart`

Code-first variable definition file loaded by Foundry during **inspect** and **cast**.

**Required contract:**

```dart
import 'package:foundry_core/foundry_core.dart';

final moldVariables = FoundryVariableGroup(
  variables: {
    'project_name': FoundryStringVariable(label: 'Project name'),
  },
);
```

- File name: **`variables.dart`**
- Required top-level symbol: **`moldVariables`**
- Type: **`FoundryVariableGroup`**
- Loaded by executing Dart code in an isolated process during inspect/cast
- Should be deterministic and side-effect free beyond schema construction

### 4.3 `template/`

- Files under `template/` mirror paths written to `--output`
- File contents are rendered with Liquid
- Path segments may include Liquid expressions for dynamic file paths (same idea as Mason's `{{name}}` segments)

---

## 5. Variable system

Support computed defaults, conditional visibility, and validation through a code-first **`FoundryVariableGroup`**. Variable fields are not declared in `pubspec.yaml`.

### 5.1 Design principles

- **Code-first schema** in `variables.dart`
- **No variable declarations** in `pubspec.yaml`
- **Nocterm-only input** in the CLI — no `--vars`
- **Core owns variable behavior** (defaults, visibility, validation); hooks handle additional context shaping and side effects

### 5.2 Supported types (v1)

| Kind | Dart API | Notes |
|------|----------|-------|
| `string` | `FoundryStringVariable` | Basic text input |
| `boolean` | `FoundryBooleanVariable` | Toggle / yes-no input |
| `int` | `FoundryIntVariable` | Integer input |
| `double` | `FoundryDoubleVariable` | Decimal input |
| `object` | `FoundryObjectVariable<T>` | Nested object or grouped fields |
| `single-choice` | `FoundrySingleChoiceVariable<T>` | Pick one option |
| `multiple-choice` | `FoundryMultipleChoiceVariable<T>` | Pick many options |
| `values` | `FoundryValuesVariable<T>` | Reorderable/repeatable values with optional custom creation |

### 5.3 Variable fields

| Property | Purpose |
|----------|---------|
| `label` | Human-readable label shown in the TUI |
| `defaultValue` | Static value or Dart callback using the current gathered context |
| `visibleWhen` | Dart callback; when false, the variable is skipped |
| `validators` | Per-variable validation callbacks |
| `groupValidators` | Cross-field validation for the whole `FoundryVariableGroup` |
| `options` / `baseOptions` | Choice values for selection-based inputs |

### 5.4 Resolution order

When casting, Foundry evaluates variables in this order:

1. **Load** `moldVariables` from `variables.dart`
2. **Seed** context from the optional **prepare** hook
3. Build the initial TUI state by evaluating each variable's **`visibleWhen`** and **`defaultValue`** against the current gathered context
4. As the user edits values, Foundry broadly **recomputes** visibility and defaults for affected screens using the latest gathered context
5. For each **visible** variable, collect or confirm the value in the Nocterm TUI
6. Run per-variable validators and group validators; invalid submission keeps the user in the TUI until the form is valid or they abort
7. Run the **shape** hook; hook may read/write `context.vars` or throw to abort

There is no `required` flag in `pubspec.yaml`. Requiredness, defaults, and conditional visibility are expressed in `variables.dart`.

### 5.5 Example

```dart
import 'package:foundry_core/foundry_core.dart';

final moldVariables = FoundryVariableGroup(
  variables: {
    'project_type': FoundrySingleChoiceVariable<String>(
      label: 'Project type',
      options: {'app', 'package'},
    ),
    'project_name': FoundryStringVariable(
      label: 'Project name',
    ),
    'package_name': FoundryStringVariable(
      label: 'Package name',
      visibleWhen: (values) => values['project_type'] == 'package',
      defaultValue: (values) {
        final projectName = values['project_name'] as String;
        return projectName.replaceAll(' ', '_').toLowerCase();
      },
    ),
    'class_name': FoundryStringVariable(
      label: 'Class name',
      defaultValue: (values) => values['project_name'],
    ),
  },
);
```

Cross-field validation in **`variables.dart`**:

```dart
import 'package:foundry_core/foundry_core.dart';

final moldVariables = FoundryVariableGroup(
  variables: { /* ... */ },
  groupValidators: [
    (values) {
      if (values['project_type'] == 'package' &&
          (values['package_name'] as String).isEmpty) {
        return 'package_name is required when project_type is package';
      }
      return null;
    },
  ],
);
```

---

## 6. Cast lifecycle and hooks

### 6.1 End-to-end flow

```
Mold
   │
   ▼
Prepare          ← hook: optional; before variable resolution
   │
   ▼
Load variable group (`variables.dart`)
   │
   ▼
Collect variables (Nocterm TUI → defaults → validators)
   │
   ▼
Shape            ← hook: optional; validate and transform context.vars
   │
   ▼
Cast             ← Liquid render template/ → files under --output
   │
   ▼
Artifact
   │
   ▼
Finish           ← hook: optional; post-process at output directory
   │
   ▼
Write .foundry/last_cast.json (on success)
```

### 6.2 Hook specification

Aligned with [Mason hooks](https://docs.brickhub.dev/hooks/): Dart-only, one `run` entry point per file, executed from the mold's root Dart package (no separate `hooks/pubspec.yaml`).

| Phase | Mason equivalent | Runs | Purpose |
|-------|------------------|------|---------|
| **prepare** | pre_gen (early) | Before variable resolution | Seed context, prefetch external data |
| **shape** | pre_gen (late) | After variables resolved | Validate, transform `context.vars` |
| **finish** | post_gen | After cast | Format, lint, run commands |

**Entry point** (sync or async):

```dart
import 'package:foundry_core/foundry_core.dart';

Future<void> run(HookContext context) async {
  context.logger.info('…');
  context.vars = {...context.vars, 'extra': 'value'};
}
```

**`HookContext` (v1):**

| Member | Type | Description |
|--------|------|-------------|
| `vars` | `Map<String, dynamic>` | Read/write variable map |
| `logger` | `Logger` | Info / warn / error / progress |
| `moldDirectory` | `Directory` | Root of the mold |
| `outputDirectory` | `Directory` | `--output` path (finish hook cwd) |

**Working directory:** hook process cwd is **`outputDirectory`** (same as Mason post_gen).

**Errors:** any uncaught exception (including `HookException`) aborts the command with exit code **1**. Partial artifacts from a failed cast are left on disk; Foundry does not roll back.

**Optional hooks:** omitted hook files are no-ops. `--no-hooks` skips all hooks.

**Mold `pubspec.yaml`:** must depend on **`foundry_core`** (provides `HookContext`, `HookException`, `Logger`, and `FoundryVariableGroup`). Molds may declare additional dependencies for shared logic in `lib/`, `variables.dart`, or hooks. Example:

```yaml
name: my_mold
description: Example mold package
version: 1.0.0
publish_to: none

environment:
  sdk: ">=3.5.0 <4.0.0"

dependencies:
  foundry_core: ^0.0.1-dev.1
  # optional: path, git, or pub.dev packages for shared mold logic
```

### 6.3 Template rendering

- **Engine:** Liquid via `liquify`
- **Source:** `template/`
- **Destination:** `--output`
- **Verb:** cast

---

## 7. Mold import

| Transport | Command |
|-----------|---------|
| **git** | `foundry mold import git --git-url=<url> [--path=<relative/path>]` |
| **local** | `foundry mold import local --path=<path>` |

**git behavior:** shallow clone (or sparse checkout of `--path` when provided) into a temp directory, then copy the mold subtree to `./<name>/`. Temp directory is deleted after import.

**local behavior:** copy the directory at `--path` to `./<name>/`.

No central registry in v1 — molds are shared via git repositories or local paths.

---

## 8. User-facing output and messaging

- **Verb:** cast — "Cast completed"
- **Noun:** artifact — "12 artifacts generated"
- Do not call generated files "casts"

Example:

```
$ foundry cast ./flutter_app --output=./my_app

✓ Cast completed
✓ 12 artifacts generated at ./my_app
```

**Exit codes:**

| Code | Meaning |
|------|---------|
| `0` | Success |
| `1` | User error (invalid variable input, invalid mold, hook failure, output exists without `--force`) |
| `2` | Unexpected internal error |

---

## 9. Technical constraints

### 9.1 Runtime

| Item | Requirement |
|------|-------------|
| Language | Dart |
| SDK | `^3.0.0` |
| Template engine | Liquid via `liquify` (pub.dev) |
| TUI engine | `nocterm` (CLI package only) |
| Reference CLI | Mason (hooks, mold layout, cast workflow) |
| Platforms | macOS, Linux, Windows (where Dart CLI runs) |
| Global binary | `foundry` |

### 9.2 Pub.dev packages

Foundry ships as two publishable packages (Clay-style split). Workspace layout and release process: [`CONTRIBUTING.md`](CONTRIBUTING.md).

| pub.dev package | Role | Install / use |
|-----------------|------|---------------|
| **`foundry_core`** | Core library — mold parsing, `FoundryVariableGroup`, variable runtime, Liquid rendering, cast pipeline, hook API | Mold root `pubspec.yaml`; programmatic API |
| **`foundry_cli`** | CLI — `foundry` executable, commands, and Nocterm-based variable TUI | `dart install foundry_cli` |

- **CLI install:** `dart install foundry_cli` (global binary name remains **`foundry`**)
- **Hook dependency:** `foundry_core` only — not `foundry_cli`
- **Release order:** when both packages release, publish **`foundry_core` first**, then **`foundry_cli`**

---

## 10. Non-goals (v1)

- Declarative `constraints` or `validate` in mold `pubspec.yaml`
- Non-interactive variable flags / batch mode
- `foundry mold derive`, pattern workflow, and template registry
- Top-level `foundry inspect`
- Foundry workspace manifest (e.g. root `foundry.yaml`)
- JavaScript hooks
- Automatic rollback of partial artifacts on failure

---

## 11. Reference example

### Root `pubspec.yaml`

```yaml
name: flutter_app
description: Flutter application starter
version: 1.0.0
publish_to: none

environment:
  sdk: ">=3.5.0 <4.0.0"

dependencies:
  foundry_core: ^0.0.1-dev.1
```

### `variables.dart`

```dart
import 'package:foundry_core/foundry_core.dart';

final moldVariables = FoundryVariableGroup(
  variables: {
    'project_type': FoundrySingleChoiceVariable<String>(
      label: 'Project type',
      options: {'app', 'package'},
    ),
    'project_name': FoundryStringVariable(
      label: 'Project name',
    ),
    'package_name': FoundryStringVariable(
      label: 'Package name',
      visibleWhen: (values) => values['project_type'] == 'package',
      defaultValue: (values) {
        final projectName = values['project_name'] as String;
        return projectName.replaceAll(' ', '_').toLowerCase();
      },
    ),
  },
);
```

### Maintainer workflow

```bash
foundry mold init --name=flutter_app
# … author pubspec.yaml, variables.dart, template/, and optional hooks/ …
foundry mold inspect
```

### Consumer workflow

```bash
dart install foundry_cli

foundry mold import git \
  --git-url=https://example.com/molds.git \
  --path=flutter_app

foundry cast ./flutter_app --output=./my_app

foundry finish
```

---

## 12. Decisions log

| # | Decision |
|---|----------|
| 1 | Bootstrap: **`foundry mold init`** |
| 2 | Import transports: **`git`** and **`local`** |
| 3 | Molds are **Dart packages**: root **`pubspec.yaml`** is the manifest; variable definitions live in root **`variables.dart`**; hook paths are conventional under **`hooks/`** |
| 4 | Variable behavior is code-first via **`FoundryVariableGroup`** |
| 5 | Template directory: **`template/`** |
| 6 | Inspect: **`foundry mold inspect`** only |
| 7 | **Foundry** = CLI only |
| 8 | **`--output` required** on cast |
| 9 | Variables: **Nocterm-based TUI only** in v1; no `--vars` |
| 10 | v1: **hand-authored molds** |
| 11 | Variable collection order: load **`moldVariables`** → broad recomputation of defaults / visibility → TUI validation |
| 12 | **`--force`**: allow non-empty `--output`; overwrite generated paths only |
| 13 | **`recast` / `finish`**: state in **`.foundry/last_cast.json`** (process cwd) |
| 14 | **Import** copies mold to **`./<name>/`**; fails if exists unless **`--force`** |
| 15 | **Cast** mold arg is a **filesystem path** to a mold directory |
| 16 | Hooks: Mason-style **`run(HookContext)`**, Dart-only, **`--no-hooks`** |
| 17 | Variable kinds v1: **string**, **boolean**, **int**, **double**, **object**, **single-choice**, **multiple-choice**, **values** |
| 18 | **pub.dev** packages **`foundry_core`** + **`foundry_cli`**; install CLI via **`dart install foundry_cli`** |
| 19 | Mold hooks depend on **`foundry_core`** (`import 'package:foundry_core/foundry_core.dart'`) |
| 20 | Platforms: **macOS, Linux, Windows** |
| 21 | No registry in v1 — **git + local import** only |
| 22 | Monorepo (**Melos**), CI/CD, and bootstrap: **[CONTRIBUTING.md](CONTRIBUTING.md)** |
| 23 | `foundry_cli` uses **`nocterm`** to render the interactive variable TUI |

---

## 13. Terminology quick reference

| Term | Role |
|------|------|
| Foundry | CLI tool (`foundry` binary; `foundry_cli` on pub.dev) |
| foundry_core | Core library and hook API on pub.dev |
| Mold | Liquid template + manifest |
| FoundryVariableGroup | Code-first variable schema loaded from `variables.dart` |
| Variables | Inputs gathered through the Nocterm TUI |
| Cast | Render mold → artifact at `--output` |
| Artifact | Generated output |
| Import | Copy mold from git or local path into `./<name>/` |
| Prepare / Shape / Finish | Hook phases |
| Inspect | Analyze a mold (`foundry mold inspect`) |
| Recast | Repeat last cast from `.foundry/last_cast.json` |
| Finish | Run finish hook on last cast output |
