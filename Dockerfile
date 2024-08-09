# Build Geth in a stock Go builder container
FROM golang:1.22-bookworm AS builder

ARG BUILD_TARGET

WORKDIR /src

RUN bash -c "git clone https://github.com/bnb-chain/bsc.git && cd bsc && git config advice.detachedHead false && git fetch --all --tags && git checkout ${BUILD_TARGET} && make geth"

# Get dasel
FROM ghcr.io/tomwright/dasel:2-alpine AS dasel

# Pull all binaries into a second stage deploy container
FROM debian:bookworm-slim

ARG USER=bsc
ARG UID=10000

RUN apt-get update && apt-get install -y ca-certificates bash tzdata hwloc libhwloc-dev wget curl unzip lz4 zstd jq aria2

# See https://stackoverflow.com/a/55757473/12429735RUN
RUN adduser \
    --disabled-password \
    --gecos "" \
    --shell "/sbin/nologin" \
    --uid "${UID}" \
    "${USER}"

RUN mkdir -p /home/${USER}/data && mkdir -p /home/${USER}/ancient && chown -R ${USER}:${USER} /home/${USER}

# Copy executable
COPY --from=builder /src/bsc/build/bin /usr/local/bin/
COPY ./docker-entrypoint.sh /usr/local/bin/
COPY --from=dasel /usr/local/bin/dasel /usr/local/bin/

RUN chmod +x /usr/local/bin/docker-entrypoint.sh

USER ${USER}
WORKDIR /home/${USER}

ENTRYPOINT ["geth"]
