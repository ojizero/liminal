# Liminal

A self-hosted link manager and bookmarking app built with Phoenix LiveView and SQLite. Save links, tag them with expiring labels, and let the app automatically fetch metadata and clean up after itself.

## Features

- **Link saving with metadata extraction** — paste a URL and the app fetches the title, description, favicon, and preview image automatically
- **Expiring tags** — tag links with labels like "read later" or "watch later", each with a configurable expiration (e.g. 14 days). Expired tags and orphaned links are cleaned up automatically
- **Filtering and sorting** — filter by viewed/unviewed status and tags, sort by date added or expiration
- **Masonry layout** — responsive card grid that adapts from 1 to 3 columns
- **Multi-user with admin roles** — user registration, invitation-based onboarding, admin panel for user management
- **Real-time updates** — PubSub-powered live updates across browser tabs
- **Dark/light themes** — Catppuccin Latte (light) and Mocha (dark)

## Tech stack

- **Elixir / Phoenix 1.8** with LiveView
- **SQLite** via `ecto_sqlite3`
- **Tailwind CSS v4** with daisyUI
- **Docker** for deployment

## Getting started

### Prerequisites

- Elixir ~> 1.20 and Erlang/OTP 27+

### Local development

```bash
mix setup      # Install deps, create DB, run migrations, build assets
mix phx.server # Start the server at localhost:4000
```

[mise](https://mise.jdx.dev/) with shell activation is required for local development. Git commit hooks for Conventional Commits are configured automatically when you enter the project directory or run `mise install`. See [Commit messages](#commit-messages) below.

Local development state is stored under `data.local/`:

- `data.local/liminal_dev.db` - local development SQLite database
- `data.local/assets/` - downloaded link preview images, served at `/assets/<file>`

Or inside IEx:

```bash
iex -S mix phx.server
```

### First-time setup

When no admin account exists, the registration page is open — the first user to sign up becomes the admin. After that, new signups are controlled by the `SIGNUPS_ENABLED` environment variable, or admins can invite users from the admin panel.

## Deployment

### Docker Compose

```bash
cp .env.example .env
# Edit .env — at minimum set SECRET_KEY_BASE
# Generate one with: mix phx.gen.secret

docker compose up -d
```

### Persistent data

The container keeps all of its state under `/data`, which the Compose file mounts
as the named volume `liminal_data`:

| Path | Contents |
|---|---|
| `/data/liminal.db` | SQLite database (set via `DATABASE_PATH`) |
| `/data/assets/` | Downloaded link preview images, served at `/assets/<file>` |

Mounting `/data` is required: without it, the database and preview images are
lost when the container is recreated. To use a host directory instead of the
named volume, replace the volume entry in `docker-compose.yml`:

```yaml
volumes:
  - ./data:/data
```

The preview image directory (`/data/assets`) is configured at **image build
time**, not at runtime — `Plug.Static` freezes the serving path when the release
is compiled, so it cannot be changed by an environment variable on a running
container. The published image defaults to `/data/assets`. To build with a
different path:

```bash
docker build --build-arg ASSETS_DIR=/custom/path .
```

The custom path must live under a writable mounted volume so images survive
restarts.

### Environment variables

| Variable | Required | Default | Description |
|---|---|---|---|
| `SECRET_KEY_BASE` | Yes | — | Secret for signing cookies/sessions. Generate with `mix phx.gen.secret` |
| `PUID` | No | `911` | UID for the container process. Match your host user (`id -u`) to avoid permission issues with mounted volumes |
| `PGID` | No | `911` | GID for the container process. Match your host group (`id -g`) |
| `DATABASE_PATH` | Yes | — | Path to the SQLite database file |
| `PHX_HOST` | No | `example.com` | Hostname for URL generation |
| `PHX_CHECK_ORIGINS` | No | — | Comma-separated additional allowed origins for LiveView WebSocket connections (e.g. `//domain2.com,//domain3.com`). `PHX_HOST` is always included automatically |
| `PORT` | No | `4000` | Server port |
| `POOL_SIZE` | No | `5` | SQLite connection pool size |
| `SIGNUPS_ENABLED` | No | `false` | Whether public registration is open |
| `AUTO_MIGRATE` | No | `true` | Automatically create database and run migrations on startup |
| `LOG_LEVEL` | No | `warning` | Log verbosity: `debug`, `info`, `notice`, `warning`, `error`, `critical`, `alert`, `emergency` |

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
- CI checks all commits in a pull request since the base branch (`mise run verify-commits`)
- Hooks are configured automatically when you enter the project or run `mise install` (requires [mise](https://mise.jdx.dev/) with shell activation)

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

**Breaking changes** — append `!` after the type or scope (e.g. `feat!: …`, `feat(api)!: …`), or add a `BREAKING CHANGE:` footer in the commit body.

**Release notes** — generated from commits between the previous release tag and `HEAD` when `VERSION` is bumped. Preview with `mise run changelog`. Included: all Conventional Commit types (`feat`, `fix`, `perf`, `revert`, `refactor`, `docs`, `build`, `chore`, `ci`, `style`, `test`) and breaking changes. Excluded: `chore(release):` commits and merge commits.

### Project structure

```
lib/
├── liminal/                  # Business logic (contexts)
│   ├── accounts.ex           # User management
│   ├── accounts/             # User schema, tokens
│   ├── links.ex              # Link & tag CRUD
│   └── links/                # Link, Tag, Indexer, Janitor, MetadataParser
└── liminal_web/              # Web layer
    ├── router.ex             # Routes and pipelines
    ├── user_auth.ex          # Auth plugs and hooks
    ├── live/                 # LiveView modules
    │   ├── link_live/        # Main links dashboard
    │   ├── tag_live/         # Tag management
    │   ├── user_live/        # Login, registration, settings
    │   └── admin/            # Admin user management
    └── components/           # Shared UI components
```

### Background workers

- **Janitor** — runs every 5 minutes to clean up expired tags and orphaned links, and triggers indexing for unindexed links
- **Indexer** — fetches metadata (title, description, favicon, preview image) from saved URLs via async tasks

## License

See [LICENSE](LICENSE) for details.
