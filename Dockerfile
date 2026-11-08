# =============================================================================
# Dockerfile for Tic-Tac-Toe (Phoenix + Elixir)
# Multi-stage build:
#   1. Builder stage — compiles Elixir code, builds assets, creates release
#   2. Runner stage  — runs the release with ERTS included (no Elixir needed)
# =============================================================================

# ------------------------------------------------------------
# Stage 1: Builder
# ------------------------------------------------------------
FROM hexpm/elixir:1.17.4-erlang-26.2.5-debian-bookworm-20240912-slim AS builder

WORKDIR /app

# System packages needed to compile and build assets
RUN apt-get update && apt-get install -y \
    build-essential \
    git \
    curl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Node.js for esbuild + tailwind (assets pipeline)
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# Hex and Rebar (Elixir package managers)
RUN mix local.hex --force && mix local.rebar --force

# Use production environment for the build
ENV MIX_ENV=prod

# ------------------------------------------------------------
# 1) Install & compile dependencies (cached layer)
# ------------------------------------------------------------
COPY mix.exs mix.lock ./
RUN mix deps.get --only prod
RUN mix deps.compile

# ------------------------------------------------------------
# 2) Copy source and compile
# ------------------------------------------------------------
COPY . .
RUN mix compile

# ------------------------------------------------------------
# 3) Build static assets (tailwind + esbuild + phx.digest)
# ------------------------------------------------------------
RUN mix assets.deploy

# ------------------------------------------------------------
# 4) Build the OTP release
# ------------------------------------------------------------
RUN mix release

# ------------------------------------------------------------
# Stage 2: Runner (minimal runtime image)
# ------------------------------------------------------------
FROM hexpm/elixir:1.17.4-erlang-26.2.5-debian-bookworm-20240912-slim AS runner

WORKDIR /app

# Runtime system libraries
RUN apt-get update && apt-get install -y \
    libstdc++6 \
    openssl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Copy the compiled release from the builder stage
COPY --from=builder /app/_build/prod/rel/tic_tac_toe ./release

# Environment variables for the release
ENV MIX_ENV=prod
ENV PHX_SERVER=true
ENV PORT=4000

# Expose HTTP port and Erlang distribution ports
#   4000   — Phoenix HTTP (Bandit)
#   4369   — EPMD (Erlang node discovery)
#   9100   — Erlang distribution (configured via inet_dist_listen_min/max)
EXPOSE 4000 4369 9100

# Start the Phoenix server as a named Erlang node.
# TIC_TAC_TOE_NODE_NAME (e.g. tic@node-a) sets both the BEAM node name
# and is read by runtime.exs for cluster configuration.
# The --kernel flags pin the distribution port to 9100 so firewalls and
# Docker port mappings stay predictable across nodes.
CMD release/bin/tic_tac_toe start --name ${TIC_TAC_TOE_NODE_NAME} --cookie ${TIC_TAC_TOE_COOKIE} -- -kernel inet_dist_listen_min 9100 -kernel inet_dist_listen_max 9100
