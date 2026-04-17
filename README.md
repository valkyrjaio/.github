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

| Workflow                                                                                         | Description                                                                                                                                                                                                                                                                                                                                                |
|--------------------------------------------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| [`_check-outdated-php-dependencies.yml`](.github/workflows/_check-outdated-php-dependencies.yml) | Runs a matrix of Composer scripts to verify all direct dependencies are up to date before a release proceeds.                                                                                                                                                                                                                                              |
| [`_update-php-dependencies.yml`](.github/workflows/_update-php-dependencies.yml)                 | Runs a set of Composer update scripts and syncs version constraints in `require`, `require-dev`, `conflict`, and `suggest` sections across each dependency's `composer.json`. If changes are found, creates or force-updates a `deps/update-dependencies-*` branch and opens a PR (or updates the existing one) against the branch the workflow runs from. |

#### Release Management

| Workflow                                                                         | Description                                                                                                                                                                                                                                                                                                                                      |
|----------------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| [`_get-version-for-release.yml`](.github/workflows/_get-version-for-release.yml) | Computes the next release version from the latest GitHub release tag, based on a `major`/`minor`/`patch` bump input. Forces `MAJOR.0.0` when no releases exist yet for the branch's major version. Validates the result against `SUPPORTED_VERSIONS` and aborts if the tag already exists. Outputs `version`, `major-version`, and `build-date`. |
| [`_get-version.yml`](.github/workflows/_get-version.yml)                         | Computes the next major version number and branch name (e.g. `27` → `27.x`) for creating a new major version branch. Must be run from `master`. Validates the new version against `SUPPORTED_VERSIONS` and aborts if the branch already exists.                                                                                                  |
| [`_update-version-files.yml`](.github/workflows/_update-version-files.yml)       | Checks out the calling repository, updates `VERSION.md` with the new version, and commits the change using the org bot as committer.                                                                                                                                                                                                             |
| [`_create-version-branch.yml`](.github/workflows/_create-version-branch.yml)     | Creates a new major version branch, rewrites `README.md`, `CHANGELOG.md`, and `VERSION.md` for that branch, commits, sets the new branch as the repository default, and updates the `LATEST_MAJOR_VERSION` org variable.                                                                                                                         |
| [`_release.yml`](.github/workflows/_release.yml)                                 | Generates and cleans release notes, updates `CHANGELOG.md`, commits it, creates the GitHub release, and tags the release.                                                                                                                                                                                                                        |

#### Branch Management

| Workflow                                                                               | Description                                                                                                                                                                                 |
|----------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| [`cherry-pick-commits.yml`](.github/workflows/cherry-pick-commits.yml)                 | Manually cherry-picks a commit hash to a target branch. Validates the destination against a configurable branch pattern and creates a backup before picking.                                |
| [`_cherry-pick-commits.yml`](.github/workflows/_cherry-pick-commits.yml)               | Reusable implementation of the above. Inputs: `destination`, `hash`, `valid-branch-pattern`.                                                                                                |
| [`_rebase-to-master.yml`](.github/workflows/_rebase-to-master.yml)                     | Rebases `master` onto the branch the workflow is run from (must be the latest major version branch). Backs up `master` first, validates the source branch major version, then force-pushes. |
| [`_rebase-from-master.yml`](.github/workflows/_rebase-from-master.yml)                 | Rebases the branch the workflow is run from onto `master`. Backs up the branch first, then force-pushes.                                                                                    |
| [`_restore-branch-from-backup.yml`](.github/workflows/_restore-branch-from-backup.yml) | Restores the branch the workflow is run from using its `<branch>-backup` counterpart.                                                                                                       |

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

### Rulesets

The [`rulesets/`](rulesets/) directory contains exported GitHub branch ruleset
definitions used across Valkyrja repositories.

| Ruleset                                                                                                        | Description                                                                       |
|----------------------------------------------------------------------------------------------------------------|-----------------------------------------------------------------------------------|
| [Protect Against Force Pushes and Deletion](rulesets/Protect%20Against%20Force%20Pushes%20and%20Deletion.json) | Prevents force pushes and branch deletion on version branches (`??.x`)            |
| [Protect Master At All Times](rulesets/Protect%20Master%20At%20All%20Times.json)                               | Prevents force pushes and deletion on `master`                                    |
| [Require Pull Request](rulesets/Require%20Pull%20Request.json)                                                 | Requires squash-merge PRs with code owner review on `master` and version branches |
| [Restrict Changes to Unsupported Branches](rulesets/Restrict%20Changes%20to%20Unsupported%20Branches.json)     | Locks backup branches (`*-backup`) against all changes                            |
| [php/Required Checks](rulesets/php/Required%20Checks.json)                                                     | Requires all PHP CI checks to pass on `master` and version branches               |

[github-special-repo]: https://docs.github.com/en/communities/setting-up-your-project-for-healthy-contributions/creating-a-default-community-health-file

[valkyrja]: https://valkyrja.io

[org-page]: https://github.com/valkyrjaio
