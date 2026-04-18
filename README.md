<p align="center"><a href="https://valkyrja.io" target="_blank">
    <img src="https://raw.githubusercontent.com/valkyrjaio/art/refs/heads/master/long-banner/orange/default.png" width="100%">
</a></p>

# Valkyrja GitHub

This is the [special `.github` repository][github-special-repo] for the
[Valkyrja][valkyrja] organization. Files placed here apply as defaults across
all repositories in the organization.

## Contents

### Community Health Files

| File                                     | Description                                                |
|------------------------------------------|------------------------------------------------------------|
| [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) | Expected standards of behavior for community members       |
| [CONTRIBUTING.md](CONTRIBUTING.md)       | Guidelines for contributing code, tests, and documentation |
| [LICENSE.md](LICENSE.md)                 | MIT license                                                |

### Organization Profile

[`profile/README.md`](profile/README.md) renders on the
[valkyrjaio organization page][org-page] on GitHub.

### Workflows

Reusable workflows shared across all Valkyrja repositories. Prefixed with `_` to
indicate they are called by other workflows rather than triggered directly.

#### PR Quality Gates

| Workflow                                                                   | Trigger         | Description                                                                         |
|----------------------------------------------------------------------------|-----------------|-------------------------------------------------------------------------------------|
| [`commit-message-check.yml`](.github/workflows/commit-message-check.yml)   | `pull_request`  | Validates that every commit message on a PR meets the project conventions           |
| [`_commit-message-check.yml`](.github/workflows/_commit-message-check.yml) | `workflow_call` | Reusable implementation of the above; posts/removes a PR comment on failure/success |

#### Dependency Management

| Workflow                                                                                         | Description                                                                                                                                                                                                                                                                                                                                                                                                                                |
|--------------------------------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| [`_check-outdated-php-dependencies.yml`](.github/workflows/_check-outdated-php-dependencies.yml) | Runs a matrix of Composer scripts to verify all direct dependencies are up to date before a release proceeds.                                                                                                                                                                                                                                                                                                                              |
| [`_update-php-dependencies.yml`](.github/workflows/_update-php-dependencies.yml)                 | Runs a set of Composer update scripts and syncs version constraints in `require`, `require-dev`, `conflict`, and `suggest` sections across each dependency's `composer.json`. Checks out an existing `deps/update-dependencies-*` PR branch first if one is open, then commits and force-pushes. Creates a new PR with a per-package version changelog if none exists. Optionally assigns a reviewer via the `VALKYRJA_REVIEWER` variable. |

#### Repository Management

| Workflow                                                                     | Trigger                                          | Description                                                                                                                                                                                                                           |
|------------------------------------------------------------------------------|--------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| [`create-repo.yml`](.github/workflows/create-repo.yml)                       | `workflow_dispatch`                              | Creates a new public repository in the organization with the given name and description. Delegates to `_create-repo.yml`.                                                                                                             |
| [`_create-repo.yml`](.github/workflows/_create-repo.yml)                     | `workflow_call`                                  | Creates and configures a public repository: enables squash-only merges, deletes branches on merge, and applies all branch rulesets from `rulesets/`. Applies PHP-specific rulesets to repos whose name or description contains "php". |
| [`enforce-repo-settings.yml`](.github/workflows/enforce-repo-settings.yml)   | `schedule` (Mon 09:00 UTC) / `workflow_dispatch` | Enforces merge settings and branch rulesets across all non-archived org repos. Can target a single repo via the optional `repo` input. Delegates to `_enforce-repo-settings.yml`.                                                     |
| [`_enforce-repo-settings.yml`](.github/workflows/_enforce-repo-settings.yml) | `workflow_call`                                  | Applies squash-only merge settings and any missing branch rulesets to each repo. Skips archived repos and `.github`. Applies PHP-specific rulesets to repos whose name or description contains "php".                                 |
| [`create-version-branch.yml`](.github/workflows/create-version-branch.yml)   | `workflow_dispatch`                              | Creates a new major release version branch from `master`. Delegates to `_get-version.yml` to compute the next major version, then to `_create-version-branch.yml` to create and configure the branch.                                 |

#### Release Management

| Workflow                                                                         | Description                                                                                                                                                                                                                                                                                                                                           |
|----------------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| [`_get-version-for-release.yml`](.github/workflows/_get-version-for-release.yml) | Computes the next release version from the latest GitHub release tag, based on a `major`/`minor`/`patch`/`rc` bump input. Forces `MAJOR.0.0` when no releases exist yet for the branch's major version. Validates the result against `SUPPORTED_VERSIONS` and aborts if the tag already exists. Outputs `version`, `major-version`, and `build-date`. |
| [`_get-version.yml`](.github/workflows/_get-version.yml)                         | Computes the next major version number and branch name (e.g. `27` → `27.x`) for creating a new major version branch. Must be run from `master`. Validates the new version against `SUPPORTED_VERSIONS` and aborts if the branch already exists.                                                                                                       |
| [`_update-version-files.yml`](.github/workflows/_update-version-files.yml)       | Checks out the calling repository, updates `VERSION.md` with the new version, and commits the change using the org bot as committer.                                                                                                                                                                                                                  |
| [`_create-version-branch.yml`](.github/workflows/_create-version-branch.yml)     | Creates a new major version branch, rewrites `README.md`, `CHANGELOG.md`, and `VERSION.md` for that branch, commits, sets the new branch as the repository default, and updates the `LATEST_MAJOR_VERSION` org variable.                                                                                                                              |
| [`_create-release.yml`](.github/workflows/_create-release.yml)                   | Orchestrates a full stable or RC release: calls `_get-version-for-release`, `_update-version-files`, and `_release` in sequence. Called by `release-new-version.yml`.                                                                                                                                                                                 |
| [`_aggregate-release.yml`](.github/workflows/_aggregate-release.yml)             | Variant of `_create-release.yml` that pins external SHA references for the version-check and file-update steps. Intended for use by consumer repositories that call centralized release workflows by SHA.                                                                                                                                             |
| [`_release.yml`](.github/workflows/_release.yml)                                 | Generates and cleans release notes, updates `CHANGELOG.md`, commits it, creates the GitHub release, and tags the release.                                                                                                                                                                                                                             |
| [`_create-php-release.yml`](.github/workflows/_create-php-release.yml)           | Full PHP release orchestrator: check-version → check-outdated-dependencies → update-version-files → update-php-info-files → release. Accepts `bump`, `php-version`, `dependencies` (JSON array), `info-class-path`, and `info-class-name` inputs.                                                                                                     |
| [`_php-release.yml`](.github/workflows/_php-release.yml)                         | Lightweight PHP release: updates a PHP Info class file's `VERSION` and `BUILD_DATE` constants via `sed`, commits the change, then calls `_release.yml`. Used when the caller already handles version computation.                                                                                                                                     |
| [`_update-php-info-files.yml`](.github/workflows/_update-php-info-files.yml)     | Updates `VERSION` and `BUILD_DATE` constants in a PHP Info class file using `sed`. Pulls latest changes, patches the file, and commits using the org bot. Accepts `version`, `build-date`, `info-class-path`, and `info-class-name` inputs.                                                                                                           |

#### Branch Management

| Workflow                                                                               | Description                                                                                                                                                  |
|----------------------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------|
| [`cherry-pick-commits.yml`](.github/workflows/cherry-pick-commits.yml)                 | Manually cherry-picks a commit hash to a target branch. Validates the destination against a configurable branch pattern and creates a backup before picking. |
| [`_cherry-pick-commits.yml`](.github/workflows/_cherry-pick-commits.yml)               | Reusable implementation of the above. Inputs: `destination`, `hash`, `valid-branch-pattern`.                                                                 |
| [`rebase-to-master.yml`](.github/workflows/rebase-to-master.yml)                       | Rebases `master` onto the current branch (must be the latest major version branch). Delegates to `_rebase-to-master.yml`.                                    |
| [`_rebase-to-master.yml`](.github/workflows/_rebase-to-master.yml)                     | Reusable implementation of the above. Backs up `master` first, validates the source branch is the latest major version, then force-pushes `master`.          |
| [`rebase-from-master.yml`](.github/workflows/rebase-from-master.yml)                   | Rebases the current branch onto `master`. Delegates to `_rebase-from-master.yml`.                                                                            |
| [`_rebase-from-master.yml`](.github/workflows/_rebase-from-master.yml)                 | Reusable implementation of the above. Backs up the current branch first, then rebases it onto `master` and force-pushes.                                     |
| [`restore-branch-from-backup.yml`](.github/workflows/restore-branch-from-backup.yml)   | Restores the current branch from its `<branch>-backup` counterpart. Delegates to `_restore-branch-from-backup.yml`.                                          |
| [`_restore-branch-from-backup.yml`](.github/workflows/_restore-branch-from-backup.yml) | Reusable implementation of the above. Force-pushes the `<branch>-backup` ref onto the current branch to restore it.                                          |

#### Required Secrets and Variables

All reusable workflows that use the Valkyrja GitHub App require these to be set
at the organization level:

| Name                       | Type     | Description                                                                                             |
|----------------------------|----------|---------------------------------------------------------------------------------------------------------|
| `VALKYRJA_GHA_APP_ID`      | Secret   | GitHub App ID used to generate short-lived tokens                                                       |
| `VALKYRJA_GHA_PRIVATE_KEY` | Secret   | GitHub App private key                                                                                  |
| `LATEST_MAJOR_VERSION`     | Variable | Current latest major version number (e.g. `26`). Falls back to current year's last two digits if unset. |
| `SUPPORTED_VERSIONS`       | Variable | Regex pattern of supported major versions (e.g. `^(26\|27)$`). Version checks are skipped if unset.     |
| `USER_EMAIL`               | Variable | Git committer email for rebase/cherry-pick operations                                                   |
| `USER_NAME`                | Variable | Git committer name for rebase/cherry-pick operations                                                    |
| `VALKYRJA_REVIEWER`        | Variable | GitHub username to assign and request review from on dependency update PRs. Optional.                   |

### Rulesets

The [`rulesets/`](rulesets/) directory contains exported GitHub branch ruleset
definitions used across Valkyrja repositories.

| Ruleset                                                                                                        | Description                                                                                   |
|----------------------------------------------------------------------------------------------------------------|-----------------------------------------------------------------------------------------------|
| [Protect Against Force Pushes and Deletion](rulesets/Protect%20Against%20Force%20Pushes%20and%20Deletion.json) | Prevents force pushes and branch deletion on version branches (`??.x`)                        |
| [Protect Master At All Times](rulesets/Protect%20Master%20At%20All%20Times.json)                               | Prevents force pushes and deletion on `26.x`                                                  |
| [Protect Release Tags](rulesets/Protect%20Release%20Tags.json)                                                 | Prevents deletion and non-fast-forward updates on version tags (`*.*.*`)                      |
| [Require Pull Request](rulesets/Require%20Pull%20Request.json)                                                 | Requires squash-merge PRs with code owner review on `26.x` and version branches               |
| [Required Commit Message Checks](rulesets/Required%20Commit%20Message%20Checks.json)                           | Requires the commit message check to pass on the default branch and version branches (`??.x`) |
| [Restrict Changes to Unsupported Branches](rulesets/Restrict%20Changes%20to%20Unsupported%20Branches.json)     | Locks backup branches (`*-backup`) against all changes                                        |
| [php/Required Checks](rulesets/php/Required%20Checks.json)                                                     | Requires all PHP CI checks to pass on `26.x` and version branches                             |

[github-special-repo]: https://docs.github.com/en/communities/setting-up-your-project-for-healthy-contributions/creating-a-default-community-health-file

[valkyrja]: https://valkyrja.io

[org-page]: https://github.com/valkyrjaio
