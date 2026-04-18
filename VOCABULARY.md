# Valkyrja Vocabulary

This document defines the canonical vocabulary used throughout the Valkyrja
project. It exists so that terms like "component," "module," and "app" have
consistent meaning across all Valkyrja repos, documentation, READMEs, PR
descriptions, issue discussions, and code comments — regardless of which
language implementation is under discussion.

When Valkyrja vocabulary conflicts with a host language community's
conventions, Valkyrja vocabulary wins inside Valkyrja contexts. For example,
Java's built-in module system (JPMS) uses the word "module" differently than
Valkyrja does. Inside Valkyrja, "module" means what this document says it
means.

See also: [`REPOSITORY_NAMING.md`](./REPOSITORY_NAMING.md) for how these terms
map to repository names.

## Brand and Organization Terms

### Valkyrja

The project, the framework, and the brand. When referring to the project in
prose, documentation, or conversation, use **Valkyrja**. This is the name
people search for, recognize, and reference.

Pronounced "Valk-ear-ya." From Old Norse for "Valkyrie."

### Valkyrjaio

The GitHub organization handle at `github.com/valkyrjaio`. Derived from the
`valkyrja.io` domain with the dot removed, because GitHub does not allow
dots in organization names. **Valkyrjaio is not a brand name.** It is an
administrative artifact of GitHub's naming rules. Do not use "Valkyrjaio" in
repo descriptions, READMEs, user-facing documentation, or marketing material.
Use "Valkyrja" instead.

Valid use of "Valkyrjaio": "the Valkyrjaio GitHub organization,"
"github.com/valkyrjaio," references to the org as a GitHub entity.

Invalid use of "Valkyrjaio": "Valkyrjaio PHP projects," "the Valkyrjaio
framework," anything that treats it as a brand.

### valkyrja.io

The project's website. The canonical public home for documentation, news,
and project information.

## Project-Level Terms

### Framework

The Valkyrja framework itself — the core product of the project. When someone
says "Valkyrja," they most commonly mean the framework. The framework is a
base project (see `REPOSITORY_NAMING.md` Category 4a) and is self-contained:
it can be used without any other Valkyrja repo.

Published as `valkyrja/valkyrja` on Packagist.

### Sindri

The Valkyrja build tool and application creator. Sindri is a base project
that interoperates with Valkyrja but can be used independently. Sindri handles
project scaffolding, builds, compilation targets, and build-time concerns.

Named after the dwarven smith in Norse mythology who forged divine artifacts
(including Mjölnir), paired thematically with Valkyrja.

Published as `valkyrja/sindri` on Packagist.

## Code-Level Terms

These terms describe what users *build* with Valkyrja and how Valkyrja's own
code is organized. Using them consistently across all repos, languages, and
documentation is critical.

Each term below includes:

- **Definition** — what the thing is
- **Examples** — concrete instances
- **Consumed by** — what uses this kind of thing
- **Built from** — what this kind of thing is composed of
- **Starter repo** — the corresponding starter template (if applicable)

### App

A complete, runnable application built on Valkyrja. An app is the top-level
thing that gets deployed — it has an entry point, routing or command
registration, configuration, and all the glue needed to serve requests, run
commands, or process work.

Apps take many forms:

- HTTP apps serving web requests
- CLI apps running commands
- RPC apps serving gRPC or similar protocols
- Queue workers processing background jobs
- Any other runnable form

Valkyrja's own codebase uses the `App` namespace for this layer, which is why
the term is "app" rather than "application" in Valkyrja contexts.

- **Consumed by:** end users (deployed to production)
- **Built from:** modules, components, custom code
- **Starter repo:** `valkyrja-starter-app-{lang}`

### Module

A self-contained, installable package that composes multiple components into
a drop-in feature for apps. A module provides complete functionality — not a
building block, but a finished capability that an app consumes.

Examples of what a module looks like:

- An auth module (composes user management, session handling, permissions,
  password hashing)
- A billing module (composes payment processing, subscription management,
  invoicing)
- An admin panel module (composes routing, views, authorization, UI)

Key distinction from a component: a module brings together many pieces to
deliver a user-facing feature. A component is a single piece.

- **Consumed by:** apps
- **Built from:** components, other modules, custom code
- **Starter repo:** `valkyrja-starter-module-{lang}`

### Component

A single-focused piece of framework functionality. Components are the narrow
building blocks that compose into modules and apps. A component does one
thing and exposes a clean interface for other code to use it.

Examples of components within Valkyrja:

- The container component (dependency injection)
- The CLI component (command-line parsing and dispatch)
- The HTTP component (request/response handling)
- The ORM component (database access and mapping)
- The event component (event dispatch)

Key distinction from a module: a component is narrow and focused. A module
composes components to deliver user-facing functionality.

- **Consumed by:** apps, modules, other components
- **Built from:** custom code, other components
- **Starter repo:** `valkyrja-starter-component-{lang}`

### Tool

A standalone executable built on Valkyrja. Tools run on their own — they are
not a framework layer inside an app. Sindri is the canonical example: it
consumes Valkyrja but is not an app serving requests. It is a CLI utility
with its own purpose, invoked by developers or operators when needed.

Key distinction from an app: an app is typically long-running (serving
requests, processing queues) or user-facing in production. A tool is
typically invoked for a specific task, usually by developers or operators
rather than end users.

- **Consumed by:** developers, operators, CI pipelines
- **Built from:** components, custom code
- **Starter repo:** `valkyrja-starter-tool-{lang}`

### Library

_Reserved term. The specific definition for "library" in Valkyrja vocabulary
has not yet been established. When we ship the first library, this entry
will be filled in with the concrete definition. Until then, do not use
"library" as a formal Valkyrja term — use app, module, component, or tool
depending on which best fits._

## Terms to Avoid

These terms come from other framework ecosystems and should not be used for
Valkyrja concepts, even when the underlying idea is similar. Using
ecosystem-specific vocabulary dilutes Valkyrja's own terminology and creates
confusion as the project ports to more languages.

- **Bundle** — Symfony's term for what we call a module. Do not use.
- **Package** — generic term used loosely across ecosystems. Avoid except
  when referring specifically to Packagist, Maven, npm, or similar
  distribution units (e.g., "the `valkyrja/valkyrja` Packagist package").
- **Plugin** — WordPress/Laravel-adjacent term that overlaps with component
  and module ambiguously. Do not use; specify component or module instead.
- **Extension** — ambiguous term that could mean component, module, or
  something else. Do not use; specify.
- **Skeleton** — Symfony's term for what we call an app starter. Do not use;
  use "starter" or "starter template."
- **Kernel** — Symfony's term for the framework's bootstrap/entry layer. Do
  not use; Valkyrja uses its own vocabulary for these concepts.
- **Service provider** — Laravel's term for part of the container component's
  registration layer. Do not use as a general concept name; if referring to
  the specific mechanism, name it explicitly.
- **Facade** — Laravel's term for a static-access wrapper around services.
  Valkyrja does not use facades; if a similar pattern appears, give it a
  Valkyrja-specific name.

## Repository Terms

These terms describe the repos themselves, as distinct from the code inside
them.

### Base project

A repo that can be used independently, without requiring any other Valkyrja
repo to function. Examples: the framework itself, Sindri. See
`REPOSITORY_NAMING.md` Category 4a.

### Project component (repo sense)

A repo that requires a base project to function. Examples: worker runtime
integrations, starter templates, benchmarking harnesses, Docker configs.
See `REPOSITORY_NAMING.md` Category 4b.

**Note on overloading:** "component" is used in two senses in Valkyrja.
In the code-level sense (above), a component is a single-focused framework
building block. In the repo-naming sense, a "project component" is any repo
that depends on a parent Valkyrja project. Context usually disambiguates,
but when precision is needed, say "code component" or "repo component."

### Starter

A template repo used to bootstrap a new Valkyrja-consuming project. Starters
are always in `REPOSITORY_NAMING.md` Category 4b (they require Valkyrja to
be useful). Starters exist per type: app, module, component, tool.

### Integration

A repo that bridges Valkyrja with a specific third-party runtime, service,
or library. Examples: `valkyrja-openswoole-php` (integrates with OpenSwoole),
`valkyrja-netty-java` (integrates with Netty). Integrations are always in
Category 4b.

## Deployment and Infrastructure Terms

### Runtime

The underlying process model that executes the language (PHP, Java, etc.)
code. For PHP, Valkyrja supports multiple runtimes:

- **Traditional PHP-FPM** — short-lived per-request process model.
- **OpenSwoole** — persistent worker model via OpenSwoole extension.
- **FrankenPHP** — persistent worker model via FrankenPHP embedded runtime.
- **RoadRunner** — persistent worker model via Go-based worker manager.

Each runtime is integrated via a corresponding repo:
`valkyrja-openswoole-php`, `valkyrja-frankenphp-php`, `valkyrja-roadrunner-php`.

Java runtime equivalents will use different integration repos:
`valkyrja-netty-java`, `valkyrja-jetty-java`, `valkyrja-tomcat-java`.

### Worker

A single instance of a runtime process handling requests or jobs.
"Persistent worker" means the process outlives a single request and handles
many requests in its lifetime. Valkyrja's OpenSwoole, FrankenPHP, and
RoadRunner integrations are all persistent worker models.

### Entry point

The specific file, class, or invocation that boots a Valkyrja app or tool.
In HTTP contexts this is typically a front controller. In CLI contexts it's
typically a command dispatcher. Different runtimes may require different
entry points (a PHP-FPM front controller vs. an OpenSwoole worker script),
but the entry point always performs the same logical role: load Valkyrja,
resolve the incoming request or command, and dispatch it.

## Contributing to This Document

This document is a living reference. When adding a new term, reserve a
placeholder entry with the reason the term is pending. When adding a new
"term to avoid," briefly note which ecosystem it comes from and why it
conflicts with Valkyrja's vocabulary.

Terms should be added to this document *before* they appear in code or repo
names. If you find a new concept while working on Valkyrja that doesn't fit
an existing term, open a discussion or PR to define it here first, then use
the defined term in your implementation.
