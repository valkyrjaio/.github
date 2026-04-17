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
- [Dependabot](#dependabot)
- [Dependency Updates](#dependency-updates)
- [Branch Utilities](#branch-utilities)
- [Cron Behavior](#cron-behavior)
- [PHP Template](#php-template)

---

## Secrets and Variables

### Secrets (org-level, also added as Dependabot secrets)

| Secret                    | Purpose                                              |
|---------------------------|------------------------------------------------------|
| `VALKYRJA_GHA_APP_ID`     | GitHub App ID used to generate short-lived tokens   |
| `VALKYRJA_GHA_PRIVATE_KEY`| Private key for the GitHub App                      |

All reusable workflows receive secrets via `secrets: inherit` from their
callers. Both secrets must also be registered as **Dependabot secrets** in org
settings so Dependabot PRs can access them.

### Variables (org-level)

| Variable               | Example          | Purpose                                                         |
|------------------------|------------------|-----------------------------------------------------------------|
| `SUPPORTED_VERSIONS`   | `2[6-9]`         | Regex matching supported major versions (used in cherry-pick, ref updates, enforce) |
| `LATEST_MAJOR_VERSION` | `26`             | Latest released major version number                           |
| `VALKYRJA_REVIEWER`    | `melechmizrachi` | GitHub username assigned as reviewer on automated PRs          |

---

## Release Process

Releases are triggered manually via **Actions → Create a New Release →
workflow_dispatch** with a `bump` input.

### Bump types

| Bump    | Source branch       | Tag format          | Notes                                      |
|---------|---------------------|---------------------|--------------------------------------------|
| `patch` | `??.x`              | `v26.0.1`           | Increments patch from latest stable tag   |
| `minor` | `??.x`              | `v26.1.0`           | Increments minor, resets patch            |
| `major` | `??.x`              | `v26.0.0`           | Always `BRANCH_MAJOR.0.0`                 |
| `rc`    | `master` only       | `v27.0.0-RC1`       | Pre-release for next unreleased major     |

### Stable release flow (`patch` / `minor` / `major`)

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
- RC number is **auto-incremented** by scanning existing pre-release tags
  (`v27.0.0-RC1` → `v27.0.0-RC2`).
- An RC is **never promoted to stable**. When the major version is ready, a
  `major` bump from the newly created version branch produces the stable
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
  (`major` → `X.0.0`, `minor` → `X.Y.0`).
- Tag must not already exist.
- For stable releases, major version must match `SUPPORTED_VERSIONS`.

---

## Version Branches

Version branches follow the pattern `??.x` (e.g., `26.x`, `27.x`). All stable
releases (`patch`, `minor`, `major`) must be triggered from a version branch.

The **default branch** of the `.github` repo is always the current active
version branch. Crons run on the default branch, so they automatically use the
latest workflow code as version branches advance.

---

## Workflow Reference Pinning

Reusable workflows in consumer repos reference `valkyrjaio/.github` by **commit
SHA** (not by tag or branch) for security and reproducibility.

### `update-github-workflow-refs.yml`

Triggers:
- On every **stable** release published in `.github` (skips pre-releases).
- Weekly cron (`0 10 * * 1` — Monday 10:00 UTC).
- Manual `workflow_dispatch`.

Behavior:
- Iterates all non-archived repos in the org (excluding `.github` itself).
- For each repo: checks `master` and all supported `??.x` branches (filtered
  by `SUPPORTED_VERSIONS`).
- Scans every workflow file for `valkyrjaio/.github/.github/workflows/*@<sha>`.
- Updates the SHA to the latest stable release's commit SHA.
- Creates a PR per base branch (`deps/update-github-workflow-refs` for master,
  `deps/update-github-workflow-refs-26.x` for version branches).
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
- Daily cron (`0 9 * * *` — 09:00 UTC).
- Manual `workflow_dispatch`.

Behavior (via `_enforce-repo-settings.yml`):
- Applies standard repository settings to all non-archived org repos:
  - Squash merge only (`PR_TITLE` + `PR_BODY`).
  - Auto-delete head branches on merge.
  - No wikis, no projects.
  - Vulnerability alerts + automated security fixes enabled.
  - Immutable releases enabled.
- Applies **all rulesets** from `rulesets/*.json` to every repo.
- Applies **PHP rulesets** from `rulesets/php/*.json` to repos whose name or
  description contains `php`.
- Compares each ruleset's normalized JSON against the live ruleset before
  updating — no-ops if already in sync.

### Adding a new ruleset

Drop a `.json` file into `rulesets/` (org-wide) or `rulesets/php/` (PHP repos
only). The enforce cron and create-repo workflow pick it up automatically — no
workflow changes needed.

The JSON structure follows the GitHub Rulesets REST API response format. The
`id` field is used to match existing rulesets for updates.

---

## Rulesets

Stored in `rulesets/` and `rulesets/php/` and auto-applied by enforce and
create-repo.

| File                                        | Scope     | Purpose                                              |
|---------------------------------------------|-----------|------------------------------------------------------|
| `rulesets/Protect Release Tags.json`        | All repos | Prevents deletion or non-fast-forward of `*.*.*` tags |
| `rulesets/Required Commit Message Checks.json` | All repos | Requires `Commit Message Check / Check Commit Message` to pass |
| `rulesets/php/Required Checks.json`         | PHP repos | Requires PHP CS Fixer, PHPCS, PHPArkitect, PHPStan, PHPUnit (8.4–8.6), Psalm, Rector |

### Bypass actors

All rulesets allow bypass for:
- `OrganizationAdmin` (always)
- Integration ID `2462900` (the Valkyrja GitHub App — always)

---

## Commit Message Rules

### Format

```
[Type] Short description.
```

- Must start with `[` and a category in brackets.
- Must end with a period.
- Types are enforced by the `Commit Message Check / Check Commit Message`
  required check.

### Dependabot exemption

Dependabot PRs (actor `dependabot[bot]`) automatically skip both the type and
period checks. The job still runs and reports success so it satisfies the
required status check.

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

Triggers: weekly cron + `workflow_dispatch`.

Runs `composer` commands defined in `update-dependencies.yml` in each repo's
`.github/` directory. Each entry specifies a `name`, `command` (full composer
subcommand string including any flags), and optional `directory`. Creates one PR
per update group. Uses `SUPPORTED_VERSIONS` to determine which version branches
to update.

To pass extra flags (e.g., ignore a platform requirement), embed them directly
in the `command` string:
```yaml
- name: Root
  command: "update --ignore-platform-req=ext-openswoole"
  directory: "."
```

---

## Branch Utilities

### `cherry-pick-commits.yml`

Manually cherry-picks a commit hash to a destination branch. Valid destination
branches must match `^2([6-9]).x$` (supported version branches only).

### `rebase-branch.yml` / `restore-branch.yml`

Rebase or restore a branch. Typically used to keep version branches in sync
with master or to recover after a bad merge.

---

## Cron Behavior

Cron workflows run on the **default branch** of the repository where the
workflow is defined. For the `.github` repo, the default branch is always the
current active version branch (e.g., `26.x`). This means crons always use the
most up-to-date workflow code as versions advance — no manual updates needed
when cutting a new version branch.

---

## PHP Template

New PHP repos are created using `valkyrjaio/php-template` as a GitHub template
repository. This applies automatically when the repo name or description
contains `php`. The template provides:

- Standard CI directory structure (`.github/ci/`)
- Pre-configured workflow files for PHP CS Fixer, PHPCS, PHPArkitect, PHPStan,
  PHPUnit, Psalm, Rector, and Dependabot dependency updates.
- `phpunit.xml`, `phpcs.xml`, `phpstan.neon`, `psalm.xml`, `rector.php`,
  `.php-cs-fixer.php`, `.phparkitect.php` baseline configs.

---

## Workflow Index

| File                                    | Trigger              | Description                                          |
|-----------------------------------------|----------------------|------------------------------------------------------|
| `release-new-version.yml`               | `workflow_dispatch`  | Create a new release (patch/minor/major/rc)          |
| `enforce-repo-settings.yml`             | cron + dispatch      | Enforce settings and rulesets across all repos       |
| `update-github-workflow-refs.yml`       | release + cron + dispatch | Pin workflow refs to latest `.github` release SHA |
| `update-php-dependencies.yml`           | cron + dispatch      | Update PHP Composer dependencies via PRs             |
| `cherry-pick-commits.yml`               | `workflow_dispatch`  | Cherry-pick a commit to a target branch              |
| `rebase-branch.yml`                     | `workflow_dispatch`  | Rebase a branch                                      |
| `restore-branch.yml`                    | `workflow_dispatch`  | Restore a branch                                     |
| `commit-message-check.yml`              | pull_request         | Validate commit message format                       |
| `_release.yml`                          | `workflow_call`      | Core release logic (notes, changelog, tag)           |
| `_get-version-for-release.yml`          | `workflow_call`      | Compute and validate the next release version        |
| `_update-version-files.yml`             | `workflow_call`      | Commit updated `VERSION.md`                          |
| `_enforce-repo-settings.yml`            | `workflow_call`      | Apply settings and rulesets to a repo                |
| `_update-github-workflow-refs.yml`      | `workflow_call`      | Update workflow SHA pins across all repos            |
| `_update-php-dependencies.yml`          | `workflow_call`      | Run composer update and open PR                      |
| `_commit-message-check.yml`             | `workflow_call`      | Commit message format check logic                    |
| `_cherry-pick-commits.yml`              | `workflow_call`      | Cherry-pick logic with branch validation             |
| `_rebase-branch.yml`                    | `workflow_call`      | Rebase logic                                         |
| `_restore-branch.yml`                   | `workflow_call`      | Restore logic                                        |