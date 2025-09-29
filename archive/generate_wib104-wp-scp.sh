#!/bin/bash

USAGE="\
  usage: $(basename "$0") [-h|--help] [--pulser|--cosmic|--wibpulser]
example: $(basename "$0")
The default is --cosmic.
"

HERE=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)
CONF_DIR=$(cd "${HERE}/../confs" && pwd)

DROMAP="${HERE}/iceberg_dromap_wib_104.json"
#DROMAP="${HERE}/iceberg_dromap_wib1.json"
#DROMAP="${HERE}/iceberg_dromap_wib1_flx.json"
#DROMAP="${HERE}/iceberg_dromap_wibs_flx.json"

do_cosmic=0
do_pulser=0
do_wibpulser=0
do_pulsechannel=0

daq_json=""
wib_json=""

set -u

while expr "x${1-}" : x- >/dev/null; do
    case "$1" in
    -x) set -x;;
    -h|-\?|--help) echo "$USAGE"; exit;;
    --cosmic*) do_cosmic=1;;
    --pulser*) do_pulser=1;;
    --wibpulser*) do_wibpulser=1;;
    --pulsechannel*) do_pulsechannel=1;;
    *) echo "Unknown option: $1"; exit 1;;
    esac
    shift
done

# Check for mutually exclusive options
if [ $((do_cosmic + do_pulser + do_wibpulser + do_pulsechannel)) -ne 1 ]; then
    echo "ERROR: Can specify only one of --cosmic, --pulser, or --wibpulser"; exit 1
fi

configure_daq_json() {
    cp -pf "${HERE}/iceberg_daq_eth.json" "${HERE}/iceberg_daq_eth.json.sav"
    sed -i '
        /"signal"/s/[0-9][0-9]*/32/
        /tc_type_name/s/k[a-zA-Z]*/kDTSCosmic/
        /hsi_re_mask/s/[0-9][0-9]*/32/
        /offline_data_stream/s/:.*/: "cosmics",/
        /hsi_source/s/:.*/: 0,/
    ' "${HERE}/iceberg_daq_eth.json"
    daq_json="iceberg_daq_eth.json"
}

configure_pulser_json() {
    echo "Configuring for pulser"
    cp -pf "${HERE}/iceberg_daq_eth.json" "${HERE}/iceberg_daq_eth.json.sav"
    sed -i '
        /"signal"/s/[0-9][0-9]*/16777216/
        /tc_type_name/s/k[a-zA-Z]*/kDTSPulser/
        /hsi_re_mask/s/[0-9][0-9]*/16777216/
        /offline_data_stream/s/:.*/: "calibration",/
        /hsi_source/s/:.*/: 0,/
    ' "${HERE}/iceberg_daq_eth.json"
    daq_json="iceberg_daq_eth.json"
}

configure_wibpulser_json() {
    echo "***************************************************************"
    echo " "
    echo "Configuring for WIB Pulser"
    echo "This does not do any modifcations to iceberg_daq_eth.json"
    echo "Modifies the same items as pulser for calibration"
    echo " "
    echo "**************************************************************"
}

# Execute configuration based on selected option
if [ "$do_cosmic" = 1 ]; then
    echo "Configuring for cosmics"
    configure_daq_json
elif [ "$do_pulser" = 1 ]; then
    configure_pulser_json
elif [ "$do_wibpulser" = 1 ]; then
    configure_wibpulser_json
    configure_pulser_json
elif [ "$do_pulsechannel" = 1 ]; then
    configure_pulser_json
fi

# Common operations for all configurations
if [ -n "$daq_json" ]; then
    fddaqconf_gen -f -c "${HERE}/${daq_json}" -m "${DROMAP}" "${CONF_DIR}/iceberg_daq_conf" \
	&& hermesmodules_gen -f -c "${HERE}/iceberg_hermes.json" -m "${DROMAP}" "${CONF_DIR}/iceberg_hermes_conf"
    test $? -eq 0 || { echo Config gen ERROR; exit 1; }
fi

sed -i 's/monkafka.cern.ch:30092/iceberg01.fnal.gov:30092/g' "${CONF_DIR}/iceberg_daq_conf/boot.json"
sed -i 's/monkafka.cern.ch:30092/iceberg01.fnal.gov:30092/g' "${CONF_DIR}/iceberg_hermes_conf/boot.json"
sed -i '
    /digits_for_file_index/s/.,/1,/
    /overall_prefix/s/iceberghd/iceberghd_raw/
' "${CONF_DIR}/iceberg_daq_conf/data/dataflow0_conf.json"
sed -i 's/PD2HDChannelMap/ICEBERGChannelMap/' \
"${CONF_DIR}/iceberg_daq_conf/data/trigger_conf.json" \
"${CONF_DIR}/iceberg_daq_conf/data/ruiceberg03eth0_conf.json" \
"${CONF_DIR}/iceberg_daq_conf/config/iceberg_daq_eth.json"
