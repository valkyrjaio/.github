# Valkyrja Copyright Header

This document specifies the standardized copyright header used across all
Valkyrja organization source files. The text is the same in every language
the framework targets (PHP, Java, Go, Python, TypeScript). PHP, Java, Go, and
TypeScript write it as a block comment (`/* ... */`). Python writes the same
text as a line comment (`# ...`).

The first line names the package, and each repository has its own identifier
for it. The two lines that follow it are the same in every repository.

The year is 2016, because the first commit in `valkyrja-php` is from October 2016. Every repository uses that year, including a port that a later year
created, because each port is a translation of the same work. `LICENSE.md`
states the same year.

Template
--------

```
/*
 * This file is part of the {PACKAGE_IDENTIFIER} package.
 *
 * Copyright (c) 2016-present Melech Mizrachi
 *
 * Released under the MIT License. See LICENSE.md for details.
 */
```

`{PACKAGE_IDENTIFIER}` is resolved per repository. See the
[Package Identifier Resolution](#package-identifier-resolution) section
below for the full mapping, and the
[Pattern Rules](#pattern-rules) section for the derivable rules.

Package Identifier Resolution
-----------------------------

| Repository                  | Package Identifier          |
| --------------------------- | --------------------------- |
| `valkyrja-php`              | `Valkyrja Framework`        |
| `valkyrja-java`             | `Valkyrja Framework`        |
| `valkyrja-ts`               | `Valkyrja Framework`        |
| `valkyrja-go`               | `Valkyrja Framework`        |
| `sindri-php`                | `Sindri`                    |
| `sindri-java`               | `Sindri`                    |
| `sindri-ts`                 | `Sindri`                    |
| `sindri-go`                 | `Sindri`                    |
| `valkyrja-starter-app-php`  | `Valkyrja Application`      |
| `valkyrja-starter-app-java` | `Valkyrja Application`      |
| `valkyrja-starter-app-ts`   | `Valkyrja Application`      |
| `valkyrja-starter-app-go`   | `Valkyrja Application`      |
| `project-template-php`      | `Project Template`          |
| `project-template-java`     | `Project Template`          |
| `project-template-go`       | `Project Template`          |
| `project-template-python`   | `Project Template`          |
| `project-template-ts`       | `Project Template`          |
| `valkyrja-docker-php`       | `Valkyrja Docker`           |
| `valkyrja-benchmarking-php` | `Valkyrja Benchmarking`     |
| `ci-psalm-php`              | `Valkyrja Psalm`            |
| `ci-rector-php`             | `Valkyrja Rector`           |
| `ci-phpstan-php`            | `Valkyrja PHPStan`          |
| `ci-phpunit-php`            | `Valkyrja PHPUnit`          |
| `ci-phpcsfixer-php`         | `Valkyrja PHP CS Fixer`     |
| `ci-phparkitect-php`        | `Valkyrja PHPArkitect`      |
| `ci-phpcodesniffer-php`     | `Valkyrja PHP Code Sniffer` |
| `ci-eslint-ts`              | `Valkyrja ESLint`           |
| `ci-spotless-java`          | `Valkyrja Spotless`         |
| `ci-golangcilint-go`        | `Valkyrja golangci-lint`    |
| `ci-ruff-python`            | `Valkyrja Ruff`             |
| `.github`                   | `Valkyrja GitHub`           |
| `architecture`              | `Valkyrja Architecture`     |
| `art`                       | `Valkyrja Art`              |
| `infra-github`              | `Valkyrja GitHub Infra`     |

The table lists each repository that exists now. A new repository takes its
identifier from the [Pattern Rules](#pattern-rules) section. Add a row to the
table when you create the repository.

Every repository is in the table, including one that holds mostly documentation
or art. Such a repository still holds a shell script, a task runner, or a
workflow helper, and that file carries the header as a line comment. This
repository is the example: it ships no language a formatter reads, and its five
shell scripts carried no header until the check reported them. A repository that
holds no program code today still needs an identifier, because the check is
closed by default and the first program file it gains must have one to name.

Pattern Rules
-------------

The resolution table follows eight patterns. New repositories should select
their package identifier based on which pattern applies.

**1. Framework (`valkyrja-{lang}`)** → `Valkyrja Framework`

The framework is language-agnostic in the package identifier — the
language is already implicit in the repo name and the file extension.

**2. Starter application (`valkyrja-starter-{type}-{lang}`)** →
`Valkyrja {Type}`

`{Type}` is title-cased. The `app` type expands to `Application`. The
identifier omits the word `Starter`. The package identifier names what the
package is, and the repository name already records that the application
is a starting point.

**3. Project template (`project-template-{lang}`)** → `Project Template`

No Valkyrja prefix. These are reusable GitHub templates, not
Valkyrja-native projects.

**4. Valkyrja-native project (`valkyrja-{thingy}-{lang}`)** →
`Valkyrja {Thingy}`

`{Thingy}` is title-cased, preserving the tool's official capitalization
where applicable (`OpenSwoole`, `FrankenPHP`, `RoadRunner`, etc.). This
pattern applies to worker integrations, Docker support, benchmarking, and
any other Valkyrja-specific code that integrates with an external tool or
runtime.

**5. CI tool (`ci-{tool}-{lang}`)** → `Valkyrja {Tool}`

`{Tool}` is the tool's official name, preserving its capitalization and
spacing convention (`PHPStan` without a space, `PHP CS Fixer` with
spaces). A tool that spells its own name in lower case keeps that spelling,
so `ci-golangcilint-go` resolves to `Valkyrja golangci-lint`. These
packages ship the rules, the configurations, the custom
expressions, the helper classes, and the reusable workflows that run the
tool. The rules encode Valkyrja's own conventions, so each package is
Valkyrja-native and takes the prefix.

**6. Standalone application (`sindri-{lang}`)** → `Sindri`

No Valkyrja prefix. Sindri is a standalone Norse-mythology-named project
that can be used alongside Valkyrja but is not part of it.

**7. Language-agnostic infrastructure (no language suffix)** →
`Valkyrja {Name}`

`{Name}` is the repository name, title-cased. `.github` keeps the
capitalization that GitHub uses, so it resolves to `Valkyrja GitHub`.
`REPOSITORY_NAMING.md` names these three repositories, and each one is
Valkyrja-native, so each takes the prefix.

**8. Operational infrastructure (`infra-{product}`)** →
`Valkyrja {Product} Infra`

`{Product}` keeps its official capitalization, so `infra-github` resolves to
`Valkyrja GitHub Infra`. The `Infra` suffix keeps the identifier distinct
from `Valkyrja GitHub`, which names the `.github` repository.

Naming Modes
------------

Three conceptual modes govern when to include `Valkyrja` in a package
identifier:

- **Valkyrja-native** → prefixed with `Valkyrja` (framework, starter
  application, worker integrations, docker, benchmarking, CI tool
  packages, language-agnostic infrastructure)
- **Standalone application** → no prefix (Sindri)
- **Reusable template** → no prefix (project templates)

The distinction captures what the package _is_, not who maintains it. A
Valkyrja-native project is one that exists because of Valkyrja and serves
it directly. A CI tool package is Valkyrja-native. The package configures
an independent tool, such as Psalm or PHPStan. The rules that the package
ships are Valkyrja's own conventions. A project template is not
Valkyrja-native, because a repository scaffolded from it does not have to
be a Valkyrja project. A standalone application like Sindri stands on its
own as a distinct project.

Enforcement
-----------

Each language enforces the header with its own formatter or linter, and
each repository configures that tool with its own
`{PACKAGE_IDENTIFIER}`. A language that gains a repository must also gain
a mechanism that enforces the header. No repository relies on a
contributor to add the header by hand.

| Language   | Mechanism                                                              |
| ---------- | ---------------------------------------------------------------------- |
| PHP        | PHP CS Fixer — the `$package` argument to `Rules::getConfig()`         |
| Java       | Spotless — `licenseHeader` in `.github/ci/spotless/build.gradle.kts`   |
| TypeScript | ESLint — the local `copyright-header` rule                             |
| Go         | golangci-lint — `goheader`, with the template in `license-header.txt`  |
| Python     | Ruff — `CPY001`, with `notice-rgx` in `.github/ci/ruff/pyproject.toml` |
| Every file | The reusable `_copyright-header-check.yml` workflow in `.github`       |

Warning: a mechanism that reports a missing header does not always report a
wrong one, and it does not always correct one. PHP CS Fixer, Spotless,
`goheader`, and the ESLint rule compare the whole header. PHP CS Fixer,
Spotless, and the ESLint rule also replace a header that differs. Ruff and
`_copyright-header-check.yml` report a header that does not match, and correct
nothing. `goheader` writes a replacement, but the replacement is not correct.
The next warning gives the detail.

Warning: do not correct a Go header with `golangci-lint run --fix`. The
`goheader` linter writes the expected text, but it also changes the indentation
of the comment. It adds a space to each line after the first, and it removes
the space before the closing `*/`. Correct a Go header by hand.

The damage is quiet, which is what makes it dangerous. `--fix` reports `0
issues` on the file it just broke, and it reports `0 issues` on every later run.
The gate calls `golangci-lint run` without `--fix`, and that command fails on
the same file. A developer therefore reads green on a Mac and red in CI. A
second `--fix` does not repair the indentation, so the file stays broken until a
person edits it. `golangci-lint fmt` also reports nothing, because a formatter
does not read the inside of a comment.

This is what `--fix` writes. Each line after the first carries two spaces, and
the closing `*/` carries none:

```go
// Wrong — `--fix` wrote this, and reported `0 issues`. The gate rejects it.
/*
 * This file is part of the Project Template package.
  *
  * Copyright (c) 2016-present Melech Mizrachi
  *
  * Released under the MIT License. See LICENSE.md for details.
*/
```

This is the form that `goheader` accepts. Write it by hand:

```go
// Right — one space on each line, and one space before the closing `*/`.
/*
 * This file is part of the Project Template package.
 *
 * Copyright (c) 2016-present Melech Mizrachi
 *
 * Released under the MIT License. See LICENSE.md for details.
 */
```

Measured in `project-template-go` with golangci-lint v2.12.2 and go-header
v0.5.0. The `ci` target and the `lint` target in the `Makefile` pass no
`--fix`, so the gate itself does not damage a file.

A formatter reads only the language it formats, so a file in any other language
keeps the header that a person gives it. A shell script is such a file, and it
carries the same text as a line comment. The reusable
`_copyright-header-check.yml` workflow covers every file, whatever its language.
It compares text against text, so it needs no toolchain.

The check is closed by default. It reads every tracked file, and it requires the
header in each file that `EXCLUDED` does not match. A new file therefore fails
the check until a person adds the header, or adds the file to `EXCLUDED`. This
is what a language tool cannot give: a tool that selects files by extension goes
green on a file type nobody taught it about. A caller keeps `IDENTIFIER` and
`EXCLUDED` in `.github/ci/copyright-header/config`, and
`.github/ci/scripts/copyright-header-check.sh` in this repository holds the
check itself.

A file that holds no program code belongs in `EXCLUDED`. A document, a lock
file, a workflow, and a configuration file are such files. A fixture that a test
renders or parses is another, because the header would become part of the output
the test compares.

Warning: a language formatter can skip a file of its own language. PHP CS Fixer
adds no header to a PHP file that opens with inline HTML, because the
`header_comment` fixer has no PHP open tag to anchor to. `valkyrja-php` holds
such a file at `tests/templates/php/page.php`, which is `<p><?php echo $content;
?></p>`. A count of matched files therefore does not prove that the tool acted
on them.

Warning: do not point a PHP tool at a shell script to close this gap. PHP CS
Fixer accepts the file, because a file without a `<?php` tag parses as one
inline-HTML token, and the `header_comment` fixer then has nothing to anchor
to. It reports no error and fixes nothing, so a wrong header passes the check.

Warning: a tool that matches a file by extension also misses a program file
that has no extension. Give the language's own finder that file by name.
`sindri-php` names `bin/sindri`, and `valkyrja-starter-app-php` names
`app/bin/cli` and `app/bin/openswoole`.

The PHP CS Fixer configuration in `ci-phpcsfixer-php` injects the header into
every file. The package holds the header text, and `Rules::getHeader()` builds
the header from a package name. A consuming repository therefore passes its
`{PACKAGE_IDENTIFIER}` value to `Rules::getConfig()`, and states nothing else.
The `$package` argument requires `valkyrja/ci-phpcsfixer` v26.3.0 or later.

Warning: pass the package name, never the assembled header. `getHeader()` puts
the argument into the first line of the header, so an assembled header names the
whole header as the package. PHP CS Fixer then writes that text into every file,
and the check afterwards passes, because the files and the configuration agree
with each other. `getHeader()` rejects a package name that spans more than one
line for that reason, and throws an `InvalidArgumentException`.

```php
return Rules::getConfig($finder, 'Valkyrja Framework');
```

Warning: a tool that injects the header replaces the first comment block
in the file. Point the tool away from any file whose first comment is not
a license header. A static-analysis stub is such a file. A fixture that a
test parses as input is another. Spotless in `sindri-java` and
`valkyrja-java` shows the pattern. It targets `src/test/java`, and it
never targets `src/test/resources`.

Examples
--------

**Framework file (`valkyrja-php/src/Valkyrja/Http/Server/Handler/RequestHandler.php`):**

```php
/*
 * This file is part of the Valkyrja Framework package.
 *
 * Copyright (c) 2016-present Melech Mizrachi
 *
 * Released under the MIT License. See LICENSE.md for details.
 */
```

**Valkyrja-native project file (`valkyrja-benchmarking-php/benchmarking/libs/output.php`):**

```php
/*
 * This file is part of the Valkyrja Benchmarking package.
 *
 * Copyright (c) 2016-present Melech Mizrachi
 *
 * Released under the MIT License. See LICENSE.md for details.
 */
```

**Sindri file (`sindri-php/src/Sindri/Cli/Command/GenerateDataFromConfigCommand.php`):**

```php
/*
 * This file is part of the Sindri package.
 *
 * Copyright (c) 2016-present Melech Mizrachi
 *
 * Released under the MIT License. See LICENSE.md for details.
 */
```

**CI tool file (`ci-phparkitect-php/src/Arkitect/Rules.php`):**

```php
/*
 * This file is part of the Valkyrja PHPArkitect package.
 *
 * Copyright (c) 2016-present Melech Mizrachi
 *
 * Released under the MIT License. See LICENSE.md for details.
 */
```
