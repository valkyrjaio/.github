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
change you want to contribute to the framework all we ask is that you ensure
these few things before submitting a PR:

1. By submitting a PR you grant the project the right to include and distribute
   your written code under the MIT license.

2. Please ensure a PR doesn't already exist that covers your change.

3. PRs with no tests will be ignored, or a comment will be left asking you to
   add tests.

4. PRs must pass all CI checks. Please run all the CI checks locally.

    #### PHP

    1. PHPArkitect: `composer phparkitect`
    2. PHP Code Sniffer: `composer phpcodesniffer`
    3. PHP CS Fixer: `composer phpcsfixer`
    4. PHPStan: `composer phpstan`
    5. PHPUnit: `composer phpunit` or `composer phpunit-coverage` to see that
       you aren't reducing the overall code coverage
    6. Psalm: `composer psalm`
    7. Rector: `composer rector`
    8. If you are changing a composer file please run either
       `composer validate --strict` in root, or
       `composer validate --no-check-publish` for the other composer files

5. Small PRs using atomic, descriptive commits are hugely appreciated as it
   will make reviewing your changes easier for the maintainers.

6. Commit and PR titles should follow the following format:
   `[VALUE] Commit message.`
    1. `[VALUE]` should be the core component you're altering.
        1. Use `[Documentation]` for any documentation changes
        2. Use `[CI]` for any CI related changes
        3. Use `[GitHub]` for any GitHub specific changes
        4. Use `[Git]` for any git related changes
        5. Use `[ModuleName]` for any module changes
           (for example: Container, Http, Cli, etc.)
       6. Use `[Composer]` for composer related changes
       7. Use `[Deprecation]` for any deprecations
       8. Use `[Functions]` for helper function changes
       9. Use `[VERSION.x]` for version specific changes (`[25.x]` for example)
       10. `[Release]` is reserved for releases
    2. End your commit messages with a period
    3. PR titles should not end in a period

### Branches for Code Changes

| Branch    |                                                                                                         |
|-----------|---------------------------------------------------------------------------------------------------------|
| master    | Active development branch, open for backwards incompatible changes and major internal API changes.      |
| `??.x`    | Version maintenance branches. Open for bugfixes only.                                                   |

## Getting Help

If you need help with contributing code you can make an [issue][issues url] and
use a title similar to `[Help] Title for what you need help with`.

[issues url]: https://github.com/valkyrjaio/valkyrja/issues