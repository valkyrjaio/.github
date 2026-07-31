# Valkyrja GitHub Workflows

Reusable GitHub Actions workflows for all `valkyrjaio` repositories. Public
workflows (no leading underscore) are entry points triggered directly by GitHub
events. Reusable workflows (leading underscore `_`) are called internally via
`workflow_call`.

---

## Table of Contents

- [Secrets and Variables](#secrets-and-variables)
- [Release Process](#release-process)
- [Version Branches](#version-branches)
- [Workflow Reference Pinning](#workflow-reference-pinning)
- [Repository Enforcement](#repository-enforcement)
- [Rulesets](#rulesets)
- [Commit Message Rules](#commit-message-rules)
- [Trailing Newline Check](#trailing-newline-check)
- [Dependabot](#dependabot)
- [Dependency Updates](#dependency-updates)
- [Branch Utilities](#branch-utilities)
- [Cron Behavior](#cron-behavior)
- [Language Templates](#language-templates)
- [Workflow Index](#workflow-index)

---

## Secrets and Variables

### Secrets (org-level)

| Secret                       | Purpose                                                                 |
|------------------------------|-------------------------------------------------------------------------|
| `VALKYRJA_GHA_APP_ID`        | GitHub App ID used to generate short-lived tokens                       |
| `VALKYRJA_GHA_PRIVATE_KEY`   | Private key for the GitHub App                                          |
| `MAVEN_CENTRAL_USERNAME`     | Maven Central (Sonatype) user-token username — publishing Java releases |
| `MAVEN_CENTRAL_PASSWORD`     | Maven Central (Sonatype) user-token password — publishing Java releases |
| `MAVEN_SIGNING_KEY`          | In-memory PGP signing key for Java release artifacts                    |
| `MAVEN_SIGNING_KEY_PASSWORD` | Passphrase for the PGP signing key                                      |
| `PYPI_API_TOKEN`             | PyPI API token for Python releases (`uv publish`)                       |

All reusable workflows receive secrets via `secrets: inherit` from their
callers. `VALKYRJA_GHA_APP_ID` and `VALKYRJA_GHA_PRIVATE_KEY` must also be
registered as **Dependabot secrets** in org settings so Dependabot PRs can
access them.

The `MAVEN_*` and `PYPI_API_TOKEN` secrets are consumed only by the Java and
Python publish workflows respectively. TypeScript/npm releases use npm
[trusted publishing](https://docs.npmjs.com/trusted-publishers) (OIDC), so no
npm token secret is required.

### Variables (org-level)

| Variable               | Example                 | Purpose                                                                                                                                  |
|------------------------|-------------------------|------------------------------------------------------------------------------------------------------------------------------------------|
| `SUPPORTED_VERSIONS`   | `2[6-9]`                | Regex matching supported major versions (used in cherry-pick, ref updates, enforce)                                                      |
| `LATEST_MAJOR_VERSION` | `26`                    | Latest released major version number                                                                                                     |
| `SUPPORTED_LANGUAGES`  | `php java python ts go` | Space-separated language suffixes; selects the `project-template-<lang>` scaffold and `rulesets/<lang>/` rulesets on repo create/enforce |
| `USER_EMAIL`           | `bot@example.com`       | Git committer email for rebase, cherry-pick, and branch operations                                                                       |
| `USER_NAME`            | `Valkyrja Bot`          | Git committer name for rebase, cherry-pick, and branch operations                                                                        |
| `VALKYRJA_REVIEWER`    | `melechmizrachi`        | GitHub username assigned as reviewer on automated PRs                                                                                    |

---

## Release Process

Releases are triggered manually via **Actions → Create a New Release →
workflow_dispatch** with a `bump` input.

### Bump types

The version format is `YY.FEATURE.PATCH` — `YY` is the two-digit year and moves
only once a year, so the middle component carries both new features and breaking
changes. See
[VERSIONING.md](https://github.com/valkyrjaio/architecture/blob/master/VERSIONING.md).

| Bump      | Source branch | Tag format    | Notes                                        |
|-----------|---------------|---------------|----------------------------------------------|
| `auto`    | `??.x`        | either        | **Default.** Resolves from the commits merged since the last tag |
| `patch`   | `??.x`        | `v26.0.1`     | Increments patch from latest stable tag      |
| `feature` | `??.x`        | `v26.1.0`     | Increments the feature component, resets patch |
| `yearly`  | `??.x`        | `v26.0.0`     | Always `BRANCH_MAJOR.0.0`                    |
| `rc`      | `master` only | `v27.0.0-RC1` | Pre-release for next unreleased major        |

`yearly` and `rc` are **manual only** — a year boundary is a decision, not
something the commit log can express, and the scheduled sweep never dispatches to
`master`.

### How `auto` resolves

`_get-version-for-release` compares the last stable tag for the branch's major
against the branch head and reads the **subject** of each commit. Squash merges
take their subject from the PR title, so the subject is the conventional line.

| Found in the window                                | Result       |
|----------------------------------------------------|--------------|
| any `feat`, any `deprecate`, or any type with `!`  | `feature`    |
| any other type                                     | `patch`      |
| nothing, or only release-version roots             | no release   |

Release bookkeeping is recognised by its release-version root (`[v26.6.1]`), not
by its type — the release run's own commits ship inside the tag they describe, so
a quiet branch has an empty window and the run exits without releasing. When
that happens `should-release` is `false` and every downstream job is skipped;
the workflow still reports success.

If the compare API returns fewer commits than it reports in total, `auto` rounds
**up** to `feature`. Under-bumping would ship a `feat` as a patch, which is worse
than the reverse.

### Scheduled auto releases

`auto-release-supported-versions.yml` runs daily and dispatches each repo's own
`release-new-version.yml` with `bump: auto` on every `??.x` branch whose major matches
`SUPPORTED_VERSIONS`. Supports `dry_run` and a single-`repo` target on manual
dispatch.

It **never dispatches to `master`.** The sibling cross-repo sweeps fall back to
`master` when a repo has no version branch; this one skips the repo instead, because a
release must never be cut from `master` — that is where the next year is prepared, and
`rc` is the only release type that comes from there. Keeping `master` out of reach here
is what makes the RC path unreachable from automation by construction rather than by a
conditional.

A dispatched run still decides for itself whether to release: `auto` exits without
releasing when nothing is pending, so quiet branches cost a workflow run and produce
nothing.

Two mechanical constraints shape it: scheduled workflows only run from the default
branch (the current-year `??.x` for these repos, not `master`), and a
`workflow_dispatch` triggered with `GITHUB_TOKEN` does not create a run — so the sweep
authenticates as the GitHub App.

### Stable release flow (`auto` / `patch` / `feature` / `yearly`)

1. `_get-version-for-release` — validates branch is a `??.x` version branch,
   computes next version from existing tags.
2. `_update-version-files` — updates `VERSION.md` on the version branch with a
   bot commit.
3. `_release` — generates release notes, updates `CHANGELOG.md` with a bot
   commit, creates the GitHub release.

### Release candidate flow (`rc`)

**Rules:**

- Must be triggered from `master`.
- Always targets the **next unreleased major** (highest existing version branch
  major + 1). If the highest branch is `26.x`, the RC is for `v27.0.0`.
- That target must be in `SUPPORTED_VERSIONS` **and** its `??.x` branch must not
  exist yet. Both are checked before anything is published, and an unset
  `SUPPORTED_VERSIONS` aborts rather than skipping the gate — the standard
  validation step returns early for RC-shaped versions, so this is the only place
  an RC's year is checked. Widen `SUPPORTED_VERSIONS` before opening a new year.
- RC number is **auto-incremented** by scanning existing pre-release tags
  (`v27.0.0-RC1` → `v27.0.0-RC2`).
- An RC is **never promoted to stable**. When the major version is ready, a
  `yearly` bump from the newly created version branch produces the stable
  release.

**RC flow:**

1. `_get-version-for-release` — validates branch is `master`, resolves next
   major from version branches, increments RC number.
2. `_update-version-files` — updates `VERSION.md` on master so the repo
   reflects the RC version.
3. `_release` — generates release notes (diff since last tag, useful for
   tracking changes between RCs), updates `CHANGELOG.md`, creates a **GitHub
   pre-release** (`prerelease: true`, `make_latest: false`).

Publishing an RC does **not** trigger `update-github-workflow-refs` — only
stable releases propagate the ref pin across repos.

### Version validation

`_get-version-for-release` enforces:

- Branch must be `master` for `rc`; must be `??.x` for all other bump types.
- Computed version must match expected semver structure for the bump type
  (`yearly` → `X.0.0`, `feature` → `X.Y.0`). `auto` is exempt because it has
  already resolved to `feature` or `patch` by then.
- Tag must not already exist.
- For stable releases, major version must match `SUPPORTED_VERSIONS`.

### Per-language releases

The flow above (`_create-release` → `_get-version-for-release` →
`_update-version-files` → `_release`) drives the `.github` repo itself. Consumer
language repos instead call `_{php,java,python,ts}-create-release.yml`, which
wraps the same core steps with a pre-release outdated-dependency gate
(`_check-outdated-<lang>-dependencies`) and a version/build-date bump in the
language's info file (`_update-<lang>-info-files`). These orchestrators end at
`_release.yml` (which creates the GitHub release and tag).

**Publishing** is a separate concern. The publish workflows below are standalone
`workflow_call` building blocks — they are **not** invoked by the create-release
orchestrators. Each language repo wires the appropriate one into its own release
workflow (typically triggered on release publish):

| Language   | Publish workflow                          | Credentials                              |
|------------|-------------------------------------------|------------------------------------------|
| PHP        | — (released via tag; no publish workflow) | none                                     |
| Java       | `_java-release-maven-publish.yml`         | `MAVEN_CENTRAL_*`, `MAVEN_SIGNING_KEY*`  |
| Python     | `_python-release-pypi-publish.yml`        | `PYPI_API_TOKEN`                         |
| TypeScript | `_ts-release-npm-publish.yml`             | npm trusted publishing (OIDC), no secret |

---

## Version Branches

Version branches follow the pattern `??.x` (e.g., `26.x`, `27.x`). All stable
releases (`auto`, `patch`, `feature`, `yearly`) must be triggered from a version
branch.

The **default branch** of the `.github` repo is always the current active
version branch. Crons run on the default branch, so they automatically use the
latest workflow code as version branches advance.

---

## Workflow Reference Pinning

Reusable workflows in consumer repos reference `valkyrjaio/.github` by **commit
SHA** (not by tag or branch) for security and reproducibility.

### `update-github-workflow-refs.yml`

Public entry point that delegates to the reusable `_update-workflow-refs.yml`
with `source-repo: .github`. (`_update-workflow-refs.yml` takes a `source-repo`
input so the same logic can repin refs sourced from any repo, e.g. a shared
`ci-*` repo.)

Triggers:

- On every **stable** release published in `.github` (skips pre-releases).
- Weekly cron (`0 10 * * 1` — Monday 10:00 UTC).
- Manual `workflow_dispatch`.

Behavior:

- Iterates all non-archived repos in the org (excluding `.github` itself).
- For each repo: targets all supported `??.x` branches (filtered by
  `SUPPORTED_VERSIONS`). Falls back to `master` only if no supported version
  branches exist in that repo.
- **`master` is intentionally skipped when version branches exist.** Master
  should be kept in sync via rebase or cherry-pick from the version branch —
  not via a direct dependency PR.
- Scans every workflow file for `valkyrjaio/.github/.github/workflows/*@<sha>`.
- Updates the SHA to the latest stable release's commit SHA.
- Creates a PR per base branch (`deps/update-github-workflow-refs-26.x` for
  version branches, `deps/update-github-workflow-refs` for master fallback).
- If branch creation or file update is blocked by a ruleset, logs a clean
  message and continues — treats protection as expected, not a failure.
- If a PR already exists for that branch, skips PR creation (does not force
  push).

### Updating refs manually

Run **Actions → Update .github Workflow References → workflow_dispatch** at any
time to force a refresh across all repos.

---

## Repository Enforcement

### `enforce-repo-settings.yml`

Triggers:

- Weekly cron (`0 9 * * 1` — Monday 09:00 UTC).
- Manual `workflow_dispatch`.

Behavior (via `_enforce-repo-settings.yml`):

- Applies standard repository settings to all non-archived org repos:
    - Squash merge only (`PR_TITLE` + `PR_BODY`).
    - Auto-delete head branches on merge.
    - No wikis, no projects.
    - Vulnerability alerts + automated security fixes enabled.
    - Immutable releases enabled.
- Applies **all rulesets** from `rulesets/*.json` to every repo.
- Applies **language rulesets** from `rulesets/<lang>/*.json` (`php`, `java`,
  `python`, `ts`, `go`) to repos whose name suffix matches a
  `SUPPORTED_LANGUAGES` entry.
- Compares each ruleset's normalized JSON against the live ruleset before
  updating — no-ops if already in sync.

### Adding a new ruleset

Drop a `.json` file into `rulesets/` (org-wide) or `rulesets/<lang>/`
(language-specific). The enforce cron and create-repo workflow pick it up
automatically — no workflow changes needed.

The JSON structure follows the GitHub Rulesets REST API response format. The
`id` field is used to match existing rulesets for updates.

---

## Rulesets

Stored in `rulesets/` (org-wide) and `rulesets/<lang>/` (language-specific) and
auto-applied by enforce and create-repo.

| File                                                      | Scope        | Purpose                                                                              |
|-----------------------------------------------------------|--------------|--------------------------------------------------------------------------------------|
| `rulesets/Protect Against Force Pushes and Deletion.json` | All repos    | Prevents force pushes and deletion on version branches (`??.x`)                      |
| `rulesets/Protect Master At All Times.json`               | All repos    | Prevents force pushes and deletion on `master`                                       |
| `rulesets/Protect Release Tags.json`                      | All repos    | Prevents deletion or non-fast-forward of `*.*.*` tags                                |
| `rulesets/Require Pull Request.json`                      | All repos    | Requires squash-merge PRs with code-owner review on `master`/`??.x`                  |
| `rulesets/Required Default PR Checks.json`                | All repos    | Requires `Commit Message Check` and `Trailing Newline Check` to pass                 |
| `rulesets/Restrict Changes to Unsupported Branches.json`  | All repos    | Locks backup branches (`*-backup`) against all changes                               |
| `rulesets/php/Required PHP PR Checks.json`                | PHP repos    | Requires PHP CS Fixer, PHPCS, PHPArkitect, PHPStan, PHPUnit (8.4–8.6), Psalm, Rector |
| `rulesets/java/Required Java PR Checks.json`              | Java repos   | Requires Spotless, ArchUnit, Error Prone, SpotBugs, JUnit                            |
| `rulesets/python/Required Python PR Checks.json`          | Python repos | Requires Ruff, mypy, import-linter, Bandit, pytest                                   |
| `rulesets/ts/Required TypeScript PR Checks.json`          | TS repos     | Requires ESLint, TypeScript (`tsc`), Vitest, Prettier                                |
| `rulesets/go/Required Go PR Checks.json`                  | Go repos     | Requires golangci-lint, go test                                                      |

### Bypass actors

All rulesets allow bypass for:

- `OrganizationAdmin` (always)
- Integration ID `2462900` (the Valkyrja GitHub App — always)

---

## Commit Message Rules

### Format

```
[Root] type: Short description.
```

A **root** in brackets says what the change is about; a **type** says what kind of
change it is. `!` before the colon marks a breaking change, and `(#123)` carries an
issue reference. Full reference:
[COMMIT_CONVENTION.md](https://github.com/valkyrjaio/architecture/blob/master/COMMIT_CONVENTION.md).

- Must start with `[` and a root in brackets, followed by a type and a colon.
- **Working-branch commits end with a period.** PR titles and direct pushes to a
  protected branch do not — those are permanent subject lines, not sentences.
- No line may exceed 120 characters.
- Enforced by the `Commit Message Check / Check Commit Message` required check.

The check inspects commits *in a pull request*, which are working-branch commits, and
never sees a direct push to a protected branch — which is why the release run's own
commits carry no period.

Only the shape is machine-checked. The root vocabulary is open by design, so no
pattern can validate it: `[http]` passes. Root choice and casing are review's job.

### Exemptions

- **Dependabot** PRs (actor `dependabot[bot]`) skip the type and period checks. The
  job still runs and reports success so it satisfies the required status check.
- **Reverts.** GitHub's revert button generates `Revert "<original title>"`, which
  cannot match the pattern, and a revert is usually being made under time pressure —
  the check must not stand in the way.

---

## Trailing Newline Check

The commit-message and trailing-newline checks run as jobs of `ci.yml` on every
pull request targeting `master` or `*.x` (see `ci.yml` → `_commit-message-check`
/ `_trailing-newline-check`). Separately, the `fix-trailing-newlines.yml` cron
proactively repairs missing newlines across all repos via PRs.

Behavior (via `_trailing-newline-check.yml`):

- Always checks all tracked files in the repository (`git ls-files`).
- Skips binary files (detected via `file --mime-encoding`).
- Skips empty files.
- Fails if any file's last byte is not a newline (`\n`), listing every offending
  file by path.
- Posts a PR comment on failure listing all offending files, and removes it when
  the check subsequently passes.

### Adding to a consumer repo

Wire the checks into the repo's `ci.yml` by calling the reusable
implementations (this is what the language templates ship):

```yaml
jobs:
    trailing-newline-check:
        if: github.event_name == 'pull_request'
        uses: valkyrjaio/.github/.github/workflows/_trailing-newline-check.yml@<sha>
        permissions:
            pull-requests: write
            contents: read
        secrets: inherit
```

---

## Dependabot

Dependabot PRs require access to `VALKYRJA_GHA_APP_ID` and
`VALKYRJA_GHA_PRIVATE_KEY`. These must be registered as **Dependabot secrets**
in org settings (separate from Actions secrets).

Commit message format check is skipped for Dependabot (see above). All other
checks run normally.

---

## Dependency Updates

### `update-php-dependencies.yml`

Trigger: `workflow_dispatch`.

Org-level fan-out entry point. Delegates to
`_php-update-dependencies-across-repos.yml`, which iterates every non-archived
`*-php` repo and triggers that repo's own `update-dependencies` workflow across
its supported `??.x` branches (per `SUPPORTED_VERSIONS`).

### Per-repo dependency updates

Each language repo ships an `update-dependencies` workflow (from its template)
that calls the reusable `_update-<lang>-dependencies.yml`
(`php`/`java`/`python`/`ts`). For PHP, that reusable workflow runs the
`composer` commands defined in the repo's `.github/update-dependencies.yml` —
each entry specifying a `name`, `command` (full composer subcommand string
including any flags), and optional `directory` — then opens one PR per update
group. Each language paired with a `_check-outdated-<lang>-dependencies.yml`
gate that runs before a release proceeds.

To pass extra flags (e.g., ignore a platform requirement), embed them directly
in the `command` string:

```yaml
-   name: Root
    command: "update --ignore-platform-req=ext-openswoole"
    directory: "."
```

---

## Branch Utilities

### `cherry-pick-commits.yml`

Manually cherry-picks a commit hash to a destination branch. Valid destination
branches must match `^2([6-9]).x$` (supported version branches only).

### `rebase-to-master.yml` / `rebase-from-master.yml`

Rebase the current version branch **to** master (rebases `master` onto the
version branch) or **from** master (rebases the version branch onto `master`).
Run from the target version branch. Only the latest major version branch may
be rebased to master. Both workflows back up the affected branch before
force-pushing.

### `restore-branch-from-backup.yml`

Restores the current branch by force-pushing its `<branch>-backup` counterpart
onto it. Used to recover after a bad rebase or merge.

---

## Cron Behavior

Cron workflows run on the **default branch** of the repository where the
workflow is defined. For the `.github` repo, the default branch is always the
current active version branch (e.g., `26.x`). This means crons always use the
most up-to-date workflow code as versions advance — no manual updates needed
when cutting a new version branch.

---

## Language Templates

New repos are scaffolded from a `valkyrjaio/project-template-<lang>` GitHub
template repository, chosen automatically from the repo name's language suffix
(the part after the last `-`) when it matches a `SUPPORTED_LANGUAGES` entry
(`php`, `java`, `python`, `ts`, `go`). The `project-template-*` repos are
themselves created bare, without referencing a template.

Each template provides the standard CI directory structure (`.github/ci/`),
pre-configured lint/static-analysis/test workflow files, baseline tool configs,
and the required entry-point workflows (`ci.yml`, `create-version-branch.yml`,
`release-new-version.yml`, `update-dependencies.yml`) from
[`required-workflows/<lang>/`](../../required-workflows). For example, the PHP
template wires PHP CS Fixer, PHPCS, PHPArkitect, PHPStan, PHPUnit, Psalm, and
Rector with their `phpunit.xml`, `phpcs.xml`, `phpstan.neon`, `psalm.xml`,
`rector.php`, `.php-cs-fixer.php`, and `.phparkitect.php` configs.

---

## Workflow Index

Public workflows (no leading underscore) are triggered by GitHub events;
reusable workflows (leading `_`) are `workflow_call` only.

### Entry points (public)

| File                                 | Trigger                               | Description                                                             |
|--------------------------------------|---------------------------------------|-------------------------------------------------------------------------|
| `ci.yml`                             | `push` / `pull_request`               | Umbrella CI. On PRs runs the commit-message and trailing-newline checks |
| `release-new-version.yml`            | `workflow_dispatch`                   | Create a new release (patch/minor/major/rc), then repin workflow refs   |
| `create-version-branch.yml`          | `workflow_dispatch`                   | Create a new major release version branch from `master`                 |
| `create-repo.yml`                    | `workflow_dispatch`                   | Create and configure a new org repository                               |
| `enforce-repo-settings.yml`          | cron (Mon 09:00) + dispatch           | Enforce settings and rulesets across all repos                          |
| `ensure-workflows.yml`               | cron (Mon 12:00) + dispatch           | Ensure required workflow files exist across all repos                   |
| `ensure-reusable-workflow-names.yml` | cron (Mon 13:00) + dispatch           | Verify reusable workflow names/filenames follow convention              |
| `fix-trailing-newlines.yml`          | cron (Mon 11:00) + dispatch           | Add missing trailing newlines across all repos via PRs                  |
| `update-github-workflow-refs.yml`    | release + cron (Mon 10:00) + dispatch | Pin workflow refs to latest `.github` release SHA                       |
| `update-php-dependencies.yml`        | `workflow_dispatch`                   | Fan out PHP dependency updates across all PHP repos                     |
| `cherry-pick-commits.yml`            | `workflow_dispatch`                   | Cherry-pick a commit to a target branch                                 |
| `rebase-to-master.yml`               | `workflow_dispatch`                   | Rebase `master` onto the current (latest major) version branch          |
| `rebase-from-master.yml`             | `workflow_dispatch`                   | Rebase the current branch onto `master`                                 |
| `restore-branch-from-backup.yml`     | `workflow_dispatch`                   | Restore a branch from its `<branch>-backup` counterpart                 |

### Release & version (reusable)

| File                                              | Description                                                                                                   |
|---------------------------------------------------|---------------------------------------------------------------------------------------------------------------|
| `_create-release.yml`                             | Orchestrate stable/RC release (version → update files → release)                                              |
| `_release.yml`                                    | Core release logic (notes, changelog, tag)                                                                    |
| `_get-version-for-release.yml`                    | Compute and validate the next release version                                                                 |
| `_get-version.yml`                                | Compute next major version number and branch name                                                             |
| `_update-version-files.yml`                       | Commit updated `VERSION.md`                                                                                   |
| `_create-version-branch.yml`                      | Orchestrate a new version branch (`_get-version` → `_version-branch`)                                         |
| `_version-branch.yml`                             | Create branch, rewrite `README`/`CHANGELOG`/`VERSION`, set default, bump `LATEST_MAJOR_VERSION`               |
| `_{php,java,python,ts}-create-release.yml`        | Per-language release orchestrators (outdated check → version → info files → release). Publishing is separate. |
| `_java-release-maven-publish.yml`                 | Publish Java artifacts to Maven Central (`MAVEN_*` secrets)                                                   |
| `_python-release-pypi-publish.yml`                | Publish Python package to PyPI (`PYPI_API_TOKEN`)                                                             |
| `_ts-release-npm-publish.yml`                     | Publish TypeScript package to npm (trusted publishing, no token)                                              |
| `_{php,java,python,ts}-update-info-files.yml`     | Update `VERSION`/`BUILD_DATE` constants in a language's info file                                             |
| `_{php,java,python,ts}-create-version-branch.yml` | Per-language new-version-branch orchestrators (run check-outdated first)                                      |
| `_{python,ts}-version-branch.yml`                 | Python/TS branch-creation logic (PHP/Java reuse `_version-branch.yml`)                                        |

### Language CI checks (reusable)

| File                          | Description                                      |
|-------------------------------|--------------------------------------------------|
| `_commit-message-check.yml`   | Commit message format check (skips Dependabot)   |
| `_trailing-newline-check.yml` | Trailing newline check; posts/removes PR comment |
| `_java-spotless.yml`          | Java formatting (Spotless)                       |
| `_java-errorprone.yml`        | Java static analysis (Error Prone)               |
| `_java-spotbugs.yml`          | Java static analysis (SpotBugs)                  |
| `_java-archunit.yml`          | Java architecture tests (ArchUnit)               |
| `_java-junit.yml`             | Java tests (JUnit)                               |
| `_python-ruff.yml`            | Python lint/format (Ruff)                        |
| `_python-mypy.yml`            | Python type checking (mypy)                      |
| `_python-bandit.yml`          | Python security scan (Bandit)                    |
| `_python-import-linter.yml`   | Python import contracts (import-linter)          |
| `_python-pytest.yml`          | Python tests (pytest)                            |
| `_ts-eslint.yml`              | TypeScript lint (ESLint)                         |
| `_ts-prettier.yml`            | TypeScript formatting (Prettier)                 |
| `_ts-typescript.yml`          | TypeScript type checking (`tsc`)                 |
| `_ts-vitest.yml`              | TypeScript tests (Vitest)                        |
| `_go-golangci-lint.yml`       | Go lint (golangci-lint)                          |
| `_go-test.yml`                | Go tests (`go test`)                             |

### Dependency management (reusable)

| File                                                    | Description                                                  |
|---------------------------------------------------------|--------------------------------------------------------------|
| `_{php,java,python,ts}-check-outdated-dependencies.yml` | Verify all direct dependencies are up to date before release |
| `_{php,java,python,ts}-update-dependencies.yml`         | Run the dependency updater and open/refresh a PR             |
| `_php-update-dependencies-across-repos.yml`             | Trigger `update-dependencies` across all PHP repos           |

### Repository & workflow management (reusable)

| File                                  | Description                                                     |
|---------------------------------------|-----------------------------------------------------------------|
| `_create-repo.yml`                    | Create and configure a new org repository with rulesets         |
| `_enforce-repo-settings.yml`          | Apply settings and rulesets to a repo                           |
| `_ensure-workflows.yml`               | Ensure required workflow files across repos (opens PRs)         |
| `_ensure-reusable-workflow-names.yml` | Verify reusable workflow `name:`/filename conventions           |
| `_fix-trailing-newlines.yml`          | Add missing trailing newlines across repos (opens PRs)          |
| `_update-workflow-refs.yml`           | Update workflow SHA pins across all repos (`source-repo` input) |

### Branch utilities (reusable)

| File                              | Description                                                        |
|-----------------------------------|--------------------------------------------------------------------|
| `_cherry-pick-commits.yml`        | Cherry-pick logic with branch validation                           |
| `_rebase-to-master.yml`           | Rebase `master` onto the current branch (with backup + validation) |
| `_rebase-from-master.yml`         | Rebase the current branch onto `master` (with backup)              |
| `_restore-branch-from-backup.yml` | Restore branch logic using its backup counterpart                  |
