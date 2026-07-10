#!/bin/bash

set -euo pipefail

HERE=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)
TOP=$(cd "${HERE}/.." && pwd)
generated_config_root=$(cd "${TOP}/config/generated/" && pwd)
generated_config_dir=""
: "${LOG_PREFIX:=$(basename "${BASH_SOURCE[0]}")}"
source $TOP/logging.sh
source $TOP/config/config_helpers.sh

usage() {
    local prog=$(basename "$0")
    cat << EOF
Usage: $prog [OPTIONS]

Run ICEBERG DAQ using an existing configuration.

Required arguments:
    --config <name>     Configuration name. Must match a directory name in 
                        ${generated_config_root}
Optional arguments:
    --time <seconds>    Run duration in seconds [default: 30]

To generate a configuration, use 
    ${TOP}/config/create_daq_config.sh

To list available configurations, run
    ${TOP}/config/create_daq_config.sh --list

Example:
    ./${prog} --time 60 --config my_config
EOF
    exit 1
}

if [[ $# == 0 ]]; then
    usage
fi

if ! declare -p DBT_AREA_ROOT; then
    error "This script requires an active DUNE DAQ environment."
    error "Navigate to the local DUNE DAQ build area and run 'source env.sh'"
    exit 2
fi

duration=30
config=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|-\?|--help)
            usage
            ;;
        --config)
            if [[ $# -eq 1 || "$2" == -* ]]; then
                error "--config requires an argument."
                list_available_configs
                exit 1
            fi
            if [[ ! -d "$generated_config_root/$2" ]]; then
                error "No generated config named $2 exists in $generated_config_root"
                error "If you need to generate a config, use $TOP/config/create_daq_config.sh"
                list_available_configs
                exit 2
            fi
            config="$2"
            generated_config_dir="$generated_config_root/$config"
            shift 2
            ;;
        -t|--time)
            if [[ -z "$2" || "$2" == -* ]]; then
                error "--time requires a duration (in seconds)."
                exit 1
            fi
            if ! [[ "$2" =~ ^[0-9]+$ ]]; then
                error "Duration must be a positive integer, got '$2'."
                exit 1
            fi
            duration="$2"
            shift 2
            ;;
        *)
            error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

if [[ -z "$config" ]]; then
    error "--config is a required argument."
    exit 1
fi

run_number=1

create_run_log_dirs() {
    run_log_area="${emulated_log_area}/run_${run_number}"
    mkdir "$run_log_area" "$run_log_area/config" "$run_log_area/processes" "$run_log_area/info"
}

move_info_files() {
    # Unlike with run configs or other logs, there's no command line option to
    # set where info log files are written, so we move them manually.
    info_files=$(find . -maxdepth 1 -name info_\* -newermt "$start")
    if [[ -n "$info_files" ]]; then
        mv $info_files $run_log_area/info
    else
        warn "No info log files found in $(cwd)"
    fi
}

start=$(date +'%Y-%m-%d %H:%M:%S')
run_number=1
partition=7
emulated_log_area="/data02/dunecet/run-logs/emulated"

while [[ -d "$emulated_log_area/run_$run_number" ]]; do
    run_number=$(($run_number+1))
done

create_run_log_dirs

run_opts="boot conf start_run --run-type TEST ${run_number} wait ${duration} stop_run scrap terminate"

echo "GENERATED CONFIG DIR: ${generated_config_dir}"

nanorc --log-path "$run_log_area/processes" \
       --partition-number "$partition" \
       --cfg-dumpdir "$run_log_area/config" \
       --logbook-prefix logs/logbook \
       "${generated_config_dir}/emulated_daq_conf" \
       "iceberg-emulated" \
       $run_opts

move_info_files

info "Emulated run $run_number complete. Logs can be found in ${run_log_area}"

