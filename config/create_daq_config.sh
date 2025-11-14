#!/bin/bash

set -euo pipefail

HERE=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)
TOP=$(cd "${HERE}/.." && pwd)
base_config_dir=$(cd "${HERE}/base/" && pwd)
generated_config_root=$(cd "${HERE}/generated/" && pwd)
: "${LOG_PREFIX:=$(basename "${BASH_SOURCE[0]}")}"
source $TOP/logging.sh
source $HERE/config_helpers.sh

usage() {
local prog=$(basename "$0")
    cat << EOF
Usage: $prog --wibs <'all'|102|105|106> --source <cosmic|pulser|wibpulser|pulsechannel> --name <config_name> [--clean]"

Generate configurations for Iceberg DAQ runs. Note that you must have an
active DUNE DAQ environment setup for this script to work.

Required arguments:
  --source
        Source of data.
        Allowed values are 'cosmic' and 'pulser'. 'wibpusler' and 'pulsechannel' are not currently enabled.
  --name
        Name of the generated configuration.
        A directory with this name will be created under ${generated_config_root}.
        The config name is also used as input to the nanorc_run script.

Optional arguments:
  --wibs
        List of three-digit WIB identifier numbers, or 'all' to configure all WIBs (default behavior).
        Allowed individual values are 102, 105, and 106.
  --isc
        Configure the WIBs to send data to NERSC through isc02.fnal.gov (in progress).
  --list
        List available configurations.
  --clean
        Remove existing configuration directory before regenerating.
  -h, --help, -?, or no arguments
        Show this message and exit.

Examples:
    Pulser configuration using only WIBs 102 and 105:
        ./$prog --wibs 102 105 --source pulser --name pulser_wibs_102_105
    Configure WIBs to send to isc02.fnal.gov:
        ./$prog --source pulser --isc --name pulser_isc
EOF
}

if [[ $# -eq 0 ]]; then
    usage
    exit 1
fi

if ! declare -p DBT_AREA_ROOT >&/dev/null; then
    error "This script requires an active DUNE DAQ environment."
    error "Navigate to the local DUNE DAQ build area and run 'source env.sh'"
    exit 2
fi

wibs=( "all" )
data_source=""
config_name=""
use_isc="false"
clean_mode="false"
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help|-?)
            usage
            exit 1
            ;;
        --list)
            list_available_configs
            exit 0
            ;;
        --wibs)
            shift
            if [[ $# -eq 0 || $1 == -* ]]; then
                error "No WIB numbers provided"
                usage 
                exit 1
            fi
            wibs=()
            while [[ $# -gt 0 && $1 != -* ]]; do
                wibs+=("$1")
                shift
            done
            ;;
        --source)
            if [[ $# -eq 1 || "$2" == -* ]]; then
                error "--source requires an argument."
                exit 1
            fi
            if [[ "$2" != "pulser" && "$2" != "cosmic" ]]; then
                error "Invalid --source argument."
                exit 1
            fi
            data_source="$2"
            shift 2
            ;;
        --name)
            if [[ $# -eq 1 || "$2" == -* ]]; then
                error "--name requires an argument"
                exit 1
            fi
            config_name="$2"
            shift 2
            ;;
        --isc)
            use_isc02="true"
            shift
            ;;
        --clean)
            clean_mode="true"
            shift
            ;;
        *)
            error "Unknown argument: $1"
            usage
            exit 1
            ;;
    esac
done

# Validate arguments
if [[ -z "$data_source" ]]; then
    error "--source is required"
    exit 1
fi

if [[ -z "$config_name" ]]; then
    error "--name is required"
    exit 1
fi

if [[ "${wibs[@]}" == "all" ]]; then
    wibs=( '102' '105' '106' )
fi

invalid_wib="false"
for wib in "${wibs[@]}"; do
    if [[ "$wib" != "102" && "$wib" != "105" && "$wib" != "106" ]]; then
        error "Invalid --wibs argument: $wib".
        invalid_wib="true"
    fi
done
[[ "$invalid_wib" == "false" ]] || exit 1

num_unique_elements=$(echo "${wibs[@]}" | tr " " "\n" | uniq -c | wc -l)
if [[ $num_unique_elements != ${#wibs[@]} ]]; then
    error "Each provided WIB number must be unique"
    error "Provided WIBs: ${wibs[@]}"
    exit 5
fi

# Create a config area. Remove an already existing area if --clean is provided.
generated_config_dir="${generated_config_root}"/"${config_name}"
if [[ -d "${generated_config_dir}" ]]; then
    if [[ "$clean_mode" == "true" ]]; then
        warn "Removing ${generated_config_dir} since '--clean' was supplied."
        rm -rf ${generated_config_dir}
    else
        error "A config area named '$config_name' already exists in $generated_config_dir"
        error "If you want to remove this directory, use '--clean'."
        exit 1
    fi
fi
mkdir -p ${generated_config_dir}

# Generate detector readout (DRO) maps from input WIB list
base_dromap_files=()
for wib in ${wibs[@]}; do 
    #filename="${base_config_dir}/dromaps/iceberg_dromap_wib_${wib}_isc02.json"
    filename="${base_config_dir}/dromaps/iceberg_dromap_wib_${wib}.json"
    if [[ ! -f "${filename}" ]]; then
        error "No detector readout map file exists for WIB $wib in $base_config_dir/dromaps"
        exit 4
    fi
    dromap_files+=("${filename}")
done
dromap="${generated_config_dir}/wib_dromap.json"
jq -s 'add' ${dromap_files[@]} > "${dromap}"

configure_cosmic_json() {
    generated_daq_config="${generated_config_dir}/iceberg_daq_eth_cosmic.json"
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
    cp -pf "${base_daq_config}" "${generated_daq_config}"
    info "Configuring for pulser"
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
    # Create a "top" configuration file that points to the correct generated config areas
    local base_top_config="${base_config_dir}/top_iceberg.json"
    generated_top_config="${generated_config_dir}/top_iceberg.json"
    cp -pf "${base_top_config}" "${generated_top_config}"
    sed -i "s|XPATHX|${generated_config_dir}|g" "${generated_top_config}"
    sed -i "s|XPATHX|${generated_config_dir}|g" "${generated_top_config}"
}

generate_wib_config() {
    # From the provided wib list, filter the template config for only the wibs we need
    jq --argjson wibs "$(printf '%s\n' "${wibs[@]}" | jq -R . | jq -s .)" \
    '.wibmod.wibserver |= map(select(.name | sub("^wib";"") as $n | ($wibs | index($n)))) ' \
    ${base_config_dir}/iceberg_wib.json > ${generated_config_dir}/wib_conf.json
}

disable_fembs() {
    # As of Nov. 2025, the first two FEMBs of WIB 106 are disabled.
    if [[ -f "$generated_config_dir/iceberg_wib_conf/data/wib106_conf.json" ]]; then
        sed -i '/femb[0]/,/enabled/{s/true/false/}' ${generated_config_dir}/iceberg_wib_conf/data/wib106_conf.json
        sed -i '/femb[1]/,/enabled/{s/true/false/}' ${generated_config_dir}/iceberg_wib_conf/data/wib106_conf.json
    fi
}

# Generate configuration area based on selected option
daq_json=""
base_daq_config="${base_config_dir}/iceberg_daq_eth.json"
generated_top_config=""
generated_daq_config=""
case "$data_source" in
    cosmic)
        base_daq_config="${base_config_dir}/iceberg_daq_cosmic.json"
        configure_cosmic_json
        ;;
    pulser)
        base_daq_config="${base_config_dir}/iceberg_daq_pulser.json"
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
        error "Unknown source: $data_source"
        usage
        exit 1
        ;;
esac

if [[ "$use_isc02" == "true" ]]; then
    sed -i '/rx_ip/s/192.168.122.100/128.55.205.29/g;
            /rx_mac/s/b4:83:51:0a:3e:d0/e4:78:76:90:ad:8f/g;
            /tx_ip/s/192.168.122.22/131.225.237.114/g;
            /tx_ip/s/192.168.122.23/131.225.237.115/g;
            /tx_ip/s/192.168.122.28/131.225.237.116/g;
            /tx_ip/s/192.168.122.29/131.225.237.117/g;
            /tx_ip/s/192.168.122.30/131.225.237.118/g;
            /tx_ip/s/192.168.122.31/131.225.237.119/g
    ' "${dromap}"
fi

generate_top_config
generate_wib_config

# Common operations for all configurations
if [ -z "$daq_json" ]; then
    error "Invalid daq config: $daq_json"
    exit 3
fi

fddaqconf_gen     -f -c "${daq_json}"                            -m "${dromap}" "${generated_config_dir}/iceberg_daq_conf"
hermesmodules_gen -f -c "${base_config_dir}/iceberg_hermes.json" -m "${dromap}" "${generated_config_dir}/iceberg_hermes_conf"
wibconf_gen       -f -c "${generated_config_dir}/wib_conf.json"                 "${generated_config_dir}/iceberg_wib_conf" #>> $HERE/../logs/iceberg_wib_conf.log

disable_fembs

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

info "Your generated configuration can be found in ${generated_config_dir}"
