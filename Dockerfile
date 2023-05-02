# Build Geth in a stock Go builder container
FROM golang:1.19-bullseye as builder

ARG BUILD_TARGET

WORKDIR /src

RUN bash -c "git clone https://github.com/bnb-chain/bsc.git && cd bsc && git config advice.detachedHead false && git fetch --all --tags && git checkout ${BUILD_TARGET} && make geth"

# Get dasel
FROM ghcr.io/tomwright/dasel:v2.2.0-alpine as dasel

# Pull all binaries into a second stage deploy container
FROM debian:bullseye-slim

ARG USER=bsc
ARG UID=10000

RUN apt-get update && apt-get install -y ca-certificates bash tzdata hwloc libhwloc-dev wget curl unzip lz4 jq

# See https://stackoverflow.com/a/55757473/12429735RUN
RUN adduser \
    --disabled-password \
    --gecos "" \
    --shell "/sbin/nologin" \
    --uid "${UID}" \
    "${USER}"

RUN mkdir -p /home/${USER}/.geth && mkdir -p /home/bsc/data && chown -R ${USER}:${USER} /home/${USER}

# VOLUME /home/bsc/data

# Copy executable
COPY --from=builder /src/bsc/build/bin /usr/local/bin/
COPY ./docker-entrypoint.sh /usr/local/bin/
COPY --from=dasel /usr/local/bin/dasel /usr/local/bin/

RUN chmod +x /usr/local/bin/docker-entrypoint.sh

USER ${USER}
WORKDIR /home/${USER}

ENTRYPOINT ["geth"]
