# bsc-docker

docker compose for bsc geth node

`./ethd install` can install docker-ce for you

To get started: `cp default.env .env`, adjust `COMPOSE_FILE` and `SNAPSHOT_FILE` and your traefik variables if you use
traefik, then `./ethd up`.

To update geth, run `./ethd update` and `./ethd up`

This is bsc-docker v1.2.0
