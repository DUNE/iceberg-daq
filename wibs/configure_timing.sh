#!/bin/bash

usage() {
    local prog=$(basename "$0")
    cat << EOF

Usage: $prog --wib [102|105|106] <status|reset>

If no --wib argument is provided, this script will attempt to configure the timing for all three WIBs.

EOF
}

HERE=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)
source $HERE/../logging.sh

check_timing_output() {
    if [[ ! -f timing_output.txt ]]; then
        echo "ERROR: No timing output file found" >&2
        exit 4
    fi

    mapfile -t timing_output < <(awk '{print $NF}' timing_output.txt | grep -E '^0x')
    for out in {0..9}; do
        if [[ "${timing_output[$out]}" != "0x0" ]]; then
            echo "Timing is not OK: entry $out"
            return 1
        fi
    done
    if [[ "${timing_output[10]}" != "0x0" && "${timing_output[10]}" != "0x1" ]]; then
        echo "Timing is not OK: entry 10"
        return 1
    fi
    if [[ "${timing_output[11]}" != "0x8" ]]; then
        echo "Timing is not OK: entry 11"
        return 1
    fi

    echo "Timing status is OK"
    return 0
}

# Determine if this script is running in the correct environment
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    #echo "ERROR: This script is intended to be executed directly, not sourced." >&2
    error "This script is intended to be executed directly, not sourced."
    usage
    return 1
fi

if [[ -n "$DBT_AREA_ROOT" ]]; then
    echo "ERROR: This script will not work inside an active DUNE DAQ environment." >&2
    echo "       Open a fresh terminal and try again." >&2
    exit 2
fi

if [[ $# == 0 ]]; then
    usage
    exit 1
fi

# Parse inputs
action=""
wib=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --wib) 
            wib="$2"; 
            shift 2
            ;;
        status|reset)
            action=$1
            shift
            ;;
        -h|--help|-?) 
            usage
            exit 1
            ;;
        *) 
            echo "ERROR: Unknown argument: $1" >&2
            usage
            exit 1
            ;;
    esac
done

if [[ -z "$action" ]]; then
    echo "ERROR: You must specify status or reset" >&2
    usage
    exit 1
fi

# Default WIB ID->IP map
declare -A WIBS=(
    ["102"]="192.168.121.21"
    ["105"]="192.168.121.24"
    ["106"]="192.168.121.25"
)
if [[ -n "$wib" && ! -v "WIBS[$wib]" ]]; then
    echo "ERROR: Invalid WIB argument: $wib" >&2
    usage
    exit 1
fi

# Use only a single WIB if provided
if [[ -v "WIBS[$wib]" ]]; then
    declare -A WIBS=( ["$wib"]="${WIBS[$wib]}" )
fi

WIB_CLIENT_SCRIPT="/home/dunecet/dunedaq/DUNE_WIB_BNL_GUI/wib_client.py"
MAX_TRIES=3

# For a timing reset, retry up to $MAX_TRIES times before giving up
for id in "${!WIBS[@]}"; do
    ip=${WIBS[$id]}
    if [[ "$action" == "status" ]]; then
        echo -e "\n===== Checking status for WIB $id ====="
    else
        echo -e "\n===== Resetting timing for WIB $id ====="
    fi

    if ! ping -c 1 -W 5 $ip &>/dev/null; then
        echo "ERROR: WIB $id (IP $ip) is not pingable. Make sure it's powered on and connected to the network." >&2
        continue
    fi

    wib_timing_is_ok="false"
    python3 "$WIB_CLIENT_SCRIPT" -w "$ip" "timing_$action" | tee timing_output.txt

    if check_timing_output; then
        wib_timing_is_ok="true"
    fi
    tries=1
    rm -f timing_output.txt

    # A timing reset may take an additional 1-2 attempts to be successful attempts for success
    while [[ "$action" == "reset" && "$wib_timing_is_ok" == "false" && $tries -lt $MAX_TRIES ]]; do
        ((++tries))
        echo "Attempt number $tries of timing reset..."
        python3 "$WIB_CLIENT_SCRIPT" -w "$ip" "timing_$action" | tee timing_output.txt
        if check_timing_output; then
            wib_timing_is_ok="true"
        else
            echo "Timing is not OK. Retrying ($tries/$MAX_TRIES)..."
            sleep 2
        fi
        rm -f timing_output.txt
    done

    if [[ "$wib_timing_is_ok" == "false" ]]; then
        echo "ERROR: Timing reset failed for WIB $id after $MAX_TRIES tries." >&2
        exit 5
    fi

    echo "==== Done with WIB $id ====="
done

















