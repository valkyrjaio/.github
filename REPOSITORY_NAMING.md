# Repository Naming Conventions

This document defines the naming conventions for all repositories in the
Valkyrjaio GitHub organization. Following these conventions keeps the org
listing scannable, makes the purpose of each repo clear from its name alone,
and scales cleanly as new projects and language ports are added.

See also: [`VOCABULARY.md`](./VOCABULARY.md) for the canonical definitions
of Valkyrja terms (app, module, component, tool, etc.) used throughout this
document.

**A note on naming:** Throughout this document, **Valkyrja** refers to the
project, framework, and brand. **Valkyrjaio** is the GitHub organization
handle (derived from the valkyrja.io website, with the dot removed to satisfy
GitHub's org naming rules). When speaking about the project or its repos in
prose, use "Valkyrja." Use "Valkyrjaio" only when specifically referring to
the GitHub org as a GitHub entity. See `VOCABULARY.md` for full definitions.

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
used across multiple Valkyrja projects. The `ci-` prefix signals the repo is
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
any Valkyrja project could consume. If the configuration is specific to one
project, put it in that project's repo instead.

**Note on repeated language:** Names like `ci-phpunit-php` have `php` twice —
once in the tool name, once in the language suffix. This is intentional and
correct. The consistency of the convention outweighs the redundancy.

### 3. Project templates (`project-template-{lang}`)

Starter templates for bootstrapping new projects in the org. These are marked
as "Template repository" in GitHub settings so they can be used with the "Use
this template" button.

**Format:** `project-template-{lang}`

**Examples:**

- `project-template-php`
- `project-template-java`
- `project-template-go`
- `project-template-python`
- `project-template-ts`

**Rule:** One project template per language. Templates are org-level
infrastructure — they're not specific to any single project.

**Note:** If other kinds of templates emerge later (module templates, library
templates, etc.), they follow the same pattern: `{type}-template-{lang}`.
The generic `template-*` namespace is reserved for this extensibility.

### 4. Project repos (`{project}[-{component}]-{lang}`)

Repos that ship actual projects. Valkyrja is the framework itself (the primary
product of the project), and everything else in the org exists to support or
extend it — Sindri (the build tool), starter templates, and the various
third-party integrations.

The distinction between 4a and 4b comes down to a single question: **does the
repo stand on its own, or does it require another Valkyrja project to
function?**

- A repo that is self-contained and usable independently is a **base project**
  (4a). Examples: the Valkyrja framework, the Sindri build tool — each is
  complete on its own, even though they interoperate.
- A repo that requires a base project to function is a **project component**
  (4b). Examples: worker runtime integrations, starter templates, benchmarking
  harnesses, Docker configs — none of these have meaning without their parent
  project.

The `{project}-` prefix on 4b repos names the parent they depend on.

#### 4a. Base project (`{project}-{lang}`)

The main repo for a self-contained project in a given language. A base project
can be cloned, installed, and used as-is without depending on any other
Valkyrja repo.

**Format:** `{project}-{lang}`

**Examples:**

- `valkyrja-php` — the Valkyrja framework in PHP
- `valkyrja-java` — the Valkyrja framework in Java
- `sindri-php` — the Sindri build tool in PHP
- `sindri-java` — the Sindri build tool in Java
- `sindri-ts` — the Sindri build tool in TypeScript

**Rule:** If the repo requires another Valkyrja project to function, it is
not a base project. Use Category 4b instead.

#### 4b. Project component (`{project}-{component}-{lang}`)

A repo that extends, integrates with, or depends on a base project. The
component cannot function on its own — it requires the named parent project
(the `{project}-` prefix) to be useful.

**Format:** `{project}-{component}-{lang}`

**Examples:**

- `valkyrja-openswoole-php` — OpenSwoole worker runtime integration
- `valkyrja-frankenphp-php` — FrankenPHP worker runtime integration
- `valkyrja-roadrunner-php` — RoadRunner worker runtime integration
- `valkyrja-netty-java` — Netty worker runtime integration
- `valkyrja-jetty-java` — Jetty worker runtime integration
- `valkyrja-tomcat-java` — Tomcat worker runtime integration
- `valkyrja-docker-php` — Docker container for running Valkyrja applications
- `valkyrja-benchmarking-php` — benchmarking harness for Valkyrja

**Rule:** The `{component}` name is either the third-party thing being
integrated (OpenSwoole, Netty, Docker) or the role the component plays
(benchmarking). Describe the specifics in the repo's description, not its
name.

**Sub-categories within a component type:** When a component family has
multiple distinct variants (starters of different types, adapters for
different database families, etc.), the variant name goes between the
component type and the language suffix: `{project}-{type}-{variant}-{lang}`.

**Starter templates** are the primary example of this pattern. Valkyrja
distinguishes between several kinds of starter based on what the user is
building. See `VOCABULARY.md` for the definitions of app, module, component,
and tool.

- `valkyrja-starter-app-{lang}` — starter for building an application on
  Valkyrja (HTTP, CLI, RPC, queue worker, or any other runnable form).
- `valkyrja-starter-module-{lang}` — starter for building a self-contained
  feature module that composes multiple components together for drop-in use.
- `valkyrja-starter-component-{lang}` — starter for building a single-purpose
  framework component.
- `valkyrja-starter-tool-{lang}` — starter for building a standalone tool
  on Valkyrja (like Sindri).

### 5. Operational infrastructure (`infra-{product}`)

Repos that hold the configuration and automation that operate the
organization on one product or platform.

- `infra-github` — declarative GitHub organization configuration (settings,
  rulesets, labels, and teams as OpenTofu configuration)

**Rule:** never a language suffix. An infra repo is language-agnostic by
definition — language-specific tooling belongs in `ci-{tool}-{lang}`
(Category 2). One product per repo, so each platform's credentials, state,
and visibility stay separate.

## Decision Rules

When creating a new repo, work through these questions in order:

1. **Is it operational infrastructure for one product or platform?** Does it
   configure or operate the organization on one external product (GitHub, a
   website host)? If yes, use `infra-{product}` (Category 5). If no, continue.

2. **Is it language-agnostic?** Does the content apply to every language port
   with no changes? If yes, no language suffix (Category 1). If no, continue.

3. **Is it shared CI or tooling configuration?** Could multiple Valkyrja
   projects consume this without modification? If yes, use `ci-{tool}-{lang}`
   (Category 2). If no, continue.

4. **Is it a starter template for new projects?** If yes, use
   `project-template-{lang}` (Category 3). If no, continue.

5. **Does it require another Valkyrja project to function?** If yes, use
   `{project}-{component}-{lang}` (Category 4b). If no, use `{project}-{lang}`
   (Category 4a).

## Language Suffixes

Use lowercase, short, unambiguous language identifiers:

| Language   | Suffix   |
| ---------- | -------- |
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

- **Don't use "Valkyrjaio" in repo descriptions, READMEs, or user-facing prose.
  **
  "Valkyrjaio" is the GitHub org handle only — an administrative artifact of
  GitHub's naming rules. Use "Valkyrja" when referring to the project in any
  user-facing context. See `VOCABULARY.md`.

- **Don't give base-project naming (4a) to a repo that requires another
  Valkyrja project to function.** If the repo would be useless without its
  parent, it's a component (4b) and takes the `{project}-` prefix.

- **Don't use alternative vocabulary for Valkyrja concepts.** Valkyrja uses a
  specific vocabulary: **app**, **module**, **component**, and **tool**. These
  words have distinct meanings within the project and should be used
  consistently in repo names and documentation. See `VOCABULARY.md` for full
  definitions and for the complete list of terms to avoid (Symfony's "bundle,"
  Laravel's "package," WordPress's "plugin," etc.).

## Current Organization State

All repos in the Valkyrjaio organization follow the conventions defined above.
Every repo either ends with a language suffix or is legitimately
language-agnostic: `.github`, `architecture`, `art`, and the `infra-{product}`
repos.

| Category               | Examples                                                                     |
| ---------------------- | ---------------------------------------------------------------------------- |
| Language-agnostic (1)  | `.github`, `architecture`, `art`                                             |
| Operational infra (5)  | `infra-github`                                                               |
| CI tooling (2)         | `ci-phpstan-php`, `ci-phpunit-php`, `ci-rector-php`                          |
| Project templates (3)  | `project-template-php`, `project-template-java`                              |
| Project base (4a)      | `valkyrja-php`, `valkyrja-java`, `sindri-php`                                |
| Project component (4b) | `valkyrja-openswoole-php`, `valkyrja-starter-app-php`, `valkyrja-docker-php` |

This table is illustrative, not exhaustive. See the Valkyrjaio organization
page on GitHub for the complete repo listing.

## Renames

Repository renames on GitHub preserve URL redirects indefinitely, so renaming
an established repo is safe for anyone clicking old links. However:

- Package names on Packagist, Maven Central, and other language-specific
  package registries are independent of GitHub repo names and do not change
  when a GitHub repo is renamed. Packages are named after what they are
  (`valkyrja/valkyrja` on Packagist is the framework), decoupling distribution
  identity from GitHub organization.
- `composer.json` `homepage` and `support.source` fields (and their equivalents
  in `pom.xml`, `package.json`, etc.) that reference the GitHub URL will
  continue to work via redirect, but should be updated when convenient.
- Local git remotes continue to work via redirect, but should be updated:

```
  git remote set-url origin git@github.com:valkyrjaio/{new-name}.git
```
