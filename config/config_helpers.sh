#!/bin/bash

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    error "This script is intended to be sourced, not executed directly."
    return 1
fi

HERE=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)
TOP=$(cd "${HERE}/.." && pwd)
generated_config_root=$(cd "${TOP}/config/generated/" && pwd)
: "${LOG_PREFIX:=$(basename "${BASH_SOURCE[0]}")}"
source $TOP/logging.sh

list_available_configs() {
    [[ -d "$generated_config_root" ]] || { error "Generated config dir $generated_config_root does not exist"; exit 1; }
    local configs
    configs=$(find "$generated_config_root" -mindepth 1 -maxdepth 1 -type d -printf "  - %f\n")
    if [[ -z "$configs" ]]; then
        warn "There are no available configurations in $generated_config_root"
        warn "To generate a configuration, use $TOP/config/create_daq_config.sh"
        return 0
    fi
    info "The available configurations are listed below:"
    echo -e "${COLOR_INFO}${configs}${COLOR_RESET}"
}