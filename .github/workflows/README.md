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
- [Scripts](#scripts)
- [Composite Actions](#composite-actions)
- [Choosing a Workflow or an Action](#choosing-a-workflow-or-an-action)
- [Repository Enforcement](#repository-enforcement)
- [Changing a Required Check Name](#changing-a-required-check-name)
- [Commit Message Rules](#commit-message-rules)
- [Trailing Newline Check](#trailing-newline-check)
- [Markdown Check](#markdown-check)
- [Claude Review](#claude-review)
- [Dependabot](#dependabot)
- [Dependency Updates](#dependency-updates)
- [Auto Merging Bot Pull Requests](#auto-merging-bot-pull-requests)
- [Branch Utilities](#branch-utilities)
- [Cron Behavior](#cron-behavior)
- [Language Templates](#language-templates)
- [Workflow Index](#workflow-index)

---

## Secrets and Variables

### Secrets (org-level)

| Secret                       | Purpose                                                                 |
| ---------------------------- | ----------------------------------------------------------------------- |
| `VALKYRJA_GHA_APP_ID`        | GitHub App ID used to generate short-lived tokens                       |
| `VALKYRJA_GHA_PRIVATE_KEY`   | Private key for the GitHub App                                          |
| `MAVEN_CENTRAL_USERNAME`     | Maven Central (Sonatype) user-token username — publishing Java releases |
| `MAVEN_CENTRAL_PASSWORD`     | Maven Central (Sonatype) user-token password — publishing Java releases |
| `MAVEN_SIGNING_KEY`          | In-memory PGP signing key for Java release artifacts                    |
| `MAVEN_SIGNING_KEY_PASSWORD` | Passphrase for the PGP signing key                                      |
| `GRADLE_PUBLISH_KEY`         | Gradle Plugin Portal API key — publishing a Java Gradle plugin          |
| `GRADLE_PUBLISH_SECRET`      | Gradle Plugin Portal API secret — publishing a Java Gradle plugin       |
| `PYPI_API_TOKEN`             | PyPI API token for Python releases (`uv publish`)                       |
| `CLAUDE_CODE_OAUTH_TOKEN`    | Claude Code OAuth token used by the pull-request review workflow        |

`VALKYRJA_GHA_APP_ID` and `VALKYRJA_GHA_PRIVATE_KEY` must also be registered as
**Dependabot secrets** in org settings so Dependabot PRs can access them.

The `MAVEN_*` and `PYPI_API_TOKEN` secrets are consumed only by the Java and
Python publish workflows respectively, the `GRADLE_PUBLISH_*` secrets only by
`_java-release-plugin-portal-publish.yml`, and `CLAUDE_CODE_OAUTH_TOKEN` only by
`_claude-review.yml`. TypeScript/npm releases use npm
[trusted publishing](https://docs.npmjs.com/trusted-publishers) (OIDC), so no npm
token secret is required.

### Which secrets a caller passes

Every reusable workflow declares the secrets it needs under
`on.workflow_call.secrets`, and every caller passes exactly that list. A caller
never uses `secrets: inherit`, which hands the called workflow every org secret
regardless of need.

| Reusable workflow                         | Secrets to pass                                      |
| ----------------------------------------- | ---------------------------------------------------- |
| `_claude-review.yml`                      | `VALKYRJA_GHA_*` and `CLAUDE_CODE_OAUTH_TOKEN`       |
| `_java-release-maven-publish.yml`         | `MAVEN_CENTRAL_*` and `MAVEN_SIGNING_KEY*`           |
| `_java-release-plugin-portal-publish.yml` | `GRADLE_PUBLISH_KEY` and `GRADLE_PUBLISH_SECRET`     |
| `_python-release-pypi-publish.yml`        | `PYPI_API_TOKEN`                                     |
| `_<lang>-check-outdated-dependencies.yml` | none — omit the `secrets:` key                       |
| `_ts-release-npm-publish.yml`             | none — omit the `secrets:` key                       |
| every other `_*.yml`                      | `VALKYRJA_GHA_APP_ID` and `VALKYRJA_GHA_PRIVATE_KEY` |

The last row covers an orchestrator such as `_php-create-release.yml` too. It
mints no token itself, but the workflows it calls do, so it declares the app
secrets and passes them down.

`GITHUB_TOKEN` never appears in a list. GitHub gives it to a called workflow
automatically, and the `GITHUB_` prefix is reserved, so a workflow cannot declare
it.

Warning: a consumer repo pins `valkyrjaio/.github` by commit SHA. An explicit
list fails with `Invalid input` if the pinned SHA is older than the declaration
it names. Re-pin the repo first, then change the list.

### Variables (org-level)

| Variable               | Example                 | Purpose                                                                                  |
| ---------------------- | ----------------------- | ---------------------------------------------------------------------------------------- |
| `SUPPORTED_VERSIONS`   | `2[6-9]`                | Regex matching supported major versions (used in cherry-pick, ref updates, enforce)      |
| `LATEST_MAJOR_VERSION` | `26`                    | Latest released major version number                                                     |
| `SUPPORTED_LANGUAGES`  | `php java python ts go` | Space-separated language suffixes the release automation iterates over                   |
| `USER_EMAIL`           | `bot@example.com`       | Git committer email for rebase, cherry-pick, and branch operations                       |
| `USER_NAME`            | `Valkyrja Bot`          | Git committer name for rebase, cherry-pick, and branch operations                        |
| `VALKYRJA_REVIEWER`    | `melechmizrachi`        | GitHub username the auto-merge sweep requests a review from when a bot PR needs a person |

---

## Release Process

Releases are triggered manually via **Actions → Create a New Release →
workflow_dispatch** with a `bump` input.

### Bump types

The version format is `YY.FEATURE.PATCH` — `YY` is the two-digit year and moves
only once a year, so the middle component carries both new features and breaking
changes. See
[VERSIONING.md](https://github.com/valkyrjaio/architecture/blob/26.x/VERSIONING.md).

| Bump      | Source branch | Tag format    | Notes                                                            |
| --------- | ------------- | ------------- | ---------------------------------------------------------------- |
| `auto`    | `??.x`        | either        | **Default.** Resolves from the commits merged since the last tag |
| `patch`   | `??.x`        | `v26.0.1`     | Increments patch from latest stable tag                          |
| `feature` | `??.x`        | `v26.1.0`     | Increments the feature component, resets patch                   |
| `yearly`  | `??.x`        | `v26.0.0`     | Always `BRANCH_MAJOR.0.0`                                        |
| `rc`      | `master` only | `v27.0.0-RC1` | Pre-release for next unreleased major                            |

`yearly` and `rc` are **manual only** — a year boundary is a decision, not
something the commit log can express, and the scheduled sweep never dispatches to
`master`.

### How `auto` resolves

`_get-version-for-release` compares the last stable tag for the branch's major
against the branch head and reads the **subject** of each commit. Squash merges
take their subject from the PR title, so the subject is the conventional line.

| Found in the window                               | Result     |
| ------------------------------------------------- | ---------- |
| any `feat`, any `deprecate`, or any type with `!` | `feature`  |
| any other type                                    | `patch`    |
| nothing, or only release-version roots            | no release |

Release bookkeeping is recognised by its release-version root (`[v26.6.1]`), not
by its type — the release run's own commits ship inside the tag they describe, so
a quiet branch has an empty window and the run exits without releasing. When
that happens `should-release` is `false` and every downstream job is skipped;
the workflow still reports success.

If the compare API returns fewer commits than it reports in total, `auto` rounds
**up** to `feature`. Under-bumping would ship a `feat` as a patch, which is worse
than the reverse.

### Scheduled auto releases

`auto-release-supported-versions.yml` divides the day into slots. Each slot
dispatches one action — a dependency refresh or a release — to one cohort of
repositories, on every `??.x` branch whose major matches `SUPPORTED_VERSIONS`.
A release dispatch runs the repo's own `release-new-version.yml` with
`bump: auto`; a refresh runs its `update-dependencies.yml`. Manual dispatch
takes a `slot` to run, plus `dry_run` and a single-`repo` target.

#### The slot plan

The slot table in the caller is the master plan. Each cohort that consumes a
first-party dependency refreshes two hours before it releases, so the hourly
`auto-merge-bot-prs.yml` sweep gets two passes to land the bump pull requests
in between — no run waits on a merge. Each cohort releases hours after the
cohorts it depends on, so every registry has served what the dependency
shipped by the time the dependent refreshes against it. All times are UTC; the
org's clock is America/Phoenix (UTC-7, no DST), so each cron maps to the same
local hour all year.

| Slot (UTC)    | Action         | Cohort             | Why it is here                                                  |
| ------------- | -------------- | ------------------ | --------------------------------------------------------------- |
| 07:00         | release        | infra              | `.github` re-pins workflow refs everywhere; ship that first     |
| 08:00 / 10:00 | deps / release | ci                 | The framework consumes the CI tools                             |
| 11:00 / 13:00 | deps / release | frameworks         | Everything else consumes the framework                          |
| 14:00 / 16:00 | deps / release | sindri             | `sindri` builds against the framework                           |
| 17:00 / 19:00 | deps / release | projects, catchall | The leaf consumers of everything above; unmatched repos go last |

The `infra` cohort releases without a refresh slot, and that is deliberate. No
repository in the cohort has a first-party dependency to gate a release on:
`architecture` and `art` have no dependency workflow, and `.github` carries no
manifest and no outdated-dependency gate. A refresh slot would have nothing to
land.

A cohort is derived from the repository name, per `REPOSITORY_NAMING.md`, with
the language suffix set read from the `SUPPORTED_LANGUAGES` org variable:
`infra` is the closed list `.github`, `architecture`, `art`; `ci-{tool}-{lang}`
is `ci`; `valkyrja-{lang}` is `frameworks`; `sindri-{lang}` is `sindri`;
`valkyrja-starter-{type}-{lang}` and `project-template-{lang}` are `projects`.
A repository that no rule claims runs in `catchall` and is flagged in the run
summary, so it can be given a slot or a rule. Project components such as
`valkyrja-docker-php` and `valkyrja-benchmarking-php` are `catchall` today and
share the `projects` slot pair.

The dispatches inside one release slot go out seconds apart, so every
outdated-dependency gate evaluates before the first sibling publishes — one
cohort member cannot turn another's gate red mid-slot.

Warning: the caller's `on.schedule` cron list and the slot table must name the
same crons. The script fails a scheduled run whose cron the table does not
name, so drift is loud, not silent.

Warning: a failed dispatch or release fails the slot, so the day's plan shows
red where it broke. A wait that times out does not fail the slot — the run it
stopped watching may still finish. A cohort whose gate rejects a stale
dependency self-heals the next day: the morning refresh lands the bump, and
the next release slot ships it.

This ordering is what a release of `@valkyrjaio/sindri` needs. Before it, the
sweep dispatched every repository at once in `gh repo list` order, so `sindri`
released before or after `valkyrja` by chance. When it lost the toss it either
shipped against a stale framework or failed its outdated-dependency gate.

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
authenticates as the GitHub App. The script mints the installation token itself and
re-mints it as it ages, because a minted token lives one hour and a wait on a slow
release can approach that.

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

### Waiting for the package to become available

A publish step finishes before the registry serves the package.
`gradle publishAndReleaseToMavenCentral` returns when the Portal accepts the
deployment, not when `repo1.maven.org` answers for the artifact. PHP has no
publish step at all: `_release.yml` creates the tag, and Packagist indexes it
through a webhook on its own schedule.

That gap is invisible and it corrupts the next release. A dependent asks the
registry for the latest version and reads the previous one. It produces no
dependency bump, so the outdated-dependency gate passes — the installed version
equals the latest version the registry reports. The dependent then releases
against the previous version of its dependency, and no check objects.

So `_wait-for-package-availability.yml` runs after each publish and holds the
release open until the registry answers for the new version. A release is not
complete until another repository can resolve the package. That is the
condition the tiered release sweep depends on.

| Ecosystem   | What the workflow polls                                    |
| ----------- | ---------------------------------------------------------- |
| `maven`     | `repo1.maven.org` for the versioned `.pom`                 |
| `npm`       | `registry.npmjs.org` for the version document              |
| `packagist` | `repo.packagist.org` for the version in the package's list |
| `pypi`      | `pypi.org` for the version's JSON                          |

The version comes from `VERSION.md`, and the package name from the manifest that
the ecosystem uses. Registries disagree about the `v` prefix. Packagist reports
the tag, and Maven Central reports the bare version. The workflow compares every
version without the prefix.

A repository that never published to a registry has nothing to wait for.
`skip-when-unknown` ends the wait for a package the registry does not know. Only
`_php-create-release.yml` asks for it. Every PHP repository reaches that job, and
several are on no registry at all. Without the skip, each of those releases would
stall for the full timeout.

A publish workflow never asks for it. The publish step just uploaded the
package, so an unknown package there means the upload has not landed. The
distinction decides a first release. Maven Central builds `maven-metadata.xml`
during the same sync this waits on. The first version of a new `group:artifact`
therefore has no metadata file yet. Reading that 404 as "does not publish here"
would end the wait at the one moment it matters most.

Warning: a wait that times out fails the job, and the release sweep reads that
as a reason to stop. The release itself already succeeded — the tag, the GitHub
release, and the upload are all done. The failure reports one thing only: the
package is not resolvable yet, so nothing may release against it.

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

| Language   | Publish workflow                          | Credentials                                   |
| ---------- | ----------------------------------------- | --------------------------------------------- |
| PHP        | — (released via tag; no publish workflow) | none                                          |
| Java       | `_java-release-maven-publish.yml`         | `MAVEN_CENTRAL_*`, `MAVEN_SIGNING_KEY*`       |
| Java       | `_java-release-plugin-portal-publish.yml` | `GRADLE_PUBLISH_KEY`, `GRADLE_PUBLISH_SECRET` |
| Python     | `_python-release-pypi-publish.yml`        | `PYPI_API_TOKEN`                              |
| TypeScript | `_ts-release-npm-publish.yml`             | npm trusted publishing (OIDC), no secret      |

Java has two publish workflows, and a repository that publishes a Gradle plugin
calls both. Maven Central receives the jar, which a
`buildscript { classpath(...) }` consumer and a dependency scanner resolve. The
Gradle Plugin Portal receives the plugin marker and the jar, and it is Gradle's
default plugin repository, so a consuming build resolves the plugin with no
`pluginManagement` block. A repository that publishes no plugin calls the Maven
Central workflow alone.

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

Two mechanisms keep those references current, and each one covers a different
side of the boundary. This repository owns the templates, so its release updates
its own references before it makes the tag. Every other repository consumes the
templates from the outside, so a pull request updates it after the release
publishes.

### The release updates this repository's own references

`_release.yml` runs `.github/ci/scripts/update-required-workflow-refs.sh`
before it makes the tag. The script rewrites every
`valkyrjaio/.github/.github/workflows/*@<sha>` reference under
`required-workflows/`, and the release commits the result. The tag then holds a
template that names the workflow code of that same release.

The script names **the last commit that changed the workflow code**, and not a
commit that the release makes. A commit cannot name itself, so the release
cannot pin the commit it is creating. The last workflow-code commit is an
ancestor of every release commit, and no release commit touches the workflow
code, so the script reads the same value at each step of the release.

Two properties follow from that choice:

- A second run finds each reference already correct and writes no file, so a
  re-run of the release produces no second commit.
- A release that changes no workflow code names the commit that is already
  pinned, so it adds no commit at all.

The pinned paths are `.github/workflows/`, `.github/actions/`, and
`.github/ci/`, and Markdown is excluded. A reference loads the workflow file
from the commit it names, and a relative `uses:` inside that file loads from the
same commit. A workflow also checks this repository out at that commit to reach
the composite actions, and an action runs a script from `.github/ci/`. A change
to any of them changes what the reference runs, so each one moves the
references. A Markdown file is documentation that a reference never reaches, so
a change to a document does not move the references.

Warning: the script reads the git history, and `actions/checkout` fetches one
commit. `_release.yml` deepens the checkout first, and the script stops on a
shallow checkout rather than write a wrong reference.

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

- Iterates all non-archived repos in the org. It excludes `.github`, because the
  release above already pinned that repository's own references.
- For each repo: targets all supported `??.x` branches (filtered by
  `SUPPORTED_VERSIONS`). Falls back to `master` only if no supported version
  branches exist in that repo.
- **`master` is intentionally skipped when version branches exist.** Master
  should be kept in sync via rebase or cherry-pick from the version branch —
  not via a direct dependency PR.
- Scans every workflow file for `valkyrjaio/.github/.github/workflows/*@<sha>`.
- Updates the SHA to the latest stable release's commit SHA.
- Creates a PR per base branch, named for the source repo
  (`deps/update-.github-workflow-refs-26.x` for version branches,
  `deps/update-.github-workflow-refs` for master fallback).
- If branch creation or file update is blocked by a ruleset, logs a clean
  message and continues — treats protection as expected, not a failure.
- If a PR already exists for that branch, skips PR creation (does not force
  push).

### Updating refs manually

Run **Actions → Update .github Workflow References → workflow_dispatch** at any
time to force a refresh across all repos.

---

## Scripts

`.github/ci/scripts/` holds the code that a workflow runs. A script in a file is a file a person
reads in an editor, a formatter formats, and a linter reads. Code inside a `run:` block is none of
those things, so put the work in a script and let the workflow name it.

Most of these scripts are shell, and the rule reaches every language. A heredoc that writes a
program to `/tmp` and then runs it hides that program from the same tools, so the program gets its
own file beside the script that calls it. `merge_ci_jobs.py` is such a file, and
`ensure-workflows.sh` names it:

```bash
# The caller runs this script from the workspace root, not from this directory.
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

python3 "$SCRIPT_DIR/merge_ci_jobs.py" /tmp/ci_existing.yml /tmp/ci_template.yml
```

Warning: a script cannot assume the working directory is its own. A `run:` step starts in the
workspace root, and a workflow may check this repository out under a path such as `dot-github`.
Derive the directory from `BASH_SOURCE`, so the sibling is reachable from either one.

The caller decides which case a workflow is in, and each case carries two forms:

- **This repository calls the workflow.** The job checks this repository out, so the script is
  already on disk. The workflow reaches the [`run-script`](#composite-actions) action at
  `./.github/actions/run-script`, or it names the script directly.
- **A consumer repository calls the workflow.** The runner holds the consumer's tree, which does not
  hold this repository's scripts, so the job checks this repository out at `job.workflow_sha` under
  `dot-github`. The workflow then reaches [`run-script`](#composite-actions) at
  `./dot-github/.github/actions/run-script`, or it names
  `dot-github/.github/ci/scripts/<name>.sh` directly.

The org-management workflows are the first case. Each one runs only from this repository:

```yaml
- name: Checkout code
  uses: actions/checkout@<sha>

- name: Ensure reusable workflow names and filenames are correct
  env:
      GH_TOKEN: ${{ steps.generate-token.outputs.token }}
  run: .github/ci/scripts/ensure-reusable-workflow-names.sh
```

Warning: a job that reaches the GitHub API alone still needs the checkout. The org-management jobs
read and write every repository through `gh`, so several of them checked nothing out. A job with no
checkout has no `.github/ci/scripts/` on disk, and the step fails with `No such file or directory`.

Warning: a `run:` block that names no shell runs under `bash -e` alone, so a script that adds `-u`
or `pipefail` does not do what the block did. GitHub runs a different command for each of the two
spellings, and the difference is `pipefail`:

| `shell` value                   | Command GitHub runs                        | Used by                          |
| ------------------------------- | ------------------------------------------ | -------------------------------- |
| unspecified (the Linux default) | `bash -e {0}`                              | every `run:` block in this repo  |
| `bash`                          | `bash --noprofile --norc -eo pipefail {0}` | every step of a composite action |

The [shell documentation](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#jobsjob_idstepsshell)
states this on the default row: "Note that this runs a different command to when `bash` is specified
explicitly."

That table is why the two families of script differ, and neither is the odd one out:

- A script a **bare `run:`** invokes sets `set -e`, because that is the shell that ran the block.
- A script **`run-script`** invokes sets `set -euo pipefail`, because `action.yml` sets `shell: bash`
  and `pipefail` is already on.

So read the shell before you copy a `set` line from a neighboring script. Then check every pipeline:
one that ends in a command which always succeeds hides a failing stage today, and `pipefail` stops
hiding it.

### Shell logic belongs in a script

Warning: `shellcheck` and SonarCloud read a `.sh` file. Neither one reads a workflow file, and
neither one reads an `action.yml`. Every shell rule in the
[canonical guide](https://github.com/valkyrjaio/architecture/blob/26.x/AGENTS.md#shell-scripts)
goes unenforced while the logic sits in a `run:` block, so a defect there ships and no tool reports
it.

So the logic of a step lives in `.github/ci/scripts/<name>.sh`, and the step names that script.
Two forms do that, and both are correct. The [`run-script`](#composite-actions) action proves the
script came from the commit the caller pinned, and it reports what the script wrote. A `run:` step
that names the script directly gives a person the output while the script runs.
[Reaching the script](#reaching-the-script-and-what-run-script-costs) states which form a workflow
takes.

The path to the action follows the path to a script. A workflow that runs from this repository names
`./.github/actions/run-script`, and a workflow that a consumer repository calls names
`./dot-github/.github/actions/run-script` after the second checkout.

A composite action obeys the rule as well, because no linter reads its `action.yml` either. An
action reaches its own script at `"$ACTION_PATH/../../ci/scripts/<name>.sh"`, since an action cannot
assume a working directory.

```yaml
# Wrong — the logic sits in a `run:` block. The `[ ]` test and the `grep` inside it each break a
# rule, and no linter reports either one, because no linter reads this file.
- name: Enable immutable releases
  env:
      GH_TOKEN: ${{ steps.generate-token.outputs.token }}
      ORG: ${{ github.repository_owner }}
      REPO_NAME: ${{ inputs.name }}
  run: |
      if ! ERR=$(gh api --method PUT "repos/$ORG/$REPO_NAME/immutable-releases" 2>&1 >/dev/null); then
          if [ -n "$(echo "$ERR" | grep 'HTTP 409')" ]; then
              echo 'Immutable releases already enforced org-wide; skipping.'
              exit 0
          fi

          echo "$ERR" >&2
          exit 1
      fi
```

```yaml
# Right — the script holds the logic, and the action runs it from the pinned commit.
- name: Enable immutable releases
  env:
      GH_TOKEN: ${{ steps.generate-token.outputs.token }}
      ORG: ${{ github.repository_owner }}
      REPO_NAME: ${{ inputs.name }}
  uses: ./.github/actions/run-script
  with:
      script: enable-immutable-releases.sh
      expected-ref: ${{ job.workflow_sha }}
```

#### What a `run:` block keeps

A `run:` block keeps two things. The first is the call that names a script, which the section above
describes. The second is glue.

Glue is a line or two that moves one value: an environment value that the next step reads, or one
API call that fills a step output. Glue holds no condition, no loop, and no pipeline, so a linter
has nothing to report on it.

```yaml
# Right — the step moves one value into a step output, so it holds no logic.
- name: Get bot user ID
  id: get-bot-user-id
  env:
      GH_TOKEN: ${{ steps.generate-token.outputs.token }}
      APP_SLUG: ${{ steps.generate-token.outputs.app-slug }}
  run: |
      BOT_USER_ID=$(gh api "/users/$APP_SLUG[bot]" --jq '.id')
      echo "user-id=$BOT_USER_ID" >> "$GITHUB_OUTPUT"
```

Warning: `run-script` forwards no step output of its own. It reports `outcome`, `report`, and
`report-markdown`, and a caller reads nothing else from the script. Glue that fills one step output
stays in the `run:` block, which is what the example above does. Logic that must also report a value
takes the direct form, where the script writes to `$GITHUB_OUTPUT` itself.
`checkout-existing-pr-branch.sh` writes `branch` and `is-new` that way.

### Moving a `run:` block into a script

**Take the body from the parsed `run:` value, never from the raw lines of the workflow file.** A
`run: |` key sits at one indent and its content sits further in, and YAML strips the **content**
indent. Dedenting by the key's indent leaves the difference on every line:

```python
# Right — the value YAML hands the runner, whatever the file's indentation is.
import subprocess, yaml

text = subprocess.run(['git', 'show', 'origin/26.x:.github/workflows/_release.yml'],
                      capture_output=True, text=True).stdout
steps = [s for j in yaml.safe_load(text)['jobs'].values() for s in j.get('steps', [])]
body = [s['run'] for s in steps if s.get('name') == 'Update the required workflow refs'][0]
```

Warning: a round trip that re-indents by the same wrong amount agrees with itself and reports
nothing. Three scripts shipped with a two-space over-indent that way, and the check that was supposed
to catch it passed on all three. Compare the file against the parsed value, not against your own
dedent.

A `|` block scalar also **clips** the blank lines at its end, so the runner never receives them. A
body taken from the raw lines carries a trailing blank line the step never had.

### Reaching the script, and what `run-script` costs

Three cases. A caller decides between the first two, and the code decides the third, because an
action reaches a script its own way. The first two cases carry two forms each, and the person who
writes the workflow chooses between them on the criterion below:

| The workflow runs          | The script is reached by                                                                                                                               | Because                                     |
| -------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------- |
| Only from this repository  | `.github/ci/scripts/<name>.sh`, or `run-script` at `./.github/actions/run-script`                                                                      | The default checkout is this repository     |
| From a consumer repository | `dot-github/.github/ci/scripts/<name>.sh`, or `run-script` at `./dot-github/.github/actions/run-script`, after a second checkout at `job.workflow_sha` | The default checkout is the consumer's tree |
| Inside a composite action  | `"$ACTION_PATH/../../ci/scripts/<name>.sh"`                                                                                                            | An action cannot assume a working directory |

Warning: `run-script` **buffers**. It runs `OUTPUT=$("$SCRIPT_PATH" 2>&1)` and prints the result
after the script exits, so a script that reports progress shows nothing until it finishes. A job that
polls for several minutes then looks identical to a job that is stuck. `run-script` also reports
`outcome` and `report-markdown` for a caller that posts a comment and decides the result itself.

The buffering decides the choice, and the exit status does not. `run-script` ends with the status of
the script, so a gate fails its own job through the action as surely as it does from a `run:` block.
Name the script directly when a person reads the output while the script runs. Take the action in
two cases:

- **A check that comments.** The caller builds the comment from `outcome` and `report-markdown`.
- **A step that must prove what it ran.** `expected-ref` fails the step unless the checkout is the
  commit the caller pinned.

---

## Composite Actions

`.github/actions/` holds the building blocks a check is assembled from. A check is a **job**, and a
building block is a **step**, which is why these are actions rather than reusable workflows. A
reusable workflow adds a job, and a job adds a segment to the check name that consumers see and that
rulesets pin. A composite action adds a step to the job that already exists, so the check keeps its
name however the work inside it is arranged.

| Action                                   | Purpose                                                              |
| ---------------------------------------- | -------------------------------------------------------------------- |
| `.github/actions/run-script`             | Runs one script from `.github/ci/scripts/` and reports what it wrote |
| `.github/actions/post-comment`           | Keeps one comment per marker on a pull request                       |
| `.github/actions/post-review-verdict`    | Submits one review that carries the verdict of a Claude review       |
| `.github/actions/resolve-review-threads` | Resolves the review threads an earlier automated review left behind  |

An action cannot fetch the files it is itself made of, so a workflow checks this repository out
before it uses one:

```yaml
- name: Checkout code
  uses: actions/checkout@<sha>

- name: Checkout the CI actions
  uses: actions/checkout@<sha>
  with:
      repository: valkyrjaio/.github
      ref: ${{ job.workflow_sha }}
      path: dot-github

- name: Run the check
  id: check
  continue-on-error: true
  uses: ./dot-github/.github/actions/run-script
  with:
      script: trailing-newline-check.sh
      expected-ref: ${{ job.workflow_sha }}
```

`job.workflow_sha` is the commit the caller pinned, so the actions and the scripts come from the
same commit as the workflow that names them. Nothing needs a reference bump, and the two can never
drift.

Warning: the property is `job.workflow_sha`, on the `job` context. `github.job_workflow_sha` does
not exist, and an expression naming a property no context holds evaluates to an empty string without
raising an error. `actions/checkout` reads an empty `ref` as the default branch, so the wrong name
gives a job that runs unpinned code and reports success. `run-script` takes `expected-ref` and
compares it against the commit it was checked out at, so an empty or wrong value fails the step.

Warning: mark the step that runs a check `continue-on-error: true`, and end the job with a step that
fails on the outcome. Without it a failing script ends the job before the comment is posted, and the
report never reaches the pull request.

---

## Choosing a Workflow or an Action

A reusable workflow is a **job**. A composite action is a **step**. Everything else follows from
that, so decide which one a thing is before deciding where to put it.

Write a reusable workflow when the thing needs something only a job has:

- A **matrix**, such as PHPUnit across several PHP versions.
- Its **own runner**, because it needs a different `runs-on`, or because it must run beside another
  job rather than after it.
- A **name a consumer depends on**. A check name is every job name down the call chain, and
  the `infra-github` configuration pins those names. See
  [Changing a Required Check Name](#changing-a-required-check-name).
- **Several jobs** it orchestrates.

Write a composite action when the thing is a piece of work **inside** somebody else's job:

- A building block a check is assembled from, such as `run-script` or `post-comment`.
- Anything whose only reason to be a job is to hand a value back. A workflow that exists to return
  an output forces every caller into `needs:` plumbing for a string.

Warning: a job boundary is not free. Each one adds a segment to the check name, a row in the pull
request check list, and a runner start. The name is the expensive part: a job added or removed
inside a chain renames the check, and a required check that never reports blocks every pull request
in the organization.

That is what settled the shape of the checks in this repository. `run-script` and `post-comment`
were reusable workflows first, which forced every check into two jobs, which renamed every check,
which would have required a ruleset change for each one. As composite actions they add no job, so a
check keeps its name however its insides are rearranged.

Warning: an action cannot declare `permissions`, and it has no `secrets` context. The calling job
declares the permissions, and a secret reaches an action as an input. Neither is a reason to keep a
workflow — they are the cost of the conversion, and worth knowing before starting one.

A mechanical rule does not finish this decision. Many workflows here _could_ be actions and gain
nothing by it: a job called once from a dispatcher pays a runner start either way, and its name
reaches no ruleset.

Two things decide whether converting one is worth it, and both were learned by trying.

**An action is only cheaper when the caller already holds this repository.** An action reaches the
runner through a checkout, so a caller with no other reason to check this repository out pays about
eight lines of preamble to use one. A reusable workflow that returns a value costs the caller a
four-line job and one `needs:` line. Converting such a workflow therefore makes every caller larger,
not smaller. `_get-version.yml` looked like an obvious candidate — one job, no matrix, existing only
to return two outputs, with eleven callers each writing `needs:` plumbing — and converting it would
have added lines to all eleven.

**A job that calls a reusable workflow cannot hold a step.** A job is `uses:` or `steps:`, never
both, so a caller whose consuming job is itself a `uses:` job cannot host an action at all. Giving
it one means adding a third job to run the action and re-expose its outputs, which restores the
boundary the conversion set out to remove. `_create-version-branch.yml` is such a caller.

So convert when the job boundary costs something specific: a name a ruleset pins, or a building
block used inside a job that already checks this repository out. That is why `run-script` and
`post-comment` were worth converting — not because they were small, but because the job each one
added renamed every check built on it. Leave the boundary alone when it is merely there.

---

## Repository Enforcement

The [`infra-github`](https://github.com/valkyrjaio/infra-github) repository
owns repository settings, rulesets, and labels as OpenTofu configuration. Its
Apply workflow applies the configuration on every merge and on a weekly
schedule. Change a setting, a ruleset, or a label with a pull request there.

### `post-create.yml`

Runs once after `infra-github` creates a repository, on `workflow_dispatch`
with the repository name. It covers the two steps that configuration cannot:

- Rewrites the copyright header package identifier
  (`set-copyright-identifier.sh`), because a template copy keeps the
  template's identifier.
- Enables immutable releases, which has no configuration resource.

The `package-identifier` input overrides the derived identifier —
`COPYRIGHT_HEADER.md` maps every repository to its value.

---

## Changing a Required Check Name

A check name is a public contract. The `infra-github` configuration pins a check by its **exact**
name, and a required check that never reports leaves a pull request pending for good. Renaming a check therefore stops every repository merging
until the ruleset agrees again.

### How a name is built

A check name is every **job** name down the call chain, joined by `/`. A repository's `ci.yml` names
a job, the reusable workflow it calls names another, and so on:

```
Trailing Newline Check  /  Check Trailing Newline
^                          ^
ci.yml job name            job name in _trailing-newline-check.yml
```

Warning: the name of the calling workflow contributes nothing. The workflow above is named `CI`, and
the context is `Trailing Newline Check / Check Trailing Newline`, which is what
the required-checks configuration holds. A context written with a leading `CI /` names a
check GitHub never reports, and a required check that never reports blocks every pull request — the
failure this section exists to prevent. Read the real name from a recent run, or from
`gh pr checks <number>`, rather than composing it by hand.

**Every reusable workflow in the chain adds a segment**, because a reusable workflow is a job. That
is why a building block belongs in [`.github/actions/`](#composite-actions) rather than in a
reusable workflow: a composite action is a step, so it adds no segment, and a check keeps its name
however the work inside it is arranged. Prefer that over a rename.

### The procedure, when a name must change

A consumer repository pins this repository by SHA, so a rename reaches a repository only when its
reference is bumped. No single ruleset state suits every repository while that is in progress, which
is why the ruleset is applied last:

1. Open a pull request that changes the workflow. Merge it.
2. Release this repository.
3. Let the reference bump reach every repository, and merge those pull requests.
4. Open a pull request in `infra-github` that changes the required context to the new name. Its
   merge applies the ruleset.
5. Rebase every open pull request, so each one runs the workflow that reports the new name.

Warning: never merge the `infra-github` pull request before step 3 completes. The ruleset would
require a name that no repository reports yet, and every pull request in the organization would
block.

Warning: a repository must already run the job before the ruleset reaches it. Adding a context for a
check a repository does not have blocks that repository as surely as a rename does. Roll the check
out first, and require it afterwards.

---

## Commit Message Rules

### Format

```
[Root] type: Short description.
```

A **root** in brackets says what the change is about; a **type** says what kind of
change it is. `!` before the colon marks a breaking change, and `(#123)` carries an
issue reference. Full reference:
[COMMIT_CONVENTION.md](https://github.com/valkyrjaio/architecture/blob/26.x/COMMIT_CONVENTION.md).

- Must start with `[` and a root in brackets, followed by a type and a colon.
- **Working-branch commits end with a period.** PR titles and direct pushes to a
  protected branch do not — those are permanent subject lines, not sentences.
- No line may exceed 120 characters.
- Enforced by the `Commit Message Check / Check Commit Message` required check.

The check inspects commits _in a pull request_, which are working-branch commits, and
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

The commit-message check runs as a job of `pr.yml`, and the trailing-newline
check as a job of `ci.yml`. The split follows what each one reads. `pr.yml`
checks pull request metadata — the title and the commit messages — so it
subscribes to `edited`, which is what GitHub reports for a title edit, a
description edit, and the auto-retarget a stacked pull request gets when its
parent merges. `ci.yml` checks file content, which an edit cannot change, so it
does not subscribe to `edited`.

Warning: do not merge the two back together, and do not add a guard that skips
the tools on an edit. A caller job skipped by `if:` produces no `<job> / <job>`
context, so the required status check waits forever and the pull request blocks.
A guard _inside_ the job is worse: it reports success without running the tools,
so editing the description of a red pull request would turn it green. Separately, the `fix-trailing-newlines.yml` cron
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
        secrets:
            VALKYRJA_GHA_APP_ID: ${{ secrets.VALKYRJA_GHA_APP_ID }}
            VALKYRJA_GHA_PRIVATE_KEY: ${{ secrets.VALKYRJA_GHA_PRIVATE_KEY }}
```

---

## Markdown Check

`_markdown-check.yml` runs [Prettier](https://prettier.io) over every Markdown file that the
repository tracks, and fails when a file is not formatted. It runs as a job of `ci.yml`, beside
the trailing-newline check, because it reads file content rather than pull request metadata.

The check exists because Markdown was the one file type no gate read. Every CI tool in every
language repository reads that language's source, so a table whose pipes stopped lining up merged
green, and a person repaired it by hand afterward.

Behavior:

- Names the files with `git ls-files`, never a `**/*.md` glob. The glob also matches a vendored
  document under `vendor/`, `node_modules/`, or a worktree directory, and the check must read only
  what the repository tracks.
- Excludes `CHANGELOG.md`, because the release automation writes it.
- Posts a PR comment on failure that carries the exact fix command and lists every unformatted
  file, and removes the comment when the check passes.
- Pins the Prettier version in this workflow, so one edit here upgrades every repository.

### Configuration

Three settings carry the whole configuration, so no repository needs a Prettier config file:

| Setting                              | Why                                                                                                                                                                    |
| :----------------------------------- | :--------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `--embedded-language-formatting=off` | The default rewrites the code inside every fence whose tag Prettier knows. A document shows what a repository contains, so the formatter must leave the example alone. |
| `--prose-wrap=preserve`              | Keeps every hand-placed line break. Documentation prose is wrapped by sentence and by clause, and a reflow to a fixed width erases that structure.                     |
| `--no-config`                        | Keeps the rules identical in every repository. A repository's own Prettier config governs its other file types, never its Markdown.                                    |

Warning: do not remove `--embedded-language-formatting=off`. Prettier then reformats the JSON and
the YAML examples inside the documents, and each example stops matching the file it describes.

### Running it locally

```bash
git ls-files -z -- '*.md' ':(exclude)*CHANGELOG.md' \
  | xargs -0 npx --yes prettier@3.9.6 \
    --no-config \
    --embedded-language-formatting=off \
    --prose-wrap=preserve \
    --write
```

Replace `--write` with `--list-different` to see what would change without changing it.

### Adding to a consumer repo

```yaml
jobs:
    markdown-check:
        if: github.event_name == 'pull_request'
        uses: valkyrjaio/.github/.github/workflows/_markdown-check.yml@<sha>
        permissions:
            pull-requests: write
            contents: read
        secrets:
            VALKYRJA_GHA_APP_ID: ${{ secrets.VALKYRJA_GHA_APP_ID }}
            VALKYRJA_GHA_PRIVATE_KEY: ${{ secrets.VALKYRJA_GHA_PRIVATE_KEY }}
```

Warning: normalize the repository's Markdown before you add the job. A repository whose documents
were never formatted fails the check on its first pull request.

`Markdown Check / Check Markdown` is a required status check in the `Required Default PR Checks`
ruleset, which `infra-github` defines. A required check that never reports blocks a pull request,
so a repository must have the job before the ruleset reaches it.

---

## Claude Review

`_claude-review.yml` runs [`anthropics/claude-code-action`](https://github.com/anthropics/claude-code-action)
against a pull request and posts its findings as review comments.

A review is **opt in**. It runs only for a pull request that meets all three
conditions:

- The `claude-review` label is on the pull request.
- The `VALKYRJA_REVIEWER` user is the one who applied that label.
- The head branch is in the repository, not in a fork.

Apply the label to ask for a review; remove it to stop. Every condition is
re-checked on each push, so a labeled pull request keeps getting reviewed while
the label stays on, and stops the moment it comes off. Nothing is reviewed
automatically, whoever opens it.

**Apply the label when you open the pull request** — `gh pr create --label
claude-review`, or tick it in the creation form. The review then starts at once,
on the `opened` event.

Warning: applying the label to a pull request that is already open does not start
a review by itself. The trigger does not list `labeled`, because
`anthropics/claude-code-action` rejects that action:

```
track_progress for pull_request events is only supported for actions:
opened, synchronize, ready_for_review, reopened. Current action: labeled
```

`track_progress` is what puts the action in tag mode, and tag mode is what posts
the findings. Without it the action runs and discards its output. So the label is
read on the actions the action does support. To start a review on a pull request
that is already open, apply the label and then push, or close the pull request and
reopen it.

The label carries the request; the `authorize` job carries the identity. The
review spends the reviewer's own Claude subscription, so only that person may
start one — but they may start one on **any** author's pull request, which is the
point of separating "who asked" from "who wrote it". Checking `github.event.sender`
would not work: it names the person who applied the label only on the `labeled`
event itself, and becomes whoever pushed on every later run. So the `authorize`
job reads the pull request timeline and takes the most recent actor to apply the
label, which stays correct across pushes.

Applying a label needs triage permission or above, so a user with read access
cannot ask for a review at all.

A draft is reviewed on request, like any other pull request. The label is the
whole gate, so a draft gets a review when you ask for one and never when you do
not. That is worth having early: a class in the wrong segment costs less to fix
at the third commit than at the thirtieth.

The label bounds the cost by itself. A review runs on every push while the label
is on, so leaving it on a long-lived pull request keeps spending usage. Take the
label off when you have the findings you wanted. Nothing carries a label unless
somebody applies one, so a dependency bump, a ref update, or any other automated
pull request is never reviewed.

The trigger sets no `branches:` filter. That filter matches the **base** branch,
so `[ 'master', '*.x' ]` excluded every pull request that targets another feature
branch — that is, every stacked pull request, which is the kind that most wants a
review. The job conditions already bound who and what gets reviewed, so a
base-branch filter adds nothing here.

Behavior:

- Mints a short-lived token from the `VALKYRJA_GHA_APP_ID` /
  `VALKYRJA_GHA_PRIVATE_KEY` app and passes it as the action's `github_token`,
  so every comment is authored by `valkyrja-volundr[bot]` rather than a personal
  account — the same identity split reviews follow everywhere else.
- Shallow-clones [`valkyrjaio/architecture`](https://github.com/valkyrjaio/architecture)
  into the runner temp directory and grants read access to it via `--add-dir`,
  so the review is judged against the cross-language canonical guide and the
  per-language guide, not just the repo's own thin `AGENTS.md`. The
  `architecture-ref` input selects the ref (default `master`).
- Uses a sticky comment, so re-runs update one comment instead of accumulating.
- Gives the reviewer read-only tools with `--allowedTools`. It reads files,
  greps, runs `git diff` / `git log` / `gh pr diff` / `gh pr view`, reads both
  comment lists on the pull request, and writes its findings as inline comments
  and the sticky comment. **`--allowedTools` adds to the action's defaults, it
  does not replace them**, so `--disallowedTools` is what removes the default
  write tools (`git add`, `git commit`, `git rm`, and the action's push script)
  and the file-editing tools. The push script is matched by a wildcard on
  purpose: its real path contains the action's pinned SHA, and naming that SHA
  here would put the action's version in a second place, where a version bump
  would leave the rule matching nothing and grant push again in silence.
- Cannot run the test suite, the coverage report, or any other CI tool. The
  prompt tells the reviewer to name a branch it believes no test reaches and to
  mark the finding unverified, rather than state a coverage number it cannot
  measure.
- Authenticates to Claude with `CLAUDE_CODE_OAUTH_TOKEN` (org secret), billing
  the Claude subscription rather than API credits.

The `prompt` input overrides the review instructions wholesale; the default asks
for an independent, defect-hunting review against the guides, inline and
concrete, with no praise or restatement of the diff.

### The verdict

`anthropics/claude-code-action` writes each finding with `pulls.createReviewComment`, which posts a
loose review comment. GitHub gathers loose comments into a review of its own, and that review is
always `COMMENTED` with an empty body. So a review that found a blocking defect and a review that
found nothing arrive in the same state, and only the prose tells them apart.

The reviewer therefore reports a verdict, and the workflow turns it into a state and a check:

| Verdict             | Review submitted | `Claude Review / Verdict` |
| :------------------ | :--------------- | :------------------------ |
| `approved`          | `APPROVE`        | passes                    |
| `commented`         | `COMMENT`        | passes                    |
| `changes_requested` | `COMMENT`        | fails                     |
| `errored`           | `COMMENT`        | fails                     |
| none                | `COMMENT`        | fails                     |

`--json-schema` in `claude_args` is what carries the verdict back. It fills the action's
`structured_output`, which the workflow reads with `jq`, so nothing parses the reviewer's prose. The
body of the review ends with `<!-- claude-review-verdict: <verdict> -->`, which reads the verdict
back without parsing prose either.

Warning: no verdict is not an approval. A run whose structured output is empty or malformed reports
`unknown` and fails the check. A contract the reviewer did not meet must never read as a clean
review.

Two jobs report, and they answer different questions. `Claude Review / Claude Review` says whether
the review ran, so a broken runner is red there. `Claude Review / Verdict` says what the review
concluded. Keeping them apart is what lets a person trust a red check: it means a finding, not an
outage. `fail-on-blocking` turns the second one off, and leaves the review state as the only signal.

`blocking-verdict` submits a `changes_requested` verdict as `REQUEST_CHANGES` rather than `COMMENT`.
It is off.

Warning: `REQUEST_CHANGES` blocks the merge until the reviewer approves or somebody dismisses the
review. The `Require Pull Request` ruleset, defined in `infra-github`, blocks on requested changes
even though `required_approving_review_count` is `0` — the count governs approvals, not blocks.
Only a bypass actor merges past it. A wrong finding would hold the pull request until a person
dismissed the review by hand. Turn the input on only when that is the behavior that is wanted.

Warning: keep `Claude Review / Verdict` out of the required checks. A review is opt in, so the job does not
run on a pull request that carries no label, and a required check that never reports blocks the pull
request for good. See [Changing a Required Check Name](#changing-a-required-check-name).

### Findings that an earlier run left behind

A review runs again on every push. GitHub re-anchors an inline comment onto the new head commit
rather than retiring it, so a finding the author has already fixed still reads as outstanding,
against code that no longer exists. Its own `isOutdated` flag does not help: a thread whose diff hunk
is plainly pre-rebase reports `isOutdated: false`, because the re-anchor is what GitHub considers
current.

So each run retires the threads of the run before it, and the reviewer states every finding that is
still outstanding. Each review is then a complete account of the head commit.

The rule needs no judgment from the reviewer. The workflow stamps the time before the review starts,
and afterwards resolves each unresolved thread where every comment is the reviewer's own and every
comment predates the stamp. Two threads are left alone by that rule:

- A thread somebody replied to, because it is a live conversation. The reviewer is told to leave
  that finding to its thread, so the finding is not lost.
- A thread from this run, because the stamp predates it.

Warning: a run that did not complete resolves nothing. It has not replaced the findings of the run
before it, so retiring those threads would drop them and put nothing in their place.

### Adding to a consumer repo

[`required-workflows/claude-review.yml`](../../required-workflows/claude-review.yml)
is a required workflow, so `ensure-workflows.yml` adds it to every repo that is
missing it via a PR, pinned to the latest `.github` release. A repo that already
has the file is left alone. It is a standalone entry point rather than a `ci.yml`
job: a review that comments is not a pass/fail gate and should not sit among the
required status checks that gate merges. `Claude Review / Verdict` reports a
result, and it is reported for a reader rather than for a ruleset.

All three conditions are in the reusable workflow, not in the caller. Every
caller gets them, and a repo cannot spend Claude usage by accident when it wires
the reusable workflow by hand. A change to the conditions also reaches every
repo through the ref repin, so no caller needs an edit.

Warning: a fork pull request cannot run this workflow. GitHub gives no secret to
a workflow that a fork triggers, so the app token and the Claude token are both
absent. The fork condition skips that run. It does not fail the run.

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

## Auto Merging Bot Pull Requests

### `auto-merge-bot-prs.yml`

Trigger: cron (hourly at `:30`) + `workflow_dispatch`.

Sweeps every non-archived repo and merges the bot's own pull requests once they
qualify. Hourly rather than daily because the release sweep at 14:00 fails a
repo outright when a dependency bump is still sitting open — the window between
green and merged is what that failure is made of.

A pull request merges only when **all** of the following hold:

| Gate          | Requirement                                                         |
| ------------- | ------------------------------------------------------------------- |
| Author        | Matches the `bot-login` input exactly, and is a bot                 |
| Title root    | Listed in the `types` input (`Dependency`, `Workflow`)              |
| Base branch   | A `??.x` branch matching `SUPPORTED_VERSIONS` — never `master`      |
| Head branch   | Begins with `deps/`                                                 |
| Changed files | Every path falls inside that type's allowlist                       |
| Status checks | Every context the branch's ruleset requires has concluded `SUCCESS` |
| Draft         | Not a draft                                                         |

Anything else is left open for a human, and the sweep requests a review from
`VALKYRJA_REVIEWER` on it. The generators request no reviewer when they open a
pull request, because a pull request that merges on its own needs nobody's
time. This request is how a person hears about the one that did not.

The sweep requests the review on each pull request it puts in the "needs a
look" table:

- A required status check concluded as a failure.
- A changed path falls outside that type's allowlist.
- The head branch does not begin with `deps/`.
- The base branch requires no status checks at all.
- The merge call itself failed.

The request goes out once. The sweep skips a pull request where the reviewer is
already requested, or has already reviewed, so a broken pull request does not
ping the person on every hourly pass. A dry run requests nobody.

### Path allowlists

The generators commit with `git add -A` after running a package manager, so
nothing upstream bounds which files land in the pull request — whatever the tool
rewrote is what gets committed. The allowlist is the only thing that bounds it,
which is why it is a list of permitted shapes rather than a list of forbidden
ones: a path nobody anticipated blocks the merge instead of riding along with
it, and the sweep fails so someone looks.

| Type         | Permitted paths                                                                                                                             |
| ------------ | ------------------------------------------------------------------------------------------------------------------------------------------- |
| `Workflow`   | `.github/workflows/*.yml`, `required-workflows/**/*.yml`                                                                                    |
| `Dependency` | Any depth: `composer.json`/`.lock`, `package.json`/`package-lock.json`, `build.gradle.kts`, `pyproject.toml`, `uv.lock`, `go.mod`, `go.sum` |

### Why checks are re-verified here

The app holds `bypass_mode: always` on the required-status-check rulesets, so
GitHub will not hold a merge open on its behalf — the ruleset that gates a human
does not gate this sweep. The check gate is therefore applied in the workflow
itself, against the contexts the branch's own ruleset names (read from
`repos/{owner}/{repo}/rules/branches/{branch}`) rather than a list kept here.
Reading the ruleset also keeps advisory checks out of it: SonarCloud, Coveralls,
and Scrutinizer report on these repos without being required, and SonarCloud is
persistently red on Java by way of `java:S110`, so requiring every reported
check to be green would mean nothing ever merged.

### `.github` is excluded

Passed explicitly as `exclude-repos`. This repository is the source every other
repository pins, so a merge here reaches all of them at once — and a bot pull
request against it can rewrite the release workflows that PR CI never exercises.
It keeps a human in the loop.

### Enabling a type, and previewing

`types` and `bot-login` are required inputs with no defaults. A default on
either would decide org-wide, and silently, whose pull requests merge without
review. To add a type, list it in the caller.

Dispatch with `dry_run: true` to see what the sweep would merge without merging
anything, optionally narrowed to one repo with `repo`.

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

| File                                 | Trigger                               | Description                                                           |
| ------------------------------------ | ------------------------------------- | --------------------------------------------------------------------- |
| `ci.yml`                             | `push` / `pull_request`               | Umbrella CI. On PRs runs the trailing-newline and Markdown checks     |
| `release-new-version.yml`            | `workflow_dispatch`                   | Create a new release (patch/minor/major/rc), then repin workflow refs |
| `create-version-branch.yml`          | `workflow_dispatch`                   | Create a new yearly release version branch from `master`              |
| `post-create.yml`                    | `workflow_dispatch`                   | Post-creation steps for a repository `infra-github` created           |
| `ensure-workflows.yml`               | cron (Mon 12:00) + dispatch           | Ensure required workflow files exist across all repos                 |
| `ensure-reusable-workflow-names.yml` | cron (Mon 13:00) + dispatch           | Verify reusable workflow names/filenames follow convention            |
| `fix-trailing-newlines.yml`          | cron (Mon 11:00) + dispatch           | Add missing trailing newlines across all repos via PRs                |
| `update-github-workflow-refs.yml`    | release + cron (Mon 10:00) + dispatch | Pin workflow refs to latest `.github` release SHA                     |
| `update-php-dependencies.yml`        | `workflow_dispatch`                   | Fan out PHP dependency updates across all PHP repos                   |
| `auto-merge-bot-prs.yml`             | cron (hourly :30) + dispatch          | Merge qualifying bot pull requests across all repos                   |
| `cherry-pick-commits.yml`            | `workflow_dispatch`                   | Cherry-pick a commit to a target branch                               |
| `rebase-to-master.yml`               | `workflow_dispatch`                   | Rebase `master` onto the current (latest major) version branch        |
| `rebase-from-master.yml`             | `workflow_dispatch`                   | Rebase the current branch onto `master`                               |
| `restore-branch-from-backup.yml`     | `workflow_dispatch`                   | Restore a branch from its `<branch>-backup` counterpart               |

### Release & version (reusable)

| File                                              | Description                                                                                                   |
| ------------------------------------------------- | ------------------------------------------------------------------------------------------------------------- |
| `_create-release.yml`                             | Orchestrate stable/RC release (version → update files → release)                                              |
| `_release.yml`                                    | Core release logic (notes, changelog, tag)                                                                    |
| `_get-version-for-release.yml`                    | Compute and validate the next release version                                                                 |
| `_get-version.yml`                                | Compute next major version number and branch name                                                             |
| `_update-version-files.yml`                       | Commit updated `VERSION.md`                                                                                   |
| `_create-version-branch.yml`                      | Orchestrate a new version branch (`_get-version` → `_version-branch`)                                         |
| `_version-branch.yml`                             | Create branch, rewrite `README`/`CHANGELOG`/`VERSION`, set default, bump `LATEST_MAJOR_VERSION`               |
| `_{php,java,python,ts}-create-release.yml`        | Per-language release orchestrators (outdated check → version → info files → release). Publishing is separate. |
| `_java-release-maven-publish.yml`                 | Publish Java artifacts to Maven Central (`MAVEN_*` secrets)                                                   |
| `_java-release-plugin-portal-publish.yml`         | Publish a Java Gradle plugin to the Gradle Plugin Portal (`GRADLE_PUBLISH_*` secrets)                         |
| `_python-release-pypi-publish.yml`                | Publish Python package to PyPI (`PYPI_API_TOKEN`)                                                             |
| `_ts-release-npm-publish.yml`                     | Publish TypeScript package to npm (trusted publishing, no token)                                              |
| `_wait-for-package-availability.yml`              | Hold the release open until the registry serves the published version                                         |
| `_{php,java,python,ts}-update-info-files.yml`     | Update `VERSION`/`BUILD_DATE` constants in a language's info file                                             |
| `_{php,java,python,ts}-create-version-branch.yml` | Per-language new-version-branch orchestrators (run check-outdated first)                                      |
| `_{python,ts}-version-branch.yml`                 | Python/TS branch-creation logic (PHP/Java reuse `_version-branch.yml`)                                        |

### Language CI checks (reusable)

| File                          | Description                                                    |
| ----------------------------- | -------------------------------------------------------------- |
| `_commit-message-check.yml`   | Commit message format check (skips Dependabot)                 |
| `_trailing-newline-check.yml` | Trailing newline check; posts/removes PR comment               |
| `_markdown-check.yml`         | Markdown formatting check (Prettier); posts/removes PR comment |
| `_java-spotless.yml`          | Java formatting (Spotless)                                     |
| `_java-errorprone.yml`        | Java static analysis (Error Prone)                             |
| `_java-spotbugs.yml`          | Java static analysis (SpotBugs)                                |
| `_java-archunit.yml`          | Java architecture tests (ArchUnit)                             |
| `_java-junit.yml`             | Java tests (JUnit)                                             |
| `_python-ruff.yml`            | Python lint/format (Ruff)                                      |
| `_python-mypy.yml`            | Python type checking (mypy)                                    |
| `_python-bandit.yml`          | Python security scan (Bandit)                                  |
| `_python-import-linter.yml`   | Python import contracts (import-linter)                        |
| `_python-pytest.yml`          | Python tests (pytest)                                          |
| `_ts-eslint.yml`              | TypeScript lint (ESLint)                                       |
| `_ts-prettier.yml`            | TypeScript formatting (Prettier)                               |
| `_ts-typescript.yml`          | TypeScript type checking (`tsc`)                               |
| `_ts-vitest.yml`              | TypeScript tests (Vitest)                                      |
| `_go-golangci-lint.yml`       | Go lint (golangci-lint)                                        |
| `_go-test.yml`                | Go tests (`go test`)                                           |

### Code review (reusable)

| File                 | Description                                                   |
| -------------------- | ------------------------------------------------------------- |
| `_claude-review.yml` | Claude pull-request review, posted as `valkyrja-volundr[bot]` |

### Dependency management (reusable)

| File                                                    | Description                                                  |
| ------------------------------------------------------- | ------------------------------------------------------------ |
| `_{php,java,python,ts}-check-outdated-dependencies.yml` | Verify all direct dependencies are up to date before release |
| `_{php,java,python,ts}-update-dependencies.yml`         | Run the dependency updater and open/refresh a PR             |
| `_php-update-dependencies-across-repos.yml`             | Trigger `update-dependencies` across all PHP repos           |

### Repository & workflow management (reusable)

| File                                  | Description                                                     |
| ------------------------------------- | --------------------------------------------------------------- |
| `_ensure-workflows.yml`               | Ensure required workflow files across repos (opens PRs)         |
| `_ensure-reusable-workflow-names.yml` | Verify reusable workflow `name:`/filename conventions           |
| `_fix-trailing-newlines.yml`          | Add missing trailing newlines across repos (opens PRs)          |
| `_update-workflow-refs.yml`           | Update workflow SHA pins across all repos (`source-repo` input) |
| `_auto-merge-bot-prs.yml`             | Merge bot pull requests that clear the allowlist and check gate |

### Branch utilities (reusable)

| File                              | Description                                                        |
| --------------------------------- | ------------------------------------------------------------------ |
| `_cherry-pick-commits.yml`        | Cherry-pick logic with branch validation                           |
| `_rebase-to-master.yml`           | Rebase `master` onto the current branch (with backup + validation) |
| `_rebase-from-master.yml`         | Rebase the current branch onto `master` (with backup)              |
| `_restore-branch-from-backup.yml` | Restore branch logic using its backup counterpart                  |
