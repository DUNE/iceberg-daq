#
# New TLU Script Sept 6 2023 
# To be used with DUNE DAQ V4.4.3
#
# Updated by Shekhar Mishra for TLU Firmware version 7.3.0
# Based on based on comments received from Dennis Lindebaum and Stoyan Trilov
# June 21, 2024
#
# Modified by Shekhar Mishra to include DAPHNE-V3/V2 End Point Feb 6, 2024
#
# Sending Cosmic Trigger on Channel 5 (Limo 6) and Pulser on Channel 2
# Edited by Shekhar Mishra June 21, 2024
#
#cd /home/dunecet/dunedaq/fddaq-v4.4.6-a9/
cd /nvme/dunecet/dunedaq/iceberg-v4.4.8
source env.sh
#
# Move to TLU area for 
#
#cd /home/dunecet/dunedaq/fddaq-v4.4.6-a9/runarea/tlu
cd /nvme/dunecet/dunedaq/iceberg-v4.4.8/runarea/tlu
#
dtsbutler io BOREAS_TLU_ICEBERG reset
sleep 2
#
dtsbutler mst BOREAS_TLU_ICEBERG synctime
sleep 2
#
dtsbutler mst BOREAS_TLU_ICEBERG faketrig-clear 0
#sleep 2
#
#dtsbutler mst BOREAS_TLU_ICEBERG faketrig-conf 0 2 2
#sleep 2
# 
