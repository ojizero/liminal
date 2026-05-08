# syntax=docker/dockerfile:1

# Build arguments for easy version pinning
ARG ELIXIR_VERSION=1.19.5
ARG OTP_VERSION=28.5
ARG DEBIAN_VERSION=bookworm-20260421-slim

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
COPY mix.exs mix.lock ./
RUN --mount=type=cache,target=/root/.hex/packages \
    --mount=type=cache,target=/root/.cache/rebar3 \
    mix deps.get --only prod
RUN mkdir config

# Copy compile-time config (cached layer)
COPY config/config.exs config/prod.exs config/
RUN --mount=type=cache,target=/root/.hex/packages \
    --mount=type=cache,target=/root/.cache/rebar3 \
    mix deps.compile

# Install esbuild + tailwind binaries
RUN mix assets.setup

# Copy application code and compile
COPY priv priv
COPY lib lib
RUN mix compile

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
    apt-get install -y libstdc++6 openssl libncurses6 locales ca-certificates \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

# Set locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

WORKDIR /app

# Create data directory for SQLite and set ownership
RUN mkdir -p /data && chown nobody:nogroup /data

# Copy release from builder
RUN chown nobody:nogroup /app
COPY --from=builder --chown=nobody:nogroup /app/_build/prod/rel/liminal ./

ENV PHX_SERVER=true
ENV DATABASE_PATH=/data/liminal.db
ENV PORT=4000

USER nobody

EXPOSE 4000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD /app/bin/liminal pid || exit 1

CMD ["/app/bin/liminal", "start"]
