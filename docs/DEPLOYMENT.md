# Deployment

## Build from source

`docker-compose.yml` builds the current checkout and mounts the named `liminal_data` volume at `/data`.

```bash
cp .env.example .env
# Set SECRET_KEY_BASE.
# For remote access, set PHX_HOST=links.example.com.
docker compose up -d --build
```

For a bind mount, replace the service volume with `./data:/data`. Set `PUID` and `PGID` to the host owner of that directory.

## Deploy a published image

Each release publishes versioned images to `ghcr.io/ojizero/liminal` and the Docker Hub account configured by the maintainer. Prefer a version tag over `latest`.

```bash
cp .env.example .env
# Set SECRET_KEY_BASE and the public PHX_HOST in .env.
docker run -d \
  --name liminal \
  --restart unless-stopped \
  --env-file .env \
  -p 4000:4000 \
  -v liminal_data:/data \
  ghcr.io/ojizero/liminal:1.11.1
```

Replace `1.11.1` with the intended release. Confirm available tags on the [GitHub releases page](https://github.com/ojizero/liminal/releases).

## Persistent data

| Path | Purpose |
|---|---|
| `/data/liminal.db` | SQLite database, configurable with `DATABASE_PATH` |
| `/data/assets/<user_id>/` | Downloaded preview images |

Mount the parent directories of both paths persistently. Back them up and restore them as one unit so database image references remain consistent.

For a consistent offline backup:

1. Stop the application container.
2. Archive the complete mounted `/data` volume or bind-mount directory.
3. Restart the container.

Restore into an empty volume while the application is stopped. Test restoration periodically; an untested copy is not a backup.

## Preview storage

`ASSETS_DIR` is read by `config/prod.exs` during compilation and baked into the release application environment. The official build defaults to `/data/assets`.

To use another path:

```bash
docker build --build-arg ASSETS_DIR=/custom/path .
```

The path must be writable by `PUID`/`PGID` and backed by persistent storage. Preview requests use `/assets/:user_id/:filename` and pass through the authenticated `AssetController`; `Plug.Static` does not serve these files.

## Reverse proxy and TLS

The release listens on HTTP inside the container. Terminate TLS at a reverse proxy and:

- Set `PHX_HOST` to the public hostname.
- Forward `Host`, WebSocket upgrade headers, and `X-Forwarded-Proto: https`.
- Add alternate LiveView origins to `PHX_CHECK_ORIGINS` in scheme-relative form, such as `//links.example.net`.

Production forces HTTPS and trusts `X-Forwarded-Proto`. Missing that header causes redirects for non-local hosts. `localhost` and `127.0.0.1` are excluded from forced HTTPS for local checks.

`PHX_HOST=localhost` is only suitable for same-machine access. A remote deployment must set its public hostname or LiveView origin checks and generated URLs will be wrong.

## Upgrading

Back up `/data`, then:

- Source build: pull the intended revision and run `docker compose up -d --build`.
- Published image: pull the versioned image, stop and remove the old container, then recreate it with the same environment, port, and `liminal_data` volume.

Leave `AUTO_MIGRATE=true`; startup applies pending migrations before the HTTP endpoint starts. This repository does not provide a separate release migration command.

## Environment variables

| Variable | Required | Default | Purpose |
|---|---:|---|---|
| `SECRET_KEY_BASE` | Yes | — | Signs and encrypts cookies and sessions |
| `DATABASE_PATH` | Yes in a release | `/data/liminal.db` in Compose | SQLite file path |
| `PHX_SERVER` | Yes for a release | `true` in the image | Enables the HTTP endpoint |
| `PHX_HOST` | Yes for remote production | `example.com`; `localhost` in Compose | Public hostname and primary LiveView origin |
| `PHX_CHECK_ORIGINS` | No | — | Comma-separated additional scheme-relative origins |
| `PORT` | No | `4000` | HTTP listen port |
| `POOL_SIZE` | No | `5` | SQLite connection pool size |
| `SIGNUPS_ENABLED` | No | `false` | Opens public registration after first-admin setup |
| `AUTO_MIGRATE` | No | `true` | Creates the database and runs migrations at startup |
| `LOG_LEVEL` | No | `warning` | `debug`, `info`, `notice`, `warning`/`warn`, `error`, `critical`, `alert`, or `emergency` |
| `DNS_CLUSTER_QUERY` | No | — | DNS query used by `dns_cluster` for distributed discovery |
| `PUID` | No | `911` | Runtime process UID |
| `PGID` | No | `911` | Runtime process GID |

Boolean variables are enabled only by the literal value `true`.

## Operations and security

- The Docker health check verifies that the BEAM release process is alive; it does not make an HTTP readiness request.
- Automatic migrations run during application startup before the HTTP endpoint accepts traffic.
- SQLite and a single serialized reindex worker make this deployment model suitable for small instances, not horizontal write scaling.
- Saved pages, oEmbed endpoints, and preview images cause outbound HTTP requests. The application does not block private or link-local destinations. Use trusted accounts and network-level egress controls.
- User deletion removes database records but does not currently remove that user's preview directory. Monitor and clean orphaned directories under `assets/`.
