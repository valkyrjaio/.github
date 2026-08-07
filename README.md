<p align="center"><a href="https://valkyrja.io" target="_blank">
    <img src="https://raw.githubusercontent.com/valkyrjaio/art/refs/heads/26.x/long-banner/orange/default.png" width="100%">
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

- **Community health files** — `CODE_OF_CONDUCT.md`, `CONTRIBUTING.md`, and
  `SECURITY.md` inherited by every repo that doesn't override them
- **Organization profile** — the `profile/README.md` that renders on the
  [Valkyrjaio organization page][org-page]
- **Reusable workflows** — PR quality gates, dependency management,
  repository management, release orchestration, and branch management
- **Branch rulesets** — defined in the
  [`infra-github`](https://github.com/valkyrjaio/infra-github) repository as
  OpenTofu configuration and applied on merge and on a weekly schedule
- **Project conventions** — `REPOSITORY_NAMING.md` and `VOCABULARY.md`
  documenting how repos are named and what terms mean across the project

Community Health Files
----------------------

| File                                       | Description                                                |
| ------------------------------------------ | ---------------------------------------------------------- |
| [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md) | Expected standards of behavior for community members       |
| [`CONTRIBUTING.md`](CONTRIBUTING.md)       | Guidelines for contributing code, tests, and documentation |
| [`SECURITY.md`](SECURITY.md)               | Security vulnerability disclosure procedure                |

GitHub does not support a default license file. Every repository carries its
own `LICENSE.md`, so the license is included when a person clones, packages,
or downloads that project.

Project Conventions
-------------------

| Document                                       | Description                                                     |
| ---------------------------------------------- | --------------------------------------------------------------- |
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
| ------------------------------------------------------------------------------ | --------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------- |
| [`ci.yml`](.github/workflows/ci.yml)                                           | `push`/`pull_request` | Umbrella CI workflow. On PRs runs the commit-message and trailing-newline checks.                                                               |
| [`_commit-message-check.yml`](.github/workflows/_commit-message-check.yml)     | `workflow_call`       | Validates that every commit message on a PR meets the project conventions; posts/removes a PR comment on failure/success. Skips Dependabot PRs. |
| [`_trailing-newline-check.yml`](.github/workflows/_trailing-newline-check.yml) | `workflow_call`       | Checks all tracked files in the repo, skips binary and empty files; posts/removes a PR comment listing offending files on failure/success       |

### Language CI Checks

Reusable lint, static-analysis, and test workflows (all `workflow_call`)
consumed by each language repo's `ci.yml`. PHP quality checks live in dedicated
`ci-*-php` repositories rather than here.

| Language   | Workflows                                                                                                                                                                                                                                                                                                                                                                              |
| ---------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Java       | [`_java-spotless.yml`](.github/workflows/_java-spotless.yml) (format), [`_java-errorprone.yml`](.github/workflows/_java-errorprone.yml), [`_java-spotbugs.yml`](.github/workflows/_java-spotbugs.yml), [`_java-archunit.yml`](.github/workflows/_java-archunit.yml) (architecture), [`_java-junit.yml`](.github/workflows/_java-junit.yml) (tests)                                     |
| Python     | [`_python-ruff.yml`](.github/workflows/_python-ruff.yml) (lint/format), [`_python-mypy.yml`](.github/workflows/_python-mypy.yml) (types), [`_python-bandit.yml`](.github/workflows/_python-bandit.yml) (security), [`_python-import-linter.yml`](.github/workflows/_python-import-linter.yml) (import contracts), [`_python-pytest.yml`](.github/workflows/_python-pytest.yml) (tests) |
| TypeScript | [`_ts-eslint.yml`](.github/workflows/_ts-eslint.yml) (lint), [`_ts-prettier.yml`](.github/workflows/_ts-prettier.yml) (format), [`_ts-typescript.yml`](.github/workflows/_ts-typescript.yml) (`tsc` types), [`_ts-vitest.yml`](.github/workflows/_ts-vitest.yml) (tests)                                                                                                               |
| Go         | [`_go-golangci-lint.yml`](.github/workflows/_go-golangci-lint.yml) (lint), [`_go-test.yml`](.github/workflows/_go-test.yml) (tests)                                                                                                                                                                                                                                                    |

### Dependency Management

Each language has a paired "check outdated" gate (run before a release) and an
"update dependencies" workflow that opens a PR. All are `workflow_call`, except
the public [
`update-php-dependencies.yml`](.github/workflows/update-php-dependencies.yml)
dispatch entry point.

| Workflow                                                                                                   | Description                                                                                                                                                                                                                                                                                                                                                            |
| ---------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [`_php-check-outdated-dependencies.yml`](.github/workflows/_php-check-outdated-dependencies.yml)           | Runs a matrix of Composer scripts to verify all direct dependencies are up to date before a release proceeds                                                                                                                                                                                                                                                           |
| [`_java-check-outdated-dependencies.yml`](.github/workflows/_java-check-outdated-dependencies.yml)         | Verifies all direct Java (Gradle) dependencies are up to date before a release proceeds                                                                                                                                                                                                                                                                                |
| [`_python-check-outdated-dependencies.yml`](.github/workflows/_python-check-outdated-dependencies.yml)     | Verifies all direct Python (uv) dependencies are up to date before a release proceeds                                                                                                                                                                                                                                                                                  |
| [`_ts-check-outdated-dependencies.yml`](.github/workflows/_ts-check-outdated-dependencies.yml)             | Verifies all direct TypeScript (npm) dependencies are up to date before a release proceeds                                                                                                                                                                                                                                                                             |
| [`_php-update-dependencies.yml`](.github/workflows/_php-update-dependencies.yml)                           | Runs a set of Composer update scripts and syncs version constraints in `require`, `require-dev`, `conflict`, and `suggest` sections across each dependency's `composer.json`. Checks out an existing `deps/update-dependencies-*` PR branch first if one is open, then commits and force-pushes. Creates a new PR with a per-package version changelog if none exists. |
| [`_java-update-dependencies.yml`](.github/workflows/_java-update-dependencies.yml)                         | Runs the Java (Gradle) dependency updater and opens/refreshes a `deps/update-dependencies-*` PR                                                                                                                                                                                                                                                                        |
| [`_python-update-dependencies.yml`](.github/workflows/_python-update-dependencies.yml)                     | Runs the Python (uv) dependency updater and opens/refreshes a `deps/update-dependencies-*` PR                                                                                                                                                                                                                                                                          |
| [`_ts-update-dependencies.yml`](.github/workflows/_ts-update-dependencies.yml)                             | Runs the TypeScript (npm) dependency updater and opens/refreshes a `deps/update-dependencies-*` PR                                                                                                                                                                                                                                                                     |
| [`update-php-dependencies.yml`](.github/workflows/update-php-dependencies.yml)                             | `workflow_dispatch` entry point that fans out dependency updates across every PHP repo. Delegates to `_php-update-dependencies-across-repos.yml`.                                                                                                                                                                                                                      |
| [`_php-update-dependencies-across-repos.yml`](.github/workflows/_php-update-dependencies-across-repos.yml) | Triggers each PHP repo's own `update-dependencies` workflow across all supported version branches                                                                                                                                                                                                                                                                      |

### Repository Management

| Workflow                                                                                     | Trigger                                          | Description                                                                                                                                                                      |
| -------------------------------------------------------------------------------------------- | ------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [`post-create.yml`](.github/workflows/post-create.yml)                                       | `workflow_dispatch`                              | Runs the post-creation steps for a repository that `infra-github` created: the copyright header package identifier rewrite and the immutable-releases setting.                   |
| [`ensure-workflows.yml`](.github/workflows/ensure-workflows.yml)                             | `schedule` (Mon 12:00 UTC) / `workflow_dispatch` | Ensures every repo carries the required workflow files from `required-workflows/`. Delegates to `_ensure-workflows.yml`, which opens PRs where files are missing or drifted.     |
| [`ensure-reusable-workflow-names.yml`](.github/workflows/ensure-reusable-workflow-names.yml) | `schedule` (Mon 13:00 UTC) / `workflow_dispatch` | Verifies reusable (`_`-prefixed, `workflow_call`-only) workflow `name:` values and filenames follow convention across repos. Delegates to `_ensure-reusable-workflow-names.yml`. |
| [`fix-trailing-newlines.yml`](.github/workflows/fix-trailing-newlines.yml)                   | `schedule` (Mon 11:00 UTC) / `workflow_dispatch` | Adds missing trailing newlines to tracked files across all repos and opens PRs with the fixes. Delegates to `_fix-trailing-newlines.yml`.                                        |
| [`create-version-branch.yml`](.github/workflows/create-version-branch.yml)                   | `workflow_dispatch`                              | Creates a new yearly release version branch from `master`. Delegates to `_create-version-branch.yml`, which calls `_get-version.yml` then `_version-branch.yml`.                 |

### Release & Version Management

Releases run from a version branch (or `master` for RCs) via
`release-new-version.yml`. The generic orchestrators below drive the `.github`
repo itself; the per-language orchestrators, publishers, info-file, and
version-branch workflows are consumed by the corresponding language repos.

| Workflow                                                                                               | Description                                                                                                                                                                                                                                                                                                                                           |
| ------------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [`_get-version-for-release.yml`](.github/workflows/_get-version-for-release.yml)                       | Computes the next release version from the latest GitHub release tag, based on a `major`/`minor`/`patch`/`rc` bump input. Forces `MAJOR.0.0` when no releases exist yet for the branch's major version. Validates the result against `SUPPORTED_VERSIONS` and aborts if the tag already exists. Outputs `version`, `major-version`, and `build-date`. |
| [`_get-version.yml`](.github/workflows/_get-version.yml)                                               | Computes the next major version number and branch name (e.g. `27` → `27.x`) for creating a new major version branch. Must be run from `master`. Validates the new version against `SUPPORTED_VERSIONS` and aborts if the branch already exists.                                                                                                       |
| [`_update-version-files.yml`](.github/workflows/_update-version-files.yml)                             | Checks out the calling repository, updates `VERSION.md` with the new version, and commits the change using the org bot as committer                                                                                                                                                                                                                   |
| [`_create-release.yml`](.github/workflows/_create-release.yml)                                         | Orchestrates a full stable or RC release: calls `_get-version-for-release`, `_update-version-files`, and `_release` in sequence. Called by `release-new-version.yml`.                                                                                                                                                                                 |
| [`_aggregate-release.yml`](.github/workflows/_aggregate-release.yml)                                   | Variant of `_create-release.yml` that pins external SHA references for the version-check and file-update steps. Intended for use by consumer repositories that call centralized release workflows by SHA.                                                                                                                                             |
| [`_release.yml`](.github/workflows/_release.yml)                                                       | Generates and cleans release notes, updates `CHANGELOG.md`, commits it, creates the GitHub release, and tags the release                                                                                                                                                                                                                              |
| [`_create-version-branch.yml`](.github/workflows/_create-version-branch.yml)                           | Orchestrates a new major version branch for the `.github` repo: calls `_get-version.yml` then `_version-branch.yml`.                                                                                                                                                                                                                                  |
| [`_version-branch.yml`](.github/workflows/_version-branch.yml)                                         | Does the actual version-branch work: creates the branch, rewrites `README.md`, `CHANGELOG.md`, and `VERSION.md` for it, commits, sets it as the repository default, and updates the `LATEST_MAJOR_VERSION` org variable                                                                                                                               |
| `_{php,java,python,ts}-create-release.yml`                                                             | Per-language release orchestrators: check-version → check-outdated-dependencies → update-version-files → update-`<lang>`-info-files → release. End at `_release.yml`; artifact publishing is handled separately by the publish workflows below. Accept language-specific inputs (e.g. `php-version`, info-class path/name).                           |
| [`_php-release.yml`](.github/workflows/_php-release.yml)                                               | Lightweight PHP release: updates a PHP Info class file's `VERSION` and `BUILD_DATE` constants via `sed`, commits, then calls `_release.yml`. Used when the caller already handles version computation.                                                                                                                                                |
| [`_java-release-maven-publish.yml`](.github/workflows/_java-release-maven-publish.yml)                 | Publishes Java artifacts to Maven Central via Gradle. Consumes `MAVEN_CENTRAL_USERNAME`/`MAVEN_CENTRAL_PASSWORD` and `MAVEN_SIGNING_KEY`/`MAVEN_SIGNING_KEY_PASSWORD`.                                                                                                                                                                                |
| [`_java-release-plugin-portal-publish.yml`](.github/workflows/_java-release-plugin-portal-publish.yml) | Publishes a Java Gradle plugin to the Gradle Plugin Portal via Gradle. Consumes `GRADLE_PUBLISH_KEY`/`GRADLE_PUBLISH_SECRET`. A repository that publishes a plugin calls this as well as the Maven Central workflow.                                                                                                                                  |
| [`_python-release-pypi-publish.yml`](.github/workflows/_python-release-pypi-publish.yml)               | Publishes Python packages to PyPI via `uv publish`. Consumes `PYPI_API_TOKEN`.                                                                                                                                                                                                                                                                        |
| [`_ts-release-npm-publish.yml`](.github/workflows/_ts-release-npm-publish.yml)                         | Publishes TypeScript packages to npm using trusted publishing (OIDC, `--provenance`). No token secret required.                                                                                                                                                                                                                                       |
| `_{php,java,python,ts}-update-info-files.yml`                                                          | Update `VERSION` and `BUILD_DATE` constants in a language's Info/version file, then commit using the org bot.                                                                                                                                                                                                                                         |
| `_{php,java,python,ts}-create-version-branch.yml`, `_{python,ts}-version-branch.yml`                   | Per-language version-branch orchestrators for consumer repos. Each runs its check-outdated gate first; PHP/Java reuse the generic `_create-version-branch.yml`, while Python/TS use their own `_version-branch-<lang>.yml`.                                                                                                                           |

### Branch Management

| Workflow                                                                               | Description                                                                                                                                                 |
| -------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
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

This repository owns the templates under `required-workflows/`, so its own
release updates their references before it makes the tag. A consumer repo is
outside that release, so a pull request updates it afterward.

| Workflow                                                                               | Trigger                                                                    | Description                                                                                                                                                                |
| -------------------------------------------------------------------------------------- | -------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [`update-github-workflow-refs.yml`](.github/workflows/update-github-workflow-refs.yml) | `release` (stable only) / `schedule` (Mon 10:00 UTC) / `workflow_dispatch` | Repins every org repo's workflow references to the latest `.github` release SHA. Delegates to `_update-workflow-refs.yml` with `source-repo: .github`. Skips pre-releases. |
| [`_update-workflow-refs.yml`](.github/workflows/_update-workflow-refs.yml)             | `workflow_call`                                                            | Scans all non-archived repos for `<source-repo>` workflow refs and opens PRs bumping them to the latest release SHA. Takes a `source-repo` input. Excludes `.github`.      |
| [`_release.yml`](.github/workflows/_release.yml)                                       | `workflow_call`                                                            | Before making the tag, rewrites this repo's own `required-workflows/` references to the last workflow-code commit, so the tag ships a current template. No-op elsewhere.   |

### Required Secrets and Variables

All reusable workflows that use the Valkyrja GitHub App require these to be
set at the organization level. Each reusable workflow declares the secrets it
needs, and a caller passes down that list. See
[the workflow guide](.github/workflows/README.md#which-secrets-a-caller-passes)
for the list per workflow.

| Name                         | Type     | Description                                                                                                                                               |
| ---------------------------- | -------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `VALKYRJA_GHA_APP_ID`        | Secret   | GitHub App ID used to generate short-lived tokens                                                                                                         |
| `VALKYRJA_GHA_PRIVATE_KEY`   | Secret   | GitHub App private key                                                                                                                                    |
| `MAVEN_CENTRAL_USERNAME`     | Secret   | Maven Central (Sonatype) user-token username. Required to publish Java releases.                                                                          |
| `MAVEN_CENTRAL_PASSWORD`     | Secret   | Maven Central (Sonatype) user-token password. Required to publish Java releases.                                                                          |
| `MAVEN_SIGNING_KEY`          | Secret   | In-memory PGP signing key used to sign Java release artifacts.                                                                                            |
| `MAVEN_SIGNING_KEY_PASSWORD` | Secret   | Passphrase for the PGP signing key.                                                                                                                       |
| `GRADLE_PUBLISH_KEY`         | Secret   | Gradle Plugin Portal API key. Required to publish a Java Gradle plugin.                                                                                   |
| `GRADLE_PUBLISH_SECRET`      | Secret   | Gradle Plugin Portal API secret. Required to publish a Java Gradle plugin.                                                                                |
| `PYPI_API_TOKEN`             | Secret   | PyPI API token used to publish Python releases (`uv publish`).                                                                                            |
| `LATEST_MAJOR_VERSION`       | Variable | Current latest major version number (e.g. `26`). Falls back to current year's last two digits if unset.                                                   |
| `SUPPORTED_VERSIONS`         | Variable | Regex pattern of supported major versions (e.g. `^(26\|27)$`). Version checks are skipped if unset.                                                       |
| `SUPPORTED_LANGUAGES`        | Variable | Space-separated language suffixes (e.g. `php java python ts go`) the release automation iterates over.                                                    |
| `USER_EMAIL`                 | Variable | Git committer email for rebase/cherry-pick operations                                                                                                     |
| `USER_NAME`                  | Variable | Git committer name for rebase/cherry-pick operations                                                                                                      |
| `VALKYRJA_REVIEWER`          | Variable | GitHub username the auto-merge sweep requests a review from when a bot PR cannot merge on its own. Also identifies the Claude review requester. Optional. |

TypeScript/npm releases publish via
npm [trusted publishing][npm-trusted-publishing]
(OIDC), so no npm token secret is required. The Java (`MAVEN_*`,
`GRADLE_PUBLISH_*`) and Python (`PYPI_API_TOKEN`) publishing secrets are only
consumed by their respective language release workflows.

Rulesets
--------

The [`infra-github`](https://github.com/valkyrjaio/infra-github) repository
defines every ruleset, repository setting, and label as OpenTofu configuration.
Its Apply workflow applies the configuration on every merge and on a weekly
schedule. Change a ruleset with a pull request there.

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
