#!/bin/sh

USAGE="\
  usage: `basename $0` [-h|--help] [--mode <run|hermes>]
example: `basename $0`
Other options:
-t <seconds>    # run duration in seconds; default (w/o -t) is 30
--confdir <dir> alt dir for top_iceberg.json (i.e. default confir is \".\")
"

duration=30
mode=run
old_ver_dir=/home/dunecet/dunedaq/*-v4.*/runarea/RunConfs/RunConf_?????*

set -u   # i.e error if no $2
while expr "x${1-}" : x- >/dev/null;do
    case "$1" in
    -h|-\?|--help) echo "$USAGE";exit;;
    -x)     set -x;;
    --mode) mode=$2; shift;;
    --confdir) mode=confdir; confdir=$2; shift;;
    -t) duration=$2; shift;;
    *) echo unknown; exit;;
    esac
    shift
done

test `basename $PWD` = runarea || { echo Must be in runarea directory; exit; }

last_old_ver_run_num=`/bin/ls -dt $old_ver_dir|grep -Eo '[0-9]{5,}$'|sort -nr|head -1`
test -n "$last_old_ver_run_num" && last_old_ver_run_num=`expr $last_old_ver_run_num + 1`
run_num() { : ${1-} is optional starting number
    test $# -eq 1 && rn=$1 || rn=${last_old_ver_run_num:-11000}
    while test -d $DBT_AREA_ROOT/runarea/RunConfs/RunConf_$rn;do
	rn=$(($rn+1))
    done
    echo $rn
}


post_run() { : 1=rr 2=status
    test -d RunConfs/RunConf_$rr; RC_status=$?
    echo "nanorc status = $status; RunConf_$rr status = $RC_status"
    files=`find . -maxdepth 1 -name info_\* -newermt "$start"` # maybe info_* file depends in opmon_impl
    if test -d RunConfs/RunConf_$rr;then
	if [ -n "file" ];then
	    mkdir info/info_$rr
	    mv $files info/info_$rr
	fi
	cd logs
	files=`find . -type f -newermt "$start"`
	echo moving $files to logs/log_$rr
	mkdir log_$rr
	mv $files log_$rr
	output_data_files=`printf "iceberghd_raw_run%06d_*_dataflow0_datawriter_0_*.hdf5" $rr`
	#output_data_files=`ls /home1/dunecet/dropbox/$output_data_files`
	#if [ -f "`echo \"$output_data_files\" | head -1`" ];then
	#    echo moving $output_data_files to /nvme/dunecet/dropbox
	#    mv $output_data_files /nvme/dunecet/dropbox
	#fi
    else
	test -n "$files" && mv $files info
    fi    
}


start=`date +'%Y-%m-%d %H:%M:%S'`   # used in 2 cases, next
case $mode in
confdir)
    rr=$(run_num); echo "Attempting to start data taking run $rr"
    echo "Using config in $confdir/top_iceberg.json:"; grep -v '^[{}]' $confdir/top_iceberg.json
    nanorc --log-path $PWD/logs --partition-number 3  --cfg-dumpdir $PWD/RunConfs --logbook-prefix logs/logbook \
	   $confdir/top_iceberg.json dunecet-iceberg boot conf start_run $rr \
	   wait $duration stop_run scrap terminate
    status=$?
    post_run
    ;;
run)
    rr=$(run_num); echo "Attempting to start data taking run $rr"
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
    rr=$(run_num 1); echo "Attempting to start hermes run $rr"
    nanorc --log-path $PWD/logs --partition-number 3 --cfg-dumpdir $PWD/RunConfs --logbook-prefix logs/logbook \
	   confs/iceberg_hermes_conf iceberg-hermes boot start_run $rr start_shell
    ;;
*)
    echo invalid mode
    ;;
esac

