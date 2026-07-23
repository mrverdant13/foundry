# Pattern annotations and `.foundry/pattern.yaml`

Authors can keep a **runnable pattern** (a real project tree) and annotate it so
`foundry mold derive` and `foundry mold sync` produce a parametrized Liquid
`template/` under the mold. Transforms run automatically during derive/sync —
there is no separate validate or preview command.

Binary files (detected by a NUL byte) are copied into `template/` unchanged and
do not go through content transforms. The `.foundry/` directory is always
excluded from `template/`. Ignore globs from the pattern marker still apply.

## Transform order

Content resolution is fixed:

1. Line deletions (`lineDeletions` in `.foundry/pattern.yaml`)
2. Content replacements (`replacements` in `.foundry/pattern.yaml`)
3. Remotions (`drop` / `remove-start`…`remove-end`)
4. Replace blocks (`replace-start` / `with` / `replace-end`)
5. Insert blocks (`insert-start` / `insert-end`)
6. Liquid tag unwrap (comment-wrapped `{{…}}` / `{%…%}`)
7. Spacing groups (`w … w`)
8. Partials (`partial v` / `partial ^`)

Path renames use the same `replacements` list outside this pipeline (see
[Path replacements](#path-replacements)).

Between steps 1 and 2, Foundry runs a **liquidize pre-pass**: accidental source
`{{` / `{%` openers are escaped so they render as literals at cast time, while
later steps can still inject live Liquid. Source liquid-tag annotations are
parked before that pre-pass so their braces stay live; tags introduced by
earlier annotation steps are unwrapped in step 6, then parked tags are restored.

## Comment flavors

In-file markers use one of three comment styles. Keywords are the same across
flavors; only the wrappers change:

| Flavor | Marker wrapper | Line body prefix (replace / insert) |
| ------ | -------------- | ----------------------------------- |
| C-style | `/*…*/` | `// ` |
| Hash | `#…#` | `# ` |
| HTML | `<!--…-->` | `<!-- …-->` |

Pick the flavor that fits the host file (Dart/JS → C-style, YAML/shell → hash,
HTML/XML → HTML). Do not mix flavors inside a single paired block.

---

## `.foundry/pattern.yaml`

Optional marker at `.foundry/pattern.yaml`. A directory is a valid pattern
without this file. `foundry pattern init` scaffolds a starter marker with
`name` and `ignore` only.

```yaml
name: demo_pattern
ignore:
  - .dart_tool/**
  - .git/**
  - build/**
replacements:
  - from: ref_pkg
    to: '{{ package_name }}'
  - from:
      pattern: 'Foo(.*)'
      caseSensitive: true
    to: 'Bar${1}'
lineDeletions:
  - filePath: lib/main.dart
    ranges:
      - start: 10
        end: 20
```

| Field | Type | Role |
| ----- | ---- | ---- |
| `name` | string | Human-readable pattern name (inspect / reports) |
| `ignore` | list of globs | Paths excluded from inspect summaries and from derive/sync into `template/` (`**/` prefixes also match at the pattern root) |
| `replacements` | list | Regex replacements for **paths and contents** during derive/sync (not applied by inspect) |
| `lineDeletions` | list | Inclusive zero-based line ranges to drop from specific files during derive/sync (not applied by inspect) |

Invalid shapes produce structured parse errors (`PatternIssue`).

### `replacements`

Each entry has:

| Key | Required | Description |
| --- | -------- | ----------- |
| `from` | yes | Non-empty regex string, **or** a map with `pattern` plus optional flags |
| `to` | yes | Replacement string; may include `${n}` capture-group references |

Regex object flags (all optional booleans; defaults match Dart `RegExp`):

- `pattern` (required when `from` is a map)
- `dotAll`
- `multiLine`
- `unicode`
- `caseSensitive`

Replacements run **in declaration order**. Each step sees the output of the
previous one. Capture references use `${n}` (not `$n`); missing groups become
an empty string.

Injected Liquid such as `to: "{{ package_name }}"` stays live after derive/sync.
Accidental braces already present in the pattern source are escaped by the
liquidize pre-pass so they remain literal text at cast time.

### Path replacements

The same `replacements` list is applied to each pattern-root-relative path when
writing into `template/`. Absolute resolved paths and any path that would escape
the mold `template/` directory are rejected.

### `lineDeletions`

Each entry has:

| Key | Required | Description |
| --- | -------- | ----------- |
| `filePath` | yes | Path relative to the pattern root (POSIX comparison) |
| `ranges` | yes | List of `{ start, end }` inclusive zero-based line indices (`start <= end`) |

Entries whose `filePath` does not match the file being resolved are no-ops.
Line numbers past the end of the file are ignored. When any matching range
applies, kept lines are rejoined with `\n` and a trailing newline (`writeln`
semantics). If every line is dropped, the result is an empty string.

---

## Remotions

### `drop`

Removes from the marker through end of file:

```dart
keepThis();
/*drop*/
goneForever();
```

Hash: `#drop#` · HTML: `<!--drop-->`

### `remove-start` … `remove-end`

Removes the markers and everything between them. Optional whitespace flags:

- `x-` before `remove-start` drops leading adjacent whitespace
- `-x` after `remove-end` drops trailing adjacent whitespace

```dart
keep /*x-remove-start*/ discard /*remove-end-x*/ this;
```

Hash: `#x-remove-start#` … `#remove-end-x#` · HTML: `<!--x-remove-start-->` …
`<!--remove-end-x-->`

Paired remove blocks are applied before `drop` so a nested `drop` cannot delete
past `remove-end`.

---

## Replace blocks

Discard scaffold text between `replace-start` and `with`, then emit the
comment-prefixed lines between `with` and `replace-end`.

Optional `iN` on the `with` marker indents each replacement line by N spaces
(`/*with i2*/`, `#with i2#`, `<!--with i2-->`). Omitting `iN` adds no extra
spaces.

Every replacement line must use the flavor’s line body prefix (`// `, `# `, or
`<!-- …-->`). Invalid lines fail derive/sync with a clear error. An empty body
(`with` immediately followed by `replace-end`) discards the scaffold and emits
nothing.

```dart
void demo() {
/*replace-start*/
  final name = 'ref_pkg';
/*with i2*/
// final name = '{{ package_name }}';
/*replace-end*/
}
```

After resolve, the scaffold is gone and the template contains the indented
Liquid line.

---

## Insert blocks

Like replace blocks, but there is no discarded scaffold region — only the lines
between `insert-start` and `insert-end` matter. Each line must be
comment-prefixed for the matched flavor. Leading/trailing whitespace on each
line is trimmed before the prefix is matched.

```yaml
#insert-start#
# name: {{ package_name }}
#insert-end#
```

An empty body removes the markers and emits nothing.

---

## Liquid tags in comments

Unwrap `{{…}}` and `{%…%}` from comment wrappers so they become live Liquid in
`template/`.

Optional `x` flags drop adjacent whitespace on that side:

- `x` before the tag (e.g. `/*x{{ name }}*/`) drops leading whitespace
- `x` after the tag (e.g. `#{{ name }}x#`) drops trailing whitespace

```dart
final id = /*{{ package_name }}*/;
```

Hash: `#{{ package_name }}#` · HTML: `<!--{{ package_name }}-->`

---

## Spacing groups

The marker letter `w` stands for whitespace. Actions are space-separated:

| Action | Meaning |
| ------ | ------- |
| `Nv` | Emit N newline characters (`2v` → two newlines) |
| `N>` | Emit N space characters (`4>` → four spaces) |

Contiguous whitespace on either side of the marker is always discarded; only
the spacing produced by the actions survives. An empty action list
(`/*w w*/`, `#w w#`, `<!--w w-->`, including the tight hash form `#ww#`)
removes the marker and merges the surrounding text.

```text
before/*w 2v 4> w*/after
```

---

## Partials

Extract a reusable fragment into `name.partial` under the mold `template/` root
and leave a Liquid render tag at the marker site:

```dart
/*partial v header*/
// shared header lines…
/*partial ^ header*/
```

Resolves to:

```liquid
{% render 'header.partial' %}
```

and writes `template/header.partial` with the block payload.

Hash: `#partial v name#` … `#partial ^ name#` · HTML: `<!--partial v name-->` …
`<!--partial ^ name-->`

Rules:

- Opening and closing names must match.
- Names must be non-empty, must not be `.` / `..`, and must not contain path
  separators or filename-invalid characters.
- Partial names share one namespace under `template/`. Writing the same name
  with identical content is allowed; a different payload for an existing name
  fails.
- At cast time, `{% render %}` resolves via a filesystem root at `template/`.
  Files ending in `.partial` are not written as cast outputs.
- Bare `{% render 'name.partial' %}` tags receive the cast variable context in
  Liquid’s render scope. Tags that already pass explicit arguments are unchanged.

---

## End-to-end sketch

1. Annotate a runnable pattern (comment markers and/or `.foundry/pattern.yaml`).
2. `foundry mold derive --pattern=./my_pattern --output=./my_mold` (or
   `foundry mold sync --pattern=./my_pattern` inside an existing mold).
3. Expand `variables.dart` so keys used in injected Liquid exist.
4. `foundry cast ./my_mold --output=./artifact --vars=…` (or the interactive
   TUI) to render the parametrized `template/`.

See the root [README](../README.md) for command flags and the
[`foundry_core`](https://pub.dev/packages/foundry_core) API for programmatic
derive/sync.
