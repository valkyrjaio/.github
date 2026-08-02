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
| `sindri-php`                | `Sindri`                    |
| `sindri-java`               | `Sindri`                    |
| `sindri-ts`                 | `Sindri`                    |
| `valkyrja-starter-app-php`  | `Valkyrja Application`      |
| `valkyrja-starter-app-java` | `Valkyrja Application`      |
| `valkyrja-starter-app-ts`   | `Valkyrja Application`      |
| `project-template-php`      | `Project Template`          |
| `project-template-java`     | `Project Template`          |
| `project-template-go`       | `Project Template`          |
| `project-template-python`   | `Project Template`          |
| `project-template-ts`       | `Project Template`          |
| `valkyrja-openswoole-php`   | `Valkyrja OpenSwoole`       |
| `valkyrja-frankenphp-php`   | `Valkyrja FrankenPHP`       |
| `valkyrja-roadrunner-php`   | `Valkyrja RoadRunner`       |
| `valkyrja-tomcat-java`      | `Valkyrja Tomcat`           |
| `valkyrja-netty-java`       | `Valkyrja Netty`            |
| `valkyrja-jetty-java`       | `Valkyrja Jetty`            |
| `valkyrja-docker-php`       | `Valkyrja Docker`           |
| `benchmark`                 | `Valkyrja Benchmarking`     |
| `ci-psalm-php`              | `Valkyrja Psalm`            |
| `ci-rector-php`             | `Valkyrja Rector`           |
| `ci-phpstan-php`            | `Valkyrja PHPStan`          |
| `ci-phpunit-php`            | `Valkyrja PHPUnit`          |
| `ci-phpcsfixer-php`         | `Valkyrja PHP CS Fixer`     |
| `ci-phparkitect-php`        | `Valkyrja PHPArkitect`      |
| `ci-phpcodesniffer-php`     | `Valkyrja PHP Code Sniffer` |

Repositories that contain only documentation, art, or GitHub configuration
(`.github`, `architecture`, `art`) do not have source files requiring this
header and are not listed above.

Pattern Rules
-------------

The resolution table follows six patterns. New repositories should select
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
spaces). These packages ship the rules, the configurations, the custom
expressions, the helper classes, and the reusable workflows that run the
tool. The rules encode Valkyrja's own conventions, so each package is
Valkyrja-native and takes the prefix.

**6. Standalone application (`sindri-{lang}`)** → `Sindri`

No Valkyrja prefix. Sindri is a standalone Norse-mythology-named project
that can be used alongside Valkyrja but is not part of it.

Naming Modes
------------

Three conceptual modes govern when to include `Valkyrja` in a package
identifier:

- **Valkyrja-native** → prefixed with `Valkyrja` (framework, starter
  application, worker integrations, docker, benchmarking, CI tool
  packages)
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
| PHP        | PHP CS Fixer — the `$header` argument to `Rules::getConfig()`          |
| Java       | Spotless — `licenseHeader` in `.github/ci/spotless/build.gradle.kts`   |
| TypeScript | ESLint — the local `copyright-header` rule                             |
| Go         | golangci-lint — `goheader`, with the template in `license-header.txt`  |
| Python     | Ruff — `CPY001`, with `notice-rgx` in `.github/ci/ruff/pyproject.toml` |
| Every file | The reusable `_copyright-header-check.yml` workflow in `.github`       |

Warning: a mechanism that reports a missing header does not always report a
wrong one, and it does not always correct one. PHP CS Fixer, Spotless,
`goheader`, and the ESLint rule compare the whole header, and the first three
replace a header that differs. Ruff and `_copyright-header-check.yml` report a
header that does not match, and correct nothing.

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

The PHP CS Fixer configuration in `ci-phpcsfixer-php` injects the header
into every file. Consuming repositories pass their
`{PACKAGE_IDENTIFIER}` value to `Rules::getConfig()` via the `$header`
argument:

```php
$header = <<<HEADER
This file is part of the Valkyrja OpenSwoole package.

Copyright (c) 2016-present Melech Mizrachi

Released under the MIT License. See LICENSE.md for details.
HEADER;

return Rules::getConfig($finder, $header);
```

Warning: a tool that injects the header replaces the first comment block
in the file. Point the tool away from any file whose first comment is not
a license header. A static-analysis stub is such a file. A fixture that a
test parses as input is another. Spotless in `sindri-java` and
`valkyrja-java` shows the pattern. It targets `src/test/java`, and it
never targets `src/test/resources`.

Examples
--------

**Framework file (`valkyrja-php/src/Valkyrja/Http/Kernel.php`):**

```php
/*
 * This file is part of the Valkyrja Framework package.
 *
 * Copyright (c) 2016-present Melech Mizrachi
 *
 * Released under the MIT License. See LICENSE.md for details.
 */
```

**Worker integration file (`valkyrja-openswoole-php/src/OpenSwooleHttp.php`):**

```php
/*
 * This file is part of the Valkyrja OpenSwoole package.
 *
 * Copyright (c) 2016-present Melech Mizrachi
 *
 * Released under the MIT License. See LICENSE.md for details.
 */
```

**Sindri file (`sindri-php/src/Sindri/Forge/Command.php`):**

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
