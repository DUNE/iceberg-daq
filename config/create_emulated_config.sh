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
Usage: $prog --base-config <config_file_path> 
             --name <config_name> 
             [--clean]"

Generate emulated configurations for Iceberg DAQ runs. Note that you must have an
active DUNE DAQ environment setup for this script to work.

Required arguments:
  --base-config
        Base configuration file from which to generate your configuration.
        Available base configurations can be found in ${base_config_dir}.
  --name
        Name of the generated configuration.
        A directory with this name will be created under ${generated_config_root}.
        The config name is also used as input to run_emulated_daq.sh.

Optional arguments:
  --list
        List available configurations.
  --clean
        Remove existing configuration directory before regenerating.
  -h, --help, -?, or no arguments
        Show this message and exit.

Examples:
    Basic cosmic configuration:
        ./$prog --base-config base/iceberg_daq_cosmic.json --name cosmic_config
    Pulser configuration using only WIBs 102 and 105:
        ./$prog --base-config base/iceberg_daq_pulser.json --name pulser_wibs_102_105 --wibs 102 105
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

base_daq_config=""
config_name=""
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
        --base-config)
            base_daq_config=$(basename "$2")
            if [[ $# -eq 1 || "$base_daq_config" == -* ]]; then
                error "--base-config requires an argument."
                exit 1
            fi
            if [[ ! -f "${base_config_dir}/${base_daq_config}" ]]; then
                error "--base-config argument must be a file from ${base_config_dir}."
                exit 1
            fi
            echo "Using base config: $base_daq_config"
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
if [[ -z "$base_daq_config" ]]; then
    error "--base-config is required"
    exit 1
fi

if [[ -z "$config_name" ]]; then
    error "--name is required"
    exit 1
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

dromap="${base_config_dir}/dromaps/emulated_dromap.json"
if [[ ! -f "${dromap}" ]]; then
    error "No detector readout map file named ${dromap} exists in $base_config_dir/dromaps"
    exit 4
fi

cp "$dromap" ${generated_config_dir}

generated_daq_config="${generated_config_dir}/${base_daq_config}"
cp -pf "${base_config_dir}/${base_daq_config}" "${generated_daq_config}"

fddaqconf_gen     -f -c "${generated_daq_config}" -m "${dromap}" "${generated_config_dir}/emulated_daq_conf"

info "Your generated configuration can be found in ${generated_config_dir}"
