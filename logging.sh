#!/bin/bash

# Any script that uses this should set LOG_PREFIX="[MyScript]"
#LOG_PREFIX="${LOG_PREFIX:=}"
: "${LOG_PREFIX:=$(basename "${BASH_SOURCE[0]}")}"

COLOR_INFO="\033[38;5;36m"    # teal-ish blue-green
COLOR_WARN="\033[38;5;178m"   # amber / gold (vs. yellow)
COLOR_ERROR="\033[38;5;203m"  # light red-orange
COLOR_RESET="\033[0m"         # Reset to non-color output

_log() {
    local level="$1"
    shift
    local msg="$*"
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    local color=""
    case "$level" in
        INFO) color="$COLOR_INFO" ;;
        WARNING) color="$COLOR_WARN" ;;
        ERROR) color="$COLOR_ERROR" ;;
    esac

    local formatted_msg="[iceberg-daq | ${LOG_PREFIX} | ${timestamp}] ${level}: ${msg}"
    if [[ "$level" == "INFO" ]]; then
        echo -e "${color}${formatted_msg}${COLOR_RESET}"
    # Warnings and error go to stderr
    else
        echo -e "${color}${formatted_msg}${COLOR_RESET}" >&2
    fi
}

info()  { _log "INFO" "$@"; }
warn()  { _log "WARNING" "$@"; }
error() { _log "ERROR" "$@"; }