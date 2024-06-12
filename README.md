# Swap & transfer all script

This script generates a tx which swaps all balances except for the tx fee and
transfers the swapped coins to the kaia chain.

**Disclaimer: it's an example. You MUST provide your own values. Misconfiguration might cause PERMANENT FINANCIAL LOSS.**

## tl;dr

```shell
# 1. install the external dependencies (requirement 1).
sudo apt update && sudo apt install jq  # ubuntu

# 2. print the usage.
sh guided.sh

# 3. check the finschia client binary version (requirement 2).
fnsad version

# 4. (optional) add the corresponding pubkey of the ledger (refer to requirement 3).
fnsad keys add foo --keyring-backend test --ledger --coin-type 118

# 5. provide the variables and trigger the script.
SENDER=link146asaycmtydq45kxc8evntqfgepagygelel00h \
RECEIVER=0x000000000000000000000000000000000000dEaD \
sh guided.sh
```

## Requirements

1. The script depends on the external command `jq`.
2. The finschia client binary version MUST be >=4.0.0.
3. If you want to use the ledger, you MUST have corresponding privileges.

## Advanced usage

1. install the external dependencies (requirement 1).
2. print the usage.
    ```shell
    sh swap-and-transfer-all.sh
    ```
3. set the parameters.
    ```shell
    export NODE=https://finschia-rpc.finschia.io:443
    export BINARY=./fnsad
    export GAS=300000
    ```
4. check the finschia client binary version (requirement 2).
    ```shell
    $BINARY version
    ```
5. prepare the key (either i, ii or iii).
    1. add the corresponding pubkey of the ledger (refer to requirement 3).
        ```shell
        export KEYRING_DIR=$(mktemp -d)
        $BINARY keys add foo --home $KEYRING_DIR --keyring-backend test --ledger --coin-type 118
        ```
    2. add the key to the local wallet.
        ```shell
        export KEYRING_DIR=$(mktemp -d)
        $BINARY keys add foo --home $KEYRING_DIR --keyring-backend test --recover
        ```
    3. use the local wallet.
        ```shell
        export KEYRING_DIR=/foo
        ```
6. provide the variables and trigger the script.
    ```shell
    SENDER=link146asaycmtydq45kxc8evntqfgepagygelel00h \
    RECEIVER=0x000000000000000000000000000000000000dEaD \
    sh swap-and-transfer-all.sh
    ```
7. (optional) remove the keyring.
    ```shell
    rm -r $KEYRING_DIR
    ```

### Node information

- Finschia mainnet: https://finschia-rpc.finschia.io:443
- Ebony testnet: https://ebony-rpc.finschia.io:443

## FAQ

1. I've entered `y` on `confirm transaction before signing and broadcasting`
   but it does not do anything.
   - A) You must also confirm your transaction within your ledger device.
