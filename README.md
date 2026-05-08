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

- Elixir ~> 1.15 and Erlang/OTP
- Node.js (for asset building)

### Local development

```bash
mix setup          # Install deps, create DB, run migrations, build assets
mix phx.server     # Start the server at localhost:4000
```

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

### Environment variables

| Variable | Required | Default | Description |
|---|---|---|---|
| `SECRET_KEY_BASE` | Yes | — | Secret for signing cookies/sessions. Generate with `mix phx.gen.secret` |
| `DATABASE_PATH` | No | `/data/liminal.db` | Path to the SQLite database file |
| `PHX_HOST` | No | `localhost` | Hostname for URL generation |
| `PORT` | No | `4000` | Server port |
| `POOL_SIZE` | No | `5` | SQLite connection pool size |
| `SIGNUPS_ENABLED` | No | `false` | Whether public registration is open |
| `LOG_LEVEL` | No | `warning` | Log verbosity: `debug`, `info`, `notice`, `warning`, `error`, `critical`, `alert`, `emergency` |

## Development

### Useful commands

```bash
mix precommit              # Compile (warnings as errors), format, and test
mix test                   # Run the test suite
mix test --failed          # Re-run only previously failed tests
mix test test/path_test.exs # Run a specific test file
```

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
