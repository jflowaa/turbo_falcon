# Build stage: Elixir/OTP matching mise.toml.
FROM elixir:1.20.4-otp-29-slim AS build

ENV MIX_ENV=prod \
    ERL_FLAGS="+JMsingle true" \
    LANG=C.UTF-8 \
    LANGUAGE=C.UTF-8 \
    LC_ALL=C.UTF-8

RUN apt-get update \
 && apt-get install -y --no-install-recommends build-essential git ca-certificates \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN mix local.hex --force && mix local.rebar --force

COPY mix.exs mix.lock ./
RUN mix deps.get --only prod
RUN mix deps.compile

COPY config config
COPY priv priv
COPY lib lib
COPY assets assets

RUN mix assets.setup \
 && mix assets.deploy \
 && mix release

# Runtime stage.
FROM debian:trixie-slim AS app

ARG TARGETARCH
ARG DBMATE_VERSION=2.37.0

ENV LANG=C.UTF-8 \
    LANGUAGE=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    MIX_ENV=prod \
    PHX_SERVER=true \
    HOME=/app

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl libncurses6 libstdc++6 openssl tzdata \
 && curl -fsSL -o /usr/local/bin/dbmate \
      "https://github.com/amacneil/dbmate/releases/download/v${DBMATE_VERSION}/dbmate-linux-${TARGETARCH}" \
 && chmod +x /usr/local/bin/dbmate \
 && rm -rf /var/lib/apt/lists/* \
 && groupadd --gid 10001 app \
 && useradd --uid 10001 --gid app --create-home --home-dir /app app

WORKDIR /app

COPY --from=build --chown=app:app /app/_build/prod/rel/turbo_falcon ./
COPY --chown=app:app db ./db

USER 10001:10001

EXPOSE 4002

ENTRYPOINT ["/app/bin/turbo_falcon"]
CMD ["start"]
