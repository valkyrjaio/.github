# Contributing to Valkyrja

Anybody who uses Valkyrja can be a contributing member of the community that
develops and releases it; the task of releasing Valkyrja, documentation and
associated websites is a never-ending one. With every release or release
candidate comes a wave of work, which takes a lot of organization and
coordination.

You don't need any special access to download, build, debug and begin submitting
code, tests or documentation.

Thank you for your interest in helping us develop, maintain, and release the
Valkyrja framework!

## Project References

These documents govern how Valkyrja is organized and described:

- [`VOCABULARY.md`](./VOCABULARY.md) — canonical definitions of Valkyrja
  terms (app, module, component, tool, etc.) used throughout the project.
- [`REPOSITORY_NAMING.md`](./REPOSITORY_NAMING.md) — naming conventions for
  repos in the Valkyrjaio GitHub organization.

Contributors should skim both before their first PR.

## Submitting Code Changes

If you have a feature, bug fix, documentation update, or any other type of code
change you want to contribute, please ensure the following before submitting a
PR:

1. By submitting a PR you grant the project the right to include and distribute
   your written code under the MIT license.
2. Check that a PR doesn't already exist covering your change.
3. Include tests. PRs without tests will be ignored or flagged for follow-up.
4. All CI checks must pass. See [Running CI Locally](#running-ci-locally) below.
5. Prefer small PRs with atomic, descriptive commits — they're much easier to
   review.
6. Follow the [commit and PR title format](#commit-and-pr-titles).
7. Fill out the PR template completely. See
   [Writing Your PR Description](#writing-your-pr-description) below.
8. Use Valkyrja vocabulary consistently — see
   [`VOCABULARY.md`](./VOCABULARY.md).

### Running CI Locally

Valkyrja is implemented across multiple languages, each with their own toolchain
and checks. Run the checks for the language(s) your PR touches before pushing.

Each language drives its CI tools through a per-language task runner — PHP
`composer`, Java Gradle (`./gradlew`), TypeScript `npm`, Go `make`, and Python
`poe` (Poe the Poet). Check that runner's config for the exact target names
(`composer.json`, `build.gradle.kts`, `package.json`, `Makefile`,
`pyproject.toml`). Whichever language(s) your PR touches, the full gate must pass
with 100% line and branch coverage before you push.

#### PHP

Each check has a composer script:

| Check              | Command                     |
|--------------------|-----------------------------|
| PHPArkitect        | `composer phparkitect`      |
| PHP Code Sniffer   | `composer phpcodesniffer`   |
| PHP CS Fixer       | `composer phpcsfixer`       |
| PHPStan            | `composer phpstan`          |
| PHPUnit            | `composer phpunit`          |
| PHPUnit (coverage) | `composer phpunit-coverage` |
| Psalm              | `composer psalm`            |
| Rector             | `composer rector`           |

Use `composer phpunit-coverage` instead of `composer phpunit` to verify you
aren't reducing overall code coverage.

If your PR changes a composer file, also validate it:

- Root `composer.json` — `composer validate --strict`
- Other composer files — `composer validate --no-check-publish`

#### Java

Each check is a Gradle task; `./gradlew ci` runs the full gate:

| Check              | Command                   |
|--------------------|---------------------------|
| Spotless (format)  | `./gradlew spotlessCheck` |
| ArchUnit           | `./gradlew archunit`      |
| Error Prone        | `./gradlew errorprone`    |
| SpotBugs           | `./gradlew spotbugs`      |
| JUnit (+ coverage) | `./gradlew junit`         |
| Full gate          | `./gradlew ci`            |

`./gradlew spotlessApply` auto-formats. JUnit runs with JaCoCo — keep line and
branch coverage at 100%.

#### Python

Each check is a Poe task (`poe`); `poe ci` runs the full gate:

| Check             | Command                 |
|-------------------|-------------------------|
| Ruff (format)     | `poe ruff-format-check` |
| Ruff (lint)       | `poe ruff`              |
| mypy              | `poe mypy`              |
| import-linter     | `poe import-linter`     |
| Bandit            | `poe bandit`            |
| pytest            | `poe pytest`            |
| pytest (coverage) | `poe pytest-coverage`   |
| Full gate         | `poe ci`                |

`poe ruff-format` and `poe ruff-fix` auto-fix. `poe pytest-coverage` enforces 100%
line and branch coverage (`--cov-branch --cov-fail-under=100`).

#### Go

Each check is a Makefile target; `make ci` runs the full gate:

| Check            | Command           |
|------------------|-------------------|
| Formatting       | `make fmt-check`  |
| golangci-lint    | `make lint`       |
| Tests (race)     | `make test`       |
| Tests (coverage) | `make coverage`   |
| Module tidiness  | `make tidy-check` |
| Full gate        | `make ci`         |

`make fmt` auto-formats and `make tidy` tidies `go.mod`/`go.sum`.

#### TypeScript

Each check has an npm script; the `-check` variants fail without modifying files:

| Check             | Command                   |
|-------------------|---------------------------|
| TypeScript (tsc)  | `npm run typescript`      |
| ESLint            | `npm run eslint-check`    |
| Prettier          | `npm run prettier-check`  |
| Vitest            | `npm run vitest`          |
| Vitest (coverage) | `npm run vitest-coverage` |

`npm run eslint` and `npm run prettier` auto-fix. Use `npm run vitest-coverage` to
verify you aren't reducing coverage (100% line and branch).

### Commit and PR Titles

Every subject line carries a **root** saying what the change is about and a
**type** saying what kind of change it is:

```
[Root] type: Message.
[Root] type(#123): Message for an issue.
[Root] type!: Message for a breaking change.
[Root] type(#123)!: Message for a breaking change with an issue.
```

|                                       | Ends with | Issue reference          |
|---------------------------------------|-----------|--------------------------|
| **Working-branch commit**             | a period  | permitted, not required  |
| **PR title**                          | no period | required when one exists |
| **Direct push to a protected branch** | no period | —                        |

A working-branch commit is a ledger entry — a sentence recording what that commit
did — so it takes a period. Anything that becomes a permanent subject line is a
title instead, and takes none: we squash-merge, so the PR title becomes the commit
subject and the PR description becomes its body.

**Types:**

| Type        | Use for                                                     |
|-------------|-------------------------------------------------------------|
| `feat`      | A new capability or an addition to the public API           |
| `fix`       | Corrects behavior that was broken                           |
| `deprecate` | Marks API as deprecated without removing it yet             |
| `docs`      | Documentation only                                          |
| `test`      | Adds or changes tests only                                  |
| `refactor`  | Internal restructuring with no behavior change              |
| `perf`      | Performance improvement with no behavior change             |
| `style`     | Formatting only — whitespace, import order, no behavior     |
| `build`     | Build scripts, dependency manifests, packaging              |
| `ci`        | CI workflows, tooling configuration, automated runs         |
| `chore`     | Routine maintenance that fits nothing else                  |
| `revert`    | Reverts an earlier change                                   |

`!` before the colon is **required** on any change that breaks a public contract.
`feat`, `deprecate`, and `!` drive the middle version component; everything else is
a patch. See [VERSIONING.md][versioning url].

**Roots** are an open vocabulary, not a fixed list. A root may be anything that
describes the thing being worked on, subject to two rules:

1. **A root names a thing** — never a kind of change, and never whatever performed
   the change. Git already records the author.
2. **A root is never the repo's own identity** — `[PhpCsFixer]` says nothing inside
   the phpcsfixer repo and everything inside a framework repo.

Common roots: a module (`[Http]`, `[Cli]`, `[Container]`), a concept spanning
modules (`[Middleware]`, `[Routing]`, `[Provider]`), `[Dependency]`, an external
tool (`[Composer]`, `[npm]`, `[PhpCsFixer]`), a port (`[PHP]`, `[Java]`), a project
surface (`[Git]`, `[Workflow]`, `[GitHub]`, `[Process]`), a version line (`[26.x]`),
or a release version (`[v26.6.1]`). Module roots take their source directory's
spelling — `[Orm]`, not `[ORM]`.

Prefer **one root**. A change that looks like it spans modules is usually about
something they share: middleware across HTTP and CLI is `[Middleware]`, not
`[Http][Cli]`. Breadth is never a root — renaming every component throwable is
`[Throwable]`. If no single root fits, the change is doing too much.

**Good examples:**

- `[Container] feat(#123): Add support for contextual bindings`
- `[Http] fix: Fix header normalization on HTTP/2 requests`
- `[Http] feat(#88)!: Remove the deprecated request attribute accessors`
- `[Middleware] refactor: Rename terminal stages to ResponseSent and ProcessExiting`
- `[Cli] test: Cover the bare double dash operand case`
- `[Workflow] ci: Update .github workflow refs to v26.12.1`
- `[Process] docs: Document the new RC release process`
- `[26.x] fix: Backport the routing regression fix`

**Bad examples:**

- `fix bug` — no root, no type, no detail
- `[http] fix: stuff` — lowercase root, vague message
- `Add caching.` — missing root and type
- `[Container] Add contextual bindings` — missing type
- `[Documentation] docs: Fix a typo` — retired root, and it restates the type
- `[All] refactor: Rename the providers.` — breadth is not a root; use `[Provider]`
- `[Http/Cli] fix: Align the stages.` — never slash roots; find the shared one
- `[Http] fix(#123): Fix normalization.` — trailing period on a PR title
- `[Http] fix: Fix normalization` — missing period on a commit

Full reference, including the retired roots and the locked forms automation emits:
[COMMIT_CONVENTION.md][commit convention url].

### Writing Your PR Description

The PR template has three sections you fill out: **Description**, **Types of
changes**, and **Changes**. Each serves a distinct purpose.

#### Description

A prose summary of what the PR does and why. Aim to answer:

- What do you want to achieve with this PR?
- Why did you write this code?
- What problem does this PR solve?

Include relevant context — design choices you made and why, tradeoffs you
considered, alternatives you rejected. If an issue tracks the work, put
`Closes #123` here: the description becomes the squash commit's body, so this is
both what closes the issue on merge and where the link durably lives.

Because the description becomes that body, it is also where any explanation that
would otherwise go in a code comment about a temporary condition belongs — a
version pinned pending a release, a workaround awaiting a fix. Automation rewrites
values but not the prose around them, so such a comment outlives what it described;
in the description it stays reachable from `git log` and `git blame` forever.

#### Types of changes

Check every box that applies to the PR. Most PRs check one box, but it's common
for a single PR to span multiple categories — for example, a bug fix that also
improves adjacent code, or a new feature that updates documentation alongside
the implementation.

#### Changes

A bulleted list of the concrete changes in the PR — one bullet per file or per
logical change. This gives reviewers a scannable map of what was touched and
why, and serves as a useful reference for anyone reading the PR months later.

**Format:**

- Bold the file path or component affected
- Follow with an em dash (`—`) and a concise description of what changed
- If one file has multiple distinct changes, break them into sub-bullets

**Good examples:**

- **`_release.yml`** — added release-type detection step; sets
  `prerelease: true` and `make_latest: false` when version contains `-RC`
- **`_update-github-workflow-refs.yml`**
    - Split `jq | gh api PUT` into discrete steps to eliminate pipefail
      ambiguity
    - Changed `2>&1` to `2>/dev/null` on `gh pr create` so the `if !` handler
      fires correctly
- **`README.md`** — updated workflow behavior description to document the
  intentional `master` skip and the rationale

The Changes section is optional for small single-file PRs where the description
already covers everything. For any PR touching multiple files or making several
discrete changes, fill it in.

### Branches for Code Changes

| Branch   | Purpose                                                                                            |
|----------|----------------------------------------------------------------------------------------------------|
| `master` | Active development branch, open for backwards incompatible changes and major internal API changes. |
| `??.x`   | Version maintenance branches. Open for bug fixes only.                                             |

### Which Branch to Target

Choosing the right base branch depends on the type of change:

| Change type     | Target branch                                                                         |
|-----------------|---------------------------------------------------------------------------------------|
| Improvement     | Lowest major affected `??.x` branch                                                   |
| Bug fix         | Lowest major affected `??.x` branch                                                   |
| New feature     | `master`                                                                              |
| Deprecation     | `master`                                                                              |
| Breaking change | `master` — unless it's a bug fix, in which case please open an issue to discuss first |
| Documentation   | Lowest major affected branch the docs apply to                                        |

If you're unsure which branch to target, open an issue first or target `master`
and a maintainer will redirect the PR if needed.

## Getting Help

If you need help contributing code, open an [issue][issues url] with a title
like `[Help] Title for what you need help with`.

[issues url]: https://github.com/valkyrjaio/valkyrja/issues
[commit convention url]: https://github.com/valkyrjaio/architecture/blob/master/COMMIT_CONVENTION.md
[versioning url]: https://github.com/valkyrjaio/architecture/blob/master/VERSIONING.md
