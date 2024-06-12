#!/bin/sh

script_file=$0

# give a guide to the user
usage() {
	cat<<EOF >&2
Usage: SENDER=xxx RECEIVER=xxx sh $script_file

Example:
  SENDER=link146asaycmtydq45kxc8evntqfgepagygelel00h \\
  RECEIVER=0x000000000000000000000000000000000000dEaD \\
  sh $script_file

Parameters:
  SENDER:    the sending address on the finschia chain
  RECEIVER:  the receiving address on the kaia chain
EOF
}

export SENDER
export RECEIVER
if [ -z "$SENDER" ] || [ -z "$RECEIVER" ]
then
	usage
	exit 2
fi

set -e

export BINARY=fnsad

# guess the testnet option
for testnet_option in "" --testnet
do
	if $BINARY keys show $SENDER --keyring-backend test --output json $testnet_option 2>/dev/null
	then
		break
	fi
done

# set node
if [ -z "$testnet_option" ]
then
	export NODE=https://finschia-rpc.finschia.io:443
else
	export NODE=https://ebony-rpc.finschia.io:443
fi

script_dir=$(dirname $script_file)
SOURCED=y sh $script_dir/swap-and-transfer-all.sh
