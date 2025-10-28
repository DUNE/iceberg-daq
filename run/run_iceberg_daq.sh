#!/bin/bash

HERE=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)
generated_config_root=$(cd "${HERE}/../config/generated/" && pwd)
generated_config_dir=""

usage() {
    local prog=$(basename "$0")
    cat << EOF
Usage: $prog [OPTIONS]

Configure and run nanorc for Iceberg.

Options:
    -t <seconds>          Run duration in seconds
                          [default: 30]
    --confdir <path>      Directory containing a file named 'top_iceberg.json' for run configuration
                          [default: current working directory]

Example:
    ./nanorc_run.sh -t 60 --confdir path/to/cosmic_config
EOF
    exit 1
}

if [[ $# == 0 ]]; then
    usage
fi

set -euo pipefail

[[ -n "$DBT_AREA_ROOT" ]] || { echo "ERROR: The DUNE DAQ environment is not setup."; exit 1; }

duration=30
mode=run
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|-\?|--help)
            usage
            ;;
        --mode)
            if [[ -z "$2" || "$2" == -* ]]; then
                echo "ERROR: --mode requires an argument." >&2
                exit 1
            fi
            if [[ "$2" != "hermes" && "$2" != "run" && "$2" != confdir ]]; then
                echo "ERROR: Invalid mode. Mode must be one of 'hermes', 'run', or 'confdir'" >&2
                usage
                exit 1
            fi
            mode="$2"
            shift 2
            ;;
        --config)
            if [[ $# -eq 1 || "$2" == -* ]]; then
                echo "ERROR: --config requires an argument." >&2
                exit 1
            fi
            if [[ ! -d "$generated_config_root/$2" ]]; then
                echo "ERROR: No generated config named $2 exists in $generated_config_root" >&2
                echo "       If you need to generate a config, use $HERE/../config/create_daq_config.sh" >&2
                exit 2
            fi
            #mode="confdir"
            config="$2"
            generated_config_dir="$generated_config_root/$config"
            shift 2
            ;;
        -t)
            if [[ -z "$2" || "$2" == -* ]]; then
                echo "ERROR: -t requires a duration (in seconds)." >&2
                exit 1
            fi
            if ! [[ "$2" =~ ^[0-9]+$ ]]; then
                echo "ERROR: Duration must be a positive integer, got '$2'." >&2
                exit 1
            fi
            duration="$2"
            shift 2
            ;;
        *)
            echo "ERROR: Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

set_run_number() {
    case "$mode" in
        run|confdir)
            run_number=16068 # Latest run number previous to moving to /exp area
            ;;
        hermes)
            run_number=1
            ;;
        *)
            echo "ERROR: Unknown error when getting run number" >&2
            exit 10
            ;;
    esac

    while [[ -d "$runconfs_dir/RunConf_$run_number" ]]; do
	    run_number=$(($run_number+1))
    done
}

post_run() {
    if [[ ! -d "$runconfs_dir/RunConf_$run_number" ]]; then
        echo "ERROR: No RunConf directory was created at $runconfs_dir/RunConf_$run_number" >&2 
        exit 8
    fi
    info_files=$(find . -maxdepth 1 -name info_\* -newermt "$start")
    if [[ -n "$info_files" ]]; then
        mkdir $iceberg_runarea/info/info_$run_number
        mv $info_files $iceberg_runarea/info/info_$run_number
    fi
    cd $iceberg_runarea/logs
    log_files=$(find . -type f -newermt "$start")
    echo "Moving log files $log_files to logs/log_$run_number"
    mkdir log_$run_number
    mv $log_files log_$run_number
}

start=$(date +'%Y-%m-%d %H:%M:%S')   # used in 2 cases, next
run_number=0
iceberg_runarea="${DBT_AREA_ROOT}/run-logs"
runconfs_dir="$iceberg_runarea/configs"
[[ -d "$iceberg_runarea" ]] || { echo "ERROR: No run area found in $iceberg_runarea"; exit 8; }
case "$mode" in
run)
    [[ -d "$runconfs_dir" ]] || { echo "ERROR: RunConf directory $runconfs_dir does not exist." >&2; exit 11; }
    set_run_number
    echo "Attempting to start data taking run $run_number with config $config"
    echo "Using config in $generated_config_dir/top_iceberg.json:"; grep -v '^[{}]' $generated_config_dir/top_iceberg.json || exit 987
    nanorc --log-path $iceberg_runarea/logs --partition-number 3  --cfg-dumpdir $runconfs_dir --logbook-prefix logs/logbook \
	   $generated_config_dir/top_iceberg.json dunecet-iceberg boot conf start_run $run_number \
	   wait $duration stop_run scrap terminate
    status=$?
    post_run
    ;;
hermes)
    runconfs_dir="$runconfs_dir/hermes"
    [[ -d "$runconfs_dir" ]] || { echo "ERROR: RunConf directory $runconfs_dir does not exist." >&2; exit 11; }
    set_run_number
    hermes_config_dir=$generated_config_dir/iceberg_hermes_conf
    echo "Attempting to start hermes run $run_number"
    if [[ ! -d "$hermes_config_dir" ]]; then
        echo "ERROR: No hermes configuration found in $generated_config_dir" >&2
        exit 5
    fi
    nanorc --log-path $iceberg_runarea/logs --partition-number 3 --cfg-dumpdir $runconfs_dir --logbook-prefix logs/logbook \
	   $hermes_config_dir iceberg-hermes boot start_run $run_number start_shell
    ;;
*)
    echo "Invalid mode: $mode"
    usage
    ;;
esac

