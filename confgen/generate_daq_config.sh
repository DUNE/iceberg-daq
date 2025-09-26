#!/bin/bash

set -euo pipefail

usage() {
    echo "Usage: $0 --wibs <'all'|102|105|106> --source <cosmic|pulser|wibpulser|pulsechannel>"
}

HERE=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)
CONF_DIR=$(cd "${HERE}/../confs" && pwd)

SOURCE=""
clean_mode="false"
wibs=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            usage;;
        --wibs)
            shift
            while [[ $# -gt 0 && $1 != -* ]]; do
                wibs+=("$1")
                shift
            done
            ;;
        --source)
            shift
            if [[ $# -ne 1 || "$1" == "-*" ]]; then
                echo "ERROR: --source requires exactly one of 'cosmic', 'pulser', 'wibpulser', or 'pulsechannel'"
                usage
                exit 1
            fi
            case "$1" in
                cosmic|pulser|wibpulser|pulsechannel)
                    SOURCE="$1"
                ;;
                *)
                    echo "ERROR: --source requires exactly one of 'cosmic', 'pulser', 'wibpulser', or 'pulsechannel'"
                    usage
                    exit 1;;
            esac
            ;;
        --clean)
            clean_mode="true"
        *)
            echo "ERROR Unknown argument: $1"
            usage
            exit 1
            ;;
    esac
done

# Validate arguments
dromap_files=()
for wib in ${wibs[@]}; do 
    filename="iceberg_dromap_wib_${wib}.json"
    if [[ ! -f "$filename" ]]; then
        echo "ERROR: No detector readout map file exists for WIB $wib"
        exit 4
    fi
    dromap_files+=("iceberg_dromap_wib_${wib}.json")
done
jq -s 'add' ${dromap_files[@]} > iceberg_dromap_unique_name_FIX_THIS.json

daq_json=""
wib_json=""

configure_cosmic_json() {
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
case "$SOURCE" in
    cosmic)
        configure_cosmic_json
        ;;
    pulser)
        configure_pulser_json
        ;;
    wibpulser)
        configure_wibpulser_json
        configure_pulser_json
        ;;
    pulsechannel)
        configure_pulser_json
        ;;
    *)
        echo "ERROR: Unknown source: $SOURCE"
        usage
        exit 1
        ;;
esac

generate_detector_readout_map() {
    echo "This should combine the individual WIB DRO maps into one"
}

# Common operations for all configurations
#DROMAP="${HERE}/iceberg_dromap_wibs_103_104_105.json"
if [ -z "$daq_json" ]; then
    echo "ERROR: Invalid daq config: $daq_json"
    exit 3
fi
fddaqconf_gen -f -c "${HERE}/${daq_json}" -m "${DROMAP}" "${CONF_DIR}/iceberg_daq_conf"
hermesmodules_gen -f -c "${HERE}/iceberg_hermes.json" -m "${DROMAP}" "${CONF_DIR}/iceberg_hermes_conf"
wibconf_gen -f -c $HERE/iceberg_wib.json $CONF_DIR/iceberg_wib_conf #>> $HERE/../logs/iceberg_wib_conf.log

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
