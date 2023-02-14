#!/bin/sh

wget $(curl -s https://api.github.com/repos/bnb-chain/bsc/releases/latest |grep browser_ |grep mainnet |cut -d\" -f4)
unzip mainnet.zip
rm mainnet.zip

if [ -z "$(ls -A /home/bsc/data)" ]; then
    geth --datadir /home/bsc/data init genesis.json
fi

dasel delete -f config.toml Node.LogConfig
dasel delete -f config.toml Node.HTTPHost
dasel delete -f config.toml Node.HTTPVirtualHosts
dasel delete -f config.toml Node.NoUSB
echo 'Setup done!'

if [ -f /home/bsc/data/prune-marker ]; then
  rm -f /home/bsc/data/prune-marker
# Word splitting is desired for the command line parameters
# shellcheck disable=SC2086
  exec "$@" snapshot prune-state
else
# Word splitting is desired for the command line parameters
# shellcheck disable=SC2086
  exec "$@"
fi
