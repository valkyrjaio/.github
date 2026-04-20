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
 * Copyright (c) 2025-present Melech Mizrachi
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

| Repository                  | Package Identifier             |
|-----------------------------|--------------------------------|
| `valkyrja-php`              | `Valkyrja Framework`           |
| `valkyrja-java`             | `Valkyrja Framework`           |
| `sindri-php`                | `Sindri`                       |
| `valkyrja-starter-app-php`  | `Valkyrja Starter Application` |
| `valkyrja-starter-app-java` | `Valkyrja Starter Application` |
| `project-template-php`      | `Project Template`             |
| `project-template-java`     | `Project Template`             |
| `valkyrja-openswoole-php`   | `Valkyrja OpenSwoole`          |
| `valkyrja-frankenphp-php`   | `Valkyrja FrankenPHP`          |
| `valkyrja-roadrunner-php`   | `Valkyrja RoadRunner`          |
| `valkyrja-tomcat-java`      | `Valkyrja Tomcat`              |
| `valkyrja-netty-java`       | `Valkyrja Netty`               |
| `valkyrja-jetty-java`       | `Valkyrja Jetty`               |
| `valkyrja-docker-php`       | `Valkyrja Docker`              |
| `valkyrja-benchmarking-php` | `Valkyrja Benchmarking`        |
| `ci-psalm-php`              | `Psalm CI`                     |
| `ci-rector-php`             | `Rector CI`                    |
| `ci-phpstan-php`            | `PHPStan CI`                   |
| `ci-phpunit-php`            | `PHPUnit CI`                   |
| `ci-phpcsfixer-php`         | `PHP CS Fixer CI`              |
| `ci-phparkitect-php`        | `PHPArkitect CI`               |
| `ci-phpcodesniffer-php`     | `PHP Code Sniffer CI`          |

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
`Valkyrja Starter {Type}`

`{Type}` is title-cased. The `app` type expands to `Application`.

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

**5. CI tool (`ci-{tool}-{lang}`)** → `{Tool} CI`

`{Tool}` is the tool's official name, preserving its capitalization and
spacing convention (`PHPStan` without space, `PHP CS Fixer` with spaces).
No Valkyrja prefix. These packages ship rules, configurations, custom
expressions, helper classes, and reusable workflows for running the tool
in a CI/CD context — they are usable in any project that wants similar
CI rules, not only Valkyrjaio org projects.

**6. Standalone application (`sindri-{lang}`)** → `Sindri`

No Valkyrja prefix. Sindri is a standalone Norse-mythology-named project
that can be used alongside Valkyrja but is not part of it.

Naming Modes
------------

Three conceptual modes govern when to include `Valkyrja` in a package
identifier:

- **Valkyrja-native** → prefixed with `Valkyrja` (framework, starter,
  worker integrations, docker, benchmarking)
- **Standalone or external tool** → no prefix (Sindri, CI tools)
- **Reusable template** → no prefix (project templates)

The distinction captures what the package *is*, not who maintains it. A
Valkyrja-native project is one that exists because of Valkyrja and serves
it directly. An external-tool CI package ships rules and helpers for a
tool (Psalm, PHPStan, etc.) that exists independently — even if
Valkyrja-specific rules are embedded, the package itself is fundamentally
a package for that tool. A standalone application like Sindri stands on
its own as a distinct project.

Enforcement
-----------

The PHP CS Fixer configuration in `ci-phpcsfixer-php` automatically
injects this header into every file. Consuming repositories pass their
`{PACKAGE_NAME}` value to `Rules::getConfig()` via the `$header` argument:

```
$header = <<<HEADER
This file is part of the Valkyrja OpenSwoole package.

Copyright (c) 2025-present Melech Mizrachi

Released under the MIT License. See LICENSE.md for details.
HEADER;

return Rules::getConfig($finder, $header);
```

When tooling adds a language port (Java, Go, Python, TypeScript), the
equivalent formatting/linting tool for that language should enforce the
same header structure by way of a shared configuration package following
the same pattern as the PHP CS Fixer setup.

Examples
--------

**Framework file (`valkyrja-php/src/Valkyrja/Http/Kernel.php`):**

```
/*
 * This file is part of the Valkyrja Framework package.
 *
 * Copyright (c) 2025-present Melech Mizrachi
 *
 * Released under the MIT License. See LICENSE.md for details.
 */
```

**Worker integration file (`valkyrja-openswoole-php/src/OpenSwooleHttp.php`):**

```
/*
 * This file is part of the Valkyrja OpenSwoole package.
 *
 * Copyright (c) 2025-present Melech Mizrachi
 *
 * Released under the MIT License. See LICENSE.md for details.
 */
```

**Sindri file (`sindri-php/src/Sindri/Forge/Command.php`):**

```
/*
 * This file is part of the Sindri package.
 *
 * Copyright (c) 2025-present Melech Mizrachi
 *
 * Released under the MIT License. See LICENSE.md for details.
 */
```

**CI tool file (`ci-phparkitect-php/src/Arkitect/Rules.php`):**

```
/*
 * This file is part of the PHPArkitect CI package.
 *
 * Copyright (c) 2025-present Melech Mizrachi
 *
 * Released under the MIT License. See LICENSE.md for details.
 */
```
