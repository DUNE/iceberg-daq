#!/bin/sh
rm -rf ../confs/*
# valid inputs are 
#     --cosmic [--femb-mask <mask>]  for  cosmic trigger on Signal 32 and tc_type_name KDTCosmic, sends the data to "Cosmic"
#     --pulser for LArASIC pulser on Signal 16777216 and tc_type_name kDTSPulser, sends the data to "Calibration"
#     --wibpulser also modifies iceberg_wib.json and modifies it to run WIB pulser
#     --pulsechannel=7 modifies wibXXXX_conf.json
#
#"wib_pulser": {
#                        "enabled_0": true,
#                        "enabled_1": true,
#                        "enabled_2": true,   # false for WIB 2  # false for WIB 3
#                        "enabled_3": true,                      # false for WIB 3
#                        "pulse_dac": 0,
#                        "pulse_duration": 255,
#                        "pulse_period": 2000,
#                        "pulse_phase": 0
#                    }
#
#
# echo "Just in case you forgot to start the environment"source ../../env.sh
#
#
echo ""
echo "Setting the DAQ for ${1} Data Taking"
echo ""
./recreate_wibs_103_104_105_configuration-W2F2m-wp-scpd.sh $1 $2 $3  # $2 $3 for optional --femb-mask <mask>
./generate_wibs_103_104_105.sh $1
cd ..
echo "****************************************************"
echo "Please type shutdown and exit during the next command"
echo "****************************************************"
./nanorc_run.sh --mode hermes
echo "****************************************************"
echo "Please type CRTL^C after 3 outputs from DPDK"
echo "****************************************************"
dpdklibs_test_frame_receiver
echo "****************************************************"
echo "Taking Data for 30 (any pulser)/600 (cosmic) secs"
echo "****************************************************"
./nanorc_run.sh -t 30
#./nanorc_run.sh -t 600
echo "****************************************************"
echo "HDF5 file is in /nvme/dunecet/dropbox"
echo "****************************************************"

