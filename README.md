# BSC Docker

Docker Compose for BSC geth node

`./bscd install` can install docker-ce for you

To get started: `cp default.env .env`, adjust `COMPOSE_FILE` and `SNAPSHOT` and `GETH_BUILD_TARGET` if
you want a specific version of bsc-geth, then `./bscd up`.

To update geth, adjust `GETH_BUILD_TARGET` if it targets a specific version, and run `./bscd update`
and `./bscd up`

## Version

BSC Docker uses semver versioning. First digit breaking changes, second digit non-breaking changes and additions,
third digit bugfixes.

This is BSC Docker v2.1.0
