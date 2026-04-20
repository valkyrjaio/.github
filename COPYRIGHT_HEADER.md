Copyright Header
----------------

All source files in Valkyrja organization repos should include the following
header at the top:

```
/*
 * This file is part of the {PACKAGE_NAME} package.
 *
 * Copyright (c) 2025-present Melech Mizrachi
 *
 * Released under the MIT License. See LICENSE.md for details.
 */
```

`{PACKAGE_NAME}` is the human-readable project name. For reference:

- Valkyrja framework: `Valkyrja Framework`
- Sindri build tool: `Sindri`
- Worker runtime integrations: `Valkyrja OpenSwoole`, `Valkyrja FrankenPHP`,
  `Valkyrja RoadRunner`
- Starter applications: `Valkyrja Starter Application`, etc.
- CI tool configurations: `Valkyrja PHPStan`, `Valkyrja PHP CS Fixer`, etc.

The header applies identically across all languages (PHP, Java, Go, Python,
TypeScript, etc.) — the block comment syntax (`/* ... */`) works in every
language the framework targets.

The PHP CS Fixer configuration in `ci-phpcsfixer-php` automatically injects
this header into every file; applications consuming that configuration
should pass their own `{PACKAGE_NAME}` string to the `Rules::getConfig()`
`$header` parameter.
