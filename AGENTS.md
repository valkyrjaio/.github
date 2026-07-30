# AGENTS.md

**valkyrja `.github`** — the organization's special repo. Files here apply as
**org-wide defaults** across every Valkyrja repository: community health files
(`CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `SECURITY.md`, `LICENSE.md`), the
`profile/` org page, reusable GitHub Actions workflows, branch rulesets, and the
project conventions (`REPOSITORY_NAMING.md`, `VOCABULARY.md`).

This is **not** a framework code repo — so only part of the canonical guide
applies.

## Read first

**Cross-language canonical** — <https://github.com/valkyrjaio/architecture/blob/master/AGENTS.md>

It governs the parts that **do** apply here: the `[Root] type:` commit / PR-title
format, the branch → commit → push → open-PR workflow (with confirmation before
each write action), the current-working-branch policy (`.github` uses `26.x`),
trailing newlines, and American English.

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
- **Community health files** (`CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`,
  `SECURITY.md`, `LICENSE.md`, `COPYRIGHT_HEADER.md`) are inherited by every repo
  that does not override them — editing them changes every repo's defaults.
- **Templates** — `.github/PULL_REQUEST_TEMPLATE.md` and `.github/ISSUE_TEMPLATE/`.
- **Rulesets** — `rulesets/` holds exported GitHub branch rulesets applied
  org-wide via the repo-management workflows.
- **Conventions** — `REPOSITORY_NAMING.md` (how repos are named) and
  `VOCABULARY.md` (shared terms) are authoritative for the whole project.
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
and this repo *is* the org's GitHub configuration — so the name says nothing here.
Name the thing instead. `[GitHub]` stays correct in any other repo, where a
GitHub-specific file genuinely stands out.
