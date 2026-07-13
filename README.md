# Liminal

Liminal is a self-hosted, multi-user link manager built with Phoenix LiveView and SQLite.

## Features

- Saves links with notes and fetches titles, descriptions, favicons, preview images, and video duration.
- Searches titles, notes, descriptions, and URLs; filters by tag and viewed state; sorts by creation or expiration.
- Uses expiring tags for workflows such as “read later.” The janitor removes expired tag assignments, viewed links past their grace period, and links left without tags.
- Detects duplicate URLs and offers to merge tag assignments.
- Opens a random saved link and provides keyboard shortcuts for common actions.
- Supports per-user defaults, automatic “viewed” marking, statistics, and metadata reindexing.
- Provides admin dashboards, invitation links, account controls, and instance-wide reindexing.
- Updates open sessions through PubSub and supports system, light, and dark themes.

## Stack

- Elixir 1.20, Erlang/OTP 29, Phoenix 1.8, and LiveView
- SQLite through `ecto_sqlite3`
- Tailwind CSS v4 and daisyUI
- Docker for production packaging

## Local development

[mise](https://mise.jdx.dev/) is the supported toolchain manager. `.mise.toml` pins Erlang 29.0.2, Elixir 1.20.2-otp-29, and the GitHub CLI.

```bash
mise install
mix setup
mix phx.server
```

Open `http://localhost:4000`. Use `iex -S mix phx.server` when an IEx shell is needed.

Local state is stored in `data.local/`:

- `liminal_dev.db`: development database
- `assets/<user_id>/`: downloaded previews, served to their owner at `/assets/<user_id>/<filename>`

For sample users and links, run `mix run priv/repo/demo_seed.exs`. Development-only diagnostics are available at `/dev/dashboard` and `/dev/mailbox`.

## Authentication

Liminal uses usernames and passwords, not email addresses. Usernames contain 3–30 letters, numbers, or underscores; passwords contain 12–72 characters.

When no admin exists, `/users/register` creates the first admin even if public signup is disabled. After bootstrap:

- `SIGNUPS_ENABLED=true` opens public registration.
- An admin can create an account at `/admin/users/new` and copy the generated password-setup link.
- Password-reset and invitation links are shared manually; production email delivery is not configured.

## Deployment

Docker Compose builds the application from the checked-out source:

```bash
cp .env.example .env
# Set SECRET_KEY_BASE in .env:
#   mix phx.gen.secret
# or
#   openssl rand -base64 64 | tr -d '\n'
docker compose up -d --build
```

The named `liminal_data` volume contains both `/data/liminal.db` and `/data/assets`. Losing this volume loses application data. Preview files are stored under a compile-time `ASSETS_DIR` (default `/data/assets`) and served through the authenticated `AssetController`; `ASSETS_DIR` is not a runtime variable.

Production hostname, reverse-proxy, persistence, backup, and environment-variable details are in [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md).

> [!WARNING]
> Liminal fetches user-supplied URLs and discovered preview URLs from the server. Deploy it only for trusted users and restrict container egress if the host can reach private services or cloud metadata endpoints.

## Development workflow

```bash
mix test                         # Create/migrate the test DB and run tests
mix test --failed                # Re-run failures
mix test test/path_test.exs      # Run one test file
mix precommit                    # Compile strictly, prune unused locks, format, test
mise run ci                      # Run CI's non-mutating format, compile, and test checks
mix ecto.reset                   # Recreate the development database
mix assets.deploy                # Build production assets
```

See [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md) for commit and pull-request rules and [docs/RELEASE.md](docs/RELEASE.md) for the maintainer release process.

## Architecture

- `lib/liminal/accounts.ex` and `lib/liminal/accounts/`: users, sessions, invitations, and authorization scopes
- `lib/liminal/links.ex` and `lib/liminal/links/`: links, tags, search, metadata indexing, retries, cleanup, statistics, and reindex jobs
- `lib/liminal_web/live/link_live/`: main dashboard and tag-management routes
- `lib/liminal_web/live/tag_live/`: tag LiveComponent embedded in the dashboard
- `lib/liminal_web/live/user_live/`: registration, login, password reset, and settings
- `lib/liminal_web/live/admin/`: instance statistics and user administration
- `lib/liminal_web/controllers/`: sessions, random-link redirect, and authorized preview serving

The indexer fetches metadata asynchronously when a link is created. `Liminal.Links.Janitor` runs every five minutes to clean up and retry eligible failed indexing. `Liminal.Links.Reindex` serializes user and instance reindex jobs into rate-limited batches.

## License

[MIT](LICENSE)
