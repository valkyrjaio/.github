# AGENTS.md

**valkyrja `.github`** — the organization's special repo. Files here apply as
**org-wide defaults** across every Valkyrja repository: community health files
(`CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `SECURITY.md`), the
`profile/` org page, reusable GitHub Actions workflows, branch rulesets, and the
project conventions (`REPOSITORY_NAMING.md`, `VOCABULARY.md`).

This is **not** a framework code repo — so only part of the canonical guide
applies.

## Read first

**Cross-language canonical** — <https://github.com/valkyrjaio/architecture/blob/26.x/AGENTS.md>

It governs the parts that **do** apply here: the `[Root] type:` commit / PR-title
format, the branch → commit → push → open-PR workflow (with confirmation before
each write action), the current-working-branch policy (`.github` uses `26.x`),
trailing newlines, American English, and the **shell script conventions**.

That last one carries the most weight in this repo, because this repo holds more
shell than any other. `.github/ci/scripts/` is where the work of a check lives,
and the canonical guide states how a script is written: `[[ ]]` rather than
`[ ]`, a default branch on every `case`, `lower_case` for a local, an array
rather than a string for a list of arguments, and a reason on every suppression.

Warning: SonarCloud and `shellcheck` both read a `.sh` file, and neither reads a
`run:` block. A rule above goes unenforced while the shell sits inline in a
workflow, so moving the shell into a script is what puts it under a linter. See
[Scripts](.github/workflows/README.md#scripts) for how a workflow reaches one,
and for the `set` line each kind of caller needs.

So the logic of a step lives in `.github/ci/scripts/`, and the step names the
script. A workflow takes one of two forms: the `run-script` action, or a `run:`
step that runs the script directly. An action takes the direct form alone, and
it reaches its script through `$ACTION_PATH`. Besides that call, a `run:` block holds glue: a
line or two that moves one value, such as the step that reads the bot user id
into a step output. Warning: one check stays inline whatever it holds. The check
that proves a checkout is the pinned commit reads the tree that holds the
scripts, so a script cannot carry it. The rule, the two forms, the exception,
and the examples are in
[Shell logic belongs in a script](.github/workflows/README.md#shell-logic-belongs-in-a-script).

## What does NOT apply

There is no framework code in this repo, so ignore the framework-specific sections
of the canonical guide: the structure/naming taxonomy (contracts, providers,
throwables, `Abstract\`/`Enum\`/`Contract\` segments, …), provider & binding-key
conventions, 100% line-and-branch code coverage, and the per-language CI gates.

## What this repo holds & its conventions

- **Reusable workflows** live in `.github/workflows/`, are **prefixed with `_`**,
  and carry a `Z Reusable <Title>` `name:` (the `Z` sorts them below the
  user-facing caller workflows in the Actions list). **Language-specific
  workflows put the language token first**, immediately after the `_`:
  `_<lang>-<descriptor>.yml`, where `<lang>` is one of `php`, `ts`, `java`,
  `python`, `go` (e.g. `_go-golangci-lint.yml`, `_java-junit.yml`,
  `_ts-eslint.yml`, `_python-check-outdated-dependencies.yml`). The `name:` title
  mirrors the filename, language first (e.g. `Z Reusable Go golangci-lint`), so
  each language's workflows group together in the list. Language-agnostic
  workflows carry no language token (e.g. `_commit-message-check.yml`,
  `_release.yml`). Naming is enforced by `_ensure-reusable-workflow-names.yml`;
  required presence by `_ensure-workflows.yml`.
- **Never use `secrets: inherit`. Pass each secret the called workflow declares.**
  `inherit` hands the called workflow every secret the repository holds, including
  the secrets it never asked for. A caller that names each secret keeps the grant
  as small as the declaration, and it states its own dependency instead of hiding
  it. This governs a caller in this repo and a caller in every other repo's
  `ci.yml`.

  ```yaml
  # Wrong — the called workflow receives every secret the repository holds.
  markdown-check:
      uses: valkyrjaio/.github/.github/workflows/_markdown-check.yml@<sha>
      secrets: inherit
  ```

  ```yaml
  # Right — the caller names the two secrets that `_markdown-check.yml` declares.
  markdown-check:
      uses: valkyrjaio/.github/.github/workflows/_markdown-check.yml@<sha>
      secrets:
          VALKYRJA_GHA_APP_ID: ${{ secrets.VALKYRJA_GHA_APP_ID }}
          VALKYRJA_GHA_PRIVATE_KEY: ${{ secrets.VALKYRJA_GHA_PRIVATE_KEY }}
  ```

  Read the reusable workflow's own `secrets:` block to find what to pass. Do not
  copy the surrounding jobs: a file that still uses `inherit` predates the rule,
  and matching it repeats the mistake.

- **Community health files** (`CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`,
  `SECURITY.md`) are inherited by every repo that does not override them —
  editing them changes every repo's defaults. GitHub does not support a default
  license file, so `LICENSE.md` applies to this repo alone.
- **Templates** — `.github/PULL_REQUEST_TEMPLATE.md` and `.github/ISSUE_TEMPLATE/`.
- **Rulesets** — the `infra-github` repository defines every ruleset as
  OpenTofu configuration and applies it on merge and on a weekly schedule.
- **Conventions** — `REPOSITORY_NAMING.md` (how repos are named),
  `VOCABULARY.md` (shared terms), and `COPYRIGHT_HEADER.md` (the source file
  header) are authoritative for the whole project.
- The org enforces **trailing newlines** (`_fix-trailing-newlines.yml`) and the
  **`[Root] type:` commit-message format** (`_commit-message-check.yml`) — this
  repo documents those standards and is held to them.

## Extra care

A change here can affect **every repo in the organization**. Keep PRs small and
scoped, and when a workflow, ruleset, or health-file change has cross-repo impact,
call it out in the PR description.

Most relevant roots here: `[Workflow]` (reusable and required workflows),
`[Ruleset]`, `[Template]` (issue and PR templates), `[Process]` (conventions such as
`REPOSITORY_NAMING.md` and `VOCABULARY.md`), and `[Git]`.

**`[GitHub]` is not a root in this repo.** A root is never the repo's own identity,
and this repo _is_ the org's GitHub configuration — so the name says nothing here.
Name the thing instead. `[GitHub]` stays correct in any other repo, where a
GitHub-specific file genuinely stands out.
