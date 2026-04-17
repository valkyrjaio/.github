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

### Running CI Locally

Valkyrja is implemented across multiple languages, each with their own toolchain
and checks. Run the checks for the language(s) your PR touches before pushing.

PHP is currently the furthest along. Java, Python, Go, and TypeScript ports are
in progress and will have their own CI sections as they come online.

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

_Coming soon._

#### Python

_Coming soon._

#### Go

_Coming soon._

#### TypeScript

_Coming soon._

### Commit and PR Titles

Use the format `[Component] Message.` for commits and `[Component] Message` for
PR titles (no trailing period on PR titles).

**Component tags:**

| Tag               | Use for                                                    |
|-------------------|------------------------------------------------------------|
| `[Documentation]` | Any documentation changes                                  |
| `[CI]`            | CI-related changes                                         |
| `[GitHub]`        | GitHub-specific changes (workflows, templates, etc.)       |
| `[Git]`           | Git-related changes (`.gitignore`, `.gitattributes`, etc.) |
| `[Composer]`      | Composer-related changes                                   |
| `[Functions]`     | Helper function changes                                    |
| `[Deprecation]`   | Any deprecations                                           |
| `[ModuleName]`    | Module changes — e.g. `[Container]`, `[Http]`, `[Cli]`     |
| `[VERSION.x]`     | Version-specific changes — e.g. `[25.x]`                   |
| `[Release]`       | Reserved for releases                                      |

**Good examples:**

- `[Container] Add support for contextual bindings.`
- `[Http] Fix header normalization on HTTP/2 requests.`
- `[Documentation] Document the new RC release process.`
- `[25.x] Backport routing regression fix.`
- `[CI] Split lint and test jobs into parallel workflows.`

**Bad examples:**

- `fix bug` — no component, no detail, no period
- `[http] fix stuff.` — lowercase tag, vague message
- `Add caching.` — missing component tag
- `[Container] Add support for contextual bindings` — missing period (commit
  message)
- `[Container] Add support for contextual bindings.` — trailing period (PR
  title)

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
