#!/bin/bash

usage() {
    local prog=$(basename "$0")
    cat << EOF

Usage: $prog --wib [102|105|106] <status|reset>

If no --wib argument is provided, this script will attempt to configure the timing for all three WIBs.

Note that this script will not work in an active DUNE DAQ environment.

EOF
}

HERE=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)
: "${LOG_PREFIX:=$(basename "${BASH_SOURCE[0]}")}"
source $HERE/../logging.sh

check_timing_output() {
    if [[ ! -f timing_output.txt ]]; then
        error "No timing output file found"
        exit 4
    fi

    mapfile -t timing_output < <(awk '{print $NF}' timing_output.txt | grep -E '^0x')
    for out in {0..9}; do
        if [[ "${timing_output[$out]}" != "0x0" ]]; then
            warn "Timing is not OK: entry $out"
            return 1
        fi
    done
    if [[ "${timing_output[10]}" != "0x0" && "${timing_output[10]}" != "0x1" ]]; then
        warn "Timing is not OK: entry 10"
        return 1
    fi
    if [[ "${timing_output[11]}" != "0x8" ]]; then
        warn "Timing is not OK: entry 11"
        return 1
    fi

    info "Timing status is OK"
    return 0
}

if [[ $# == 0 ]]; then
    usage
    exit 1
fi

if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    error "This script is intended to be executed directly, not sourced."
    return 1
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
            error "Unknown argument: $1"
            usage
            exit 1
            ;;
    esac
done

if [[ -z "$action" ]]; then
    error "You must specify status or reset"
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
    error "Invalid WIB argument: $wib"
    usage
    exit 1
fi

# Use only a single WIB if provided
if [[ -v "WIBS[$wib]" ]]; then
    declare -A WIBS=( ["$wib"]="${WIBS[$wib]}" )
fi

WIB_CLIENT_SCRIPT="/home/dunecet/dunedaq/DUNE_WIB_BNL_GUI/wib_client.py"
MAX_TRIES=3

for id in "${!WIBS[@]}"; do
    ip=${WIBS[$id]}
    if [[ "$action" == "status" ]]; then
        info "Checking status for WIB $id"
    else
        info "Resetting timing for WIB $id"
    fi

    if ! ping -c 1 -W 5 $ip &>/dev/null; then
        error "WIB $id (IP $ip) is not pingable. Make sure it's powered on and connected to the network."
        continue
    fi

    wib_timing_is_ok="false"
    # Use env -i since the power script won't work in a DUNE DAQ environment
    env -i python3 "$WIB_CLIENT_SCRIPT" -w "$ip" "timing_$action" | tee timing_output.txt

    if check_timing_output; then
        wib_timing_is_ok="true"
    fi
    tries=1

    # A timing reset may take an additional 1-2 attempts to be successful attempts for success
    while [[ "$action" == "reset" && "$wib_timing_is_ok" == "false" && $tries -lt $MAX_TRIES ]]; do
        ((++tries))
        info "Attempt number $tries of timing reset..."
        env -i python3 "$WIB_CLIENT_SCRIPT" -w "$ip" "timing_$action" | tee timing_output.txt
        if check_timing_output; then
            wib_timing_is_ok="true"
        else
            warn "Timing is not OK. Retrying ($tries/$MAX_TRIES)..."
            sleep 2
        fi
        rm -f timing_output.txt
    done

    if [[ "$wib_timing_is_ok" == "false" ]]; then
        error "Timing reset failed for WIB $id after $MAX_TRIES tries."
        exit 5
    fi

    info "Done with WIB $id"
done


