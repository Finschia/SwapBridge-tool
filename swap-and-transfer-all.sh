#!/bin/sh

# Exit codes
# 0: success (including cancellation by you)
# 1: unhandled error
# 2: error in your input
# 3: precondition violated on chain (not you)
# 4: precondition violated on chain (by you)

script_file=$0

# developers only, end users are not expected to modify these values
# you MUST know what you're doing
gas_price=0.015              # gas price of the chain
binary_default=fnsad         # the default value of BINARY
home_dir_default=~/.finschia # the default value of HOME_DIR
gas_default=500000           # the default value of GAS
ledger_default=yes           # the default value of LEDGER

# clean the temporary files
clean() {
	if [ -n "$unsigned_file" ]
	then
		rm $unsigned_file
	fi
	if [ -n "$signed_file" ]
	then
		rm $signed_file
	fi
}
trap clean EXIT INT TERM

# give a guide to the user
usage() {
	if [ -n "$SOURCED" ]
	then
		return
	fi

	cat<<EOF >&2
Usage: SENDER=xxx RECEIVER=xxx [BINARY=xxx] [HOME_DIR=xxx] [GAS=xxx] [LEDGER=xxx] sh $script_file

Example:
  SENDER=link146asaycmtydq45kxc8evntqfgepagygelel00h RECEIVER=0x000000000000000000000000000000000000dEaD sh $script_file

Defaults:
  BINARY=$binary_default
  HOME_DIR=$home_dir_default
  GAS=$gas_default
  LEGDER=$ledger_default
EOF
}

add_violation() {
	local add="Error: $*"

	if [ -z "$violations" ]
	then
		violations="$add"
	else
		violations="$violations\n$add"
	fi
}

# validate the sender address
[ -n "$SENDER" ] || add_violation "no sender provided"

# validate the receiver address
[ -n "$RECEIVER" ] || add_violation "no receiver provided"

# validate the binary
eval BINARY=$BINARY
BINARY=${BINARY:-$binary_default}
which -s $BINARY || add_violation "no such binary: $BINARY"

# validate the home directory
eval HOME_DIR=$HOME_DIR
HOME_DIR=${HOME_DIR:-$home_dir_default}
[ -d "$HOME_DIR" ] || add_violation "HOME_DIR not exists: $HOME_DIR"

# validate the gas amount
GAS=${GAS:-$gas_default}
[ -n "$(echo "if ($GAS > 0) if ($GAS % 1 == 0) 42" | bc)" ] || add_violation "gas should be a positive integer"

LEDGER=${LEDGER-$ledger_default}

# exit with hints if any violations on the inputs are found
if [ -n "$violations" ]
then
	echo $violations >&2
	echo >&2
	usage
	exit 2
fi

set -e

# get the first swap information
swaps=$($BINARY q fswap swaps --home $HOME_DIR --output json)
num_swaps=$(echo $swaps | jq ".swaps | length")
case $num_swaps in
	0)
		echo Error: no swaps found >&2
		exit 3
		;;
	1)
		;;
	*)
		echo Error: multiple swaps found: $num_swaps swaps >&2
		exit 3
		;;
esac
swap=$(echo $swaps | jq .swaps[0])

# assure the x/fbridge supports swapped coins
to_denom_by_swap=$(echo $swap | jq -r .to_denom)
fbridge_params=$($BINARY q fbridge params --home $HOME_DIR --output json)
to_denom_by_fbridge=$(echo $fbridge_params | jq -r .params.target_denom)
[ $to_denom_by_swap = $to_denom_by_fbridge ] || (echo Error: fbridge not supports swapped coins: $to_denom_by_swap != $to_denom_by_fbridge >&2; exit 3)
to_denom=$to_denom_by_swap

# get the balance for the fee
staking_params=$($BINARY q staking params --home $HOME_DIR --output json)
bond_denom=$(echo $staking_params | jq -r .bond_denom)
fee_balance=$($BINARY q bank balances $SENDER --denom $bond_denom --home $HOME_DIR --output json | jq -r .amount)

# evaluate the fee
fee_amount=$(echo "v = $GAS * $gas_price; if (v % 1 != 0) v += 1; v / 1" | bc)
fee_balance=$(echo "$fee_balance - $fee_amount" | bc)
if [ -n "$(echo "if ($fee_balance < 0) 42" | bc)" ]
then
	echo Error: not enough balance left for the tx fee >&2
	exit 4
fi

# evaluate the swap amount
from_denom=$(echo $swap | jq -r .from_denom)
if [ $from_denom = $bond_denom ]
then
	swap_amount=$fee_balance
else
	swap_amount=$($BINARY q bank balances $SENDER --denom $from_denom --home $HOME_DIR --output json | jq -r .amount)
fi
if [ -n "$(echo "if ($swap_amount <= 0) 42" | bc)" ]
then
	echo Error: not enough balance left for the swap >&2
	exit 4
fi

# generate the x/fswap swap message
chain_id=$($BINARY q block --home $HOME_DIR | jq -r .block.header.chain_id)
swap_tx=$($BINARY tx fswap swap $SENDER $swap_amount$from_denom $to_denom --gas $GAS --fees $fee_amount$bond_denom --generate-only --chain-id $chain_id --output json)
swap_msg=$(echo $swap_tx | jq -c .body.messages[0])

# generate the x/fbridge transfer message
rate=$(echo $swap | jq -r ".swap_rate")
transfer_amount=$(echo "$swap_amount * $rate / 1" | bc)
transfer_tx=$($BINARY tx fbridge transfer $RECEIVER $transfer_amount$to_denom --from $SENDER --chain-id $chain_id --generate-only --output json)
transfer_msg=$(echo $transfer_tx | jq -c .body.messages[0])

# combine the messages into a tx
unsigned_file=$(mktemp)
echo $swap_tx | jq -c ".body.messages = [$swap_msg, $transfer_msg]" >$unsigned_file

# ask for the confirmation
jq -Mc . $unsigned_file
printf "\nconfirm transaction before signing and broadcasting [y/N]: "
read confirm

# check the answer and cancel the process if the user denies
confirm=$(echo $confirm | tr [:upper:] [:lower:])
if [ "$confirm" != y ]
then
	echo cancelled transaction
	exit
fi

# sign the tx
signed_file=$(mktemp)
case $(echo $LEDGER | tr [:upper:] [:lower:]) in
	no|n|0|"")  # do not use ledger
		$BINARY tx sign $unsigned_file --chain-id $chain_id --home $HOME_DIR --from $SENDER --output-document $signed_file
		;;
	*)
		$BINARY tx sign $unsigned_file --chain-id $chain_id --home $HOME_DIR --from $SENDER --output-document $signed_file --ledger --sign-mode amino-json || (echo Error: failed to sign the tx: check your ledger >&2; exit 2)
		;;
esac

# broadcast the tx
$BINARY tx broadcast $signed_file --home $HOME_DIR
