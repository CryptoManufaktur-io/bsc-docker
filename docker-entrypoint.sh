#!/usr/bin/env bash

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

# Set static nodes, and also as trusted nodes
curl -s https://api.binance.org/v1/discovery/peers | jq .peers >/home/bsc/data/static-nodes.json
for string in $(cat /home/bsc/data/static-nodes.json | jq -r .[]); do
  dasel put -v $(echo $string) -f config.toml 'Node.P2P.StaticNodes.[]'
done
dasel put -f config.toml -t json -v "$(cat /home/bsc/data/static-nodes.json)" Node.P2P.TrustedNodes
if [ -n "${EXTRA_STATIC_NODES}" ]; then
  for string in $(echo "${EXTRA_STATIC_NODES}" | jq -r .[]); do
    dasel put -v $(echo $string) -f config.toml 'Node.P2P.StaticNodes.[]'
    dasel put -v $(echo $string) -f config.toml 'Node.P2P.TrustedNodes.[]'
  done
fi

# Set verbosity
shopt -s nocasematch
case ${LOG_LEVEL} in
  error)
    __verbosity="--verbosity 1"
    ;;
  warn)
    __verbosity="--verbosity 2"
    ;;
  info)
    __verbosity="--verbosity 3"
    ;;
  debug)
    __verbosity="--verbosity 4"
    ;;
  trace)
    __verbosity="--verbosity 5"
    ;;
  *)
    echo "LOG_LEVEL ${LOG_LEVEL} not recognized"
    __verbosity=""
    ;;
esac

__public_ip=$(curl -s ifconfig.me/ip)

if [ -f /home/bsc/data/prune-marker ]; then
  rm -f /home/bsc/data/prune-marker
# Word splitting is desired for the command line parameters
# shellcheck disable=SC2086
  exec "$@" snapshot prune-state
else
  if [ ! -f /home/bsc/data/setupdone ]; then
    wget -q -O - "${SNAPSHOT_FILE}" | tar -I lz4 -xvf - -C /home/bsc/data
    mv /home/bsc/data/server/data-seed/geth /home/bsc/data/geth
    touch /home/bsc/data/setupdone
  fi
# Word splitting is desired for the command line parameters
# shellcheck disable=SC2086
  exec "$@" --nat extip:${__public_ip} ${__verbosity}
fi
