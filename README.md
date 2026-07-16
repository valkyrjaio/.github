<p align="center"><a href="https://valkyrja.io" target="_blank">
    <img src="https://raw.githubusercontent.com/valkyrjaio/art/refs/heads/master/long-banner/orange/default.png" width="100%">
</a></p>

# Valkyrja `.github`

The [special `.github` repository][github-special-repo] for the
[Valkyrjaio][org-page] GitHub organization. Files placed here apply as
defaults across all repositories in the organization — community health
files, reusable workflows, branch rulesets, and the organization profile
page.

This repository is the center of Valkyrja's org-wide automation. The
reusable workflows here power CI, releases, dependency updates, branch
management, and repository provisioning across every Valkyrja repo.

What's Included
---------------

- **Community health files** — `CODE_OF_CONDUCT.md`, `CONTRIBUTING.md`,
  `LICENSE.md`, and `SECURITY.md` inherited by every repo that doesn't
  override them
- **Organization profile** — the `profile/README.md` that renders on the
  [Valkyrjaio organization page][org-page]
- **Reusable workflows** — PR quality gates, dependency management,
  repository management, release orchestration, and branch management
- **Branch rulesets** — exported GitHub ruleset definitions applied across
  Valkyrja repos via the repo-management workflows
- **Project conventions** — `REPOSITORY_NAMING.md` and `VOCABULARY.md`
  documenting how repos are named and what terms mean across the project

Community Health Files
----------------------

| File                                       | Description                                                |
|--------------------------------------------|------------------------------------------------------------|
| [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md) | Expected standards of behavior for community members       |
| [`CONTRIBUTING.md`](CONTRIBUTING.md)       | Guidelines for contributing code, tests, and documentation |
| [`SECURITY.md`](SECURITY.md)               | Security vulnerability disclosure procedure                |
| [`LICENSE.md`](LICENSE.md)                 | MIT license                                                |

Project Conventions
-------------------

| Document                                       | Description                                                     |
|------------------------------------------------|-----------------------------------------------------------------|
| [`REPOSITORY_NAMING.md`](REPOSITORY_NAMING.md) | Naming conventions for all repos in the Valkyrjaio organization |
| [`VOCABULARY.md`](VOCABULARY.md)               | Canonical definitions of Valkyrja terms used across the project |

Workflows
---------

Reusable workflows shared across all Valkyrja repositories. Workflows
prefixed with `_` are called by other workflows rather than triggered
directly.

### PR Quality Gates

The public [`ci.yml`](.github/workflows/ci.yml) is the CI entry point
(`push`/`pull_request` on `master` and `*.x`). On pull requests it calls the
reusable commit-message and trailing-newline checks below. Consumer repos wire
their own `ci.yml` to the language check workflows in the next table.

| Workflow                                                                       | Trigger               | Description                                                                                                                                     |
|--------------------------------------------------------------------------------|-----------------------|-------------------------------------------------------------------------------------------------------------------------------------------------|
| [`ci.yml`](.github/workflows/ci.yml)                                           | `push`/`pull_request` | Umbrella CI workflow. On PRs runs the commit-message and trailing-newline checks.                                                               |
| [`_commit-message-check.yml`](.github/workflows/_commit-message-check.yml)     | `workflow_call`       | Validates that every commit message on a PR meets the project conventions; posts/removes a PR comment on failure/success. Skips Dependabot PRs. |
| [`_trailing-newline-check.yml`](.github/workflows/_trailing-newline-check.yml) | `workflow_call`       | Checks all tracked files in the repo, skips binary and empty files; posts/removes a PR comment listing offending files on failure/success       |

### Language CI Checks

Reusable lint, static-analysis, and test workflows (all `workflow_call`)
consumed by each language repo's `ci.yml`. PHP quality checks live in dedicated
`ci-*-php` repositories rather than here.

| Language   | Workflows                                                                                                                                                                                                                                                                                                                                                                              |
|------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Java       | [`_spotless-java.yml`](.github/workflows/_spotless-java.yml) (format), [`_errorprone-java.yml`](.github/workflows/_errorprone-java.yml), [`_spotbugs-java.yml`](.github/workflows/_spotbugs-java.yml), [`_archunit-java.yml`](.github/workflows/_archunit-java.yml) (architecture), [`_junit-java.yml`](.github/workflows/_junit-java.yml) (tests)                                     |
| Python     | [`_ruff-python.yml`](.github/workflows/_ruff-python.yml) (lint/format), [`_mypy-python.yml`](.github/workflows/_mypy-python.yml) (types), [`_bandit-python.yml`](.github/workflows/_bandit-python.yml) (security), [`_import-linter-python.yml`](.github/workflows/_import-linter-python.yml) (import contracts), [`_pytest-python.yml`](.github/workflows/_pytest-python.yml) (tests) |
| TypeScript | [`_eslint-ts.yml`](.github/workflows/_eslint-ts.yml) (lint), [`_prettier-ts.yml`](.github/workflows/_prettier-ts.yml) (format), [`_typescript-ts.yml`](.github/workflows/_typescript-ts.yml) (`tsc` types), [`_vitest-ts.yml`](.github/workflows/_vitest-ts.yml) (tests)                                                                                                               |
| Go         | [`_golangci-lint-go.yml`](.github/workflows/_golangci-lint-go.yml) (lint), [`_test-go.yml`](.github/workflows/_test-go.yml) (tests)                                                                                                                                                                                                                                                    |

### Dependency Management

Each language has a paired "check outdated" gate (run before a release) and an
"update dependencies" workflow that opens a PR. All are `workflow_call`, except
the public [
`update-php-dependencies.yml`](.github/workflows/update-php-dependencies.yml)
dispatch entry point.

| Workflow                                                                                                   | Description                                                                                                                                                                                                                                                                                                                                                                                                                                |
|------------------------------------------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| [`_check-outdated-php-dependencies.yml`](.github/workflows/_check-outdated-php-dependencies.yml)           | Runs a matrix of Composer scripts to verify all direct dependencies are up to date before a release proceeds                                                                                                                                                                                                                                                                                                                               |
| [`_check-outdated-java-dependencies.yml`](.github/workflows/_check-outdated-java-dependencies.yml)         | Verifies all direct Java (Gradle) dependencies are up to date before a release proceeds                                                                                                                                                                                                                                                                                                                                                    |
| [`_check-outdated-python-dependencies.yml`](.github/workflows/_check-outdated-python-dependencies.yml)     | Verifies all direct Python (uv) dependencies are up to date before a release proceeds                                                                                                                                                                                                                                                                                                                                                      |
| [`_check-outdated-ts-dependencies.yml`](.github/workflows/_check-outdated-ts-dependencies.yml)             | Verifies all direct TypeScript (npm) dependencies are up to date before a release proceeds                                                                                                                                                                                                                                                                                                                                                 |
| [`_update-php-dependencies.yml`](.github/workflows/_update-php-dependencies.yml)                           | Runs a set of Composer update scripts and syncs version constraints in `require`, `require-dev`, `conflict`, and `suggest` sections across each dependency's `composer.json`. Checks out an existing `deps/update-dependencies-*` PR branch first if one is open, then commits and force-pushes. Creates a new PR with a per-package version changelog if none exists. Optionally assigns a reviewer via the `VALKYRJA_REVIEWER` variable. |
| [`_update-java-dependencies.yml`](.github/workflows/_update-java-dependencies.yml)                         | Runs the Java (Gradle) dependency updater and opens/refreshes a `deps/update-dependencies-*` PR                                                                                                                                                                                                                                                                                                                                            |
| [`_update-python-dependencies.yml`](.github/workflows/_update-python-dependencies.yml)                     | Runs the Python (uv) dependency updater and opens/refreshes a `deps/update-dependencies-*` PR                                                                                                                                                                                                                                                                                                                                              |
| [`_update-ts-dependencies.yml`](.github/workflows/_update-ts-dependencies.yml)                             | Runs the TypeScript (npm) dependency updater and opens/refreshes a `deps/update-dependencies-*` PR                                                                                                                                                                                                                                                                                                                                         |
| [`update-php-dependencies.yml`](.github/workflows/update-php-dependencies.yml)                             | `workflow_dispatch` entry point that fans out dependency updates across every PHP repo. Delegates to `_update-php-dependencies-across-repos.yml`.                                                                                                                                                                                                                                                                                          |
| [`_update-php-dependencies-across-repos.yml`](.github/workflows/_update-php-dependencies-across-repos.yml) | Triggers each PHP repo's own `update-dependencies` workflow across all supported version branches                                                                                                                                                                                                                                                                                                                                          |

### Repository Management

| Workflow                                                                                     | Trigger                                          | Description                                                                                                                                                                                                                                                                                              |
|----------------------------------------------------------------------------------------------|--------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| [`create-repo.yml`](.github/workflows/create-repo.yml)                                       | `workflow_dispatch`                              | Creates a new public repository in the organization with the given name and description. Delegates to `_create-repo.yml`.                                                                                                                                                                                |
| [`_create-repo.yml`](.github/workflows/_create-repo.yml)                                     | `workflow_call`                                  | Creates and configures a public repository: enables squash-only merges, deletes branches on merge, and applies all branch rulesets from `rulesets/`. Scaffolds from `project-template-<lang>` and applies `rulesets/<lang>/` rulesets when the repo's name suffix matches a `SUPPORTED_LANGUAGES` entry. |
| [`enforce-repo-settings.yml`](.github/workflows/enforce-repo-settings.yml)                   | `schedule` (Mon 09:00 UTC) / `workflow_dispatch` | Enforces merge settings and branch rulesets across all non-archived org repos. Can target a single repo via the optional `repo` input. Delegates to `_enforce-repo-settings.yml`.                                                                                                                        |
| [`_enforce-repo-settings.yml`](.github/workflows/_enforce-repo-settings.yml)                 | `workflow_call`                                  | Applies squash-only merge settings and any missing branch rulesets to each repo. Skips archived repos and `.github`. Also applies `rulesets/<lang>/` rulesets to repos whose name suffix matches a `SUPPORTED_LANGUAGES` entry.                                                                          |
| [`ensure-workflows.yml`](.github/workflows/ensure-workflows.yml)                             | `schedule` (Mon 12:00 UTC) / `workflow_dispatch` | Ensures every repo carries the required workflow files from `required-workflows/`. Delegates to `_ensure-workflows.yml`, which opens PRs where files are missing or drifted.                                                                                                                             |
| [`ensure-reusable-workflow-names.yml`](.github/workflows/ensure-reusable-workflow-names.yml) | `schedule` (Mon 13:00 UTC) / `workflow_dispatch` | Verifies reusable (`_`-prefixed, `workflow_call`-only) workflow `name:` values and filenames follow convention across repos. Delegates to `_ensure-reusable-workflow-names.yml`.                                                                                                                         |
| [`fix-trailing-newlines.yml`](.github/workflows/fix-trailing-newlines.yml)                   | `schedule` (Mon 11:00 UTC) / `workflow_dispatch` | Adds missing trailing newlines to tracked files across all repos and opens PRs with the fixes. Delegates to `_fix-trailing-newlines.yml`.                                                                                                                                                                |
| [`create-version-branch.yml`](.github/workflows/create-version-branch.yml)                   | `workflow_dispatch`                              | Creates a new major release version branch from `master`. Delegates to `_create-version-branch.yml`, which calls `_get-version.yml` then `_version-branch.yml`.                                                                                                                                          |

### Release & Version Management

Releases run from a version branch (or `master` for RCs) via
`release-new-version.yml`. The generic orchestrators below drive the `.github`
repo itself; the per-language orchestrators, publishers, info-file, and
version-branch workflows are consumed by the corresponding language repos.

| Workflow                                                                                 | Description                                                                                                                                                                                                                                                                                                                                           |
|------------------------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| [`_get-version-for-release.yml`](.github/workflows/_get-version-for-release.yml)         | Computes the next release version from the latest GitHub release tag, based on a `major`/`minor`/`patch`/`rc` bump input. Forces `MAJOR.0.0` when no releases exist yet for the branch's major version. Validates the result against `SUPPORTED_VERSIONS` and aborts if the tag already exists. Outputs `version`, `major-version`, and `build-date`. |
| [`_get-version.yml`](.github/workflows/_get-version.yml)                                 | Computes the next major version number and branch name (e.g. `27` → `27.x`) for creating a new major version branch. Must be run from `master`. Validates the new version against `SUPPORTED_VERSIONS` and aborts if the branch already exists.                                                                                                       |
| [`_update-version-files.yml`](.github/workflows/_update-version-files.yml)               | Checks out the calling repository, updates `VERSION.md` with the new version, and commits the change using the org bot as committer                                                                                                                                                                                                                   |
| [`_create-release.yml`](.github/workflows/_create-release.yml)                           | Orchestrates a full stable or RC release: calls `_get-version-for-release`, `_update-version-files`, and `_release` in sequence. Called by `release-new-version.yml`.                                                                                                                                                                                 |
| [`_aggregate-release.yml`](.github/workflows/_aggregate-release.yml)                     | Variant of `_create-release.yml` that pins external SHA references for the version-check and file-update steps. Intended for use by consumer repositories that call centralized release workflows by SHA.                                                                                                                                             |
| [`_release.yml`](.github/workflows/_release.yml)                                         | Generates and cleans release notes, updates `CHANGELOG.md`, commits it, creates the GitHub release, and tags the release                                                                                                                                                                                                                              |
| [`_create-version-branch.yml`](.github/workflows/_create-version-branch.yml)             | Orchestrates a new major version branch for the `.github` repo: calls `_get-version.yml` then `_version-branch.yml`.                                                                                                                                                                                                                                  |
| [`_version-branch.yml`](.github/workflows/_version-branch.yml)                           | Does the actual version-branch work: creates the branch, rewrites `README.md`, `CHANGELOG.md`, and `VERSION.md` for it, commits, sets it as the repository default, and updates the `LATEST_MAJOR_VERSION` org variable                                                                                                                               |
| `_create-{php,java,python,ts}-release.yml`                                               | Per-language release orchestrators: check-version → check-outdated-dependencies → update-version-files → update-`<lang>`-info-files → release. End at `_release.yml`; artifact publishing is handled separately by the publish workflows below. Accept language-specific inputs (e.g. `php-version`, info-class path/name).                           |
| [`_php-release.yml`](.github/workflows/_php-release.yml)                                 | Lightweight PHP release: updates a PHP Info class file's `VERSION` and `BUILD_DATE` constants via `sed`, commits, then calls `_release.yml`. Used when the caller already handles version computation.                                                                                                                                                |
| [`_java-release-maven-publish.yml`](.github/workflows/_java-release-maven-publish.yml)   | Publishes Java artifacts to Maven Central via Gradle. Consumes `MAVEN_CENTRAL_USERNAME`/`MAVEN_CENTRAL_PASSWORD` and `MAVEN_SIGNING_KEY`/`MAVEN_SIGNING_KEY_PASSWORD`.                                                                                                                                                                                |
| [`_python-release-pypi-publish.yml`](.github/workflows/_python-release-pypi-publish.yml) | Publishes Python packages to PyPI via `uv publish`. Consumes `PYPI_API_TOKEN`.                                                                                                                                                                                                                                                                        |
| [`_ts-release-npm-publish.yml`](.github/workflows/_ts-release-npm-publish.yml)           | Publishes TypeScript packages to npm using trusted publishing (OIDC, `--provenance`). No token secret required.                                                                                                                                                                                                                                       |
| `_update-{php,java,python,ts}-info-files.yml`                                            | Update `VERSION` and `BUILD_DATE` constants in a language's Info/version file, then commit using the org bot.                                                                                                                                                                                                                                         |
| `_create-{php,java,python,ts}-version-branch.yml`, `_version-branch-{python,ts}.yml`     | Per-language version-branch orchestrators for consumer repos. Each runs its check-outdated gate first; PHP/Java reuse the generic `_create-version-branch.yml`, while Python/TS use their own `_version-branch-<lang>.yml`.                                                                                                                           |

### Branch Management

| Workflow                                                                               | Description                                                                                                                                                 |
|----------------------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------|
| [`cherry-pick-commits.yml`](.github/workflows/cherry-pick-commits.yml)                 | Manually cherry-picks a commit hash to a target branch. Validates the destination against a configurable branch pattern and creates a backup before picking |
| [`_cherry-pick-commits.yml`](.github/workflows/_cherry-pick-commits.yml)               | Reusable implementation of the above. Inputs: `destination`, `hash`, `valid-branch-pattern`.                                                                |
| [`rebase-to-master.yml`](.github/workflows/rebase-to-master.yml)                       | Rebases `master` onto the current branch (must be the latest major version branch). Delegates to `_rebase-to-master.yml`.                                   |
| [`_rebase-to-master.yml`](.github/workflows/_rebase-to-master.yml)                     | Reusable implementation of the above. Backs up `master` first, validates the source branch is the latest major version, then force-pushes `master`.         |
| [`rebase-from-master.yml`](.github/workflows/rebase-from-master.yml)                   | Rebases the current branch onto `master`. Delegates to `_rebase-from-master.yml`.                                                                           |
| [`_rebase-from-master.yml`](.github/workflows/_rebase-from-master.yml)                 | Reusable implementation of the above. Backs up the current branch first, then rebases it onto `master` and force-pushes.                                    |
| [`restore-branch-from-backup.yml`](.github/workflows/restore-branch-from-backup.yml)   | Restores the current branch from its `<branch>-backup` counterpart. Delegates to `_restore-branch-from-backup.yml`.                                         |
| [`_restore-branch-from-backup.yml`](.github/workflows/_restore-branch-from-backup.yml) | Reusable implementation of the above. Force-pushes the `<branch>-backup` ref onto the current branch to restore it.                                         |

### Workflow Reference Pinning

Consumer repos reference `valkyrjaio/.github` reusable workflows by commit SHA.
These workflows keep those pins current.

| Workflow                                                                               | Trigger                                                                    | Description                                                                                                                                                                |
|----------------------------------------------------------------------------------------|----------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| [`update-github-workflow-refs.yml`](.github/workflows/update-github-workflow-refs.yml) | `release` (stable only) / `schedule` (Mon 10:00 UTC) / `workflow_dispatch` | Repins every org repo's workflow references to the latest `.github` release SHA. Delegates to `_update-workflow-refs.yml` with `source-repo: .github`. Skips pre-releases. |
| [`_update-workflow-refs.yml`](.github/workflows/_update-workflow-refs.yml)             | `workflow_call`                                                            | Scans all non-archived repos for `<source-repo>` workflow refs and opens PRs bumping them to the latest release SHA. Takes a `source-repo` input.                          |

### Required Secrets and Variables

All reusable workflows that use the Valkyrja GitHub App require these to be
set at the organization level. Callers pass them down via `secrets: inherit`.

| Name                         | Type     | Description                                                                                                                                                                        |
|------------------------------|----------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `VALKYRJA_GHA_APP_ID`        | Secret   | GitHub App ID used to generate short-lived tokens                                                                                                                                  |
| `VALKYRJA_GHA_PRIVATE_KEY`   | Secret   | GitHub App private key                                                                                                                                                             |
| `MAVEN_CENTRAL_USERNAME`     | Secret   | Maven Central (Sonatype) user-token username. Required to publish Java releases.                                                                                                   |
| `MAVEN_CENTRAL_PASSWORD`     | Secret   | Maven Central (Sonatype) user-token password. Required to publish Java releases.                                                                                                   |
| `MAVEN_SIGNING_KEY`          | Secret   | In-memory PGP signing key used to sign Java release artifacts.                                                                                                                     |
| `MAVEN_SIGNING_KEY_PASSWORD` | Secret   | Passphrase for the PGP signing key.                                                                                                                                                |
| `PYPI_API_TOKEN`             | Secret   | PyPI API token used to publish Python releases (`uv publish`).                                                                                                                     |
| `LATEST_MAJOR_VERSION`       | Variable | Current latest major version number (e.g. `26`). Falls back to current year's last two digits if unset.                                                                            |
| `SUPPORTED_VERSIONS`         | Variable | Regex pattern of supported major versions (e.g. `^(26\|27)$`). Version checks are skipped if unset.                                                                                |
| `SUPPORTED_LANGUAGES`        | Variable | Space-separated language suffixes (e.g. `php java python ts go`). Selects the `project-template-<lang>` scaffold and language-specific rulesets when creating and enforcing repos. |
| `USER_EMAIL`                 | Variable | Git committer email for rebase/cherry-pick operations                                                                                                                              |
| `USER_NAME`                  | Variable | Git committer name for rebase/cherry-pick operations                                                                                                                               |
| `VALKYRJA_REVIEWER`          | Variable | GitHub username to assign and request review from on dependency update PRs. Optional.                                                                                              |

TypeScript/npm releases publish via
npm [trusted publishing][npm-trusted-publishing]
(OIDC), so no npm token secret is required. The Java (`MAVEN_*`) and Python
(`PYPI_API_TOKEN`) publishing secrets are only consumed by their respective
language release workflows.

Rulesets
--------

The [`rulesets/`](rulesets/) directory contains exported GitHub branch
ruleset definitions applied across Valkyrja repositories by the
repository-management workflows. Org-wide rulesets live in `rulesets/`;
language-specific rulesets live in `rulesets/<lang>/` and are applied only to
repos whose name suffix matches a `SUPPORTED_LANGUAGES` entry.

| Ruleset                                                                                                        | Scope        | Description                                                                                                         |
|----------------------------------------------------------------------------------------------------------------|--------------|---------------------------------------------------------------------------------------------------------------------|
| [Protect Against Force Pushes and Deletion](rulesets/Protect%20Against%20Force%20Pushes%20and%20Deletion.json) | All repos    | Prevents force pushes and branch deletion on version branches (`??.x`)                                              |
| [Protect Master At All Times](rulesets/Protect%20Master%20At%20All%20Times.json)                               | All repos    | Prevents force pushes and deletion on `master`                                                                      |
| [Protect Release Tags](rulesets/Protect%20Release%20Tags.json)                                                 | All repos    | Prevents deletion and non-fast-forward updates on version tags (`*.*.*`)                                            |
| [Require Pull Request](rulesets/Require%20Pull%20Request.json)                                                 | All repos    | Requires squash-merge PRs with code owner review on `master` and version branches                                   |
| [Required Default PR Checks](rulesets/Required%20Default%20PR%20Checks.json)                                   | All repos    | Requires the commit-message and trailing-newline checks to pass on the default branch and version branches (`??.x`) |
| [Restrict Changes to Unsupported Branches](rulesets/Restrict%20Changes%20to%20Unsupported%20Branches.json)     | All repos    | Locks backup branches (`*-backup`) against all changes                                                              |
| [php/Required PHP PR Checks](rulesets/php/Required%20PHP%20PR%20Checks.json)                                   | PHP repos    | Requires all PHP CI checks (PHP CS Fixer, PHPCS, PHPArkitect, PHPStan, PHPUnit 8.4–8.6, Psalm, Rector)              |
| [java/Required Java PR Checks](rulesets/java/Required%20Java%20PR%20Checks.json)                               | Java repos   | Requires all Java CI checks (Spotless, Error Prone, SpotBugs, ArchUnit, JUnit)                                      |
| [python/Required Python PR Checks](rulesets/python/Required%20Python%20PR%20Checks.json)                       | Python repos | Requires all Python CI checks (Ruff, mypy, Bandit, import-linter, pytest)                                           |
| [ts/Required TypeScript PR Checks](rulesets/ts/Required%20TypeScript%20PR%20Checks.json)                       | TS repos     | Requires all TypeScript CI checks (ESLint, Prettier, tsc, Vitest)                                                   |
| [go/Required Go PR Checks](rulesets/go/Required%20Go%20PR%20Checks.json)                                       | Go repos     | Requires all Go CI checks (golangci-lint, go test)                                                                  |

Contributing
------------

Improvements to the shared workflows, rulesets, community health files, and
org conventions are welcome. See [`CONTRIBUTING.md`](CONTRIBUTING.md) for
the submission process, [`REPOSITORY_NAMING.md`](REPOSITORY_NAMING.md) for
how repos are named, and [`VOCABULARY.md`](VOCABULARY.md) for terminology
used across the project.

License
-------

Licensed under the [MIT license][MIT license url]. See
[`LICENSE.md`](LICENSE.md).

[github-special-repo]: https://docs.github.com/en/communities/setting-up-your-project-for-healthy-contributions/creating-a-default-community-health-file

[npm-trusted-publishing]: https://docs.npmjs.com/trusted-publishers

[valkyrja]: https://valkyrja.io

[org-page]: https://github.com/valkyrjaio

[MIT license url]: https://opensource.org/licenses/MIT
