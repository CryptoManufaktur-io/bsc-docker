# bsc-docker

docker-compose for bsc geth node

To get started: `cp default.env .env`, adjust `COMPOSE_FILE` and your traefik variables if you use traefik, then `docker-compose build --no-cache && docker-compose up -d`.

To update geth, run `docker-compose build --no-cache`, followed by `docker-compose down && docker-compose up -d`.
