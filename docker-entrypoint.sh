#!/usr/bin/env bash
set -euo pipefail

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
__ancient=""

if [ -n "${ANCIENT_DIR}" ] && [ ! "${ANCIENT_DIR}" = ".nada" ]; then
    __ancient="--datadir.ancient /home/bsc/ancient"
fi

if [ -f /home/bsc/data/prune-marker ]; then
  rm -f /home/bsc/data/prune-marker

  wget "$(curl -s https://api.github.com/repos/bnb-chain/bsc/releases/latest |grep browser_ |grep "${NETWORK}" |cut -d\" -f4)"
  unzip -o "${NETWORK}".zip
  rm "${NETWORK}".zip

# Word splitting is desired for the command line parameters
# shellcheck disable=SC2086
  exec "$@" ${__ancient} snapshot prune-block --block-amount-reserved 1024
else
  if [ -n "${SNAPSHOT}" ] && [ ! -f /home/bsc/data/setupdone ]; then
    if [ -n "${__ancient}" ]; then
       __snap_dir=/home/bsc/ancient/snapshot
       __data_dir=/home/bsc/ancient
    else
       __snap_dir=/home/bsc/data/snapshot
       __data_dir=/home/bsc/data
    fi
    mkdir -p "${__snap_dir}"

    # Download snapshot
    cd "${__snap_dir}"
    wget https://raw.githubusercontent.com/bnb-chain/bsc-snapshots/main/dist/fetch-snapshot.sh
    bash fetch-snapshot.sh -d -c -D "${__snap_dir}" "${SNAPSHOT}"
    bash fetch-snapshot.sh -e -D "${__snap_dir}" -E "${__data_dir}"
    rm -rf "${__snap_dir}/*"

    # try to find the directory
    __search_dir="geth/chaindata"
    __base_dir="${__data_dir}"
    __found_path=$(find "$__base_dir" -type d -path "*/$__search_dir" -print -quit)
    if [ -n "$__found_path" ]; then
      __geth_dir=$(dirname "$__found_path")
      __geth_dir=${__geth_dir%/chaindata}
      if [ "${__geth_dir}" = "${__base_dir}geth" ]; then
         echo "Snapshot extracted into ${__geth_dir}/chaindata"
      else
        echo "Found a geth directory at ${__geth_dir}, moving it."
        mv "$__geth_dir" "$__base_dir"
        rm -rf "$__geth_dir"
      fi
    fi
    if [[ ! -d "${__data_dir}/geth/chaindata" ]]; then
      echo "Chaindata isn't in the expected location."
      echo "This snapshot likely won't work until the entrypoint script has been adjusted for it."
      exit 1
    fi

    if [ -n "${__ancient}" ]; then
        rm -rf /home/bsc/data/geth
        mkdir -p /home/bsc/data/geth/chaindata
        find "/home/bsc/ancient/geth" -mindepth 1 -maxdepth 1 ! -name 'chaindata' -exec mv {} /home/bsc/data/geth/ \;
        find "/home/bsc/ancient/geth/chaindata" -mindepth 1 -maxdepth 1 ! -name 'ancient' -exec mv {} /home/bsc/data/geth/chaindata/ \;
        find "/home/bsc/ancient/geth/chaindata/ancient" -mindepth 1 -maxdepth 1 -exec mv {} "/home/bsc/ancient/" \;
        rm -rf "/home/bsc/ancient/geth"
    fi
    touch /home/bsc/data/setupdone
  fi

  cd /home/bsc
  # The wget was moved down here so that repeated failures with SNAPSHOT above don't exhaust
  # the github API rate limit
  wget "$(curl -s https://api.github.com/repos/bnb-chain/bsc/releases/latest |grep browser_ |grep "${NETWORK}" |cut -d\" -f4)"
  unzip -o "${NETWORK}".zip
  rm "${NETWORK}".zip

  # Remove unwanted settings in config.toml
  dasel delete -f config.toml Node.LogConfig
  dasel delete -f config.toml Node.HTTPHost
  dasel delete -f config.toml Node.HTTPVirtualHosts

  # Duplicate binance-supplied static nodes to trusted nodes
  for string in $(dasel -f config.toml -w json 'Node.P2P.StaticNodes' | jq -r .[]); do
# Word splitting is desired
# shellcheck disable=SC2086,SC2046,SC2116
    dasel put -v $(echo $string) -f config.toml 'Node.P2P.TrustedNodes.[]'
  done

  # Set user-supplied static nodes, and also as trusted nodes
  if [ -n "${EXTRA_STATIC_NODES}" ]; then
    for string in $(jq -r .[] <<< "${EXTRA_STATIC_NODES}"); do
# Word splitting is desired
# shellcheck disable=SC2086,SC2046,SC2116
      dasel put -v $(echo $string) -f config.toml 'Node.P2P.StaticNodes.[]'
# shellcheck disable=SC2086,SC2046,SC2116
      dasel put -v $(echo $string) -f config.toml 'Node.P2P.TrustedNodes.[]'
    done
  fi

  # Sync from genesis if no snapshot was downloaded, above
  if [ ! -d /home/bsc/data/geth/chaindata ]; then
    echo "No SNAPSHOT provided in .env."
    echo "Initiating sync from genesis. This will take 2-3 months."
# Word splitting is desired for the command line parameters
# shellcheck disable=SC2086
    __db_format="--state.scheme path --db.engine pebble"
  else
    __db_format=""
  fi

# Word splitting is desired for the command line parameters
# shellcheck disable=SC2086
  exec "$@" ${__ancient} ${__db_format} --nat extip:${__public_ip} ${__verbosity} ${EXTRAS}
fi
