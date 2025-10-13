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

duration=30
mode=run
old_ver_dir=/home/dunecet/dunedaq/*-v4.*/runarea/RunConfs/RunConf_?????*

set -euo pipefail

if [[ -z $DBT_AREA_ROOT ]]; then
    echo "ERROR: The DUNE DAQ environment is not setup."
    exit 1
fi

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
            if [[ $# -lt 2 ]]; then
                echo "ERROR: --mode requires an argument"
                exit 1
            fi
            mode="$2"
            shift 2
            ;;
        --confdir)
            if [[ $# -lt 2 ]]; then
                echo "ERROR: --confdir requires an argument"
                exit 1
            fi
            mode="confdir"
            confdir="$2"
            shift 2
            ;;
        -t)
            if [[ $# -lt 2 ]]; then
                echo "ERROR: -t requires a duration (in seconds)"
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

get_run_number() {
    local rn=0
    case "$mode" in
        run)
            runconfs_dir="$DBT_AREA_ROOT/runarea/RunConfs"
            rn=16000
            ;;
        hermes)
            runconfs_dir="$DBT_AREA_ROOT/runarea/RunConfs/hermes"
            rn=1
            ;;
        *)
            echo "ERROR: Invalid mode $mode when determining run number."
            exit 7
            ;;
    esac
    if [[ ! -d "$runconfs_dir" ]]; then
        echo "No RunConfs directory found in $runconfs_dir; cannot determine last run number."
        exit 6
    fi

    while [[ -d "$runconfs_dir/RunConf_$rn" ]]; do
	    rn=$(($rn+1))
    done
    echo $rn
}

post_run() { : 1=rr 2=status
    test -d RunConfs/RunConf_$rr; RC_status=$?
    echo "nanorc status = $status; RunConf_$rr status = $RC_status"
    files=$(find . -maxdepth 1 -name info_\* -newermt "$start") # maybe info_* file depends in opmon_impl
    if test -d RunConfs/RunConf_$rr;then
	if [ -n "file" ];then
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
case $mode in
confdir)
    #rr=$(run_num); echo "Attempting to start data taking run $rr"
    rr=$(get_run_number); echo "Attempting to start data taking run $rr with confdir $confdir"
    echo "STOPPING CONFDIR"
    exit 125
    echo "Using config in $confdir/top_iceberg.json:"; grep -v '^[{}]' $confdir/top_iceberg.json
    nanorc --log-path $PWD/logs --partition-number 3  --cfg-dumpdir $PWD/RunConfs --logbook-prefix logs/logbook \
	   $confdir/top_iceberg.json dunecet-iceberg boot conf start_run $rr \
	   wait $duration stop_run scrap terminate
    status=$?
    post_run
    ;;
run)
    #rr=$(run_num); echo "Attempting to start data taking run $rr"
    rr=$(get_run_number); echo "Attempting to start data taking run $rr"
    echo "STOPPING RUN"
    exit 126
    echo "Using config in top_iceberg.json:"; grep -v '^[{}]' top_iceberg.json
    echo "dts Sent cmd counters:"
    dtsbutler mst  BOREAS_TLU_ICEBERG status | awk '/Sent cmd counters/,/^$/'
    # start_run <runnum> OR start <runnum> enable_triggers
    if false;then
	nanorc --log-path $PWD/logs --partition-number 3 --cfg-dumpdir $PWD/RunConfs --logbook-prefix logs/logbook \
	   ./top_iceberg.json dunecet-iceberg boot conf start_run $rr \
	   wait $duration stop_run scrap terminate
	status=$?
    else
	nanorc --log-path $PWD/logs --partition-number 3 --cfg-dumpdir $PWD/RunConfs --logbook-prefix logs/logbook \
	   ./top_iceberg.json dunecet-iceberg boot conf start $rr wait 5 enable_triggers\
	   wait $duration stop_run scrap terminate
	status=$?
    fi
    post_run
    ;;
hermes)
    #rr=$(run_num 1); echo "Attempting to start hermes run $rr"
    rr=$(get_run_number); echo "Attempting to start hermes run $rr"
    echo "STOPPING HERMES"
    exit 128
    nanorc --log-path $PWD/logs --partition-number 3 --cfg-dumpdir $PWD/RunConfs --logbook-prefix logs/logbook \
	   confs/iceberg_hermes_conf iceberg-hermes boot start_run $rr start_shell
    ;;
*)
    echo invalid mode
    ;;
esac

