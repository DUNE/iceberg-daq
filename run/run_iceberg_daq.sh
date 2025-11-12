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
    --mode <mode>       Run mode ('main' or 'hermes') [default: main]

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
mode="main"
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|-\?|--help)
            usage
            ;;
        --mode)
            if [[ -z "$2" || "$2" == -* ]]; then
                error "--mode requires an argument."
                exit 1
            fi
            if [[ "$2" != "hermes" && "$2" != "main" && "$2" != confdir ]]; then
                error "Invalid mode. Mode must be one of 'hermes', 'main', or 'confdir'"
                usage
                exit 1
            fi
            mode="$2"
            shift 2
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
            #mode="confdir"
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

set_run_number() {
    #case "$mode" in
    #    main|confdir)
    #        run_number=16091 # Latest run number previous to moving log directories
    #        ;;
    #    hermes)
    #        run_number=1
    #        ;;
    #    *)
    #        error "Unknown error when getting run number"
    #        exit 10
    #        ;;
    #esac

    #while [[ -d "$runconfs_dir/RunConf_$run_number" ]]; do
    while [[ -d "$iceberg_log_area/run_$run_number" ]]; do
	    run_number=$(($run_number+1))
    done
}

create_run_log_dirs() {
    run_log_area="${iceberg_log_area}/run_${run_number}"
    mkdir "$run_log_area" "$run_log_area/config" "$run_log_area/processes" "$run_log_area/info"
}

post_run() {
    #if [[ ! -d "$runconfs_dir/RunConf_$run_number" ]]; then
    #if [[ ! -d "$run_log_area/run_$run_number" ]]; then
    #    error "No RunConf directory was created at $runconfs_dir/RunConf_$run_number"
    #    exit 8
    #fi
    info_files=$(find . -maxdepth 1 -name info_\* -newermt "$start")
    if [[ -n "$info_files" ]]; then
        #mkdir $iceberg_log_area/info/info_$run_number
        #mv $info_files $iceberg_log_area/info/info_$run_number
        info "Moving the following files to $run_log_area/info:\n${info_files}"
        mv $info_files $run_log_area/info
    fi
    #cd $iceberg_log_area/logs
    #log_files=$(find . -type f -newermt "$start")
    #info "Moving log files $log_files to logs/log_$run_number"
    #mkdir log_$run_number
    #mv $log_files log_$run_number
}

start=$(date +'%Y-%m-%d %H:%M:%S')   # used in 2 cases, next
run_number=0
iceberg_log_area="${DBT_AREA_ROOT}/run-logs/$mode"
#runconfs_dir="$iceberg_log_area/"
#[[ -d "$iceberg_log_area" ]] || { error "No run area found in $iceberg_log_area"; exit 8; }
set_run_number
create_run_log_dirs
case "$mode" in
main)
    [[ -d "$runconfs_dir" ]] || { error "RunConf directory $runconfs_dir does not exist."; exit 11; }
    #set_run_number
    info "Attempting to start data taking run $run_number with config $config"
    info "Using config in $generated_config_dir/top_iceberg.json:"; grep -v '^[{}]' $generated_config_dir/top_iceberg.json || exit 987
    #nanorc --log-path $iceberg_log_area/logs --partition-number 3  --cfg-dumpdir $runconfs_dir --logbook-prefix logs/logbook \
    nanorc --log-path $run_log_area/processes --partition-number 3  --cfg-dumpdir $run_log_area/config --logbook-prefix logs/logbook \
	   $generated_config_dir/top_iceberg.json dunecet-iceberg boot conf start_run $run_number \
	   wait $duration stop_run scrap terminate
    status=$?
    post_run
    ;;
hermes)
    #runconfs_dir="$runconfs_dir/hermes"
    #[[ -d "$runconfs_dir" ]] || { error "RunConf directory $runconfs_dir does not exist."; exit 11; }
    #set_run_number
    #create_run_log_dirs
    hermes_config_dir=$generated_config_dir/iceberg_hermes_conf
    #run_log_dir="$iceberg_log_area/hermes/run_${run_number}"
    #mkdir $run_log_dir
    info "Attempting to start hermes run $run_number"
    if [[ ! -d "$hermes_config_dir" ]]; then
        error "No hermes configuration found in $generated_config_dir"
        exit 5
    fi
    nanorc --log-path $run_log_area/processes --partition-number 3 --cfg-dumpdir $run_log_area/config --logbook-prefix logs/logbook \
	   $hermes_config_dir iceberg-hermes boot start_run $run_number start_shell
    ;;
*)
    error "Invalid mode: $mode"
    usage
    ;;
esac

