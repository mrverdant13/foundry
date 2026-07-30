# foundry_cli

Command-line interface for **Foundry** — mold authoring, inspection, import,
and cast workflows.

> **Preview release.** Commands and flags may change before `1.0.0`.

## What it does

The `foundry` executable wraps the
[`foundry_core`](https://pub.dev/packages/foundry_core) library with commands
for the full mold lifecycle:

- **`foundry mold init`** — scaffold a new mold package in the current directory
- **`foundry mold inspect`** — validate mold layout and report live variable
  metadata from a describe session
- **`foundry mold derive`** — generate a starter mold from a pattern directory
  (resolves pattern annotations and `.foundry/pattern.yaml` `replacements` /
  `lineDeletions`)
- **`foundry mold sync`** — refresh an existing mold `template/` from a pattern
  (same annotation rules as derive)
- **`foundry mold import`** — copy a mold from git or a local path
- **`foundry cast`** — run a mold cast session (live `variables.dart`, in-process
  hooks, template render) to `--output`
- **`foundry recast`** — replay the last successful cast from the encodable
  projection in `.foundry/last_cast.json`
- **`foundry finish`** — run only the finish hook against the last cast output

Molds are Dart packages with a root `pubspec.yaml`, `variables.dart`, a
`template/` tree, and optional lifecycle hooks. See the
[hook authoring guide](https://github.com/mrverdant13/foundry/blob/main/doc/hooks.md),
[pattern annotations](https://github.com/mrverdant13/foundry/blob/main/doc/annotations.md),
and the [mold pubspec schema](https://github.com/mrverdant13/foundry/blob/main/doc/mold-pubspec.schema.json).

## Installation

Install the CLI globally with [`dart install`](https://dart.dev/tools/dart-install):

```bash
dart install foundry_cli
```

The global binary is **`foundry`** (`executables: foundry:`), even though the
pub.dev package is **`foundry_cli`**.

```bash
foundry --version
```

Requires Dart SDK `>=3.5.0 <4.0.0`.

## Quick start

### Scaffold a mold

```bash
foundry mold init --name=hello_mold
cd hello_mold
```

### Derive a mold from a pattern

```bash
foundry mold derive --pattern=../demo_pattern --output=./hello_mold
```

### Sync a mold template from a pattern

```bash
cd hello_mold
foundry mold sync --pattern=../demo_pattern
```

### Inspect

```bash
foundry mold inspect
```

### Cast

```bash
foundry cast . --output=../hello_out
```

Cast runs inside a **mold cast session**: a short-lived helper that imports the
mold's live `variables.dart` and runs prepare → gather → shape → render → finish
in one process with in-process hooks (no JSON round-trip between phases). See the
[hook authoring guide](https://github.com/mrverdant13/foundry/blob/main/doc/hooks.md).

By default Foundry gathers variables through an interactive TUI inside that
session, renders `template/` into `--output`, and on success writes
`.foundry/last_cast.json` in the process working directory. That file stores an
**encodable projection** of resolved values only (JSON primitives, lists, and
string-keyed maps) — non-encodable prepare seeds from the cast are not persisted.

Pass `--vars` and/or `--vars-file` to supply values in batch and skip the TUI:

```bash
foundry cast . --output=../hello_out --vars=project_name=Hello
foundry cast . --output=../hello_out --vars-file=./vars.json
```

Object fields accept dotted `--vars` paths (for example
`publish.host=api.example.com,publish.port=443`) or a nested JSON object in
`--vars-file`. Prefer `--vars-file` for deep nests. A whole-object `--vars`
flag assignment such as `publish={…}` cannot be combined with `publish.*`
dotted children; a `--vars-file` object value at that path can deep-merge with
dotted `--vars` overrides.

Use `--force` to cast into a non-empty output directory. Use
`--skip-hooks=<phase>` (repeatable: `prepare`, `shape`, `finish`) to skip
individual hook phases.

### Recast and finish

```bash
foundry recast
foundry finish
```

`recast` and `finish` also launch a mold cast session. `recast` re-runs the full
pipeline from the encodable `vars` in `.foundry/last_cast.json` (JSON-safe values
only). `finish` runs only the finish hook against the stored output without
re-rendering templates.

See the [`example/`](example/) directory for a bundled mold you can inspect and
cast with `dart run`.

## CLI reference

### Invocation

```
foundry [--version] <command> [arguments] [options]
```

### Global flags

| Flag | Description |
| ---- | ----------- |
| `--version` | Print the CLI version and exit |

### Exit codes

| Code | Meaning |
| ---- | ------- |
| `0` | Success |
| `1` | User-facing error (invalid input, mold load failure, hook abort, etc.) |
| `2` | Unexpected internal error |

### Commands

| Command | Description |
| ------- | ----------- |
| `foundry mold init` | Scaffold a new mold in the current directory |
| `foundry mold derive` | Derive a starter mold from a pattern directory |
| `foundry mold sync` | Sync an existing mold template from a pattern directory |
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
| ------ | ----------- |
| `--name` | Mold package name (defaults to the current directory basename) |

#### `foundry mold derive`

```
foundry mold derive --pattern=<path> [--output=<dir>] [--force]
```

| Option | Description |
| ------ | ----------- |
| `--pattern` | **Required.** Pattern directory to derive from |
| `--output` | Destination for the derived mold (defaults to the current directory; requires `--force` when omitted, since cwd already exists) |
| `--force` | Overwrite the destination directory if it already exists |

Resolves pattern annotations and `.foundry/pattern.yaml` `replacements` /
`lineDeletions` into the mold `template/` (see
[pattern annotations](https://github.com/mrverdant13/foundry/blob/main/doc/annotations.md)).

#### `foundry mold sync`

```
foundry mold sync --pattern=<path> [--force]
```

| Option | Description |
| ------ | ----------- |
| `--pattern` | **Required.** Pattern directory to sync from |
| `--force` | Replace `template/` wholesale (remove orphans); author edits outside `template/` are still preserved |

Syncs the mold in the current directory. Refreshes `template/` from the pattern
(same annotation / `replacements` / `lineDeletions` rules as derive) while
preserving root `pubspec.yaml`, `variables.dart`, `hooks/`, and other
non-`template/` files.

#### `foundry mold import git`

```
foundry mold import git --git-url=<url> [--path=<relative/path>] [--force]
```

| Option | Description |
| ------ | ----------- |
| `--git-url` | **Required.** Git repository URL to shallow-clone |
| `--path` | Relative path to the mold within the repository |
| `--force` | Overwrite the destination directory if it already exists |

#### `foundry mold import local`

```
foundry mold import local --path=<dir> [--force]
```

| Option | Description |
| ------ | ----------- |
| `--path` | **Required.** Local directory containing the mold |
| `--force` | Overwrite the destination directory if it already exists |

#### `foundry mold inspect`

```
foundry mold inspect [<path>]
```

| Argument | Description |
| -------- | ----------- |
| `<path>` | Mold directory (defaults to the current directory) |

#### `foundry cast`

```
foundry cast <mold-path> --output=<dir> [--force] [--skip-hooks=<phase>]
  [--vars=<k=v,…>] [--vars-file=<path>]
```

Runs a mold cast session (live `variables.dart` + in-process hooks). On success,
writes `.foundry/last_cast.json` with an encodable `vars` projection only.

| Argument / option | Description |
| ----------------- | ----------- |
| `<mold-path>` | **Required.** Path to the mold directory |
| `--output` | **Required.** Destination directory for rendered artifacts |
| `--force` | Allow casting into a non-empty output directory |
| `--skip-hooks` | Skip a lifecycle phase (`prepare`, `shape`, or `finish`); repeatable |
| `--vars` | Comma-separated `key=value` pairs (skips the TUI) |
| `--vars-file` | Path to a JSON object of variable values (skips the TUI) |

#### `foundry recast`

```
foundry recast [--force] [--skip-hooks=<phase>]
```

Replays the last successful cast via a mold cast session seeded from
`.foundry/last_cast.json`. Stored `vars` are an encodable projection only.

| Option | Description |
| ------ | ----------- |
| `--force` | Allow casting into a non-empty output directory |
| `--skip-hooks` | Skip a lifecycle phase (`prepare`, `shape`, or `finish`); repeatable |

#### `foundry finish`

```
foundry finish [--skip-hooks=<phase>]
```

Runs a finish-only mold cast session for the last cast (requires
`hooks/finish.dart` unless finish is skipped and not required by policy). Seeds
context from the encodable `vars` projection in `.foundry/last_cast.json`
without re-rendering templates.

| Option | Description |
| ------ | ----------- |
| `--skip-hooks` | Skip a lifecycle phase (`prepare`, `shape`, or `finish`); repeatable |

## Resources

- [Repository README](https://github.com/mrverdant13/foundry/blob/main/README.md) — product overview and full CLI guide
- [Hook authoring guide](https://github.com/mrverdant13/foundry/blob/main/doc/hooks.md)
- [Pattern annotations and `.foundry/pattern.yaml`](https://github.com/mrverdant13/foundry/blob/main/doc/annotations.md)
- [Repository](https://github.com/mrverdant13/foundry/tree/main/packages/foundry_cli)
- [Issue tracker](https://github.com/mrverdant13/foundry/issues)
- [Changelog](CHANGELOG.md)
- [`foundry_core` library](https://pub.dev/packages/foundry_core) — embed Foundry in Dart tools

## License

MIT — see [LICENSE](LICENSE).
