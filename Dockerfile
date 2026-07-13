# syntax=docker/dockerfile:1

# Build arguments for easy version pinning
ARG ELIXIR_VERSION=1.20.2
ARG OTP_VERSION=29.0.2
ARG DEBIAN_VERSION=bookworm-20260623-slim

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="debian:${DEBIAN_VERSION}"

# Stage 1: Build
FROM ${BUILDER_IMAGE} AS builder

RUN apt-get update -y && apt-get install -y build-essential git \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

WORKDIR /app

ENV HOME=/root

RUN mix local.hex --force && \
    mix local.rebar --force

ENV MIX_ENV="prod"

# Install dependencies (cached layer)
COPY mix.exs mix.lock VERSION ./
RUN mix deps.get --only prod
RUN mkdir config

# Copy compile-time config (cached layer)
COPY config/config.exs config/prod.exs config/
RUN mix deps.compile

# Install esbuild + tailwind binaries
RUN mix assets.setup

# Directory where downloaded link preview images are stored. `config/prod.exs`
# reads it during `mix compile`, and the value is baked into the release
# application environment. `AssetController` serves the files at runtime.
# Override with `--build-arg ASSETS_DIR=/custom/path`; the path must be writable
# and persistently mounted. This ARG is absent from the final image.
ARG ASSETS_DIR=/data/assets

# Copy application code and compile
COPY priv priv
COPY lib lib
RUN ASSETS_DIR="${ASSETS_DIR}" mix compile

# Build assets
COPY assets assets
RUN mix assets.deploy

# Copy runtime config
COPY config/runtime.exs config/

# Build release
RUN mix release

# Stage 2: Runner
FROM ${RUNNER_IMAGE}

RUN apt-get update -y && \
    apt-get install -y libstdc++6 openssl libncurses6 locales ca-certificates gosu \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

# Set locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

WORKDIR /app

# Pre-create liminal user with default UID/GID
RUN addgroup --gid 911 liminal && \
    adduser --uid 911 --ingroup liminal \
            --home /app --no-create-home \
            --disabled-password --gecos "" liminal

# Copy release from builder
COPY --from=builder /app/_build/prod/rel/liminal ./

# Copy entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENV PHX_SERVER=true
ENV PORT=4000

# UID/GID for the container process (LinuxServer.io-style)
ENV PUID=911
ENV PGID=911

EXPOSE 4000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD /app/bin/liminal pid || exit 1

ENTRYPOINT ["/entrypoint.sh"]
CMD ["/app/bin/liminal", "start"]
