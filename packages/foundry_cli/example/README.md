# foundry_cli example

Minimal mold that exercises the `foundry` CLI (`mold inspect` and `cast`).

## Layout

```
example/
├── mold/
│   ├── pubspec.yaml
│   ├── variables.dart
│   └── template/
│       └── README.md
└── output/                 # created by `foundry cast` (gitignored)
```

## Prerequisites

Install the CLI globally:

```bash
dart install foundry_cli
```

Ensure `~/.pub-cache/bin` is on your `PATH`, then verify:

```bash
foundry --version
```

When developing this repository locally, run the CLI with `dart run` from
`packages/foundry_cli` instead of a global install.

## Inspect the mold

From this directory:

```bash
foundry mold inspect mold
```

Local development:

```bash
dart run ../bin/foundry.dart mold inspect mold
```

Exits with code `0` when the mold loads and passes inspection.

## Cast the mold

Interactive cast (prompts for `project_name`):

```bash
foundry cast mold --output=output --force --no-hooks
```

Local development:

```bash
dart run ../bin/foundry.dart cast mold --output=output --force --no-hooks
```

After a successful cast, `output/README.md` contains the rendered project name
and `.foundry/last_cast.json` is written in the process working directory.
