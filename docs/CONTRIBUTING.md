# Contributing

## Setup

Install [mise](https://mise.jdx.dev/) and activate it in the shell, then run:

```bash
mise install
mix setup
mix phx.server
```

`mise install` installs the versions pinned in `.mise.toml` and configures `.githooks/commit-msg`. Run `mise run setup:git-hooks` if hooks are missing.

## Before opening a pull request

Run:

```bash
mix precommit
```

This compiles with warnings as errors, removes unused lock entries, formats the code, and runs the tests. Because it may modify files, review and commit the resulting diff.

`mise run ci` mirrors the Test & Lint job without modifying formatting: it installs dependencies, checks formatting, compiles with warnings as errors, and runs tests.

Every pull request to `main` verifies:

1. Every commit follows Conventional Commits.
2. `mise run ci` passes.

A pull request that changes `VERSION` also verifies that it is not behind the latest GitHub release.

## Commit messages

Use [Conventional Commits 1.0.0](https://www.conventionalcommits.org/en/v1.0.0/):

```text
<type>[optional scope][optional !]: <description>
```

Allowed types are `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert`. Custom types are rejected.

Examples:

```text
feat(links): add fuzzy note search
fix(auth): reject disabled sessions
docs: clarify reverse proxy setup
feat!: remove legacy bookmark import
```

Append `!` or add a `BREAKING CHANGE:` footer for breaking changes. Use `chore(release): version X.Y.Z` only for a release version bump.

Useful commands:

```bash
mix test
mix test --failed
mix test test/path_test.exs
mix ecto.reset
mix run priv/repo/demo_seed.exs
```

## Project rules

Repository-specific implementation and test guidance is in [`AGENTS.md`](../AGENTS.md). It applies to human and automated contributors.
