#!/bin/bash

# ------------------------------------------------------------------------------
#
#   Copyright 2023 Valory AG
#
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.
#
# ------------------------------------------------------------------------------

# Convert Hex to Dec
hex_to_decimal() {
    $PYTHON_CMD -c "print(int('$1', 16))"
}

# Convert Wei to Dai
wei_to_dai() {
    local wei="$1"
    local decimal_precision=4  # Change this to your desired precision
    local dai=$($PYTHON_CMD -c "print('%.${decimal_precision}f' % ($wei / 1000000000000000000.0))")
    echo "$dai"
}

# Function to get the balance of an Ethereum address
get_balance() {
    local address="$1"
    curl -s -S -X POST \
        -H "Content-Type: application/json" \
        --data "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBalance\",\"params\":[\"$address\",\"latest\"],\"id\":1}" "$rpc" | \
        $PYTHON_CMD -c "import sys, json; print(json.load(sys.stdin)['result'])"
}

# Function to ensure a minimum balance for an Ethereum address
ensure_minimum_balance() {
    local address="$1"
    local minimum_balance="$2"
    local address_description="$3"
    local token="${4:-"0x0000000000000000000000000000000000000000"}"

    erc20_balance=0
    if [ ! "$token" = "0x0000000000000000000000000000000000000000" ]
    then
        erc20_balance=$(poetry run python "../scripts/erc20_balance.py" "$token" "$address" "$rpc")
    fi

    balance_hex=$(get_balance "$address")
    balance=$(hex_to_decimal "$balance_hex")
    balance=$($PYTHON_CMD -c "print(int($balance) + int($erc20_balance))")

    echo "Checking balance of $address_description (minimum required $(wei_to_dai "$minimum_balance") DAI):"
    echo "  - Address: $address"
    echo "  - Balance: $(wei_to_dai "$balance") DAI"

    if [ "$($PYTHON_CMD -c "print($balance < $minimum_balance)")" == "True" ]; then
        echo ""
        echo "    Please, fund address $address with at least $(wei_to_dai "$minimum_balance") DAI."

        local spin='-\|/'
        local i=0
        local cycle_count=0
        while [ "$($PYTHON_CMD -c "print($balance < $minimum_balance)")" == "True" ]; do
            printf "\r    Waiting... %s" "${spin:$i:1} "
            i=$(((i + 1) % 4))
            sleep .1

            # This will be checked every 10 seconds (100 cycles).
            cycle_count=$((cycle_count + 1))
            if [ "$cycle_count" -eq 100 ]; then
                balance_hex=$(get_balance "$address")
                balance=$(hex_to_decimal "$balance_hex")
                balance=$((erc20_balance+balance))
                cycle_count=0
            fi
        done

        printf "\r    Waiting...   \n"
        echo ""
        echo "  - Updated balance: $(wei_to_dai "$balance") DAI"
    fi

    echo "    OK."
    echo ""
}

# ensure erc20 balance
ensure_erc20_balance() {
    local address="$1"
    local minimum_balance="$2"
    local address_description="$3"
    local token="$4"
    local token_name="$5"

    balance=0
    if [ ! "$token" = "0x0000000000000000000000000000000000000000" ]
    then
        balance=$(poetry run python "../scripts/erc20_balance.py" "$token" "$address" "$rpc")
    fi

    echo "Checking balance of $address_description (minimum required $(wei_to_dai "$minimum_balance") $token_name):"
    echo "  - Address: $address"
    echo "  - Balance: $(wei_to_dai "$balance") $token_name"

    if [ "$($PYTHON_CMD -c "print($balance < $minimum_balance)")" == "True" ]; then
        echo ""
        echo "    Please, fund address $address with at least $(wei_to_dai "$minimum_balance")."

        local spin='-\|/'
        local i=0
        local cycle_count=0
        while [ "$($PYTHON_CMD -c "print($balance < $minimum_balance)")" == "True" ]; do
            printf "\r    Waiting... %s" "${spin:$i:1} "
            i=$(((i + 1) % 4))
            sleep .1

            # This will be checked every 10 seconds (100 cycles).
            cycle_count=$((cycle_count + 1))
            if [ "$cycle_count" -eq 100 ]; then
                balance=$(poetry run python "../scripts/erc20_balance.py" "$token" "$address" "$rpc")
                cycle_count=0
            fi
        done

        printf "\r    Waiting...   \n"
        echo ""
        echo "  - Updated balance: $(wei_to_dai "$balance") $token_name"
    fi

    echo "    OK."
    echo ""
}

# Get the address from a keys.json file
get_address() {
    local keys_json_path="$1"

    if [ ! -f "$keys_json_path" ]; then
        echo "Error: $keys_json_path does not exist."
        return 1
    fi

    local address_start_position=17
    local address=$(sed -n 3p "$keys_json_path")
    address=$(echo "$address" |
        awk '{ print substr( $0, '$address_start_position', length($0) - '$address_start_position' - 1 ) }')

    echo -n "$address"
}

# Get the private key from a keys.json file
get_private_key() {
    local keys_json_path="$1"

    if [ ! -f "$keys_json_path" ]; then
        echo "Error: $keys_json_path does not exist."
        return 1
    fi

    local private_key_start_position=21
    local private_key=$(sed -n 4p "$keys_json_path")
    private_key=$(echo -n "$private_key" |
        awk '{ printf substr( $0, '$private_key_start_position', length($0) - '$private_key_start_position' ) }')

    private_key=$(echo -n "$private_key" | awk '{gsub(/\\"/, "\"", $0); print $0}')
    private_key="${private_key#0x}"

    echo -n "$private_key"
}

# Function to warm start the policy
warm_start() {
    echo '["claude-prediction-offline", "claude-prediction-online", "deepmind-optimization", "deepmind-optimization-strong", "prediction-offline", "prediction-offline-sme", "prediction-online", "prediction-online-sme"]' | sudo tee "$PWD/../$store/available_tools_store.json"  > /dev/null
    echo '{"counts": [23, 16, 54, 52, 20, 113, 33, 54], "eps": 0.1, "rewards": [0.21330030417382723, -0.06394516434480157, 0.5042296458897277, 0.38925697131774417, -0.2978133327512751, 1.055336834629253, -0.5935249657470777, 0.507192767958923]}' | sudo tee "$PWD/../$store/policy_store.json"  > /dev/null
    echo '{}' | sudo tee "$PWD/../$store/utilized_tools.json"  > /dev/null
}

# Function to add a volume to a service in a Docker Compose file
add_volume_to_service() {
    local compose_file="$1"
    local service_name="$2"
    local volume_name="$3"
    local volume_path="$4"

    # Check if the Docker Compose file exists
    if [ ! -f "$compose_file" ]; then
        echo "Docker Compose file '$compose_file' not found."
        return 1
    fi

    # Check if the service exists in the Docker Compose file
    if ! grep -q "^[[:space:]]*${service_name}:" "$compose_file"; then
        echo "Service '$service_name' not found in '$compose_file'."
        return 1
    fi

    if grep -q "^[[:space:]]*volumes:" "$compose_file"; then
        awk -v volume_path="$volume_path" -v volume_name="$volume_name" '
            /^ *volumes:/ {
                found_volumes = 1
                print
                print "      - " volume_path ":" volume_name ":Z"
                next
            }
            1
        ' "$compose_file" > temp_compose_file
    else
        awk -v service_name="$service_name" -v volume_path="$volume_path" -v volume_name="$volume_name" '
            /^ *'"$service_name"':/ {
                found_service = 1
                print
                print "    volumes:"
                print "      - " volume_path ":" volume_name ":Z"
                next
            }
            /^ *$/ && found_service == 1 {
                print "    volumes:"
                print "      - " volume_path ":" volume_name ":Z"
                found_service = 0
            }
            1
        ' "$compose_file" > temp_compose_file
    fi

    mv temp_compose_file "$compose_file"
}

# Function to retrieve on-chain service state (requires env variables set to use --use-custom-chain)
get_on_chain_service_state() {
    local service_id="$1"
    local service_info=$(poetry run autonomy service --use-custom-chain info "$service_id")
    local state="$(echo "$service_info" | awk '/Service State/ {sub(/\|[ \t]*Service State[ \t]*\|[ \t]*/, ""); sub(/[ \t]*\|[ \t]*/, ""); print}')"
    echo "$state"
}

# stake or unstake a service
perform_staking_ops() {
    local unstake="$1"
    output=$(poetry run python "../scripts/staking.py" "$service_id" "$CUSTOM_SERVICE_REGISTRY_ADDRESS" "$CUSTOM_STAKING_ADDRESS" "../$operator_pkey_path" "$rpc" "$unstake" "$SKIP_LAST_EPOCH_REWARDS")
    if [[ $? -ne 0 ]]; then
      echo "Swapping Safe owner failed.\n$output"
      exit 1
    fi
    echo "$output"
}


store=".trader_runner"
rpc_path="$store/rpc.txt"
operator_keys_file="$store/operator_keys.json"
operator_pkey_path="$store/operator_pkey.txt"
keys_json="keys.json"
keys_json_path="$store/$keys_json"
agent_pkey_path="$store/agent_pkey.txt"
agent_address_path="$store/agent_address.txt"
service_id_path="$store/service_id.txt"
service_safe_address_path="$store/service_safe_address.txt"
store_readme_path="$store/README.txt"

# Check the command-line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --with-staking) use_staking=true ;;
        *) echo "Unknown parameter: $1" ;;
    esac
    shift
done

# Function to create the .trader_runner storage
create_storage() {
    local rpc="$1"

    echo "This is the first run of the script. The script will generate new operator and agent instance addresses."
    echo ""

    mkdir "../$store"

    # Generate README.txt file
    echo -e 'IMPORTANT:\n\n' \
        '   This folder contains crucial configuration information and autogenerated keys for your Trader agent.\n' \
        '   Please back up this folder and be cautious if you are modifying or sharing these files to avoid potential asset loss.' > "../$store_readme_path"

    # Generate the RPC file
    echo -n "$rpc" > "../$rpc_path"

    # Generate the operator's key
    poetry run autonomy generate-key -n1 ethereum
    mv "$keys_json" "../$operator_keys_file"
    operator_address=$(get_address "../$operator_keys_file")
    operator_pkey=$(get_private_key "../$operator_keys_file")
    echo -n "$operator_pkey" > "../$operator_pkey_path"
    echo "Your operator's autogenerated public address: $operator_address"
    echo "(The same address will be used as the service owner.)"

    # Generate the agent's key
    poetry run autonomy generate-key -n1 ethereum
    mv "$keys_json" "../$keys_json_path"
    agent_address=$(get_address "../$keys_json_path")
    agent_pkey=$(get_private_key "../$keys_json_path")
    echo -n "$agent_pkey" > "../$agent_pkey_path"
    echo -n "$agent_address" > "../$agent_address_path"
    echo "Your agent instance's autogenerated public address: $agent_address"
    echo ""
}

# Function to read and load the .trader_runner storage information if it exists.
# Also sets `first_run` flag to identify whether we are running the script for the first time.
try_read_storage() {
    if [ -d $store ]; then

        # INFO: This is a fix to avoid corrupting already-created stores
        if [[ -f "$operator_keys_file" && ! -f "$operator_pkey_path" ]]; then
            operator_pkey=$(get_private_key "$operator_keys_file")
            echo -n "$operator_pkey" > "$operator_pkey_path"
        fi

        # INFO: This is a fix to avoid corrupting already-created stores
        if [[ -f "$keys_json_path" && ! -f "$agent_pkey_path" ]]; then
            agent_pkey=$(get_private_key "$keys_json_path")
            echo -n "$agent_pkey" > "$agent_pkey_path"
        fi

        first_run=false
        paths="$rpc_path $operator_keys_file $operator_pkey_path $keys_json_path $agent_address_path $agent_pkey_path $service_id_path"

        for file in $paths; do
            if ! [ -f "$file" ]; then
                if [ "$file" != $service_safe_address_path ] && [ "$file" != $service_id_path ]; then
                    echo "The runner's store is corrupted!"
                    echo "Please manually investigate the $store folder"
                    echo "Make sure that you do not lose your keys or any other important information!"
                    exit 1
                fi
            fi
        done

        rpc=$(cat $rpc_path)
        agent_address=$(cat $agent_address_path)
        operator_address=$(get_address "$operator_keys_file")
        if [ -f "$service_id_path" ]; then
            service_id=$(cat $service_id_path)
        fi
    else
        first_run=true
    fi
}

# ------------------
# Script starts here
# ------------------

set -e  # Exit script on first error
echo ""
echo "---------------"
echo " Trader runner "
echo "---------------"
echo ""
echo "This script will assist you in setting up and running the Trader service (https://github.com/valory-xyz/trader)."
echo ""

# Check if user is inside a venv
if [[ "$VIRTUAL_ENV" != "" ]]
then
    echo "Please exit the virtual environment!"
    exit 1
fi

# Check dependencies
if command -v python3 >/dev/null 2>&1; then
    PYTHON_CMD="python3"
elif command -v python >/dev/null 2>&1; then
    PYTHON_CMD="python"
else
    echo >&2 "Python is not installed!";
    exit 1
fi

if [[ "$($PYTHON_CMD --version 2>&1)" != "Python 3.10."* ]] && [[ "$($PYTHON_CMD --version 2>&1)" != "Python 3.11."* ]]; then
    echo >&2 "Python version >=3.10.0, <3.12.0 is required but found $($PYTHON_CMD --version 2>&1)";
    exit 1
fi

command -v git >/dev/null 2>&1 ||
{ echo >&2 "Git is not installed!";
  exit 1
}

command -v poetry >/dev/null 2>&1 ||
{ echo >&2 "Poetry is not installed!";
  exit 1
}

command -v docker >/dev/null 2>&1 ||
{ echo >&2 "Docker is not installed!";
  exit 1
}

docker rm -f abci0 node0 trader_abci_0 trader_tm_0 &> /dev/null ||
{ echo >&2 "Docker is not running!";
  exit 1
}

try_read_storage

# Prompt for RPC
[[ -z "${rpc}" ]] && read -rsp "Enter a Gnosis RPC that supports eth_newFilter [hidden input]: " rpc && echo || rpc="${rpc}"

# Check if eth_newFilter is supported
new_filter_supported=$(curl -s -S -X POST \
  -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_newFilter","params":["invalid"],"id":1}' "$rpc" | \
  $PYTHON_CMD -c "import sys, json; print(json.load(sys.stdin)['error']['message']=='The method eth_newFilter does not exist/is not available')")

if [ "$new_filter_supported" = True ]
then
    echo "The given RPC ($rpc) does not support 'eth_newFilter'! Terminating script..."
    exit 1
fi

# clone repo
directory="trader"
# This is a tested version that works well.
# Feel free to replace this with a different version of the repo, but be careful as there might be breaking changes
service_version="v0.8.2"
service_repo=https://github.com/valory-xyz/$directory.git
if [ -d $directory ]
then
    echo "Detected an existing $directory repo. Using this one..."
    echo "Please stop and manually delete the $directory repo if you updated the service's version ($service_version)!"
    echo "You can run the following command, or continue with the pre-existing version of the service:"
    echo "rm -r $directory"
else
    echo "Cloning the $directory repo..."
    git clone --depth 1 --branch $service_version $service_repo
fi

cd $directory
if [ "$(git rev-parse --is-inside-work-tree)" = true ]
then
    poetry install
    poetry run autonomy packages sync
else
    echo "$directory is not a git repo!"
    exit 1
fi

if [ "$first_run" = "true" ]
then
    create_storage "$rpc"
fi

echo ""
echo "-----------------------------------------"
echo "Checking Autonolas Protocol service state"
echo "-----------------------------------------"

gnosis_chain_id=100
n_agents=1

# setup the minting tool
export CUSTOM_CHAIN_RPC=$rpc
export CUSTOM_CHAIN_ID=$gnosis_chain_id
export CUSTOM_SERVICE_MANAGER_ADDRESS="0x04b0007b2aFb398015B76e5f22993a1fddF83644"
export CUSTOM_SERVICE_REGISTRY_ADDRESS="0x9338b5153AE39BB89f50468E608eD9d764B755fD"
export CUSTOM_STAKING_ADDRESS="0x337b53b4471775a7F87c8D5d077B17BbF9a0D369"
export CUSTOM_OLAS_ADDRESS="0xFC846A9EfC5C00d347Fd5A3759017DebeAdA3B74"
export CUSTOM_SERVICE_REGISTRY_TOKEN_UTILITY_ADDRESS="0xa45E64d13A30a51b91ae0eb182e88a40e9b18eD8"
export CUSTOM_GNOSIS_SAFE_PROXY_FACTORY_ADDRESS="0x3C1fF68f5aa342D296d4DEe4Bb1cACCA912D95fE"
export CUSTOM_GNOSIS_SAFE_SAME_ADDRESS_MULTISIG_ADDRESS="0x6e7f594f680f7aBad18b7a63de50F0FeE47dfD06"
export CUSTOM_MULTISEND_ADDRESS="0x40A2aCCbd92BCA938b02010E17A5b8929b49130D"
export AGENT_ID=12
export MECH_AGENT_ADDRESS="0x77af31De935740567Cf4fF1986D04B2c964A786a"
export WXDAI_ADDRESS="0xe91D153E0b41518A2Ce8Dd3D7944Fa863463a97d"


if [ -z ${service_id+x} ];
then
    # Check balances
    suggested_amount=50000000000000000
    ensure_minimum_balance "$operator_address" $suggested_amount "operator's address"

    echo "[Service owner] Minting your service on the Gnosis chain..."

    # create service
    nft="bafybeig64atqaladigoc3ds4arltdu63wkdrk3gesjfvnfdmz35amv7faq"
    cmd="poetry run autonomy mint \
      --skip-hash-check \
      --use-custom-chain \
      service packages/valory/services/$directory/ \
      --key \"../$operator_pkey_path\" \
      --nft $nft \
      -a $AGENT_ID \
      -n $n_agents \
      --threshold $n_agents"

    if [ "${use_staking}" = true ]; then
      cost_of_bonding=1000000000000000000
      cmd+=" -c $cost_of_bonding --token $CUSTOM_OLAS_ADDRESS"
    else
      cost_of_bonding=10000000000000000
      cmd+=" -c $cost_of_bonding"
    fi
    service_id=$(eval $cmd)
    # parse only the id from the response
    service_id="${service_id##*: }"
    # validate id
    if ! [[ "$service_id" =~ ^[0-9]+$ || "$service_id" =~ ^[-][0-9]+$ ]]
    then
        echo "Service minting failed: $service_id"
        exit 1
    fi

    echo -n "$service_id" > "../$service_id_path"
fi

# Update the on-chain service if outdated
packages="packages/packages.json"
local_service_hash="$(grep 'service' $packages | awk -F: '{print $2}' | tr -d '", ' | head -n 1)"
remote_service_hash=$(poetry run python "../scripts/service_hash.py")
operator_address=$(get_address "../$operator_keys_file")

if [ "$local_service_hash" != "$remote_service_hash" ]; then
    echo ""
    echo "Your currently minted on-chain service (id $service_id) mismatches the fetched trader service ($service_version):"
    echo "  - Local service hash ($service_version): $local_service_hash"
    echo "  - On-chain service hash (id $service_id): $remote_service_hash"
    echo ""
    echo "This is most likely caused due to an update of the trader service code."
    echo "The script will proceed now to update the on-chain service."
    echo "The operator and agent addresses need to have enough funds so that the process is not interrupted."
    echo ""

    response="y"
    if [ "${use_staking}" = true ]; then
      echo "Warning: updating the on-chain may require that your service is unstaked."
      echo "Continuing will automatically unstake your service if it is staked, which may effect your staking rewards."
      echo "Do you want to continue? [y/N]"
      read -r response
    fi

    if [[ ! "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        echo "Skipping on-chain hash update."
    else
      # unstake the service
      if [ "${use_staking}" = true ]; then
          perform_staking_ops true
      fi

      # Check balances
      suggested_amount=50000000000000000
      ensure_minimum_balance "$operator_address" $suggested_amount "operator's address"

      suggested_amount=50000000000000000
      ensure_minimum_balance $agent_address $suggested_amount "agent instance's address"

      echo "------------------------------"
      echo "Updating on-chain service $service_id"
      echo "------------------------------"
      echo ""
      echo "PLEASE, DO NOT INTERRUPT THIS PROCESS."
      echo ""
      echo "Cancelling the on-chain service update prematurely could lead to an inconsistent state of the Safe or the on-chain service state, which may require manual intervention to resolve."
      echo ""

      # TODO this condition should be increased to be service_state=DEPLOYED && current_safe_owner=agent_address.
      # Otherwise the script will not recover the on-chain state in the (rare) case where this transaction succeeds but terminating transaction fails.
      if [ "$(get_on_chain_service_state "$service_id")" == "DEPLOYED" ]; then
          # transfer the ownership of the Safe from the agent to the service owner
          # (in a live service, this should be done by sending a 0 DAI transfer to its Safe)
          service_safe_address=$(<"../$service_safe_address_path")
          echo "[Agent instance] Swapping Safe owner..."
          output=$(poetry run python "../scripts/swap_safe_owner.py" "$service_safe_address" "../$agent_pkey_path" "$operator_address" "$rpc")
          if [[ $? -ne 0 ]]; then
              echo "Swapping Safe owner failed.\n$output"
              exit 1
          fi
          echo "$output"
      fi

      # terminate current service
      if [ "$(get_on_chain_service_state "$service_id")" == "DEPLOYED" ]; then
          echo "[Service owner] Terminating on-chain service $service_id..."
          output=$(
              poetry run autonomy service \
                  --use-custom-chain \
                  terminate "$service_id" \
                  --key "../$operator_pkey_path"
          )
          if [[ $? -ne 0 ]]; then
              echo "Terminating service failed.\n$output"
              echo "Please, delete or rename the ./trader folder and try re-run this script again."
              exit 1
          fi
      fi

      # unbond current service
      if [ "$(get_on_chain_service_state "$service_id")" == "TERMINATED_BONDED" ]; then
          echo "[Operator] Unbonding on-chain service $service_id..."
          output=$(
              poetry run autonomy service \
                  --use-custom-chain \
                  unbond "$service_id" \
                  --key "../$operator_pkey_path"
          )
          if [[ $? -ne 0 ]]; then
              echo "Unbonding service failed.\n$output"
              echo "Please, delete or rename the ./trader folder and try re-run this script again."
              exit 1
          fi
      fi

      # update service
      if [ "$(get_on_chain_service_state "$service_id")" == "PRE_REGISTRATION" ]; then
          echo "[Service owner] Updating on-chain service $service_id..."
          nft="bafybeig64atqaladigoc3ds4arltdu63wkdrk3gesjfvnfdmz35amv7faq"
          export cmd="poetry run autonomy mint \
                  --skip-hash-check \
                  --use-custom-chain \
                  service packages/valory/services/trader/ \
                  --key \"../$operator_pkey_path\" \
                  --nft $nft \
                  -a $AGENT_ID \
                  -n $n_agents \
                  --threshold $n_agents \
                  --update \"$service_id\""
          if [ "${use_staking}" = true ]; then
              cost_of_bonding=1000000000000000000
              cmd+=" -c $cost_of_bonding --token $CUSTOM_OLAS_ADDRESS"
          else
              cost_of_bonding=10000000000000000
              cmd+=" -c $cost_of_bonding"
          fi
          output=$(eval "$cmd")
          if [[ $? -ne 0 ]]; then
              echo "Updating service failed.\n$output"
              echo "Please, delete or rename the ./trader folder and try re-run this script again."
              exit 1
          fi
      fi

      echo ""
      echo "Finished updating on-chain service $service_id."
  fi
fi


echo ""
echo "Ensuring on-chain service $service_id is in DEPLOYED state..."

if [ "$(get_on_chain_service_state "$service_id")" != "DEPLOYED" ]; then
    suggested_amount=25000000000000000
    ensure_minimum_balance "$operator_address" $suggested_amount "operator's address"
fi

# activate service
if [ "$(get_on_chain_service_state "$service_id")" == "PRE_REGISTRATION" ]; then
    echo "[Service owner] Activating registration for on-chain service $service_id..."
    export cmd="poetry run autonomy service --use-custom-chain activate --key "../$operator_pkey_path" "$service_id""
    if [ "${use_staking}" = true ]; then
        minimum_olas_balance=1000000000000000000
        ensure_erc20_balance "$operator_address" $minimum_olas_balance "operator's address" $CUSTOM_OLAS_ADDRESS "OLAS"
        cmd+=" --token $CUSTOM_OLAS_ADDRESS"
    fi
    output=$(eval "$cmd")
    if [[ $? -ne 0 ]]; then
        echo "Activating service failed.\n$output"
        echo "Please, delete or rename the ./trader folder and try re-run this script again."
        exit 1
    fi
fi

# register agent instance
if [ "$(get_on_chain_service_state "$service_id")" == "ACTIVE_REGISTRATION" ]; then
    echo "[Operator] Registering agent instance for on-chain service $service_id..."
    export cmd="poetry run autonomy service --use-custom-chain register --key "../$operator_pkey_path" "$service_id" -a $AGENT_ID -i "$agent_address""

    if [ "${use_staking}" = true ]; then
        minimum_olas_balance=1000000000000000000
        ensure_erc20_balance "$operator_address" $minimum_olas_balance "operator's address" $CUSTOM_OLAS_ADDRESS "OLAS"
        cmd+=" --token $CUSTOM_OLAS_ADDRESS"
    fi

    output=$(eval "$cmd")
    if [[ $? -ne 0 ]]; then
        echo "Registering agent instance failed.\n$output"
        echo "Please, delete or rename the ./trader folder and try re-run this script again."
        exit 1
    fi
fi

# deploy on-chain service
service_state="$(get_on_chain_service_state "$service_id")"
if [ "$service_state" == "FINISHED_REGISTRATION" ] && [ "$first_run" = "true" ]; then
    echo "[Service owner] Deploying on-chain service $service_id..."
    output=$(poetry run autonomy service --use-custom-chain deploy "$service_id" --key "../$operator_pkey_path")
    if [[ $? -ne 0 ]]; then
        echo "Deploying service failed.\n$output"
        echo "Please, delete or rename the ./trader folder and try re-run this script again."
        exit 1
    fi
elif [ "$service_state" == "FINISHED_REGISTRATION" ]; then
    echo "[Service owner] Deploying on-chain service $service_id..."
    output=$(poetry run autonomy service --use-custom-chain deploy "$service_id" --key "../$operator_pkey_path" --reuse-multisig)
    if [[ $? -ne 0 ]]; then
        echo "Deploying service failed.\n$output"
        echo "Please, delete or rename the ./trader folder and try re-run this script again."
        exit 1
    fi
fi

# perform staking operations
# the following will stake the service in case it is not staked, and there are available rewards
# if the service is already staked, and there are no available rewards, it will unstake the service
if [ "${use_staking}" = true ]; then
  perform_staking_ops
fi

# check state
service_state="$(get_on_chain_service_state "$service_id")"
if [ "$service_state" != "DEPLOYED" ]; then
    echo "Something went wrong while deploying on-chain service. The service's state is $service_state."
    echo "Please check the output of the script and the on-chain registry for more information."
    exit 1
fi

echo ""
echo "Finished checking Autonolas Protocol service $service_id state."


echo ""
echo "------------------------------"
echo "Starting the trader service..."
echo "------------------------------"
echo ""

# Get the deployed service's Safe address from the contract
service_info=$(poetry run autonomy service --use-custom-chain info "$service_id")
safe=$(echo "$service_info" | grep "Multisig Address")
address_start_position=31
safe=$(echo "$safe" |
  awk '{ print substr( $0, '$address_start_position', length($0) - '$address_start_position' - 3 ) }')
export SAFE_CONTRACT_ADDRESS=$safe
echo -n "$safe" > "../$service_safe_address_path"

echo "Your agent instance's address: $agent_address"
echo "Your service's Safe address: $safe"
echo ""

# Set environment variables. Tweak these to modify your strategy
export RPC_0="$rpc"
export CHAIN_ID=$gnosis_chain_id
export ALL_PARTICIPANTS='["'$agent_address'"]'
# This is the default market creator. Feel free to update with other market creators
export OMEN_CREATORS='["0x89c5cc945dd550BcFfb72Fe42BfF002429F46Fec"]'
export BET_AMOUNT_PER_THRESHOLD_000=0
export BET_AMOUNT_PER_THRESHOLD_010=0
export BET_AMOUNT_PER_THRESHOLD_020=0
export BET_AMOUNT_PER_THRESHOLD_030=0
export BET_AMOUNT_PER_THRESHOLD_040=0
export BET_AMOUNT_PER_THRESHOLD_050=0
export BET_AMOUNT_PER_THRESHOLD_060=0
export BET_AMOUNT_PER_THRESHOLD_070=0
export BET_AMOUNT_PER_THRESHOLD_080=30000000000000000
export BET_AMOUNT_PER_THRESHOLD_090=80000000000000000
export BET_AMOUNT_PER_THRESHOLD_100=100000000000000000
export BET_THRESHOLD=5000000000000000
export PROMPT_TEMPLATE="Please take over the role of a Data Scientist to evaluate the given question. With the given question \"@{question}\" and the \`yes\` option represented by \`@{yes}\` and the \`no\` option represented by \`@{no}\`, what are the respective probabilities of \`p_yes\` and \`p_no\` occurring?"

service_dir="trader_service"
build_dir="abci_build"
directory="$service_dir/$build_dir"

suggested_amount=50000000000000000
ensure_minimum_balance "$agent_address" $suggested_amount "agent instance's address"

suggested_amount=500000000000000000
ensure_minimum_balance "$SAFE_CONTRACT_ADDRESS" $suggested_amount "service Safe's address" $WXDAI_ADDRESS

if [ -d $directory ]
then
    echo "Detected an existing build. Using this one..."
    cd $service_dir

    if rm -rf "$build_dir"; then
        echo "Directory "$build_dir" removed successfully."
    else
        # If the above command fails, use sudo to remove
        echo "You will need to provide sudo password in order for the script to delete part of the build artifacts."
        sudo rm -rf "$build_dir"
        echo "Directory "$build_dir" removed successfully."
    fi
else
    echo "Setting up the service..."

    if ! [ -d "$service_dir" ]; then
        # Fetch the service
        poetry run autonomy fetch --local --service valory/trader --alias $service_dir
    fi

    cd $service_dir
    # Build the image
    poetry run autonomy build-image
    cp ../../$keys_json_path $keys_json
fi

# Build the deployment with a single agent
poetry run autonomy deploy build --n $n_agents -ltm

cd ..

warm_start
add_volume_to_service "$PWD/trader_service/abci_build/docker-compose.yaml" "trader_abci_0" "/data" "$PWD/../$store/"

# Run the deployment
poetry run autonomy deploy run --build-dir $directory --detach
