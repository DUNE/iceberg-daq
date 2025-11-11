#!/bin/bash

usage() {
    local prog=$(basename "${BASH_SOURCE[0]}")
    cat << EOF

Usage: $prog [on|off]

EOF
}

HERE=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)
: "${LOG_PREFIX:=$(basename "${BASH_SOURCE[0]}")}"
source $HERE/../logging.sh

if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    error "This script is intended to be executed directly, not sourced."
    return 1
fi

if [[ $# == 0 ]]; then
    usage
    exit 1
fi

power=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        on|off) 
            power="$1"; 
            shift
            ;;
        -h|--help|-?) 
            usage
            exit 1
            ;;
        *) 
            error "Unknown argument: $1"; 
            usage
            exit 1
            ;;
    esac
done

declare -a WIBS=()
if [[ "$power" == "on" ]]; then
    WIBS=(
        "102 192.168.121.21 on on on on"
        "105 192.168.121.24 on on on on"
        "106 192.168.121.25 off off on on"
    )
elif [[ "$power" == "off" ]]; then
    WIBS=(
        "102 192.168.121.21 off off off off"
        "105 192.168.121.24 off off off off"
        "106 192.168.121.25 off off off off"
    )
fi

WIB_POWER_SCRIPT="/home/dunecet/dunedaq/DUNE_WIB_BNL_GUI/wib_power.py"

could_not_power=("")
for entry in "${WIBS[@]}"; do
    read -r id ip f0 f1 f2 f3 <<<"$entry"
    if ! ping -c 1 -W 5 "$ip" &>/dev/null; then
        info "In ping loop"
        warn "Could not ping $ip"
        could_not_power+=("WIB $id (IP $ip) is not pingable and its FEMBs are not powered.\n Make sure it's powered on and connected to the network.\n")
        continue
    fi
    # Use env -i since the power script won't work in a DUNE DAQ environment
    env -i python3 "$WIB_POWER_SCRIPT" -c -w "$ip" "$f0" "$f1" "$f2" "$f3"
done

if [[ -n "$could_not_power" ]]; then
    warn "${could_not_power[@]}"
fi
