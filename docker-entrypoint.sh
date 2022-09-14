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

exec "$@"
