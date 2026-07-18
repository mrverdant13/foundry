# Contributing

Thank you for helping build Foundry. This guide covers local development, testing
expectations, and collaboration conventions for this repository.

---

## Local development

### Prerequisites

- **Dart SDK** — stable channel (3.5+). [Install Dart](https://dart.dev/get-dart) or
  use Flutter's bundled SDK.
- **Ripple** — package discovery and script runner for this monorepo. Install
  globally (pinned git SHA):
  ```bash
  dart install 'ripple_cli@{git: {url: https://github.com/mrverdant13/ripple.git, ref: 74c8fe4c0e246c818071e1f83b207a0616c5f1d2}}'
  ```
- **Git**

### Clone and bootstrap

```bash
git clone https://github.com/mrverdant13/foundry.git
cd foundry
dart pub get
ripple exec --fail-fast -- dart pub get
```

Packages are isolated (no Dart workspace). Local path links for unpublished
sibling packages live in committed `pubspec_overrides.yaml` files. Named scripts
are defined in [`ripple.yaml`](ripple.yaml).

### Repository layout

```
foundry/
├── packages/
│   ├── foundry_core/       # Core library (mold parsing, cast pipeline)
│   │   └── e2e/            # End-to-end library tests
│   └── foundry_cli/        # Publishable CLI
│       └── e2e/            # End-to-end CLI tests
├── ripple.yaml             # Ripple package discovery and scripts
├── README.md               # User-facing overview
└── CONTRIBUTING.md         # This file
```

**Dependency direction** (do not invert):

```
bin/foundry.dart → CommandRunner → commands → foundry_core

mold hooks/hooks/pubspec.yaml → foundry_core (HookContext, HookException, Logger)
```

`foundry_cli` must not depend on monorepo-specific tooling packages. Mold hooks
(authored by users) depend on **`foundry_core`** — not `foundry_cli`.

### Running the CLI during development

From the repo root:

```bash
dart run packages/foundry_cli/bin/foundry.dart
```

Use `dart run` against the local package so local changes are exercised
without relying on a globally installed `foundry` binary from pub.dev.

### Common Ripple commands

```bash
ripple run format.ci      # Verify formatting (CI)
ripple run analyze.ci     # Analyze all packages (CI)
ripple run test.ci        # Unit tests + coverage
ripple run coverage.merge && ripple run coverage.check
ripple run test.e2e.ci    # E2E packages only
```

Additional scripts (`release.check`, `release.prepare`, and others) are defined
in [`ripple.yaml`](ripple.yaml). Scope package-filtered `exec:` steps with
`RIPPLE_PACKAGES=<package>`. `release.check` is an unscoped `run:` gate; for a
single package, run `format.ci` / `analyze.ci` repo-wide, then scope
`test.ci`, `pub-score.local`, and `dart pub publish --dry-run` with
`RIPPLE_PACKAGES=<package>`.

### CI secrets

The **Codecov** job in [`.github/workflows/ci.yaml`](.github/workflows/ci.yaml) is
commented out until a repository secret is configured. When enabled, it uploads
merged coverage from the Ubuntu test runner. Add a repository secret named
`CODECOV_TOKEN` with the upload token from your [Codecov project
settings](https://docs.codecov.com/docs/codecov-uploader#usage), then uncomment
the `codecov` job block in the workflow file.

---

## Testing expectations

All behavior changes should include or update tests.

| Layer | Location | Notes |
| --- | --- | --- |
| Unit tests | `packages/foundry_core/test/` | Mold parsing, variable resolution, rendering |
| Command tests | `packages/foundry_cli/test/` | Args parsing, exit codes, stderr formatting |
| E2E | `packages/foundry_core/e2e/` | Public API integration (cast pipeline) |
| E2E | `packages/foundry_cli/e2e/` | Full CLI invocations |

---

## Commit conventions

This repository uses [Conventional Commits](https://www.conventionalcommits.org/).

### Format

- Setup/infra work (no scope): `<type>: <description>`
- Scoped work (one area): `<type>(<scope>): <description>`
- Scoped work (multiple areas): `<type>(<scope>,<scope>): <description>`

Use a **single scope** when the change is confined to one package or area. Use
**multiple comma-separated scopes** (no spaces) when a PR or commit intentionally
spans more than one.

PR titles follow the same format as commit messages.

### Allowed types

| Type | Use for |
| --- | --- |
| `chore` | Setup, infrastructure, maintenance |
| `ci` | CI/CD workflow changes |
| `docs` | Documentation-only changes |
| `feat` | New user-facing functionality |
| `fix` | Bug fixes |
| `refactor` | Internal code changes without behavior changes |
| `test` | Test additions or updates |

### Scopes

Use scopes for changes tied to a specific package or area:

| Scope | Area |
| --- | --- |
| `foundry_core` | Core library (`packages/foundry_core`) |
| `foundry_cli` | CLI package (`packages/foundry_cli`) |

For cross-cutting setup or CI-only changes, omit the scope: `chore: …`, `ci: …`,
`docs: …`.

### Multiple scopes

When a change touches more than one scoped area, list every affected scope in
parentheses, separated by commas:

```
feat(foundry_cli,foundry_core): wire cast command through core pipeline
fix(foundry_core,foundry_cli): align exit codes for usage errors
```

Guidelines:

- Include only scopes that are **meaningfully changed**.
- Prefer **one scope** when one area owns the change.
- The **PR title** should use the same scoped format as the primary commit when
  the PR spans multiple areas.

### Examples

```
chore: scaffold ripple scripts and package skeletons
ci: add format and analyze workflow
feat(foundry_core): add mold manifest model and yaml loader
feat(foundry_cli): add command runner and version flag
fix(foundry_cli): resolve relative mold paths from cwd
test(foundry_core): add variable resolution unit tests
docs: add README and CONTRIBUTING
```

**Release PR titles:** `chore(foundry_core): release 0.0.1-dev.2`

---

## Dart package releases

Both publishable packages ship to [pub.dev](https://pub.dev) with per-package
changelogs. Each package exposes a compile-time version constant that must stay in
sync with its `pubspec.yaml`:

| Package | Manifest | Runtime constant |
| --- | --- | --- |
| `foundry_core` | `packages/foundry_core/pubspec.yaml` | `foundryCoreVersion` in `lib/src/version.dart` |
| `foundry_cli` | `packages/foundry_cli/pubspec.yaml` | `foundryCliVersion` in `lib/src/version.dart` |

**Release invariants:**

- **One package per release PR** — a `foundry_core` release touches only
  `packages/foundry_core/**`; a `foundry_cli` release touches only
  `packages/foundry_cli/**` (plus any `foundry_core:` constraint update in that
  package's `pubspec.yaml`).
- **Release order** — when both packages change, publish **`foundry_core` first**,
  then **`foundry_cli`**.

### Release workflow

1. **Prepare** — run the **Prepare Dart package release** workflow
   (`prepare-release.yaml`) for `foundry_core` or `foundry_cli`. It opens a PR
   titled `chore(<package>): release <version>` on branch
   `<package>/chore/release-<version>`.
2. **Verify** — the **Dart release PR check** workflow (`release-pr.yaml`) runs
   `ripple run release.check` when the PR title and branch match the release
   pattern.
3. **Tag** — merge the release PR. **Release tag on merge**
   (`release-tag.yaml`) creates an annotated git tag `<package>/<version>` on
   the merge commit (for example `foundry_core/0.0.1-dev.2`).
4. **Publish** — dispatch **Publish Dart package** (`publish.yaml`) on the tag
   ref with `dry_run: false`. Live publish requires the `pub-dev-publish`
   GitHub environment (OIDC to pub.dev). Use `dry_run: true` from `main` or a
   tag to run `release.check` without publishing.

**Tag format:** `<package>/<version>` — pub.dev automated publishing should use
the same pattern (for example `foundry_core/{{version}}`).

---

## Pull request guidelines

- Keep PRs **atomic and reviewable** — one logical change per PR.
- Align the **PR title** with the main commit intent, using the same
  [Conventional Commits](#commit-conventions) format.
- Include **tests** for any behavior changes (unit, command, or e2e as appropriate).
- Link related issues or milestone items when applicable.
- Do not commit secrets, `.env` files, or local editor state.

### Review checklist

- [ ] Behavior matches documented CLI and API contracts (or documents intentional deviation)
- [ ] Tests added or updated
- [ ] Formatting verified (`ripple run format.ci`)
- [ ] Analysis verified (`ripple run analyze.ci`)
- [ ] Tests verified (`ripple run test.ci`)
- [ ] No imports from monorepo-only tooling packages in `foundry_cli`
- [ ] Public API changes reflected in `README.md` or `doc/` when user-facing

---

## Documentation

| Artifact | Audience |
| --- | --- |
| [README.md](README.md) | Users — install, quick start, CLI reference |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Contributors — this guide |
| `packages/*/CHANGELOG.md` | Per-package release notes |

When adding user-facing behavior, update `README.md` and plan corresponding entries
in `doc/` or package changelogs.

---

## Questions

Open an issue for bugs, design questions, or parity gaps. For behavior changes,
update `README.md` and this guide in the same PR so user and contributor docs stay
in sync.
