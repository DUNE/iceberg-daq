#!/bin/bash

# Kurt Biery, October 2021 - April 2024
# Updated by Andrew Mogan, Oct 2025

set -eo pipefail

usage() {
  local prog
  prog=$(basename "$0")
  cat <<EOF

Usage: $prog

Scan /nvme/dunecet/dropbox for new HDF5 files and generate JSON metadata.

Arguments:
  data_disk_number   Two-digit disk ID (e.g. 01)

Notes:
  - Must be run in a clean environment (no DAQ setup active)
  - Creates a lockfile to prevent concurrent runs
  - Configurable variables are defined near the top of the script

Example:
  $prog 01

EOF
}

if [[ $# -eq 0 ]]; then
	usage; exit 1
fi
case "${1:-}" in
	-h|--help|-?) usage; exit 0 ;;
	[0-9][0-9]) data_disk_number="$1" ;;
	*) echo "Invalid argument: $1"; usage; exit 1 ;;
esac

if [[ -n "$DBT_AREA_ROOT" ]]; then
	echo "ERROR: This script needs to be run in a fresh environment without DUNE DAQ setup. Exiting..."
	exit 1
fi

# assign parameter values
#dataDirs="/data${data_disk_number}/amoganMetadataTests"  # may be a space-separate list
dataDirs="/nvme/dunecet/dropbox"
minDataFileAgeMinutes=0
maxDataFileAgeMinutes=172800
filenamePrefixList=( "iceberghd_raw" "iceberghd_tp")
duneDaqVersion="fddaq-v4.4.8-a9"

lockFileDir="/tmp"
lockFileName=".mdFileCronjob_dropbox.lock"

exec 200>$lockFileDir/$lockFileName
flock -n 200 || { echo "Another instance of this script is already running; exiting..."; exit 1; }

#setupScriptPath="/home/dunecet/file_transfer_metadata_scripts/setupDuneDAQ"
ourHDF5DumpScript="print_values_for_file_transfer_metadata.py"
scratchFile="/tmp/metadata_scratch_$$.out"
requestedJSONFileOutputDir="."  # an empty or "." value puts JSON files in the same dirs as the ROOT files
#logPath="/home/dunecet/file_transfer_metadata_scripts/log/createMDFile_data${data_disk_number}.log"
# TODO: Figure out a more permanent log path
#logPath="/nvme/dunecet/dunedaq/iceberg-v4.4.8/runarea/iceberg-daq/file_transfer_scripts/log/createMDFile_data${data_disk_number}.log"
logPath="/nvme/dunecet/dunedaq/data/metadata_logs/createMDFile_dropbox_$(date +"%Y%m%d%H%M").log"
extraFieldCommand="python /exp/pdune/daq/dunecet/fddaq-v4.4.8-iceberg/iceberg-daq/file_transfer_scripts/insert_extra_fields.py"
debugLevel=2  # only zero, one, and two are useful, at the moment; two is for performance tracing
versionOfThisScript="v3.2.0"

# define a function to log messages
function logMessage() {
    local msgText=$1
    local pid=$$
    local timestamp=`date '+%Y-%m-%d %H:%M:%S'`
    if [[ "$logPath" != "" ]]; then
        echo "${timestamp} (${pid}) ${msgText}" >> $logPath
    else
        echo "${timestamp} (${pid}) ${msgText}"
    fi
}

# initialization
logMessage "Starting $0 ${versionOfThisScript} for ${dataDirs}."

dunedaqSetupAttempted="no"
found_one_or_more_files="yes"
errors_were_encountered=""
echo "Beginning first while loop"
while [[ "${found_one_or_more_files}" != "" ]] && [[ "$errors_were_encountered" == "" ]] ; do
    found_one_or_more_files=""

    # 29-Oct-2021, KAB: added loop over filename prefixes
    for filenamePrefix in ${filenamePrefixList[@]}; do

	dataFileNamePattern="${filenamePrefix}_run??????_*.hdf5"
    offlineRunTypeReallyOpEnv="hd-iceberg"

	if [[ $debugLevel -ge 1 ]]; then
            logMessage "Searching for filenames like \"${dataFileNamePattern}\" in \"${dataDirs}\"."
            logMessage "Offline run_type is \"${offlineRunTypeReallyOpEnv}\"."
	fi

	# loop over all of the files that are found in the requested data directories
	found_file_count=0
	for volatileFileName in $(find "${dataDirs}" -user dunecet -maxdepth 1 -name "${dataFileNamePattern}" -type f -mmin +${minDataFileAgeMinutes} -mmin -${maxDataFileAgeMinutes} -print 2>/dev/null | sort -r); do

	    # determine the base filename for the current raw data file
	    baseFileName=`basename $volatileFileName`
	    fullFileName=${volatileFileName}

	    # determine the JSON file output dir, if not explicitly specified
	    jsonFileOutputDir=${requestedJSONFileOutputDir}
	    if [[ "$requestedJSONFileOutputDir" == "" ]] || [[ "$requestedJSONFileOutputDir" == "." ]]; then
			jsonFileOutputDir=`dirname $volatileFileName`
	    fi

	    # only do the work if the metadata file doesn't already exist
	    jsonFileName="${jsonFileOutputDir}/${baseFileName}.json"
	    if [[ ! -e "${jsonFileName}" ]] && [[ ! -e "${jsonFileName}.copied" ]]; then
		workingJSONFileName="${jsonFileName}.tmp"

		# if needed, setup dunedaq, etc. so that we can look inside the file
		if [[ "${dunedaqSetupAttempted}" == "no" ]]; then
		    if [[ $debugLevel -ge 1 ]]; then logMessage "Setting up dunedaq"; fi
			source /cvmfs/dunedaq.opensciencegrid.org/setup_dunedaq.sh
			setup_dbt fddaq-v4.4.8
			dbt-setup-release ${duneDaqVersion}
		    hdf5DumpFullPath=`eval which ${ourHDF5DumpScript} 2>/dev/null`
		    if [[ "$hdf5DumpFullPath" == "" ]]; then
				logMessage "ERROR: The ${ourHDF5DumpScript} script was not found!"
				exit 3
		    fi
		    dunedaqSetupAttempted="yes"
		fi

		# pull the run number out of the filename
		runNumber=`echo ${baseFileName} | sed 's/\(.*_run\)\([[:digit:]]\+\)\(_.*\)/\2/'`
		# strip off leading zeroes
		runNumber=`echo ${runNumber} | sed 's/^0*//'`
		# convert it to a number (may be needed later if we do range comparisons)
		let runNumber=$runNumber+0
		let subrunNumber=$runNumber*100000+1

		# double-check that we have a copy of the our HDF5 dumper utility
		if [[ "$hdf5DumpFullPath" == "" ]]; then
		    logMessage "ERROR: The ${ourHDF5DumpScript} script is not available, so the file-transfer metadata file will not be created."

		else
		    if [[ $debugLevel -ge 1 ]]; then
			logMessage "Creating ${jsonFileName} from ${fullFileName} using ${hdf5DumpFullPath} and local modifications."
		    else
			logMessage "Creating ${jsonFileName} using ${ourHDF5DumpScript} and local modifications."
		    fi

		    if [[ $debugLevel -ge 2 ]]; then logMessage "Before the needed HDF5 file values are fetched"; fi
		    rm -f ${scratchFile} || exit 128
		    ${hdf5DumpFullPath} ${fullFileName} > ${scratchFile} 2>/dev/null || exit 125
		    script_retcode=$?
		    if [[ $debugLevel -ge 2 ]]; then logMessage "After the needed HDF5 file values are fetched"; fi || echo 4

		    # if the dumper utility worked, process the results
		    if [[ $script_retcode == 0 ]]; then
			creation_time=`grep creation_timestamp ${scratchFile} | awk '{print $2}'`
			let creation_time=$creation_time+0
			let creation_time=$creation_time/1000
			closing_time=`grep closing_timestamp ${scratchFile} | awk '{print $2}'`
			let closing_time=$closing_time+0
			let closing_time=$closing_time/1000
			offline_data_stream=`grep offline_data_stream ${scratchFile} | awk '{print $2}'`
			daq_test_flag=`grep run_was_for_test_purposes ${scratchFile} | awk '{print $2}'`
			event_list=`cat ${scratchFile} | grep -A 99999999 'start of record list' | grep -B 99999999 'end of record list' | grep -v 'record list'`
			#logMessage "event list is ${event_list}"
			rm -f ${scratchFile}

			IFS=$'\n' trimmed_list1=($(sed 's/0$/TLZ/' <<<"${event_list[*]}"))
			IFS=$'\n' trimmed_list2=($(sed 's/^0+//' <<<"${trimmed_list1[*]}"))
			IFS=$'\n' trimmed_list3=($(sed 's/TLZ$/0/' <<<"${trimmed_list2[*]}"))
			IFS=$'\n' trimmed_list4=($(sed 's/\..*//' <<<"${trimmed_list3[*]}"))
			IFS=$'\n' sorted_list=($(sort -u -n <<<"${trimmed_list4[*]}"))
			IFS=$'\n' event_count=($(wc -l <<<"${sorted_list[*]}"))
			unset IFS

			min_event_num=${sorted_list[0]}
			max_event_num=${sorted_list[-1]}

			formatted_event_list=`echo "${sorted_list[*]}" | sed 's/ /,/g'`
			if [[ $debugLevel -ge 2 ]]; then logMessage "Midway through processing the needed HDF5 file values"; fi

			echo "{" > ${workingJSONFileName}
			echo "  \"name\": \"${baseFileName}\"," >> ${workingJSONFileName}
			echo "  \"namespace\": \"${offlineRunTypeReallyOpEnv}\"," >> ${workingJSONFileName}
			echo "  \"metadata\": {" >> ${workingJSONFileName}
			echo "    \"core.data_stream\": \"${offline_data_stream}\"," >> ${workingJSONFileName}
			if [[ "`echo ${filenamePrefix} | grep '_tp$'`" != "" ]]; then
			    echo "    \"core.data_tier\": \"trigprim\"," >> ${workingJSONFileName}
			else
			    echo "    \"core.data_tier\": \"raw\"," >> ${workingJSONFileName}
			fi
			echo "    \"core.file_format\": \"hdf5\"," >> ${workingJSONFileName}
			echo "    \"core.file_type\": \"detector\"," >> ${workingJSONFileName}
			echo "    \"core.file_content_status\": \"good\"," >> ${workingJSONFileName}
			echo "    \"retention.status\": \"active\"," >> ${workingJSONFileName}
			echo "    \"retention.class\": \"physics\"," >> ${workingJSONFileName}
			echo "    \"core.start_time\": ${creation_time}.0," >> ${workingJSONFileName}
			echo "    \"core.end_time\": ${closing_time}.0," >> ${workingJSONFileName}
			echo "    \"dune.daq_test\": ${daq_test_flag}," >> ${workingJSONFileName}
			echo "    \"core.event_count\": ${event_count}," >> ${workingJSONFileName}
			echo "    \"core.events\": [${formatted_event_list}]," >> ${workingJSONFileName}
			#if [[ "`echo ${fullFileName} | grep 'transfer_test'`" != "" ]]; then
			#    echo "  \"DUNE.campaign\": \"DressRehearsalNov2023\"," >> ${workingJSONFileName}
			#fi
			echo "    \"core.first_event_number\": ${min_event_num}," >> ${workingJSONFileName}
			echo "    \"core.last_event_number\": ${max_event_num}," >> ${workingJSONFileName}
			echo "    \"core.runs\": [${runNumber}]," >> ${workingJSONFileName}
			echo "    \"core.runs_subruns\": [$subrunNumber]," >> ${workingJSONFileName}
			echo "    \"core.run_type\": \"${offlineRunTypeReallyOpEnv}\"" >> ${workingJSONFileName}
			echo "  }" >> ${workingJSONFileName}
			echo "}" >> ${workingJSONFileName}

			if [[ $debugLevel -ge 2 ]]; then logMessage "After the needed HDF5 file values are processed"; fi

			${extraFieldCommand} ${fullFileName} ${workingJSONFileName} >/dev/null 2>/dev/null
			mv ${workingJSONFileName} ${jsonFileName}
			if [[ $debugLevel -ge 2 ]]; then logMessage "After extra field(s) are added"; fi
		    else
			logMessage "ERROR: unable to run ${ourHDF5DumpScript} on \"${fullFileName}\"."
			errors_were_encountered="yes"
		    fi
		fi

		let found_file_count=$found_file_count+1
		found_one_or_more_files="yes"
	    fi

	    if [[ $found_file_count -ge 16 ]]; then break; fi
	done # loop over the files that have been found

    done # loop over filename prefixes

done # loop until there are no files to be processed

# cleanup
logMessage "Done with $0 for ${dataDirs}."
