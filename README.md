# Swap & transfer all script

This script generates a tx which swaps all balances except for the tx fee and
transfers the swapped coins to the kaia chain.

## tl;dr

```shell
# 1. make sure client.toml is up-to-date (requirement 1).
vi ~/.finschia/config/client.toml

# 2. add the corresponding pubkey of the ledger.
#    please refer to requirement 2.
fnsad keys add myaccount --ledger --coin-type 118

# 3. install the external dependencies (requirement 3).
sudo apt update && sudo apt install jq  # ubuntu

# 4. print the usage.
./swap-and-transfer-all

# 5. provide the variables and trigger the script.
#    CAUTION: it's an example. You MUST provide your own values.
#    Misconfiguration might cause PERMANENT FINANCIAL LOSS.
./swap-and-transfer-all link146asaycmtydq45kxc8evntqfgepagygelel00h 0x000000000000000000000000000000000000dEaD
```

## Requirements

1. The script uses finschia-sdk CLIs under the hood, so the user MUST update
`client.toml`.
2. The script will try to access the ledger, so the user MUST have
corresponding privileges.
3. The script depends on the external command `jq`.

## FAQ

1. I've entered `y` on `confirm transaction before signing and broadcasting`
   but it does not do anything.
   - A) You must also confirm your transaction within your ledger device.
