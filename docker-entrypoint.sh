#!/bin/sh

if [ ! -f /home/bsc/.geth/setupdone ]; then
    wget $(curl -s https://api.github.com/repos/bnb-chain/bsc/releases/latest |grep browser_ |grep mainnet |cut -d\" -f4)
    unzip mainnet.zip
    rm mainnet.zip

    if [ -z "$(ls -A /home/bsc/data)" ]; then
        geth --datadir /home/bsc/data init genesis.json
    fi

    dasel delete -f config.toml Node.LogConfig
    echo 'Setup done!'
    touch /home/bsc/.geth/setupdone
fi

exec /usr/local/bin/geth --config /home/bsc/config.toml --datadir /home/bsc/data --cache 8000 --http --http.addr 0.0.0.0 --http.vhosts '*' --rpc.allow-unprotected-txs --txlookuplimit 0 --diffsync --ipcdisable
