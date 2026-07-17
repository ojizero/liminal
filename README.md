# Liminal

A self-hosted link manager and bookmarking app built with Phoenix LiveView and SQLite. Save links, tag them with expiring labels, and let the app fetch metadata and clean up after itself.

## Features

- **Link saving with metadata extraction** — paste a URL; the app fetches title, description, favicon, preview image, and video duration (YouTube/Vimeo) in the background
- **Expiring tags** — label links (e.g. "read later", "watch later") with per-tag expiration. Expired tags and untagged links are removed automatically
- **Search, filter, and sort** — typo-tolerant search across title, note, description, and URL; filter by viewed/unviewed status and tags; sort by date added or expiration
- **Per-link notes** — optional short notes on each saved link
- **Masonry layout** — responsive card grid (1–3 columns)
- **Random link** — open a random saved link in one click (optional auto-mark-as-viewed)
- **Multi-user with admin roles** — registration, invitation-based onboarding, admin panel for user management and instance stats
- **Background reindex** — user- or admin-scoped jobs to re-fetch metadata for failed or all links (one job at a time, rate-limited)
- **Real-time updates** — PubSub sync across browser tabs
- **Dark/light themes** — Catppuccin Latte (light) and Mocha (dark)

## Tech stack

- **Elixir / Phoenix 1.8** with LiveView
- **SQLite** via `ecto_sqlite3`
- **Tailwind CSS v4** with daisyUI
- **Docker** for deployment

## Getting started

### Prerequisites

- [mise](https://mise.jdx.dev/) with the Elixir and Erlang/OTP versions pinned in `.mise.toml`

### Local development

```bash
mix setup      # Install deps, create DB, run migrations, seed demo data, build assets
mix phx.server # Start the server at localhost:4000
```

mise with shell activation is required. Git commit hooks for Conventional Commits are configured automatically when you enter the project or run `mise install`. See [Commit messages](#commit-messages).

Local state lives under `data.local/`:

| Path | Contents |
|---|---|
| `data.local/liminal_dev.db` | Development SQLite database |
| `data.local/assets/` | Downloaded preview images, served at `/assets/<user_id>/<file>` |

Or inside IEx:

```bash
iex -S mix phx.server
```

### Demo data

`mix setup` loads demo users and sample links via `priv/repo/demo_seed.exs`. Re-seed anytime:

```bash
mix run priv/repo/demo_seed.exs
```

Shared password for password-bearing accounts: `liminaldev123!`. Primary demo account: `demo`. Admin: `admin`.

### First-time setup

When no admin exists, registration is open and the first signup becomes admin. After that, new signups follow `SIGNUPS_ENABLED`, or admins invite users from the admin panel.

## Deployment

### Docker Compose

```bash
cp .env.example .env
# Edit .env — at minimum set SECRET_KEY_BASE
# Generate one with: mix phx.gen.secret

docker compose up -d
```

### Persistent data

The container keeps state under `/data`, mounted as the named volume `liminal_data`:

| Path | Contents |
|---|---|
| `/data/liminal.db` | SQLite database (`DATABASE_PATH`) |
| `/data/assets/` | Downloaded preview images, served at `/assets/<user_id>/<file>` |

Mounting `/data` is required — without it, the database and images are lost on container recreate. For a host directory instead of the named volume:

```yaml
volumes:
  - ./data:/data
```

Preview images are configured at **image build time**, not runtime — `Plug.Static` freezes the serving path when the release is compiled. The published image defaults to `/data/assets`. To override:

```bash
docker build --build-arg ASSETS_DIR=/custom/path .
```

The path must sit on a writable mounted volume so images survive restarts.

### Environment variables

| Variable | Required | Default | Description |
|---|---|---|---|
| `SECRET_KEY_BASE` | Yes | — | Secret for signing cookies/sessions. Generate with `mix phx.gen.secret` |
| `PUID` | No | `911` | Container process UID — match host user (`id -u`) to avoid volume permission issues |
| `PGID` | No | `911` | Container process GID — match host group (`id -g`) |
| `DATABASE_PATH` | Yes | — | Path to the SQLite database file |
| `PHX_HOST` | No | `example.com` | Hostname for URL generation |
| `PHX_CHECK_ORIGINS` | No | — | Comma-separated extra allowed origins for LiveView WebSocket (e.g. `//domain2.com`). `PHX_HOST` is always included |
| `PORT` | No | `4000` | Server port |
| `POOL_SIZE` | No | `5` | SQLite connection pool size |
| `SIGNUPS_ENABLED` | No | `false` | Whether public registration is open |
| `AUTO_MIGRATE` | No | `true` | Create database and run migrations on startup |
| `LOG_LEVEL` | No | `warning` | `debug`, `info`, `notice`, `warning`, `error`, `critical`, `alert`, `emergency` |

## Development

### Useful commands

```bash
mix precommit              # Compile (warnings as errors), format, and test
mix test                   # Run the test suite
mix test --failed          # Re-run only previously failed tests
mix test test/path_test.exs # Run a specific test file
mise run changelog         # Preview release notes for the current VERSION
```

### Commit messages

This project uses [Conventional Commits 1.0.0](https://www.conventionalcommits.org/en/v1.0.0/). Every commit subject must match:

```
<type>[optional scope][optional !]: <description>
```

Examples:

```
feat(links): add fuzzy search across title and URL
fix: stabilize flaky SQLite tests
feat!: drop legacy bookmark import API
chore(release): version 1.11.0
```

**Enforcement**

- A `commit-msg` Git hook validates each commit locally (`mise run verify-commit`)
- CI checks all commits in a PR since the base branch (`mise run verify-commits`)
- Hooks are configured automatically when you enter the project or run `mise install` (requires mise with shell activation)

**Allowed types** — custom types such as `security` or `deps` are rejected:

| Type | Use for |
|------|---------|
| `feat` | New feature |
| `fix` | Bug fix |
| `docs` | Documentation only |
| `style` | Formatting, no logic change |
| `refactor` | Code change that is neither feat nor fix |
| `perf` | Performance improvement |
| `test` | Tests only |
| `build` | Build system or dependencies |
| `ci` | CI configuration |
| `chore` | Other maintenance (use `chore(release):` for version bumps) |
| `revert` | Revert a prior commit |

**Breaking changes** — append `!` after the type or scope (e.g. `feat!: …`), or add a `BREAKING CHANGE:` footer in the commit body.

**Release notes** — generated from commits between the previous release tag and `HEAD` when `VERSION` is bumped. Preview with `mise run changelog`. Included: all Conventional Commit types and breaking changes. Excluded: `chore(release):` commits and merge commits.

### Project structure

```
lib/
├── liminal/                  # Domain contexts
│   ├── accounts.ex           # Users, sessions, admin actions
│   ├── accounts/             # User, UserToken, Scope
│   ├── links.ex              # Link & tag CRUD, PubSub broadcasts
│   ├── links/                # Indexer, Janitor, Reindex, Stats, parsers
│   ├── asset_paths.ex        # Preview image paths (compile-time in prod)
│   ├── retry.ex              # Index retry backoff
│   └── schema.ex             # Shared UUID schema defaults
└── liminal_web/              # Web layer
    ├── router.ex
    ├── user_auth.ex          # Auth plugs and LiveView on_mount hooks
    ├── live/
    │   ├── link_live/        # Main dashboard (+ tag routes)
    │   ├── tag_live/         # Tag management LiveComponent
    │   ├── user_live/        # Login, registration, settings
    │   └── admin/            # Dashboard and user management
    └── components/           # Shared UI (modal, stats, reindex)
```

### Background workers

- **Janitor** (GenServer) — sweeps every 5 minutes (configurable): removes expired tags and orphaned links, then queues index retries for eligible links
- **Indexer** (Tasks) — fire-and-forget HTTP fetch per link under `IndexerTaskSupervisor`; records failures with exponential backoff for the Janitor to retry
- **Reindex** (GenServer) — coordinates one bulk reindex job at a time in rate-limited batches; progress is broadcast to subscribed LiveViews

## License

See [LICENSE](LICENSE) for details.
