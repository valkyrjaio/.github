# Valkyrja Copyright Header

This document specifies the standardized copyright header used across all
Valkyrja organization source files. The header applies identically across
every language the framework targets (PHP, Java, Go, Python, TypeScript)
since the block comment syntax (`/* ... */`) is shared.

Template
--------

```
/*
 * This file is part of the {PACKAGE_IDENTIFIER} package.
 *
 * (c) Melech Mizrachi <melechmizrachi@gmail.com>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
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

| Language   | Mechanism                                                            |
| ---------- | -------------------------------------------------------------------- |
| PHP        | PHP CS Fixer — the `$header` argument to `Rules::getConfig()`        |
| Java       | Spotless — `licenseHeader` in `.github/ci/spotless/build.gradle.kts` |
| TypeScript | ESLint — the local `copyright-header` rule                           |

The PHP CS Fixer configuration in `ci-phpcsfixer-php` injects the header
into every file. Consuming repositories pass their
`{PACKAGE_IDENTIFIER}` value to `Rules::getConfig()` via the `$header`
argument:

```php
$header = <<<HEADER
This file is part of the Valkyrja OpenSwoole package.

(c) Melech Mizrachi <melechmizrachi@gmail.com>

For the full copyright and license information, please view the LICENSE
file that was distributed with this source code.
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
 * (c) Melech Mizrachi <melechmizrachi@gmail.com>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */
```

**Worker integration file (`valkyrja-openswoole-php/src/OpenSwooleHttp.php`):**

```php
/*
 * This file is part of the Valkyrja OpenSwoole package.
 *
 * (c) Melech Mizrachi <melechmizrachi@gmail.com>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */
```

**Sindri file (`sindri-php/src/Sindri/Forge/Command.php`):**

```php
/*
 * This file is part of the Sindri package.
 *
 * (c) Melech Mizrachi <melechmizrachi@gmail.com>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */
```

**CI tool file (`ci-phparkitect-php/src/Arkitect/Rules.php`):**

```php
/*
 * This file is part of the Valkyrja PHPArkitect package.
 *
 * (c) Melech Mizrachi <melechmizrachi@gmail.com>
 *
 * For the full copyright and license information, please view the LICENSE
 * file that was distributed with this source code.
 */
```
