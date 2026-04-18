# Repository Naming Conventions

This document defines the naming conventions for all repositories in the
Valkyrjaio GitHub organization. Following these conventions keeps the org
listing scannable, makes the purpose of each repo clear from its name alone,
and scales cleanly as new projects and language ports are added.

## Current Organization State

All repos in the Valkyrjaio organization follow the conventions defined above.
Every repo either ends with a language suffix or is one of the three
legitimately language-agnostic exceptions (`.github`, `architecture`, `art`).

| Category                 | Examples                                                                                    |
|--------------------------|---------------------------------------------------------------------------------------------|
| Language-agnostic (1)    | `.github`, `architecture`, `art`                                                            |
| CI tooling (2)           | `ci-phpstan-php`, `ci-phpunit-php`, `ci-rector-php`                                         |
| Project templates (3)    | `project-template-php`, `project-template-java`                                             |
| Project base (4a)        | `valkyrja-php`, `sindri-php`, `application-java`                                            |
| Project integration (4b) | `valkyrja-openswoole-php`, `valkyrja-netty-java`, `valkyrja-docker-php`                     |

This table is illustrative, not exhaustive. See the Valkyrjaio organization
page on GitHub for the complete repo listing.

## Core Principle

Every repo name encodes three things (where applicable):

1. **Category** — what kind of repo this is
2. **Identity** — which project or tool this repo is for
3. **Language** — which language implementation this repo targets

Language is always the suffix. Category (when present) is always the prefix.
Identity sits in the middle.

## Repository Categories

Repos in the org fall into one of four categories.

### 1. Language-agnostic infrastructure (no suffix)

Repos that genuinely span all languages and projects. These are the only repos
without a language suffix.

- `.github` — GitHub-mandated name for org-wide community health files and
  shared workflows
- `architecture` — cross-language design decisions, roadmaps, and port planning
- `art` — logos, banners, and shared branding assets

**Rule:** If adding a new repo here, it must be genuinely language-agnostic.
If there's any chance it becomes language-specific, use a different category.

### 2. CI and shared tooling (`ci-{tool}-{lang}`)

Repos that ship shared CI configuration, linting rules, and tooling conventions
used across multiple projects in the org. The `ci-` prefix signals the repo is
shared infrastructure rather than project-specific code.

**Format:** `ci-{tool}-{lang}`

**Examples:**

- `ci-rector-php`
- `ci-psalm-php`
- `ci-phpstan-php`
- `ci-phpunit-php`
- `ci-phpcodesniffer-php`
- `ci-phpcsfixer-php`
- `ci-phparkitect-php`
- `ci-archunit-java` _(future)_
- `ci-checkstyle-java` _(future)_
- `ci-errorprone-java` _(future)_
- `ci-junit-java` _(future)_
- `ci-spotbugs-java` _(future)_

**Rule:** Use this category when the repo contains configuration or rules that
any project in the org could consume. If the configuration is specific to one
project, put it in that project's repo instead.

**Note on repeated language:** Names like `ci-phpunit-php` have `php` twice —
once in the tool name, once in the language suffix. This is intentional and
correct. The consistency of the convention outweighs the redundancy.

### 3. Project templates (`template-{lang}`)

Starter templates for bootstrapping new projects in the org. These are marked
as "Template repository" in GitHub settings so they can be used with the "Use
this template" button.

**Format:** `template-{lang}`

**Examples:**

- `template-php`
- `template-java`

**Rule:** One template per language. Templates are org-level infrastructure —
they're not specific to any single project.

### 4. Project repos (`{project}[-{integration}]-{lang}`)

Repos that ship actual projects — frameworks, applications, build tools, and
their integrations with third-party runtimes.

#### 4a. Base project (`{project}-{lang}`)

The main repo for a project in a given language.

**Format:** `{project}-{lang}`

**Examples:**

- `valkyrja-php`
- `valkyrja-java`
- `sindri-php`
- `sindri-java` _(future)_
- `application-php`
- `application-java`

#### 4b. Project integration (`{project}-{integration}-{lang}`)

A repo that ships an integration between a project and a specific third-party
runtime, library, or service. The integration name sits between the project
name and the language suffix.

**Format:** `{project}-{integration}-{lang}`

**Examples:**

- `valkyrja-openswoole-php`
- `valkyrja-frankenphp-php`
- `valkyrja-roadrunner-php`
- `valkyrja-netty-java`
- `valkyrja-jetty-java`
- `valkyrja-tomcat-java`
- `valkyrja-docker-php`

**Rule:** The integration name is the third-party thing being integrated
(OpenSwoole, Netty, Docker), not a description of what the integration does.
Describe the role of the integration in the repo's description, not its name.

## Decision Rules

When creating a new repo, work through these questions in order:

1. **Is it language-agnostic?** Does the content apply to every language port
   with no changes? If yes, no language suffix (Category 1). If no, continue.

2. **Is it shared CI or tooling configuration?** Could multiple projects in the
   org consume this without modification? If yes, use `ci-{tool}-{lang}`
   (Category 2). If no, continue.

3. **Is it a starter template for new projects?** If yes, use `template-{lang}`
   (Category 3). If no, continue.

4. **Is it an integration with a specific third-party thing?** If yes, use
   `{project}-{integration}-{lang}` (Category 4b). If no, use `{project}-{lang}`
   (Category 4a).

## Language Suffixes

Use lowercase, short, unambiguous language identifiers:

| Language   | Suffix   |
|------------|----------|
| PHP        | `php`    |
| Java       | `java`   |
| Python     | `python` |
| Go         | `go`     |
| TypeScript | `ts`     |

These match the file extensions and community norms for each language.

## What Not to Do

- **Don't put the language before the project name.** Use `valkyrja-java`, not
  `java-valkyrja`. Project identity comes first; language is a qualifier.

- **Don't use uppercase or CamelCase in repo names.** Everything is lowercase
  with hyphens: `valkyrja-php`, not `Valkyrja-PHP`.

- **Don't use underscores as separators.** Hyphens only:
  `valkyrja-openswoole-php`, not `valkyrja_openswoole_php`.

- **Don't skip the language suffix on project repos "because it's obvious."**
  It's obvious to you today. It won't be obvious to contributors six months
  from now, and it breaks the convention's consistency.

- **Don't add project prefixes to shared CI or tooling repos.** A repo named
  `valkyrja-ci-rector-php` would imply the config is Valkyrja-specific when
  it's actually shared across all projects in the org.

- **Don't create new top-level category prefixes lightly.** `ci-` earns its
  place because there's a large, well-defined category of shared tooling. New
  prefixes should meet the same bar: they represent a real category with
  multiple repos, not a one-off.

## Renames

Repository renames on GitHub preserve URL redirects indefinitely, so renaming
an established repo is safe for anyone clicking old links. However:

- Packagist package names are independent of GitHub repo names and do not need
  to change when a GitHub repo is renamed.
- Composer `composer.json` `homepage` and `support.source` fields that
  reference the GitHub URL will continue to work via redirect, but should be
  updated when convenient.
- Local git remotes continue to work via redirect, but should be updated:
