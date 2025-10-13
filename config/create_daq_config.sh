#!/bin/bash

set -euo pipefail

usage() {
    echo "Usage: $0 --wibs <'all'|102|105|106> --source <cosmic|pulser|wibpulser|pulsechannel> --name <config_name> [--clean]"
}

if [[ $# -eq 0 ]]; then
    usage
    exit 1
fi

HERE=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)
base_config_dir=$(cd "${HERE}/base/" && pwd)
generated_config_root=$(cd "${HERE}/generated/" && pwd)

wibs=()
data_source=""
config_name=""
clean_mode="false"
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            usage;;
        --wibs)
            shift
            if [[ $# -eq 0 || $1 == -* ]]; then
                echo "ERROR: No WIB numbers provided"
                usage 
                exit 1
            fi
            while [[ $# -gt 0 && $1 != -* ]]; do
                wibs+=("$1")
                shift
            done
            ;;
        --source)
            shift
            if [[ "$1" == "-*" ]]; then
                echo "ERROR: --source requires exactly one of 'cosmic', 'pulser', 'wibpulser', or 'pulsechannel'"
                usage
                exit 1
            fi
            case "$1" in
                cosmic | pulser | wibpulser | pulsechannel)
                    data_source="$1"
                    shift
                ;;
                *)
                    echo "ERROR: --source requires exactly one of 'cosmic', 'pulser', 'wibpulser', or 'pulsechannel'"
                    usage
                    exit 1;;
            esac
            ;;
        --name)
            shift
            if [[ -d $1 ]]; then
                echo "ERROR: A configuration directory named $1 already exists"
                exit 2
            fi
            config_name="$1"
            shift;;
        --clean)
            clean_mode="true"
            shift;;
        *)
            echo "ERROR Unknown argument: $1"
            usage
            exit 1
            ;;
    esac
done

# Validate arguments
if [[ -z "$data_source" ]]; then
    echo "ERROR: --source is required"
    exit 1
fi

if [[ -z "$config_name" ]]; then
    echo "ERROR: --name is required"
    exit 1
fi
generated_config_dir="${generated_config_root}"/"${config_name}"
if [[ -d "${generated_config_dir}" ]]; then
    echo "ERROR: A config area named $config_name already exists in $generated_config_dir"
    exit 1
fi
mkdir -p ${generated_config_dir}

if [[ "${wibs[@]}" == "all" ]]; then 
    wibs=( '102' '105' '106' ) 
fi

num_unique_elements=$(echo "${wibs[@]}" | tr " " "\n" | uniq -c | wc -l)
if [[ $num_unique_elements != ${#wibs[@]} ]]; then
    echo "ERROR: Each provided wib number must be unique"
    echo "${wibs[@]}"
    exit 5
fi

# Generate detector readout (DRO) maps from input WIB list
base_dromap_files=()
for wib in ${wibs[@]}; do 
    filename="${base_config_dir}/dromaps/iceberg_dromap_wib_${wib}.json"
    if [[ ! -f "${filename}" ]]; then
        echo "ERROR: No detector readout map file exists for WIB $wib in $base_config_dir/dromaps"
        exit 4
    fi
    dromap_files+=("${filename}")
done
dromap="${generated_config_dir}/wib_dromap.json"
#jq -s 'add' ${dromap_files[@]} > "${config_dir}/generated/${config_name}/wib_dromap.json"
jq -s 'add' ${dromap_files[@]} > "${dromap}"

configure_cosmic_json() {
    generated_daq_config="${generated_config_dir}/iceberg_daq_eth_cosmic.json"
    #cp -pf "${HERE}/iceberg_daq_eth.json" "${HERE}/iceberg_daq_eth.json.sav"
    cp -pf "${base_daq_config}" "${generated_daq_config}"
    sed -i '
        /"signal"/s/[0-9][0-9]*/32/
        /tc_type_name/s/k[a-zA-Z]*/kDTSCosmic/
        /hsi_re_mask/s/[0-9][0-9]*/32/
        /offline_data_stream/s/:.*/: "cosmics",/
        /hsi_source/s/:.*/: 0,/
    ' "${generated_daq_config}"
    daq_json="${generated_daq_config}"
}

configure_pulser_json() {
    generated_daq_config="${generated_config_dir}/iceberg_daq_eth_pulser.json"
    #cp -pf "${HERE}/iceberg_daq_eth.json" "${HERE}/iceberg_daq_eth.json.sav"
    cp -pf "${base_daq_config}" "${generated_daq_config}"
    echo "Configuring for pulser"
    #cp -pf "${HERE}/iceberg_daq_eth.json" "${HERE}/iceberg_daq_eth.json.sav"
    sed -i '
        /"signal"/s/[0-9][0-9]*/16777216/
        /tc_type_name/s/k[a-zA-Z]*/kDTSPulser/
        /hsi_re_mask/s/[0-9][0-9]*/16777216/
        /offline_data_stream/s/:.*/: "calibration",/
        /hsi_source/s/:.*/: 0,/
    ' "${generated_daq_config}"
    daq_json="${generated_daq_config}"
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

generate_top_config() {
    local base_top_config="${base_config_dir}/top_iceberg.json"
    generated_top_config="${generated_config_dir}/top_iceberg.json"
    cp -pf "${base_top_config}" "${generated_top_config}"
    sed -i "s|XPATHX|${generated_config_dir}|g" "${generated_top_config}"
    sed -i "s|XPATHX|${generated_config_dir}|g" "${generated_top_config}"
}

# Execute configuration based on selected option
daq_json=""
base_daq_config="${base_config_dir}/iceberg_daq_eth.json"
generated_top_config=""
generated_daq_config=""
case "$data_source" in
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
        echo "ERROR: Unknown source: $data_source"
        usage
        exit 1
        ;;
esac

generate_top_config || exit 234

# Common operations for all configurations
if [ -z "$daq_json" ]; then
    echo "ERROR: Invalid daq config: $daq_json"
    exit 3
fi

#CONF_DIR=$(cd "${HERE}/../configs/${config_name}" && pwd)
fddaqconf_gen     -f -c "${daq_json}" -m "${dromap}" "${generated_config_dir}/iceberg_daq_conf"
hermesmodules_gen -f -c "${base_config_dir}/iceberg_hermes.json" -m "${dromap}" "${generated_config_dir}/iceberg_hermes_conf"
wibconf_gen       -f -c "${base_config_dir}/iceberg_wib.json"        ${generated_config_dir}/iceberg_wib_conf #>> $HERE/../logs/iceberg_wib_conf.log

sed -i 's/monkafka.cern.ch:30092/iceberg01.fnal.gov:30092/g' "${generated_config_dir}/iceberg_daq_conf/boot.json"
sed -i 's/monkafka.cern.ch:30092/iceberg01.fnal.gov:30092/g' "${generated_config_dir}/iceberg_hermes_conf/boot.json"
sed -i '
    /digits_for_file_index/s/.,/1,/
    /overall_prefix/s/iceberghd/iceberghd_raw/
' "${generated_config_dir}/iceberg_daq_conf/data/dataflow0_conf.json"
sed -i 's/PD2HDChannelMap/ICEBERGChannelMap/' \
"${generated_config_dir}/iceberg_daq_conf/data/trigger_conf.json" \
"${generated_config_dir}/iceberg_daq_conf/data/ruiceberg03eth0_conf.json" \
"${generated_daq_config}"
