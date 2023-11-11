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

  wget $(curl -s https://api.github.com/repos/bnb-chain/bsc/releases/latest |grep browser_ |grep ${NETWORK} |cut -d\" -f4)
  unzip -o ${NETWORK}.zip
  rm ${NETWORK}.zip

# Word splitting is desired for the command line parameters
# shellcheck disable=SC2086
  exec "$@" ${__ancient} snapshot prune-state
elif [ -f /home/bsc/data/convert-marker ]; then
  rm -f /home/bsc/data/convert-marker
  echo "Converting Geth DB to PBSS for continous prune. Do NOT abort this process."
  geth db hbss-to-pbss --datadir /home/bsc/data ${__ancient} 1000
  echo "Conversion done, compacting DB"
  exec geth db compact --datadir /home/bsc/data ${__ancient}
else
  if [ -n "${SNAPSHOT}" ] && [ ! -f /home/bsc/data/setupdone ]; then
    if [ -n "${__ancient}" ]; then
       __snap_dir=/home/bsc/ancient/snapshot
       __data_dir=/home/bsc/ancient
    else
       __snap_dir=/home/bsc/data/snapshot
       __data_dir=/home/bsc/data
    fi
    # Check for enough space

    __free_space=$(df -P "${__data_dir}" | awk '/[0-9]%/{print $(NF-2)}')
    if [ -z "$__free_space" ]; then
        echo "Unable to determine free disk space. This is a bug."
        echo "Aborting"
        exit 1
    fi
    __filesize=$(curl -Is "${SNAPSHOT}" | grep -i Content-Length | awk '{print $2}')
    __filesize=${__filesize%$'\r'}
    if [ -z "$__filesize" ]; then
        echo "Unable to determine SNAPSHOT size, downloading optimistically"
    elif (( $__filesize * 2 + 1073741824 > $__free_space * 1024 )); then
        __free_gib=$(( $__free_space / 1024 / 1024 ))
        __file_gib=$(( $__filesize / 1024 / 1024 / 1024 ))
        echo "SNAPSHOT is $__file_gib GiB and you have $__free_gib GiB free."
        echo "You need at least 2x the size of the snapshot plus a safety buffer of 10 GiB."
        echo "Continuing anyway, but that may fail."
    fi

    mkdir -p "${__snap_dir}"
    aria2c -c -s14 -x14 -k100M -d ${__snap_dir} --auto-file-renaming=false --conditional-get=true \
      --allow-overwrite=true "${SNAPSHOT}"
    # Unpacks into server/data-seed/geth
    tar -I lz4 -xvf "${__snap_dir}/$(basename "${SNAPSHOT}")" -C ${__data_dir}
    rm -rf ${__data_dir}/geth
    # Move from server/data-seed into ${__data_dir}
    if [ -d "${__data_dir}/server/data-seed/geth" ]; then
        mv "${__data_dir}/server/data-seed/geth" "${__data_dir}"
        rm -rf "${__data_dir}/server/data-seed"
    elif [ -d "${__data_dir}/data-seed/geth" ]; then
        mv "${__data_dir}/data-seed/geth" "${__data_dir}"
        rm -rf "${__data_dir}/data-seed"
    else
        echo "Unexpected SNAPSHOT directory layout. It's unlikely to work until the entrypoint script is adjusted."
    fi
    # If there is ancient/chain but no ancient/state move it
    if [ -d "${__data_dir}/geth/chaindata/ancient/chain" ] && [ ! -d "${__data_dir}/geth/chaindata/ancient/state" ]; then
        find "${__data_dir}/geth/chaindata/ancient/chain" -mindepth 1 -maxdepth 1 -exec mv {} "${__data_dir}/geth/chaindata/ancient/" \;
        rm -rf "${__data_dir}/geth/chaindata/ancient/chain"
    fi

    if [ -n "${__ancient}" ]; then
        rm -rf /home/bsc/data/geth
        mkdir -p /home/bsc/data/geth/chaindata
        find "/home/bsc/ancient/geth" -mindepth 1 -maxdepth 1 ! -name 'chaindata' -exec mv {} /home/bsc/data/geth/ \;
        find "/home/bsc/ancient/geth/chaindata" -mindepth 1 -maxdepth 1 ! -name 'ancient' -exec mv {} /home/bsc/data/geth/chaindata/ \;
        find "/home/bsc/ancient/geth/chaindata/ancient" -mindepth 1 -maxdepth 1 -exec mv {} "/home/bsc/ancient/" \;
        rm -rf "/home/bsc/ancient/geth"
    fi
    rm -rf "${__snap_dir}"
    touch /home/bsc/data/setupdone
  fi

  # The wget was moved down here so that repeated failures with SNAPSHOT above don't exhaust
  # the github API rate limit
  wget $(curl -s https://api.github.com/repos/bnb-chain/bsc/releases/latest |grep browser_ |grep ${NETWORK} |cut -d\" -f4)
  unzip -o ${NETWORK}.zip
  rm ${NETWORK}.zip

  # Remove unwanted settings in config.toml
  dasel delete -f config.toml Node.LogConfig
  dasel delete -f config.toml Node.HTTPHost
  dasel delete -f config.toml Node.HTTPVirtualHosts

  # Duplicate binance-supplied static nodes to trusted nodes
  for string in $(dasel -f config.toml -w json 'Node.P2P.StaticNodes' | jq -r .[]); do
    dasel put -v $(echo $string) -f config.toml 'Node.P2P.TrustedNodes.[]'
  done

  # Set user-supplied static nodes, and also as trusted nodes
  if [ -n "${EXTRA_STATIC_NODES}" ]; then
    for string in $(jq -r .[] <<< "${EXTRA_STATIC_NODES}"); do
      dasel put -v $(echo $string) -f config.toml 'Node.P2P.StaticNodes.[]'
      dasel put -v $(echo $string) -f config.toml 'Node.P2P.TrustedNodes.[]'
    done
  fi

  # Sync from genesis if no snapshot was downloaded, above
  if [ ! -d /home/bsc/data/geth/chaindata ]; then
    echo "No SNAPSHOT provided in .env."
    echo "Initiating PBSS sync from genesis. This will take 2-3 months."
    geth --state.scheme path --datadir /home/bsc/data ${__ancient} init genesis.json
  fi

# Word splitting is desired for the command line parameters
# shellcheck disable=SC2086
  exec "$@" ${__ancient} --nat extip:${__public_ip} ${__verbosity}
fi
