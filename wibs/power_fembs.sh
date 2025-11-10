#!/bin/bash

usage() {
    local prog=$(basename "${BASH_SOURCE[0]}")
    cat << EOF

Usage: $prog [on|off]

EOF
}

if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    echo "ERROR: This script is intended to be executed directly, not sourced." >&2
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

power=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        on|off) 
            power="$1"; 
            shift
            ;;
        -h|--help|-?) 
            usage
            ;;
        *) 
            echo "ERROR: Unknown argument: $1"; 
            usage
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
        echo "WARNING: Could not ping $ip"
        could_not_power+=("WARNING: WIB $id (IP $ip) is not pingable and its FEMBs are not powered.\n Make sure it's powered on and connected to the network.\n")
        continue
    fi
    python3 "$WIB_POWER_SCRIPT" -c -w "$ip" "$f0" "$f1" "$f2" "$f3"
done

if [[ -n "$could_not_power[@]" ]]; then
    echo -e "${could_not_power[@]}"
fi
