FROM node:22-bookworm-slim AS node-build

WORKDIR /src
RUN corepack enable && corepack prepare pnpm@10.24.0 --activate
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml tsconfig.base.json ./
COPY packages ./packages
RUN pnpm install --frozen-lockfile && pnpm build

FROM hexpm/elixir:1.18.4-erlang-27.3.4.16-debian-bookworm-20260803-slim AS elixir-build

RUN apt-get update \
  && apt-get install -y --no-install-recommends build-essential git \
  && rm -rf /var/lib/apt/lists/* \
  && mix local.hex --force \
  && mix local.rebar --force

WORKDIR /src/services/coordinator
COPY services/coordinator ./
RUN MIX_ENV=prod mix deps.get \
  && MIX_ENV=prod mix compile --warnings-as-errors \
  && MIX_ENV=prod mix release --overwrite

WORKDIR /src/services/proxy
COPY services/proxy ./
RUN MIX_ENV=prod mix deps.get \
  && MIX_ENV=prod mix compile --warnings-as-errors \
  && MIX_ENV=prod mix release --overwrite

FROM debian:bookworm-slim AS asset-build

RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates curl e2fsprogs squashfs-tools \
  && rm -rf /var/lib/apt/lists/*
WORKDIR /src
COPY guest ./guest
COPY scripts/setup/build-rootfs.sh scripts/setup/setup-assets.sh ./scripts/setup/
RUN ./scripts/setup/setup-assets.sh

FROM debian:bookworm-slim

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    ca-certificates curl iproute2 libstdc++6 nftables openssl procps util-linux \
  && rm -rf /var/lib/apt/lists/*

COPY --from=node-build /usr/local /usr/local
COPY --from=node-build /src/node_modules /opt/firemig/node_modules
COPY --from=node-build /src/packages /opt/firemig/packages
COPY --from=elixir-build /src/services/coordinator/_build/prod/rel/firemig_coordinator /opt/firemig/coordinator
COPY --from=elixir-build /src/services/proxy/_build/prod/rel/firemig_proxy /opt/firemig/proxy
COPY --from=asset-build /src/assets /opt/firemig/assets
COPY scripts/runtime/docker-entrypoint.sh /usr/local/bin/firemig-entrypoint

RUN chmod 0755 /usr/local/bin/firemig-entrypoint \
  && mkdir -p /var/lib/firemig /run/netns

ENV FIREMIG_DATA_ROOT=/var/lib/firemig
EXPOSE 4000 8080
ENTRYPOINT ["/usr/local/bin/firemig-entrypoint"]
