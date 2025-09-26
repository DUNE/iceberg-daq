# 
# TLU Status for DUNEDAQ
#
cd /home/dunecet/dunedaq/fddaq-v4.4.6-a9
source env.sh
#
cd tlu
#
dtsbutler mst BOREAS_TLU_ICEBERG status

dtsbutler hsi BOREAS_TLU_ICEBERG readback
#
