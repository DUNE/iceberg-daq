#!/bin/sh

USAGE="\
  usage: $(basename $0) [--femb-mask <mask>] [--cosmic|--pulser|--wibpulser|--pulsechannel[=<0-15>]]
For --pulsechannel[=<0-15>], the default index is 9
Example: $(basename $0) --cosmic --femb-mask 0x1
"

# Define directories
HERE=$(cd $(dirname $(readlink -f ${BASH_SOURCE[0]})) && pwd)
CONF_DIR=$(cd ${HERE}/../confs && pwd)

# Initialize variables
do_cosmic=0
do_pulser=0
do_wibpulser=0
do_pulsechannel=0
pulsechannel=9
buffer=0
femb_mask=0xf

# Functions for each option
cosmic_config() {
    sed -i '/"cold"/s/false/true/' $CONF_DIR/iceberg_wib_conf/data/wib10*_conf.json
}

pulser_config() {
    sed -i '
/"cold"/s/false/true/
/femb[0-3]/,/}/{
  /pulse_dac/s/[0-9][0-9]*/1/
  /baseline/s/[0-9][0-9]*/2/
  /test_cap/s/false/true,/
  /test_cap.*/a \                         "buffer": 0
}
/"pulser":/s/false/true/
' $CONF_DIR/iceberg_wib_conf/data/wib10*_conf.json
}

#
# WIB python has cp_period=2000, cp_high_time = 2000*32*(1/4), dacvol = 1.1 - x*0.05
#
wibpulser_config() {
    sed -i '
/"cold"/s/false/true/
/femb[0-3]/,/}/{
  /pulse_dac/s/[0-9][0-9]*/0/
  /test_cap/s/true/false/
}
/wib_pulser/,/}$/{
  /enabled_[0-3]/s/false/true/
  #/pulse_dac/     {s/[0-9.][0-9.]*/1/}
  #/pulse_dac/     {s/[0-9.][0-9.]*/10000/}
  /pulse_dac/     {s/[0-9.][0-9.]*/32000/} # 1.0
  #/pulse_dac/     {s/[0-9.][0-9.]*/28800/} # 0.9   run 15958
  #/pulse_dac/     {s/[0-9.][0-9.]*/25600/} # 0.8 0x6400
  #/pulse_dac/     {s/[0-9.][0-9.]*/22400/} # 0.7 0x5780
  #/pulse_dac/     {s/[0-9.][0-9.]*/19200/} # 0.6 0x4b00
  #/pulse_dac/     {s/[0-9.][0-9.]*/11200/} # 
  /pulse_duration/{s/[0-9][0-9]*/2000/}
  /pulse_period/  {s/[0-9][0-9]*/16000/}
}
' $CONF_DIR/iceberg_wib_conf/data/wib10*_conf.json
}

pulsechannel_config() {
    pulsechannel_json=$(python3 -c "terms=['false']*16;terms[$pulsechannel]=True;print(','.join([str(term).lower() for term in terms]))")
    sed -i '
/"cold"/s/false/true/
/femb[0-3]/,/}/{
  /pulse_channels/s/\[\]/['"$pulsechannel_json"']/
  /pulse_dac/s/[0-9][0-9]*/20/
  /gain/s/[0-9][0-9]*/2/
  /baseline/s/[0-9][0-9]*/2/
  /test_cap/s/false/true,/
  /test_cap.*/a \                         "buffer": 0
}
/"pulser":/s/false/true/
' $CONF_DIR/iceberg_wib_conf/data/wib10*_conf.json
}

# Parse command-line arguments
# Enable error on unset variables
set -u
while expr "x${1-}" : x- >/dev/null; do
    case "$1" in
        -x) set -x;;
        -h|-\?|--help) echo "$USAGE"; exit;;
	--femb-mask) femb_mask=$2; shift;;
        --cosmic*) do_cosmic=1;;
        --pulser*) do_pulser=1;;
        --wibpulser*) do_wibpulser=1;;
        --pulsechannel*)
            do_pulsechannel=1
            xx=$(expr "$1" : '.*=\([0-9]*\)')
            test -n "$xx" && pulsechannel=$xx || pulsechannel=9;;
        *) echo "Unknown option: $1"; exit 1;;
    esac
    shift
done

# Check for mutually exclusive options
if [ $((do_cosmic + do_pulser + do_wibpulser + do_pulsechannel)) -ne 1 ]; then
    echo "ERROR: Can specify only one of --cosmic, --pulser, --wibpulser or --pulsechannel[=<0-15>]"
    exit 1
fi

# Ensure the configuration directory exists
mkdir -p $CONF_DIR/iceberg_wib_conf

# Generate WIB configuration
echo "$(date) Creating WIB configuration" | tee -a $HERE/../logs/iceberg_wib_conf.log
#wibconf_gen -f -c $HERE/iceberg_wib1.json $CONF_DIR/iceberg_wib_conf >> $HERE/../logs/iceberg_wib_conf.log
wibconf_gen -f -c $HERE/iceberg_wib.json $CONF_DIR/iceberg_wib_conf >> $HERE/../logs/iceberg_wib_conf.log

# Check if the configuration directory exists
if [ ! -d "$CONF_DIR/iceberg_wib_conf" ]; then
    echo "ERROR: $CONF_DIR/iceberg_wib_conf does not exist"
    exit 1
fi

# Execute configuration based on selected option
if [ "$do_wibpulser" = 1 ]; then
    wibpulser_config    # see also below
elif [ "$do_pulsechannel" = 1 ]; then
    pulsechannel_config
elif [ "$do_pulser" = 1 ]; then
    pulser_config
elif [ "$do_cosmic" = 1 ]; then
    cosmic_config
fi

# Adjust configuration files
find $CONF_DIR/iceberg_wib_conf -type f | xargs sed -i 's/monkafka.cern.ch/iceberg01.fnal.gov/'

if [ $femb_mask \!= 0xf ];then
    for ff in $CONF_DIR/iceberg_wib_conf/data/wib10*_conf.json;do
	for femb in `seq 0 3`;do
	    if awk "BEGIN{exit and(${femb_mask},2^${femb})}";then
		test -n "${opt_v-}" && echo disabling FEMB$femb
		# disable in both the Larasic and wib_pulser sections
		sed -i  "/femb$femb/,/enabled/{s/true/false/}
                         /enabled_$femb/      {s/true/false/}
" $ff
	    fi
	done
    done
fi
	
# now disable the problematic or missing FEMBs
if [ "$do_wibpulser" = 1 ]; then
    sed -i '/femb[2]/,/enabled/{s/true/false/}
           /enabled_[2]/       {s/true/false/}' $CONF_DIR/iceberg_wib_conf/data/wib104_conf.json
    sed -i '/femb[23]/,/enabled/{s/true/false/}
            /enabled_[23]/      {s/true/false/}' $CONF_DIR/iceberg_wib_conf/data/wib105_conf.json
else
    sed -i '/femb[2]/,/enabled/{s/true/false/}' $CONF_DIR/iceberg_wib_conf/data/wib104_conf.json
    #sed -i '/femb[23]/,/enabled/{s/true/false/}' $CONF_DIR/iceberg_wib_conf/data/wib105_conf.json
    sed -i '/femb[3]/,/enabled/{s/true/false/}' $CONF_DIR/iceberg_wib_conf/data/wib105_conf.json
fi

# Display the last 3 lines of the log
tail -3 $HERE/../logs/iceberg_wib_conf.log
