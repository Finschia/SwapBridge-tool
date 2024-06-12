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
gas_price=0.015                  # gas price of the chain
keyring_backend=test             # supporting keyring backend
binary_default=fnsad             # the default value of BINARY
keyring_dir_default=~/.finschia  # the default value of KEYRING_DIR
gas_default=500000               # the default value of GAS

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
Usage: SENDER=xxx RECEIVER=xxx NODE=xxx [BINARY=xxx] [KEYRING_DIR=xxx] [GAS=xxx] sh $script_file

Example:
  SENDER=link146asaycmtydq45kxc8evntqfgepagygelel00h \\
  RECEIVER=0x000000000000000000000000000000000000dEaD \\
  NODE=tcp://localhost:26657 \\
  sh $script_file

Parameters:
  SENDER:       the sending address on the finschia chain (required)
  RECEIVER:     the receiving address on the kaia chain (required)
  NODE:         the finschia node address to connect to (required)
  BINARY:       the path of the binary (default: $binary_default)
  KEYRING_DIR:  the client keyring directory (default: $keyring_dir_default)
  GAS:          the gas wanted for the tx (default: $gas_default)
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

# validate the node address
[ -n "$NODE" ] || add_violation "no node provided"

# validate the binary
eval BINARY=$BINARY
BINARY=${BINARY:-$binary_default}
which -s $BINARY || add_violation "no such binary: $BINARY"

# validate the keyring directory
# c.f. will be used for --home, because of a bug
eval KEYRING_DIR=$KEYRING_DIR
KEYRING_DIR=${KEYRING_DIR:-$keyring_dir_default}
[ -d "$KEYRING_DIR" ] || add_violation "KEYRING_DIR not exists: $KEYRING_DIR"

# validate the gas amount
GAS=${GAS:-$gas_default}
[ -n "$(echo "if ($GAS > 0) if ($GAS % 1 == 0) 42" | bc)" ] || add_violation "gas should be a positive integer"

# exit with hints if any violations on the inputs are found
if [ -n "$violations" ]
then
	echo $violations >&2
	echo >&2
	usage
	exit 2
fi

set -e

# find the sender key and guess the testnet option
for testnet_option in "" --testnet
do
	if sender_key=$($BINARY keys show $SENDER --home $KEYRING_DIR --keyring-backend $keyring_backend --output json $testnet_option 2>/dev/null)
	then
		break
	fi
done
[ -n "$sender_key" ] || (echo Error: no sender key found: $SENDER >&2; exit 2)

# get the first swap information
swaps=$($BINARY q fswap swaps --node $NODE --output json)
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
to_denom_by_fbridge=$($BINARY q fbridge params --node $NODE --output json | jq -r .params.target_denom)
[ $to_denom_by_swap = $to_denom_by_fbridge ] || (echo Error: fbridge not supports swapped coins: $to_denom_by_swap != $to_denom_by_fbridge >&2; exit 3)
to_denom=$to_denom_by_swap

# get the balance for the fee
bond_denom=$($BINARY q staking params --node $NODE --output json | jq -r .bond_denom)
fee_balance=$($BINARY q bank balances $SENDER --denom $bond_denom --node $NODE --output json $testnet_option | jq -r .amount)

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
	swap_amount=$($BINARY q bank balances $SENDER --denom $from_denom --node $NODE --output json $testnet_option | jq -r .amount)
fi
if [ -n "$(echo "if ($swap_amount <= 0) 42" | bc)" ]
then
	echo Error: not enough balance left for the swap >&2
	exit 4
fi

# generate the x/fswap swap message
chain_id=$($BINARY q block --node $NODE | jq -r .block.header.chain_id)
swap_tx=$($BINARY tx fswap swap $SENDER $swap_amount$from_denom $to_denom --gas $GAS --fees $fee_amount$bond_denom --generate-only --chain-id $chain_id --output json $testnet_option)
swap_msg=$(echo $swap_tx | jq -c .body.messages[0])

# generate the x/fbridge transfer message
rate=$(echo $swap | jq -r ".swap_rate")
transfer_amount=$(echo "$swap_amount * $rate / 1" | bc)
transfer_tx=$($BINARY tx fbridge transfer $RECEIVER $transfer_amount$to_denom --from $SENDER --chain-id $chain_id --generate-only --output json $testnet_option)
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
if [ $(echo $sender_key | jq -r .type) = ledger ]
then
	ledger_option="--ledger --sign-mode amino-json"
fi
signed_file=$(mktemp)
$BINARY tx sign $unsigned_file --chain-id $chain_id --home $KEYRING_DIR --keyring-backend $keyring_backend --from $SENDER --output-document $signed_file $testnet_option $ledger_option

# broadcast the tx
$BINARY tx broadcast $signed_file --node $NODE --output json
