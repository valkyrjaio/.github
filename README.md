# Valkyrja GitHub Project

This is the [special `.github` repository][github-special-repo] for the
[Valkyrja][valkyrja] organization. Files placed here apply as defaults across
all repositories in the organization.

## Contents

### Community Health Files

| File                                     | Description                                                |
|------------------------------------------|------------------------------------------------------------|
| [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) | Expected standards of behavior for community members       |
| [CONTRIBUTING.md](CONTRIBUTING.md)       | Guidelines for contributing code, tests, and documentation |
| [LICENSE.md](LICENSE.md)                 | MIT license                                                |

### Organization Profile

[`profile/README.md`](profile/README.md) renders on the
[valkyrjaio organization page][org-page] on GitHub.

### Rulesets

The [`rulesets/`](rulesets/) directory contains exported GitHub branch ruleset
definitions used across Valkyrja repositories.

| Ruleset                                                                                                        | Description                                                                       |
|----------------------------------------------------------------------------------------------------------------|-----------------------------------------------------------------------------------|
| [Protect Against Force Pushes and Deletion](rulesets/Protect%20Against%20Force%20Pushes%20and%20Deletion.json) | Prevents force pushes and branch deletion on version branches (`??.x`)            |
| [Protect Master At All Times](rulesets/Protect%20Master%20At%20All%20Times.json)                               | Prevents force pushes and deletion on `master`                                    |
| [Require Pull Request](rulesets/Require%20Pull%20Request.json)                                                 | Requires squash-merge PRs with code owner review on `master` and version branches |
| [Restrict Changes to Unsupported Branches](rulesets/Restrict%20Changes%20to%20Unsupported%20Branches.json)     | Locks backup branches (`*-backup`) against all changes                            |
| [php/Required Checks](rulesets/php/Required%20Checks.json)                                                     | Requires all PHP CI checks to pass on `master` and version branches               |

[github-special-repo]: https://docs.github.com/en/communities/setting-up-your-project-for-healthy-contributions/creating-a-default-community-health-file

[valkyrja]: https://valkyrja.io

[org-page]: https://github.com/valkyrjaio
