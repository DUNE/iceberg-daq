#!/bin/bash

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

HERE=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)
generated_config_dir=$(cd "${HERE}/../config/generated/" && pwd)

duration=30
mode=run
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|-\?|--help)
            usage
            ;;
        -x)
            set -x
            shift
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
        --confdir)
            if [[ -z "$2" || "$2" == -* ]]; then
                echo "ERROR: --confdir requires an argument." >&2
                exit 1
            fi
            #mode="confdir"
            confdir="$2"
            shift 2
            ;;
        --config)
            if [[ -z "$2" || "$2" == -* ]]; then
                echo "ERROR: --config requires an argument." >&2
                exit 1
            fi
            if [[ ! -d "$generated_config_dir/$2" ]]; then
                echo "ERROR: No generated config named $2 exists in $generated_config_dir" >&2
                echo "ERROR: If you need to generate a config, use $HERE/../config/create_daq_config.sh" >&2
                exit 2
            fi
            #mode="confdir"
            config="$2"
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
            echo "$USAGE"
            exit 1
            ;;
    esac
done

# TODO: Make sure this script is not directory dependent
#test "$(basename "$PWD")" = "runarea" || { echo "Must be in runarea directory"; exit; }

set_run_number() {
    case "$mode" in
        run|confdir)
            run_number=16000
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

post_run() { : 1=rr 2=status
    #test -d RunConfs/RunConf_$rr; RC_status=$?
    test -d RunConfs/RunConf_$run_number; RC_status=$?
    echo "nanorc status = $status; RunConf_$rr status = $RC_status"
    files=$(find . -maxdepth 1 -name info_\* -newermt "$start") # maybe info_* file depends in opmon_impl
    if test -d RunConfs/RunConf_$rr; then
        if [ -n "file" ]; then
            mkdir info/info_$rr
            mv $files info/info_$rr
        fi
        cd logs
        files=$(find . -type f -newermt "$start")
        echo moving $files to logs/log_$rr
        mkdir log_$rr
        mv $files log_$rr
        output_data_files=$(printf "iceberghd_raw_run%06d_*_dataflow0_datawriter_0_*.hdf5" $rr)
        #output_data_files=$(ls /home1/dunecet/dropbox/$output_data_files)
        #if [ -f "$(echo \"$output_data_files\" | head -1)" ];then
        #    echo moving $output_data_files to /nvme/dunecet/dropbox
        #    mv $output_data_files /nvme/dunecet/dropbox
        #fi
        else
        test -n "$files" && mv $files info
    fi    
}

start=$(date +'%Y-%m-%d %H:%M:%S')   # used in 2 cases, next
run_number=0
runconfs_dir=""                      # Set in get_run_number
iceberg_runarea="${DBT_AREA_ROOT}/runarea"
[[ -d "$iceberg_runarea" ]] || { echo "ERROR: No run area found in $iceberg_runarea"; exit 8; }
case "$mode" in
confdir)
    runconfs_dir="$DBT_AREA_ROOT/runarea/RunConfs"
    #rr=$(run_num); echo "Attempting to start data taking run $rr"
    #runconfs_dir="$DBT_AREA_ROOT/runarea/RunConfs"
    #rr=$(get_run_number) 
    [[ -d "$runconfs_dir" ]] || { echo "ERROR: RunConf directory $runconfs_dir does not exist." >&2; exit 11; }
    set_run_number
    echo "Attempting to start data taking run $run_number with confdir $confdir"
    echo "STOPPING CONFDIR"
    exit 125
    echo "Using config in $confdir/top_iceberg.json:"; grep -v '^[{}]' $confdir/top_iceberg.json
    nanorc --log-path $PWD/logs --partition-number 3  --cfg-dumpdir $PWD/RunConfs --logbook-prefix logs/logbook \
	   $confdir/top_iceberg.json dunecet-iceberg boot conf start_run $run_number \
	   wait $duration stop_run scrap terminate
    status=$?
    post_run
    ;;
run)
    runconfs_dir="$DBT_AREA_ROOT/runarea/RunConfs"
    [[ -d "$runconfs_dir" ]] || { echo "ERROR: RunConf directory $runconfs_dir does not exist." >&2; exit 11; }
    #rr=$(run_num); echo "Attempting to start data taking run $rr"
    #rr=$(get_run_number); 
    set_run_number
    #echo "Attempting to start data taking run $rr"
    echo "Attempting to start data taking run $run_number"
    echo "STOPPING RUN"
    exit 126
    echo "Using config in top_iceberg.json:"; grep -v '^[{}]' top_iceberg.json
    echo "dts Sent cmd counters:"
    dtsbutler mst  BOREAS_TLU_ICEBERG status | awk '/Sent cmd counters/,/^$/'
    # start_run <runnum> OR start <runnum> enable_triggers
    if false;then
	nanorc --log-path $PWD/logs --partition-number 3 --cfg-dumpdir $PWD/RunConfs --logbook-prefix logs/logbook \
	   ./top_iceberg.json dunecet-iceberg boot conf start_run $run_number \
	   wait $duration stop_run scrap terminate
	status=$?
    else
	nanorc --log-path $PWD/logs --partition-number 3 --cfg-dumpdir $PWD/RunConfs --logbook-prefix logs/logbook \
	   ./top_iceberg.json dunecet-iceberg boot conf start $run_number wait 5 enable_triggers\
	   wait $duration stop_run scrap terminate
	status=$?
    fi
    post_run
    ;;
hermes)
    runconfs_dir="$DBT_AREA_ROOT/runarea/RunConfs/hermes"
    [[ -d "$runconfs_dir" ]] || { echo "ERROR: RunConf directory $runconfs_dir does not exist." >&2; exit 11; }
    #rr=$(run_num 1); echo "Attempting to start hermes run $rr"
    #rr=$(get_run_number); 
    set_run_number
    hermes_config_dir=$generated_config_dir/$config/iceberg_hermes_conf
    echo "Attempting to start hermes run $run_number"
    if [[ ! -d "$hermes_config_dir" ]]; then
        echo "ERROR: No hermes configuration found in $generated_config_dir/$config" >&2
        exit 5
    fi
    nanorc --log-path $iceberg_runarea/logs --partition-number 3 --cfg-dumpdir $runconfs_dir --logbook-prefix logs/logbook \
	   $hermes_config_dir iceberg-hermes boot start_run $run_number start_shell
	   #confs/iceberg_hermes_conf iceberg-hermes boot start_run $run_number start_shell
    ;;
*)
    echo "Invalid mode: $mode"
    usage
    ;;
esac

