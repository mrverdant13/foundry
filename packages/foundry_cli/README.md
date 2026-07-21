# foundry_cli

Command-line interface for **Foundry** — mold authoring, inspection, import,
and cast workflows.

> **Preview release.** Commands and flags may change before `1.0.0`.

## What it does

The `foundry` executable wraps the
[`foundry_core`](https://pub.dev/packages/foundry_core) library with commands
for the full mold lifecycle:

- **`foundry mold init`** — scaffold a new mold package in the current directory
- **`foundry mold inspect`** — validate mold layout, variables, and hooks
- **`foundry mold derive`** — generate a starter mold from a pattern directory
- **`foundry mold import`** — copy a mold from git or a local path
- **`foundry cast`** — gather variables, run hooks, and render templates to
  `--output`
- **`foundry recast`** — replay the last successful cast from
  `.foundry/last_cast.json`
- **`foundry finish`** — run only the finish hook against the last cast output

Molds are Dart packages with a root `pubspec.yaml`, `variables.dart`, a
`template/` tree, and optional lifecycle hooks. See the
[hook authoring guide](https://github.com/mrverdant13/foundry/blob/main/doc/hooks.md)
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

### Inspect

```bash
foundry mold inspect
```

### Cast

```bash
foundry cast . --output=../hello_out
```

Foundry gathers variables through an interactive TUI by default, renders
`template/` into `--output`, and writes `.foundry/last_cast.json` in the process
working directory on success.

Pass `--vars` and/or `--vars-file` to supply values in batch and skip the TUI:

```bash
foundry cast . --output=../hello_out --vars=project_name=Hello
foundry cast . --output=../hello_out --vars-file=./vars.json
```

Use `--force` to cast into a non-empty output directory. Use `--no-hooks` to
skip all hook phases.

### Recast and finish

```bash
foundry recast
foundry finish
```

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
foundry cast <mold-path> --output=<dir> [--force] [--no-hooks]
  [--vars=<k=v,…>] [--vars-file=<path>]
```

| Argument / option | Description |
| ----------------- | ----------- |
| `<mold-path>` | **Required.** Path to the mold directory |
| `--output` | **Required.** Destination directory for rendered artifacts |
| `--force` | Allow casting into a non-empty output directory |
| `--no-hooks` | Skip prepare, shape, and finish hooks |
| `--vars` | Comma-separated `key=value` pairs (skips the TUI) |
| `--vars-file` | Path to a JSON object of variable values (skips the TUI) |

#### `foundry recast`

```
foundry recast [--force] [--no-hooks]
```

Replays the last successful cast from `.foundry/last_cast.json`.

#### `foundry finish`

```
foundry finish [--no-hooks]
```

Runs only the finish hook against the last cast output without re-rendering
templates.

## Resources

- [Repository README](https://github.com/mrverdant13/foundry/blob/main/README.md) — product overview and full CLI guide
- [Hook authoring guide](https://github.com/mrverdant13/foundry/blob/main/doc/hooks.md)
- [Repository](https://github.com/mrverdant13/foundry/tree/main/packages/foundry_cli)
- [Issue tracker](https://github.com/mrverdant13/foundry/issues)
- [Changelog](CHANGELOG.md)
- [`foundry_core` library](https://pub.dev/packages/foundry_core) — embed Foundry in Dart tools

## License

MIT — see [LICENSE](LICENSE).
